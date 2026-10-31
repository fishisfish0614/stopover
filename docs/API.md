# 经停 Stopover · 接口文档 / API Reference

这份文档写给两类人：想用自己的后端（Node、Go……）重新实现这套接口、直接复用本仓库 `web/index.html` 和 `ios/` App 的人，以及对接 iOS 的开发者。一切以 `server/stopover.py` 为准；这里的字段名、状态码、错误文案都能在代码里找到。

目录：

1. [概览 / Overview](#1-概览--overview)
2. [身份 / Auth](#2-身份--auth)
3. [数据模型 / Data model](#3-数据模型--data-model)
4. [接口 / Endpoints](#4-接口--endpoints)
5. [投递流程 / Delivery](#5-投递流程--delivery)
6. [推送 / Push](#6-推送--push)
7. [MCP 与 CLI / MCP & CLI](#7-mcp-与-cli--mcp--cli)
8. [照片签名与卡片钥匙 / Signed photos & card keys](#8-照片签名与卡片钥匙--signed-photos--card-keys)
9. [重新实现清单 / Re-implementing checklist](#9-重新实现清单--re-implementing-checklist)

---

## 1. 概览 / Overview

- **一个服务同时托管前端和接口。** `web/` 挂在站点根（静态文件，`index.html` 是默认页），接口在 `/api/*`，另有 `/mcp` 和 `/card/*`。城市数据就是静态文件：`data/cities.json`、`data/city/{id}.json`。
- **路径都是相对的。** 网页用 `fetch("api/state")`、`data/cities.json` 这类相对地址，`sw.js` 用 `registration.scope` 拼链接；iOS 把用户填的服务器地址当 base，再拼 `api/...`、`data/...`。所以整套东西可以挂在子路径下（如 `https://example.com/stopover/`）。
- **JSON 进出。** 请求体是 JSON（照片上传除外，是 multipart）；所有写接口的请求体都可省略，缺省为 `{}`。成功的写操作返回 `{"ok": true, ...}`。
- **时间戳**：`created` `updated` `sent` `read_at` `taken` `ts` 都是 **unix 秒，浮点数**（Python `time.time()`）。
- **日期**：`date_start` / `date_end` 是字符串，只接受 `YYYY`、`YYYY-MM`、`YYYY-MM-DD` 三种（正则 `\d{4}(-\d{2}(-\d{2})?)?`，不校验月日范围）。
- **错误格式**：`{"detail": "给人看的中文"}`，配 4xx/5xx 状态码。网页和 iOS 都直接把 `detail` 当 toast 显示（iOS 前面加「没存上：」）。路径参数类型不对（如 `/api/trip/abc`）由框架回 422，`detail` 是数组——客户端只会显示状态码，重新实现时可以照样回 422 或改成 404。
- **"软失败"**：推送相关几个接口在功能没开时回 **200** + `{"ok": false, "reason": "..."}`，不是 4xx（见 §4.9）。
- **配置每次请求都重新读**（`server/config.json`，缺失时读 `config.example.json`），改完不用重启。

## 2. 身份 / Auth

服务端只区分两种身份，没有登录：

| 身份 | 怎么判定 |
|---|---|
| `partner` | 配置了 `partner_key`，且请求头 `Authorization: Bearer <partner_key>` 完全一致（常量时间比较，`Bearer` 大小写不敏感） |
| `me` | 其它一切请求——包括**带错钥匙**的请求（普通接口不会因钥匙错误回 401，只会被当成 me） |

网页和 iOS App 永远是 `me`，从不发 `Authorization`。保护 me 靠你自己的反向代理鉴权（见 README「安全」节）。

**partner 被拦下的写操作（403）**：对以下前缀的非 GET/HEAD 请求，统一回
`403 {"detail": "这是{me}的经停：{partner}只能看、留言、点星、递东西"}`（`{me}` `{partner}` 是配置里的显示名）：

```
/api/checkin  /api/trip  /api/photo（POST /api/photo/check 除外）  /api/note  /api/place  /api/push
```

这是**前缀匹配**（`/api/trip/3/note`、`/api/trip/3/upload` 都在内）。

**partner 能做的**：所有 GET（包括 `/api/state`、照片、城市数据）；`POST /api/share`（只能递 city / sight / food，否则 400）；`POST /api/comment`、删自己的评论；点 / 收自己的星（`by` 只能是 `partner`）；`POST /api/city/{id}/gen`；`PUT /api/share/{id}/read`、`DELETE /api/share/{id}`（不在拦截前缀里，但 partner 递的东西直接是 `sent`，撤不了）。

**需要 partner 身份的接口**：

| 接口 | 不是 partner 时 |
|---|---|
| `GET /api/partner/inbox`、`POST /api/partner/tool` | `401 {"detail": "需要 partner 钥匙（Authorization: Bearer <partner_key>）"}`；没配 `partner_key` 时 detail 是 `"服务端没有设置 partner_key"` |
| `POST /mcp` | `401`，头 `WWW-Authenticate: Bearer`，体 `{"jsonrpc":"2.0","id":null,"error":{"code":-32001,"message":"partner key required"}}` |

**`partner_key` 为空时**：所有请求都是 me；上面三个接口一律 401；为兼容 v1，me 可以写任一颗星（`PUT /api/wish/{city}` 带 `"by": "partner"` 也行）。

## 3. 数据模型 / Data model

SQLite 表结构见 `init()`。下面只列客户端能看到的字段。

### checkin（一次「来过」，客户端叫 trip）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | int | 自增 |
| `city` | string | 城市 id |
| `origin` | string \| null | 出发城市 id；`null` = 不画线 |
| `dest` | string \| null | 之后去了哪（终点）城市 id |
| `date_start` / `date_end` | string \| null | 见 §1 日期格式 |
| `remark` | string \| null | 一句备注，≤60 字 |
| `created` / `updated` | float | |

`origin` / `dest` 等于本城时存成 `null`；写入时会检查城市存在（否则 404）。

### note（随记）

`id` int · `trip_id` int · `text` string（≤5000，不能为空）· `created` · `updated`

### photo（照片）

| 字段 | 说明 |
|---|---|
| `id`, `trip_id` | |
| `caption` | string，默认 `""`，≤1000 |
| `tag` | `/api/config` 下发的 `tags` 之一（`美食` `风景` `名胜` `艺术品` `个人照片`）或 `null` |
| `w`, `h` | 原图按 EXIF 转正后的尺寸 |
| `taken` | 拍摄时间（EXIF DateTimeOriginal，按服务器本地时区换算）或 `null` |
| `created` | |
| `file`, `sha256` | 只出现在上传 / 修改接口的返回里，`/api/state` 不给 |

客户端排序约定：同一次里按 `COALESCE(taken, created), id`。

### wish（想去的星）

`city` · `by`（`"me"` 金星 / `"partner"` 蓝星）· `note`（≤200，默认 `""`）· `created`。主键 `(city, by)`，每人每城一颗；重复点只更新 `note`。

### share（递送）

| 字段 | 说明 |
|---|---|
| `id`, `created` | |
| `who` | `"me"` / `"partner"`（谁递的） |
| `items` | 数组，见下 |
| `note` | 附言，≤500 |
| `status` | `"pending"`（me 递的，还在合并窗口里，可撤回）/ `"sent"` |
| `sent` | 送出时间或 `null` |
| `img` | `1` / `0`：city / sight / food 是否附维基配图（trip / photo 的照片总是附） |
| `read_at` | me 点开 partner 递来的那一样的时间（收件处红点），或 `null` |
| `err` | 最近一次 webhook 失败原因，或 `null` |
| `key` | 卡片钥匙（§8） |

内部还有 `tries`、`taken_at`（partner 是否已取走），不对外。

**items 各类型**（服务端会规整成下面的形状，多余字段丢掉）：

| `type` | 字段 | 谁能递 | 检查 |
|---|---|---|---|
| `trip` | `id` | me | 那一次要存在 |
| `note` | `id` | me | 随记要存在 |
| `photo` | `id` | me | 照片要存在 |
| `city` | `city` | me / partner | 城市 id 要存在 |
| `sight` | `city`, `i` | me / partner | 城市要存在；`i` 是 `sights[]` 的 **0 起**下标（HTTP 接口不检查越界） |
| `food` | `city`, `i` | me / partner | 同上，对应 `foods[]` |

一次 1–100 样。

### comment（对话）

`id` · `target` · `who` · `text`（≤2000，不能为空）· `reply_to`（int \| null）· `created` · `key`

`target` 写成 `类型:编号`：`city:<城市id>`、`trip:<n>`、`note:<n>`、`photo:<n>`、`share:<n>`。`reply_to` 接受 `7` 或 `"c:7"`，只检查那条评论存在。客户端约定：递送组的话挂 `share:<id>`，其余（城市 / 某一次 / 照片 / 随记下）归「平时说的」。

**级联删除**：删一次 → 删它的随记、照片记录（文件留在磁盘），以及挂在 `trip:` / 它的 `photo:` / `note:` 上的评论（`share:` 下的不删）；如果这座城没别的「来过」了，以它为 `origin` 的其它次改回默认出发地，以它为 `dest` 的清空。删随记 / 照片 → 删挂在上面的评论。

### 城市数据文件（静态）

**`data/cities.json`**：`{"cities": [...], "extra": [...], "cz": {...}}`

`cities[]`——有长卷的城：

| 键 | 说明 |
|---|---|
| `id` | 城市 id（如 `kyoto`、`lisbon`），也是 `data/city/{id}.json` 的文件名 |
| `n` | 中文名 |
| `e` | 英文名 |
| `c` | 国家（Natural Earth 英文国名，如 `Japan`） |
| `la`, `lo` | 纬度、经度 |
| `b` | 范围框 `[南纬, 北纬, 西经, 东经]`（纬度 min/max、经度 min/max），网页用来定缩放；可能为 `null` |
| `t` | 档位：预置数据是 `p` / `f`，现场整理生成的是 `g`；网页在「附近」列表里把 `p` 排前面 |

`extra[]`——地图上能点、还没长卷的城，每行是数组 `[中文名, 英文名, 纬度, 经度, 国家]`。它的 id 是 `n_<英文名>_<纬度>`，纬度按 **JavaScript 数字转字符串**的写法（`34.122`、整数纬度写 `10` 而不是 `10.0`）——网页、iOS 和服务端（`xid()`）都这么拼。

`cz`：英文国名 → 中文国名。

`cities.json` 会变：现场整理（城从 `extra` 移进 `cities`，id 不变）、`POST /api/place`（追加到 `extra`）。iOS 每次启动都重新拉；网页整理完会带 `?t=` 重新拉。

**`data/city/{id}.json`**（长卷）：

| 键 | 说明 |
|---|---|
| `id`, `name`, `en`, `country`, `lat`, `lng` | |
| `dek` | 一句话导语 |
| `history`, `culture` | 正文，段落以空行分隔 |
| `pull` | 引语 |
| `sights[]`, `foods[]` | `{name, orig, intro, img: {u, w, h} \| null, src}`；`orig` 是当地原名，`src` 是来源链接 |
| `hero[]` | 版头图 `{u, w, h}` |
| `outline` | GeoJSON `Polygon` / `MultiPolygon` 或 `null` |
| `credit` | `{model, wiki, generated?}` |

## 4. 接口 / Endpoints

「谁」一栏：**me** = 无钥匙即可；**都行** = me 和 partner；**partner** = 必须带钥匙。

### 4.1 配置与状态 / Config & state

**`GET /api/config`** · 都行

```json
{"me": "我", "partner": "TA",
 "home": {"label": "家", "lat": 31.23, "lng": 121.474, "tz": "Asia/Shanghai"},
 "default_origin": {"domestic": "shanghai", "abroad": "shanghai"},
 "domestic_countries": ["China", "Hong Kong S.A.R.", "Macao S.A.R", "Taiwan"],
 "clocks": [{"label": "家里", "tz": "Asia/Shanghai"}, {"label": "伦敦", "tz": "Europe/London"}],
 "tags": ["美食", "风景", "名胜", "艺术品", "个人照片"],
 "features": {"share": true, "push_apns": false, "push_web": true}}
```

前六项原样取自配置（没配就是 `null`）。`features.share=false` 时网页和 iOS 藏起递送 / 对话 / 收件箱 / 通知；`push_web` / `push_apns` 表示服务端这两种推送能不能用（依赖已装、配置齐全）。

**`GET /api/state`** · 都行 · 客户端的唯一数据源，每次写完都重拉一遍（没有定时轮询）。

```json
{"checkins": [{"id": 2, "city": "kyoto", "origin": "shanghai", "dest": null, "date_start": "2023-04", "date_end": null,
               "remark": "第一次见到满山的樱花。", "created": 1793479134.27, "updated": 1793479134.27}],
 "notes":    [{"id": 1, "trip_id": 2, "text": "清晨的伏见稻荷……", "created": 1793479134.27, "updated": 1793479134.27}],
 "photos":   [{"id": 1, "trip_id": 2, "caption": "", "tag": null, "w": 800, "h": 600, "taken": null, "created": 1793479155.48}],
 "wishes":   [{"city": "reykjavk", "by": "me", "note": "想看极光", "created": 1793479134.27}],
 "comments": [{"id": 2, "target": "share:1", "who": "me", "text": "好，要清晨去。", "reply_to": 1, "created": 1793227134.27, "key": "eI3wQbHvFL3Dqhm9"}],
 "shares":   [{"id": 1, "created": 1793219934.27, "who": "me", "note": "这张票给你。", "status": "sent", "sent": 1793220054.27,
               "img": 1, "read_at": null, "err": null, "key": "KcFVhNVONG_5uied", "items": [{"type": "trip", "id": 2}]}],
 "config":   { "...": "同 /api/config" }}
```

排序：checkins / comments / shares 按 `id`；notes 按 `trip_id, id`；photos 按 `trip_id, COALESCE(taken, created), id`；wishes 按 `created`。

### 4.2 经停 / Trips

**`POST /api/checkin/{city}`** · me · 再来一次（同一座城可以有多次）

- 体：`{"origin": "<城市id>"}`，可省。省略或为空 → 用默认出发地（`default_origin.domestic` 或 `.abroad`，按城市国家是否在 `domestic_countries` 里；等于本城时为 `null`）。`origin` 等于本城 → `null`（不画线）。
- 返回：`{"ok": true, "checkin": {checkin}}`
- 错误：404 `没有这座城：{city}`（city 或 origin 不存在）

**`PUT /api/trip/{tid}`** · me · 只改传了的键

- 体：任选 `origin`、`dest`（城市 id，空 / `null` 清空）、`date_start`、`date_end`、`remark`（空串清空）
- 返回：`{"ok": true, "checkin": {checkin}}`
- 错误：404 `没有这一次`；404 `没有这座城：…`；400 `日期写成 2019 / 2019-08 / 2019-08-03`（整次修改回滚）

**`DELETE /api/trip/{tid}`** · me

- 返回：`{"ok": true, "reset_children": ["porto"]}`——因为这座城没人来过了、`origin` 被改回默认的那些次的城市 id（客户端据此 toast）
- 级联见 §3

### 4.3 随记 / Notes

| 方法 + 路径 | 谁 | 体 | 返回 | 错误 |
|---|---|---|---|---|
| `POST /api/trip/{tid}/note` | me | `{"text"}` | `{"ok": true, "note": {note}}` | 400 `随记是空的`；404 `没有这一次` |
| `PUT /api/note/{nid}` | me | `{"text"}` | `{"ok": true, "note": {note}}` | 400 `随记是空的，要删请用删除`；404 `没有这段随记` |
| `DELETE /api/note/{nid}` | me | — | `{"ok": true}` | 404 `没有这段随记` |

### 4.4 照片 / Photos

**`POST /api/photo/check`** · 都行 · 上传前按指纹查重

- 体：`{"sha256": ["<hex>", ...]}`（最多看前 200 个）
- 返回：`{"hits": {"<sha256>": {"file": "75920cdc9f13_t.jpg"}}}`——只列已存在的
- 网页上传前会调它，显示「传过了 / 新照片」；失败就当全是新的。iOS 不调。

**`POST /api/trip/{tid}/upload`** · me · multipart，字段名 `file`，传原图（HEIC 也行，服务端装了 `pillow-heif` 就能读）

- 返回：`{"ok": true, "photo": {photo, 含 file / sha256}, "dedup": false}`
  - 同一次里已有同一张（sha256 相同）→ 直接回那一行，`dedup: true`，不新建
  - 别的次里有同一张 → 新建一行、复用文件，`dedup: true`
- 服务端存原图 + 两张缩略图（宽 600 / 1600，JPEG），读 EXIF 拍摄时间
- 错误：413 `照片太大（超过 40MB）`；400 `认不出这张图片`；404 `没有这一次`

**`GET /api/photo/img/{pid}?w=600[&s=签名]`** · 都行 · 返回 `image/jpeg`，`Cache-Control: private, max-age=2592000`

- `w ≤ 600` 给 600 宽缩略图，`w > 600` 给 1600 宽的。客户端用 `w=600`（列表）和 `w=1600`（大图）。
- 带 `s`：必须是 §8 的签名，不对回 403 `照片链接签名不对`；不带 `s`：不检查（视为在 me 的鉴权后面）。
- 错误：404 `没有这张照片` / `缩略图丢了`

**`PUT /api/photo/{pid}`** · me · 体任选 `caption`、`tag`（`null` / `""` 清空）→ `{"ok": true, "photo": {photo}}`；400 `标签只能是 美食/风景/名胜/艺术品/个人照片`；404

**`DELETE /api/photo/{pid}`** · me → `{"ok": true}`（文件留在磁盘）；404

### 4.5 想去 / Wishes

**`PUT /api/wish/{city}`** · 都行

- 体：`{"by": "me" | "partner", "note": "..."}`，`by` 省略 = 调用者自己。客户端总是显式传 `"by": "me"`。
- 返回：`{"ok": true}`；partner 点星会推送给 me（§6）
- 错误：400 `by 只能是 me 或 partner`；403 `只能改自己的星星（你是 me）`；404 `没有这座城：…`

**`DELETE /api/wish/{city}?by=me`** · 都行 → `{"ok": true, "removed": 0|1}`；同样的 by 规则

### 4.6 递送 / Shares

**`POST /api/share`** · 都行

- 体：`{"items": [...], "note": "附言", "img": true}`（`img` 默认 true）
- 返回：`{"ok": true, "id": 4, "status": "pending"}`——me 递的是 `pending`，partner 递的直接 `sent`（并推送给 me）
- 错误：400 `没选东西`（空 / 非数组 / 超 100）；400 `不认识的类型：bus`；400 `这一样缺编号：{...}`；400 `TA能递的是城市 / 景点 / 美食`（partner 递了 trip/photo/note）；404 对应对象不存在

**`DELETE /api/share/{sid}`** · 都行 · 撤回，只撤**自己的、还是 pending 的** → `{"ok": true, "removed": 0|1}`。`removed: 0` 时客户端提示「已经送出去了，撤不回」。

**`PUT /api/share/{sid}/read`** · me（partner 不被拦）· 标记 partner 递来的已读（只在 `read_at` 为空时写）→ `{"ok": true}`；404 `没有这次递送`

### 4.7 评论 / Comments

**`POST /api/comment`** · 都行

- 体：`{"target": "share:4", "text": "...", "reply_to": 3}`（`reply_to` 可省 / `null`）
- 返回：`{"ok": true, "comment": {"id", "target", "who", "text", "reply_to", "created"}}`（不含 `key`，要钥匙从 `/api/state` 取）
- me 的话进投递队列（§5）；partner 的话推送给 me
- 错误：400 `话是空的`；400 `target 是 city:/trip:/note:/photo:/share: 加编号`；400 `target 写错了：…`；400 `reply_to 是评论编号`；404 `没有 c:{n} 这条`；404 target 指向的对象不存在

**`DELETE /api/comment/{cid}`** · 都行 · 只删自己的 → `{"ok": true, "removed": 0|1}`

### 4.8 伴侣 / Partner

**`GET /api/partner/inbox[?mark=1]`** · partner · me 递来、还没取走的 + me 回的话

```json
{"count": 2,
 "text": "我递给你：\n· 京都 · 2023.04 · 从上海出发（t:2）\n  …\n  回这一样：say d:4 \"…\"\n\n我回你的话：\n· 在我递的「京都的整张票」（c:4）…",
 "images": ["https://example.com/api/photo/img/1?w=600&s=f24d93d2…"],
 "shares": [{"id": 4, "created": 1793479165.59, "items": [{"type": "trip", "id": 2}], "note": "给你",
             "text": "这一样单独渲染的一段", "images": ["…"], "card": {"url": "…/card/share/4?k=…", "json": {card}}}],
 "replies": [{"id": 4, "created": 1793479165.65, "target": "share:4", "where": "我递的「京都的整张票」", "text": "再说一句",
              "reply_to": 3, "card": {"url": "…/card/comment/4?k=…", "json": {card}}}],
 "marked": false}
```

`mark=1` 把这些标成已取（下次就不再出现）；不带只是看看。`text` 是给 AI 读的合并摘要（和 webhook 的 `body` 同源），`images` 最多 `inject.max_images` 张；每个 share 自己的 `images` 最多 9 张。

**`POST /api/partner/tool`** · partner · CLI 用，见 §7

### 4.9 推送 / Push

| 方法 + 路径 | 谁 | 体 / 参数 | 返回 |
|---|---|---|---|
| `GET /api/push/vapid` | 都行 | — | `{"ok": true, "publicKey": "<base64url 未压缩 P-256 公钥>"}`；不可用时 `{"ok": false, "reason": "web push not available (pip install pywebpush)"}` |
| `POST /api/push/web` | me | `{"subscription": PushSubscription.toJSON()}` | `{"ok": true}`；400 `subscription 要有 endpoint 和 keys.p256dh / keys.auth`；不可用时 `{"ok": false, "reason": "web push not available"}` |
| `DELETE /api/push/web` | me | `?endpoint=` 或体 `{"endpoint"}` / `{"subscription": {"endpoint"}}` | `{"ok": true, "removed": n}` |
| `POST /api/push/apns` | me | `{"token": "<十六进制设备 token>", "env": "sandbox" \| "production"}` | `{"ok": true}`；没配 APNs 时（先查这个）`{"ok": false, "reason": "apns not configured"}`；400 `token 是设备 token 的十六进制串`（32–200 位 hex）/ `env 是 sandbox 或 production` |
| `DELETE /api/push/apns` | me | `?token=` 或体 `{"token"}` | `{"ok": true, "removed": n}` |

订阅按 endpoint / token 去重（再登记一次就是更新）。`env` 省略用配置 `push.apns.env`。iOS 的 Debug 构建登记 `sandbox`，Release 登记 `production`。

### 4.10 城市整理 / City pages on demand

**`POST /api/city/{cid}/gen`** · 都行 · 体 `{"pro": true}` 可省（`pro` = 用更好的模型）

按顺序判断：

| 情况 | 返回 |
|---|---|
| 城市不存在 | 404 `没有这座城：…` |
| 已有 `data/city/{cid}.json` | `{"status": "done", "stage": "done"}` |
| 没配 `DEEPSEEK_API_KEY` | 503 `服务器没配 DEEPSEEK_API_KEY，整理不了` |
| 正在整理这一座 | `{"status": "running", ...进度}` |
| 正在整理别的城（同一时间只整理一座） | 409 `正在整理{城名}，等它好了再来` |
| 过去 24 小时已整理 ≥ `gen.daily_max`（默认 20） | 429 `今天已经整理了 {n} 座，明天再来` |
| 开始 | `{"status": "running", "stage": "start", "msg": "准备中"}` |

**`GET /api/city/{cid}/gen`** · 都行 · 查进度（不检查城市是否存在）

- `{"status": "none"}`：没开始过
- `{"status": "running", "stage": "wiki", "msg": "正在翻维基", "ts": …}`：`stage` 依次 `start` → `wiki` → `write` → `images` → `save`
- `{"status": "done", "stage": "done", "msg": "整理好了", "entry": {cities[] 的一项}, "sights": 6, "foods": 5}`
- `{"status": "error", "stage": "error", "msg": "…"}`：出错，或进程已不在（`msg` 为 `整理中断了，再点一次试试`）

网页和 iOS 都每 **2.5 秒**轮询一次，最多 120 次；`done` 后网页重拉 `data/cities.json?t=…` 和长卷，iOS 直接用 `entry`。

### 4.11 地点 / Places（Wikidata）

**`GET /api/place/search?q=里斯本`** · 都行 · 服务端去查 Wikidata

```json
{"items": [{"qid": "Q597", "name": "里斯本", "en": "Lisbon", "desc": "葡萄牙首都", "lat": 38.708, "lng": -9.139,
            "country": "Portugal", "exists": "lisbon", "exists_name": "里斯本"}]}
```

最多 8 条，只收有坐标的条目；`exists` / `exists_name` 只在 0.05° 内已有城市时出现（客户端据此「直接跳过去」而不是新加）。`q` 为空 → `{"items": []}`；连不上 → 502 `维基数据没连上：…`。

**`POST /api/place`** · me · 体 `{"qid": "Q597"}`

- 返回：`{"ok": true, "id": "n_Lisbon_38.708", "city": ["里斯本", "Lisbon", 38.708, -9.139, "Portugal"]}`——追加进 `cities.json` 的 `extra`（已在就不重复加）
- 错误：400 `缺维基数据编号`；404 `这个条目没有坐标，加不了`

### 4.12 卡片 / Cards

| 方法 + 路径 | 返回 |
|---|---|
| `GET /api/share/{sid}/card?k=<key>` | 卡片 JSON |
| `GET /card/share/{sid}?k=<key>[&theme=light\|dark]` | 可 iframe 的 HTML（透明底、最宽 360px、整张是指向 `link` 的链接） |
| `GET /api/comment/{cid}/card?k=<key>` | 卡片 JSON |
| `GET /card/comment/{cid}?k=<key>[&theme=…]` | HTML |

钥匙不对、缺失、或编号不存在，一律 403 `卡片钥匙不对`。卡片 JSON：

```json
{"kind": "share", "id": 4, "who": "me", "theme": "light",
 "eyebrow": "STOPOVER · 递给TA", "title": "京都", "subtitle": "整张票 · 2023.04", "body": "给你",
 "image": "https://example.com/api/photo/img/1?w=600&s=…", "link": "https://example.com/?city=kyoto",
 "city": "kyoto", "url": "https://example.com/card/share/4?k=…"}
```

- `theme`：me 发的 `light`，partner 发的 `dark`；`eyebrow`：`STOPOVER · 递给TA` / `STOPOVER · TA递给你` / `STOPOVER · 回TA` / `STOPOVER · TA说`
- 评论卡 `kind: "comment"`，多一个 `target`；`subtitle` 如 `回TA：「…」`、`在这张照片下面说`；挂在照片上时 `image` 是那张照片
- `image` 可能是 `null`；链接在配了 `public_url` 时是绝对地址，否则相对

### 4.13 健康检查 / Health

**`GET /api/health`** → `{"ok": true, "cities": 1621}`（`cities` + `extra` 的总数）

### 4.14 MCP

**`POST /mcp`** · partner · 见 §7。`GET` / `PUT` / `DELETE /mcp` → 405，头 `Allow: POST`。

## 5. 投递流程 / Delivery

**me 递出 / me 回话**

1. `POST /api/share`（me）→ `status: "pending"`；`POST /api/comment`（me）→ 进队列（内部 `sent` 为空）。两者都会唤醒投递线程。
2. **合并窗口**：投递线程每 `max(1, min(30, merge_seconds / 2))` 秒醒一次（或被新东西唤醒）。只有当**所有**待送的递送和未送的话里最新的那一样也已经安静了 `inject.merge_seconds`（默认 120）秒，才把它们一起合成一条——窗口里每来一样新的都会把整批往后推。窗口内 me 可以撤回（`DELETE /api/share/{id}`、`DELETE /api/comment/{id}`）。
3. **配了 `inject.url`**：POST 一条 JSON 过去（`Content-Type: application/json`，附 `inject.headers`，超时 `inject.timeout` 秒）：

```json
{"text": "〔经停 Stopover · 来自我〕\n我递给你 2 样：\n· 京都 · 2023.04 · 从上海出发（t:2）\n  照片 1 张（附了 1 张）：p:1「金阁」\n  → 目录：look t:2　照片：img p:编号\n  我说：给你\n  回这一样：say d:4 \"…\"\n· 京都的景点「清水寺」（图：img s:京都/1）\n  …\n  回这一样：say d:5 \"…\"\n\n我回你的话：\n· 在我递的「京都的整张票」（c:4），回你的「那就定在秋天」：再说一句\n  → 回：say d:4 \"…\" reply_to=c:4",
 "shares":  [{"id": 4, "items": [{"type": "trip", "id": 2}], "note": "给你"},
             {"id": 5, "items": [{"type": "sight", "city": "kyoto", "i": 0}], "note": ""}],
 "images":  ["https://example.com/api/photo/img/1?w=600&s=f24d93d2a2e155b1673a7083059bb46e"],
 "cards":   [{"url": "https://example.com/card/share/4?k=y45sGiKLsbpobT7q", "json": {"kind": "share", "...": "见 §4.12"}},
             {"url": "https://example.com/card/share/5?k=…", "json": {"...": "…"}},
             {"url": "https://example.com/card/comment/4?k=v2AgI0Jwg6JBvJ93", "json": {"kind": "comment", "...": "…"}}],
 "replies": [{"id": 4, "target": "share:4", "where": "我递的「京都的整张票」", "text": "再说一句", "reply_to": 3}]}
```

   - `text` = `inject.template` 套上 `{me}` `{partner}` `{body}` `{n}`（`n` = 递送数 + 话数）；模板里别的 `{xxx}` 原样保留。
   - `images`：trip / photo 的照片（签名链接，§8）+ `img=1` 的 city / sight / food 的维基配图，去重后最多 `inject.max_images`（默认 9）张。
   - `cards`：每样递送一张、每句话一张，顺序同 `shares` + `replies`。
   - 任何 2xx 都算成功。**成功** → 递送 `status: "sent"`，话标为已送，并且都记为已取走（不进收件箱）。
   - **失败** → 记 `err`，保持 pending，下一轮（几秒后）重试一次；**第二次还失败** → 标 `sent` 但不算取走，留在收件箱等 partner 来拉。
4. **没配 `inject.url`**：窗口一过直接标 `sent`，全部进收件箱（`GET /api/partner/inbox`、MCP `inbox`）。
5. 投递给 partner **不会**推送到 me 的设备。

**partner 递出 / partner 回话**：没有合并窗口。递送直接 `status: "sent"`，话直接落库；两者都立即推送给 me（§6）。me 在网页 / App 的「递来的」里看到，点开后客户端调 `PUT /api/share/{id}/read`。

## 6. 推送 / Push

**什么时候推、推给谁**：只推给 **me** 的设备（所有已登记的 Web Push 订阅 + APNs token），触发于 partner 的三种动作：

| 动作 | 正文（`push.title` 作标题，默认 `经停`） | 附带数据 |
|---|---|---|
| partner 留言 | `TA在{位置}下面说：{话}` | `{"route": "stopover", "city": "<城市id或空>", "target": "photo:1"}` |
| partner 递东西 | `TA递来{一座城：京都 / 京都的美食「…」}：{附言}` | `{"route": "stopover", "city": "lisbon", "target": "", "share_id": 6}` |
| partner 点星 | `TA想和你去{城名}：{理由}` | `{"route": "stopover", "city": "kyoto", "target": ""}` |

正文截到 120 字（各字段先截 60）；附言 / 理由为空时不带冒号那段。

**Web Push**

- `GET /api/push/vapid` 拿公钥 → `pushManager.subscribe({userVisibleOnly: true, applicationServerKey})` → `POST /api/push/web`。VAPID 私钥第一次用时生成在 `var/vapid.json`；联系方式 `push.web.vapid_subject`；TTL 86400。推送服务回 404 / 410 时自动删掉该订阅。
- 推送体（JSON 字符串）：`{"title": "经停", "body": "TA在京都下面说：…", "data": {"route": "stopover", "city": "kyoto", "target": "city:kyoto"}}`
- `web/sw.js`：没有 fetch 处理、不做离线缓存。收到推送 → `showNotification(title, {body, icon, data, tag})`，`tag` 优先 `share-<share_id>`，其次 `target`、`city`（同一处的通知会互相替换）。点开 → 已有窗口就 `postMessage({type: "open", city, target, share_id})` 并聚焦（页面收到后重拉 state、打开那座城），否则打开 `./?city=<id>`。网页也认 `#city=<id>` 深链。
- 网页只在 `features.share` 且 `features.push_web` 为真、浏览器支持时显示铃铛。iPhone / iPad 要「添加到主屏幕」后从主屏幕打开才能订阅。

**APNs**（iOS 原生）

- 配置 `push.apns.key_path`（`.p8`）、`key_id`、`team_id`、`bundle_id` 四项都填且文件存在才启用（`features.push_apns` 为真）；iOS 只在它为真、用户在设置里打开时才登记。
- App 拿到 device token 后以十六进制 `POST /api/push/apns {"token", "env"}`。
- 服务端用 ES256 JWT（45 分钟换一次）走 HTTP/2，`apns-push-type: alert`、`apns-priority: 10`、`apns-topic: <bundle_id>`，按每个 token 自己的 `env` 选网关。回 410 或 `Unregistered` / `BadDeviceToken` 时删掉该 token。
- payload：

```json
{"route": "stopover", "city": "lisbon", "target": "", "share_id": 6,
 "aps": {"alert": {"title": "经停", "body": "TA递来里斯本的美食「…」：下次替你尝一口。"}, "sound": "default"}}
```

  App 点开时检查 `route` 以 `stopover` 结尾、有 `city`，就飞到那座城。

## 7. MCP 与 CLI / MCP & CLI

**传输**：`POST /mcp`，streamable HTTP 的**无状态子集**——没有 SSE、没有会话 id，每个请求体是一条 JSON-RPC 2.0 消息或一个批量数组，直接回 JSON。鉴权见 §2（401 / -32001）。

| 情况 | 回应 |
|---|---|
| `initialize` | `{"protocolVersion": <客户端给的，若在 2025-06-18 / 2025-03-26 / 2024-11-05 里，否则 2025-06-18>, "capabilities": {"tools": {"listChanged": false}}, "serverInfo": {"name": "stopover", "version": "2.0"}}` |
| `ping` | `{}` |
| `tools/list` | `{"tools": [{name, description, inputSchema}]}` |
| `tools/call` | `{"content": [{"type": "text", "text"}, 可选 {"type": "image", "data": <base64 JPEG>, "mimeType": "image/jpeg"}], "isError": bool}` |
| 没有 `id` 的消息（通知，如 `notifications/initialized`） | 不回；整批都是通知 → 202 空体 |
| 其它 method | error `-32601 method not found: …` |
| 不是 JSON-RPC 2.0 / 缺 method | error `-32600 invalid request` |
| 体不是 JSON | 400，error `-32700 parse error` |

**工具**（MCP 名 = CLI 命令；也认中文别名 `收件箱/新 看 读 图 说 想去 不想去 清单 递 去过 逛 整理`）：

| 工具 | 参数（必填加粗） | 做什么 |
|---|---|---|
| `inbox` | `peek`: bool | 收件箱；不带 `peek` 时看完即标记已取 |
| `look` | **`ref`** | 目录：城市名 / `t:编号` / `p:编号`（带图）/ `n:编号` / `d:编号` |
| `read` | **`ref`**, `section`: `history`\|`culture`\|`all` | 读全文：城市（先给目录）/ `s:城市/编号` / `f:城市/编号` / `n:编号` |
| `img` | **`ref`** | 看图（≤1024px JPEG）：`p:编号` / 城市名 / `s:` / `f:` |
| `say` | **`to`**, **`text`**, `reply_to` | 留言 / 回复：`to` = `d:` `t:` `n:` `p:` 编号或城市名；`reply_to` = `c:编号` |
| `wish` | **`city`**, `note` | 点亮 partner 的蓝星 |
| `unwish` | **`city`** | 收回 |
| `wishes` | — | 两个人的想去清单 |
| `share` | **`ref`**, `note`, `with_image`: bool | 递给 me：城市名 / `s:` / `f:` |
| `been` | — | me 去过的城（按国家） |
| `wander` | — | 随机一座有资料的城 |
| `gen` | **`city`** | 现场整理一页（走 §4.10 的同一套限制） |

引用写法：`t:` 某一次、`n:` 随记、`p:` 照片、`d:` 递送、`c:` 评论；景点 / 美食 `s:京都/2`、`f:京都/1` 是 **1 起**编号（对应 items 里 `i` 的 0 起下标）。城市名接受中文名、英文名、id、前缀和按序出现的简称；有歧义或是国家名时回 ✗ 并给候选。

**输出约定（省 token）**：写操作只回一行，成功 `✓ …`（如 `✓ c:5`、`✓ 点亮了 → 京都`、`✓ 递给我了 → 里斯本`），失败 `✗ 原因`（`isError: true`，少数「没做成但不算错」的如 `✗ 京都本来就没点` 是 `isError: false`）；读操作给目录，末尾 `——` 后写下一步怎么读。

**CLI**：`cli/stopover.py` 只用标准库，每个命令都是 `POST /api/partner/tool`：

```
→ {"name": "say", "args": {"to": "d:4", "text": "收到", "reply_to": "c:4"}}
← {"ok": true, "text": "✓ c:5"}
← {"ok": true, "text": "✓ p:1", "image": {"mime": "image/jpeg", "data": "<base64>"}}
← {"ok": false, "text": "✗ 没有 nope 这个工具"}
```

## 8. 照片签名与卡片钥匙 / Signed photos & card keys

**照片签名 `s`**

```
secret = var/secret 文件内容（64 位十六进制串，第一次用时生成，0600），按 UTF-8 字节当 HMAC 密钥
s      = hex(HMAC-SHA256(secret, "photo:{pid}:{w}"))[:32]
链接    = {public_url}/api/photo/img/{pid}?w={w}&s={s}
```

签名同时绑定照片编号和 `w`（服务端发出去的都是 `w=600`；改成 `w=1600` 就 403）。用在 webhook 的 `images`、收件箱、卡片的 `image`。不带 `s` 的请求不验签——那是 me 自己的网页 / App 在用，要靠反向代理鉴权保护。重新实现时只要自己发出去的签名能自己验过即可，算法不必一致。

**卡片钥匙 `k`**：每条 share / comment 建立时生成一把随机串（`secrets.token_urlsafe(12)`，16 字符），存在行里，常量时间比较。出现在 `/api/state`（`shares[].key`、`comments[].key`）、webhook 的 `cards[].url`、收件箱里。

**反向代理放行**：只把 `/mcp`、`/api/partner/*`、`/card/*` 和**带 `s=` 的** `/api/photo/img/*` 放给公网，其余套你自己的鉴权——Caddy / nginx 写法见 README「7. 安全 / Security」。

## 9. 重新实现清单 / Re-implementing checklist

**一期：一个人记（必需）**

- 静态托管 `web/`（含 `data/cities.json`、`data/city/*.json`、`sw.js`），且和 `/api` 同源同前缀
- `GET /api/config`——想先不做两个人的部分就回 `features: {"share": false, "push_web": false, "push_apns": false}`
- `GET /api/state`——`comments`、`shares` 可以回 `[]`
- `POST /api/checkin/{city}`、`PUT` / `DELETE /api/trip/{tid}`（含 `reset_children`）
- `POST /api/trip/{tid}/note`、`PUT` / `DELETE /api/note/{nid}`
- `POST /api/trip/{tid}/upload`、`GET /api/photo/img/{pid}?w=`、`PUT` / `DELETE /api/photo/{pid}`
- `PUT` / `DELETE /api/wish/{city}`
- 错误都回 `{"detail": "…"}`

**二期：两个人（`features.share: true` 时需要）**

- `POST` / `DELETE /api/share`、`PUT /api/share/{id}/read`、`POST` / `DELETE /api/comment`
- 投递：合并窗口 + webhook 或收件箱（`GET /api/partner/inbox`）
- partner 鉴权和 403 规则；`/mcp` 或 `/api/partner/tool`（伴侣要能进来）
- 卡片和照片签名（只有给聊天程序发卡片 / 图时才需要）

**可选：不实现时怎样让客户端优雅降级**

| 接口 | 不实现时回什么 | 客户端表现 |
|---|---|---|
| `POST /api/photo/check` | 404 即可 | 网页当作全是新照片照传；iOS 本来不调 |
| `GET /api/city/{id}/gen` | `{"status": "none"}`（或任意非 2xx） | 显示「整理这座城的资料」按钮 |
| `POST /api/city/{id}/gen` | 503 `{"detail": "这个服务器不整理城市资料"}` | 点按钮后 toast 这句 detail |
| `GET /api/place/search` | 502 / 任意非 2xx | 网页和 iOS 都显示「维基数据没连上，过一会儿再试」 |
| `POST /api/place` | 4xx + detail | toast「没加上：…」 |
| 推送四个接口 | `features.push_web` / `push_apns` 回 `false` | 网页不显示铃铛；iOS 不登记 token |
| `/card/*`、`/api/*/card` | 不做 | 只影响外部聊天程序；网页和 iOS 不用 |
| `/api/health` | 不做 | 客户端不用 |

不想支持 partner 时：`features.share: false`，`/mcp`、`/api/partner/*` 都回 401。

---

### 附：已知不一致 / Known mismatches

- 城市 id 里可能有空格和非 ASCII（`n_San Bernardino_34.122`）：客户端拼路径时要做百分号编码（网页用 `encodeURIComponent`），服务端按解码后的路径参数匹配。
