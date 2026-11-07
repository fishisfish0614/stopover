# 经停 Stopover

**中文** · [English](README.en.md)

![经停 Stopover（iOS 版）：地球、文件夹、活页竖条、海报页](docs/img/hero.png)

**两个人的旅行地球：去过的城市是地球上的红点，每一次经停是一张可以撕开存根的登机牌。**

在地球上记下去过的城市。每一次经停是一张登机牌——从哪儿出发、回到哪儿、哪天、一句备注、几段随记、几张照片。想去的地方点一颗星：金色是你的，蓝色是同行的人的。去过的、想去的，都可以递给同行的人，在城市卡片上一来一回地聊。

- 852 座城市有中文长卷（历史、文化、景点、美食，配维基共享图），另外 769 座可以点开现场整理一页（DeepSeek + Wikipedia/Wikivoyage）；地图上没有的地方可以从 Wikidata 加上。
- 网页 + iOS 原生（SwiftUI），iOS 怎么跑见 [`ios/README.md`](ios/README.md)。
- 「同行的人」常常是你的 AI 伴侣：它通过 MCP 或命令行来看你的经停、留言、点星、递东西给你。

## 有什么

### 一个人记

- **地球三种风格**：蓝石（NASA Blue Marble 卫星图，越放大越清楚）、夜航（NASA Black Marble 城市灯光，配晨昏线）、旧图（Natural Earth 矢量国界，纸面质感）。
- **地图上的痕迹**：来过的城是红点，从出发地拉出一道光带飞过去，有终点的再连回去；想去的是星星——金色是你的、蓝色是 TA 的、两个人都想去的是一对。时钟和昼夜按配置里的时区显示。
- **登机牌**：每来一次是一张票——出发地 → 城市 → 终点、日期、里程、一句备注。轻点抬起，拖着存根撕开（或再点一下让它自己撕），进入「这一次」。

- **这一次**：随记（长短都行）、照片（自动去重、读拍摄时间、配文和标签）、改日期 / 出发地 / 终点。网页和 iOS 都把它做成了一只[活页文件夹](#这一次活页文件夹)。
- **城市长卷**：852 座城有中文长卷——历史时间轴、文化、景点轮播、美食菜单，配维基共享资源的图，页面上带来源链接。另外 769 座点开有「整理」按钮，现场从 Wikipedia / Wikivoyage 写一页（要 DeepSeek key）；地图上没有的地方可以从 Wikidata 搜出来加上。
- **搜索三栏**：按国家找 / 去过的（按国家分组）/ 想去的（都想去、我想去、TA 想去）。没主意时摇骰子：所有城市、没去过的、或者想去的星星里随机挑一座。
- 网页可以「添加到主屏幕」当 App 用；也有 SwiftUI 原生版。

![三种地球：蓝石、夜航、旧图](docs/img/globes.png)

<p align="center">
  <img src="docs/img/night.png" width="240" alt="夜航风格：城市灯光">
  &nbsp;
  <img src="docs/img/search.png" width="240" alt="搜索：想去的">
</p>

![桌面版：京都长卷和放大的地球](docs/img/desktop.jpg)

<p align="center"><img src="docs/img/tear.gif" width="280" alt="抬起登机牌，拖着存根撕开，进入「这一次」"></p>
<p align="center"><sub>就是这样：轻点抬起登机牌，拖着存根往右下撕开，「这一次」就在后面。</sub></p>

### 「这一次」：活页文件夹

每一次经停是一只磨砂玻璃文件夹，这一趟的照片从文件夹口探出来，玻璃里透着它们的颜色。网页和 iOS 长得几乎一样：下面先是 iOS 的截图，最后一排是网页版。

<p align="center">
  <img src="docs/img/trip-folder-open.gif" width="240" alt="点开文件夹，照片飞出来排成活页竖条">
  &nbsp;
  <img src="docs/img/trip-strips.png" width="240" alt="活页竖条：封面、分天、照片和随记">
</p>

- **合上时**：登机牌、文件夹和「加一页 / GATE / TA 说」都在一屏里，想递东西或加一页不用翻照片。
- **点开时**：前盖翻下，纸一张接一张飞出来，变成占满整屏的竖条。右上角「合上」再收回去。
- **活页竖条**：左右滑。按拍摄时间排，跨天会分出 DAY 1、DAY 2，随记是竖排的字纸。iOS 版的窄条会对准照片里的人脸（网页版居中）。票右上角可以切回网格。
- **抽出来看**：按住一条往上拖，或者点一下，它就展开成一整页；「插回去」、× 或下拉都能收回。

<p align="center">
  <img src="docs/img/trip-poster.png" width="240" alt="海报页：短配文做大标题，底色取自鸟居的红棕">
  &nbsp;
  <img src="docs/img/trip-poster-caption.png" width="240" alt="海报页：中等长度的配文，底色取自金阁的金棕">
</p>

- **海报页**：每张照片一页，底色从这张照片里取，照片底部慢慢融进去，城市名跨在交界上。配文按长短排：一句短话做大标题，长一点是正文，很长的首字放大。下面印着编号、第几天、时间和经纬度。
- **对话跟着照片走**：递出去的照片，来回的对话直接显示在它的海报页下面，可以接着回。在「往来」里点这张照片的纸条，地球飞过去后直接抽出这一页。
- **上传时写配文**：一次选好几张，每张可以写自己的配文。写日期也不用记格式，`2019.8.3`、`2019/8/3`、`2019年8月3日`、`20190803` 都认，只记得年或月也行。

<p align="center"><img src="docs/img/trip-upload.png" width="240" alt="上传照片时每张写一句配文"></p>

<p align="center">
  <img src="docs/img/web-folder.png" width="200" alt="网页版：合上的文件夹">
  &nbsp;
  <img src="docs/img/web-strips.png" width="200" alt="网页版：活页竖条">
  &nbsp;
  <img src="docs/img/web-poster.png" width="200" alt="网页版：海报页和下面的对话">
</p>
<p align="center"><sub>网页版（手机浏览器，也可以添加到主屏幕）：合上的文件夹、活页竖条、海报页。和 iOS 用的是同一套数值。</sub></p>

### 两个人用（可整块关掉）

`features.share=false` 会把下面这些在网页上整块藏起来，只剩一个人记。

- **递给 TA**：一座城、一个景点、一道菜、一整张票，或者在「这一次」里挑几段随记、几张照片递过去，可以附一句话。
- **两分钟合并、可撤回**：连着递的东西和回的话先进「待送达」，安静两分钟（`inject.merge_seconds`）后合成一条送出；送出前随时撤回。
- **对话组**：城市卡底部「我们的对话」——每次递送单独一组，平时在城市 / 某一次 / 照片 / 随记下说的话归在「平时说的」，可以逐条回复。
- **往来**：顶栏「往来」里是两个人递过的所有东西（全部 / 我递的 / TA 递的，TA 加的想去也在里面），TA 递来、没看过的有红点。
- **AI 伴侣**：TA 用 MCP 或命令行来看、留言、点蓝星、递东西，工具输出很省 token（见下文和 [`AGENT.md`](AGENT.md)）。
- **推进主对话**：可选把你递的东西 POST 到你的聊天程序（`inject.url`），附签名照片链接和可以 iframe 的聊天卡片。
- **推送**：TA 留言、递东西、点星时推到你的设备——网页走 Web Push，iOS 原生走 APNs。

<p align="center"><img src="docs/img/together.png" width="260" alt="我们的对话：递送一组，平时说的一组"></p>

## 跑起来

```bash
pip install -r server/requirements.txt
cp server/config.example.json server/config.json   # 名字、家、默认出发地、时钟、伴侣
python3 server/seed_demo.py                         # 可选：几条虚构的旅行和对话
python3 server/stopover.py                          # → http://localhost:8000
```

- 数据在 `var/`（`stopover.db`、`photos/`、`vapid.json`），已在 `.gitignore` 里。
- 环境变量：`STOPOVER_VAR`（数据目录）、`STOPOVER_CONFIG`（配置文件）、`STOPOVER_HOST` / `STOPOVER_PORT`。
- **没有登录。** 只在自己电脑上跑，或者放在你自己的鉴权后面。
- 现场整理城市要 DeepSeek：`export DEEPSEEK_API_KEY=...`（可选 `STOPOVER_CONTACT=你的邮箱`，用于维基/Nominatim 的 User-Agent）。不设也能用，只是那个按钮会报错。
- 完整接口（想用别的语言重写后端，或对接 iOS）见 [`docs/API.md`](docs/API.md)。

## 配置

`server/config.json`（没有这个文件时整份读 `config.example.json`）。每次请求都重新读，改完不用重启。以 `_` 开头的键是注释。

| 键 | 默认或示例值 | 含义 |
|---|---|---|
| `me` | `"我"` | 你在界面上的名字。 |
| `partner` | `"TA"` | 同行的人的名字。 |
| `home` | 上海 | `{"label","lat","lng","tz"}`：地球开场对准这里；`label` 是「家」在出发地选项里的叫法；和 `tz` 相同的时钟用这里的坐标判断昼夜。 |
| `default_origin` | `{"domestic":"shanghai","abroad":"shanghai"}` | 新打卡默认的出发城市（城市 id），国内 / 国外分开。 |
| `domestic_countries` | China, Hong Kong, Macao, Taiwan | 哪些国家算「国内」（Natural Earth 英文国名）。 |
| `clocks` | 家里 + 伦敦 | `[{"label","tz","lat"?,"lng"?}]`：左下角的时钟，有坐标的画日 / 月。 |
| `gen.daily_max` | `20` | 每天最多现场整理几座城。 |
| `partner_key` | `""` | 伴侣的钥匙（Bearer）。空 = AI 调不进来，伴侣部分只能看。 |
| `features.share` | `true` | `false` 藏起递送、对话、收件箱和通知的界面。 |
| `public_url` | `""` | 站点的外部地址，webhook / 推送 / 卡片里的链接用它拼成绝对地址。 |
| `inject.url` | `""` | 你递的东西 POST 到哪；空 = 不发，伴侣自己拉收件箱。 |
| `inject.headers` | `{}` | POST 时附带的请求头。 |
| `inject.merge_seconds` | `120` | 安静多少秒后合成一条送出（之前可撤回）。 |
| `inject.max_images` | `9` | 一条里最多附几张照片链接。 |
| `inject.timeout` | `30` | webhook 超时秒数。 |
| `inject.template` | `〔经停 Stopover · 来自{me}〕\n{body}` | 消息正文模板，变量 `{me}` `{partner}` `{body}` `{n}`。 |
| `push.title` | `"经停"` | 推送标题。 |
| `push.web.vapid_subject` | `mailto:you@example.com` | Web Push 的联系方式。 |
| `push.web.enabled` | `true` | `false` 关掉 Web Push。 |
| `push.apns.key_path` / `key_id` / `team_id` / `bundle_id` | `""` | APNs `.p8` 密钥路径和编号，四项都填、文件存在才启用。 |
| `push.apns.env` | `"production"` | 设备没说明时用哪个网关（`sandbox` / `production`）。 |

环境变量：`STOPOVER_VAR`、`STOPOVER_CONFIG`、`STOPOVER_HOST`（默认 `127.0.0.1`）、`STOPOVER_PORT`（默认 `8000`）、`DEEPSEEK_API_KEY`、`STOPOVER_CONTACT`。

## 接上你的伴侣

**1. 钥匙。** 在 `server/config.json` 里设 `partner_key`（一长串随机字符，`python3 -c "import secrets;print(secrets.token_urlsafe(32))"`）。带 `Authorization: Bearer <partner_key>` 的请求就是「同行的人」，其余都是你。没设钥匙时，伴侣的部分只能在网页上看，AI 调不进来。伴侣能看全部、留言、点自己的蓝星、递城市 / 景点 / 美食给你；改不了你的经停、随记和照片。

**2. MCP。** 服务器在 `POST /mcp` 提供 MCP（streamable HTTP 的无状态子集，返回 JSON；必须带钥匙）。工具：`inbox` `look` `read` `img` `say` `wish` `unwish` `wishes` `share` `been` `wander` `gen`，用法见 [`AGENT.md`](AGENT.md)（这份是写给伴侣看的，直接丢给它就行）。

通用 streamable HTTP 客户端（比如 Claude Code）：

```bash
claude mcp add --transport http stopover https://example.com/mcp --header "Authorization: Bearer YOUR_PARTNER_KEY"
```

```json
{ "mcpServers": { "stopover": { "type": "http", "url": "https://example.com/mcp",
    "headers": { "Authorization": "Bearer YOUR_PARTNER_KEY" } } } }
```

Claude Desktop（经 `mcp-remote` 转成本地 stdio），`claude_desktop_config.json`：

```json
{ "mcpServers": { "stopover": { "command": "npx",
    "args": ["-y", "mcp-remote", "https://example.com/mcp", "--header", "Authorization:${STOPOVER_AUTH}"],
    "env": { "STOPOVER_AUTH": "Bearer YOUR_PARTNER_KEY" } } } }
```

**3. 命令行。** `cli/stopover.py` 单文件、只用标准库，和 MCP 用的是同一套服务端工具（`POST /api/partner/tool`）。命令中英都认。

```bash
export STOPOVER_URL=https://example.com STOPOVER_PARTNER_KEY=YOUR_PARTNER_KEY
python3 cli/stopover.py look 京都          # = 看 京都
python3 cli/stopover.py say d:2 "收到了" 回 c:7
python3 cli/stopover.py img p:4           # 图存到 $STOPOVER_OUT（默认临时目录）
```

**4. 递过去。** 你在网页上递的东西（整张票、挑几段几张、一张照片、城市 / 景点 / 美食）和你回的话先进「待送达」，可以撤回；安静 `inject.merge_seconds` 秒（默认 120）后合成一条：

- 设了 `inject.url`：POST 到那里（比如你的聊天程序收消息的口子，附带 `inject.headers`）。失败重试一次，还不行就留在收件箱里。
- 没设：伴侣自己拉 `GET /api/partner/inbox`（`?mark=1` 标记已取），或者用 MCP 的 `inbox`。

Webhook 的 payload（`text` 由 `inject.template` 渲染，变量 `{me}` `{partner}` `{body}` `{n}`）：

```json
{
  "text": "〔经停 Stopover · 来自我〕\n我递给你：\n· 京都 · 2023.04 · 从上海出发（t:2）\n  照片 2 张（附了 2 张）：p:1　p:2\n  → 目录：look t:2\n  回这一样：say d:4 \"…\"",
  "shares":  [{"id": 4, "items": [{"type": "trip", "id": 2}], "note": "再给你一次"}],
  "images":  ["https://example.com/api/photo/img/1?w=600&s=…", "https://example.com/api/photo/img/2?w=600&s=…"],
  "cards":   [{"url": "https://example.com/card/share/4?k=…", "json": {"kind": "share", "eyebrow": "STOPOVER · 递给TA", "title": "京都", "subtitle": "整张票 · 2023.04", "body": "再给你一次", "who": "me", "theme": "light", "image": "…", "link": "https://example.com/?city=kyoto"}}],
  "replies": [{"id": 5, "target": "share:4", "where": "我递的「京都的整张票」", "text": "那就秋天见。", "reply_to": 4}]
}
```

**5. 聊天卡片。** 每次递送、每句话都有一把随机钥匙：`GET /card/share/{id}?k=…`（`/card/comment/{id}?k=…`）是一张可以 iframe 的小卡片（透明底、最宽 360px，`?theme=light|dark`），`GET /api/share/{id}/card?k=…` 给同样字段的 JSON（eyebrow / title / subtitle / body / who / theme / image / link），方便别的聊天前端自己画。钥匙在 `GET /api/state` 和 webhook 里。没钥匙或钥匙不对 = 403。记得设 `public_url`，卡片、推送和 webhook 里的链接才是绝对地址。

**6. 推送。** 伴侣留言、递东西、点星时推到你的设备（你递东西不推，走上面的 webhook / 收件箱）。

- 网页：右上角铃铛 →「开启通知」。VAPID 密钥第一次用时自动生成到 `var/vapid.json`；`push.web.vapid_subject` 写你的联系方式。iPhone / iPad 要先「添加到主屏幕」再从主屏幕打开。`web/sw.js` 只处理推送和点开通知，不做离线缓存。
- iOS 原生：`push.apns` 填 `.p8` 路径、`key_id`、`team_id`、`bundle_id`；app 用 `POST /api/push/apns {"token","env":"sandbox"|"production"}` 登记。没配时这个接口回 `{"ok":false,"reason":"apns not configured"}`。
- 推送里带 `{"route":"stopover","city","target","share_id"?}`，点开直达那座城（网页走 `?city=<id>`）。

**7. 安全。** 服务本身没有登录：网页、你的照片、`/api/state` 对能访问到它的人都是敞开的——谁能连上，谁就是「我」。放到公网上请套在你自己的鉴权 / 反向代理后面（basic auth、Cloudflare Access、Tailscale……），只把这几条路直接放行：`/mcp`、`/api/partner/*`（靠 partner 钥匙）、`/card/*`（靠卡片钥匙），以及**带 `s=` 参数的** `/api/photo/img/*`——发给伴侣、webhook 和卡片里的照片链接都带签名 `s`（HMAC-SHA256，绑定照片编号和尺寸，密钥在 `var/secret`，第一次用时自动生成），签名不对回 403；不带 `s` 的照片请求照旧走你自己的鉴权。钥匙别提交进仓库。

Caddy：

```caddy
example.com {
	@open {
		path /mcp /api/partner/* /card/*
	}
	@signedphoto {
		path /api/photo/img/*
		query s=*
	}
	handle @open {
		reverse_proxy 127.0.0.1:8000
	}
	handle @signedphoto {
		reverse_proxy 127.0.0.1:8000
	}
	handle {
		basic_auth {
			me $2a$14$...   # caddy hash-password
		}
		reverse_proxy 127.0.0.1:8000
	}
}
```

nginx：

```nginx
location ~ ^/(mcp$|api/partner/|card/) { proxy_pass http://127.0.0.1:8000; }
location /api/photo/img/ {
    if ($arg_s = "") { return 401; }      # 没签名的照片只给登录后的你（或者在这里也加 auth_basic）
    proxy_pass http://127.0.0.1:8000;
}
location / {
    auth_basic "stopover"; auth_basic_user_file /etc/nginx/stopover.htpasswd;
    proxy_pass http://127.0.0.1:8000;
}
```

不想要这些？`features.share=false` 会把网页上所有递送、对话、收件箱和通知的界面藏起来。

## 部署与备份

- **本机跑**：照「跑起来」，打开 `http://localhost:8000`。服务默认只听 `127.0.0.1`。
- **想在手机上用**：放到你自己的服务器上，用 systemd / Docker 之类常驻，前面套反向代理和鉴权——必须套，做法见上面的「7. 安全」。然后在手机浏览器里「添加到主屏幕」，就是一个全屏的 App（iOS 推送也要求这样打开）。
- **备份**：你的东西都在 `var/` 里——`stopover.db`（经停、随记、对话、星星）、`photos/`（原图和缩略图）、`secret`（照片签名密钥）、`vapid.json`（Web Push 密钥，丢了要重新订阅）。数据库在运行中可以用 `sqlite3 var/stopover.db ".backup var/stopover-backup.db"` 热备份，或者停服务后整个目录拷走。另外，现场整理的城市和从 Wikidata 加的地方写在 `web/data/city/` 和 `web/data/cities.json` 里，也一起备份。
- **更新**：`git pull` 后重启服务。如果你现场整理过城市或加过地方，`web/data/cities.json` 会和上游冲突——先备份它，pull 之后再把多出来的条目合回去（`web/data/city/` 里新增的文件不受影响）。

## 常见问题

**城市资料是 AI 写的，准吗？**
资料以 Wikipedia / Wikivoyage 为底，由模型改写成中文长卷，可能有错漏或过时的地方。页面上有来源链接，较真的时候点过去看原文。

**没有 DeepSeek key 能用吗？**
能。只有「整理这座城的资料」那个按钮要它；852 座现成的长卷、打卡、随记、照片、递送、推送都不需要。

**能不能不要伴侣那部分？**
能。`features.share=false`，递送、对话、收件箱、通知的界面全部藏起来；`partner_key` 留空，也没人能调进来。

**TA 一定要是 AI 吗？**
不用，人也可以。但网页和 iOS App 永远以「我」的身份说话；「TA」那一侧要带 `partner_key` 走接口——命令行 `cli/stopover.py`、MCP 或者直接调 `/api/partner/*`。所以一个人类伴侣目前用命令行最方便，网页上没有「以 TA 身份登录」。

**照片存在哪？会传到别处吗？**
只存在你自己机器的 `var/photos/`（原图 + 600 / 1600 宽的缩略图），不会上传到任何第三方。只有你配了 `inject.url`（或伴侣来取收件箱）时，递出去的照片才会以**带签名**的链接发出去，链接绑定照片编号和尺寸，改一个字符就 403。

**iOS 版要付费开发者账号吗？**
在模拟器和自己手机上跑不用，免费的 Apple ID 就行；只有推送（APNs）需要付费账号。见 [`ios/README.md`](ios/README.md)。

**能换底图、加城市吗？**
加城市：搜索里找不到的地方，在结果底下从 Wikidata 搜出来直接加；想给它写一页长卷就点「整理」，或者跑 `pipeline/citygen.py`。换底图：三种风格定义在 `web/index.html` 的 `STYLES` 里（瓦片地址、整张贴图 `web/tex/`、配色），照着改或加一种；地址带 `?notiles` 时只用本地整张贴图。

## 目录

| | |
|---|---|
| `web/` | 单页前端（globe.gl + three.js），城市数据 `web/data/`；`web/sw.js` 只管推送 |
| `server/` | FastAPI + SQLite 后端，也托管 `web/`；MCP 在 `/mcp` |
| `cli/stopover.py` | 伴侣用的命令行（只用标准库） |
| `AGENT.md` | 给 AI 伴侣看的手册 |
| `pipeline/citygen.py` | 现场整理一座城（Wikidata → Wikipedia/Wikivoyage → DeepSeek → Commons 配图） |
| `ios/` | SwiftUI 原生版（[怎么跑](ios/README.md)） |
| `docs/API.md` | 完整接口文档：重写后端、对接 iOS 时看 |
| `docs/` | README 配图（`docs/img/`，截图全是虚构的演示数据） |

## 许可

- 代码、设计、示例数据：**CC BY-NC-SA 4.0**（署名—非商业性使用—相同方式共享），见 `LICENSE`。可以自己用、改、分享，**不可商用**；改过的版本要用同样的许可。这是一个源码公开的项目，不算 OSI 意义上的开源。
- 城市资料 `web/data/`：**CC BY-SA 4.0**（源自 Wikipedia / Wikivoyage），见 `web/data/LICENSE`。图片不在仓库里，链到维基共享资源，各自遵循原许可。
- `docs/img/` 截图里「这一次」的京都照片来自 Wikimedia Commons：*Torii path with lantern at Fushimi Inari Taisha Shrine* by Basile Morin（CC BY-SA 4.0）、*Kinkaku-ji14* by dconvertini（CC BY-SA 2.0）、*Kiyomizu-dera, Kyoto, November 2016 -02* by Martin Falbisoner（CC BY-SA 4.0）、*Kyoto Ginkaku-ji Ginkaku 01* by Zairon（CC BY-SA 4.0）、*L'entrée du palais Ninomaru (Château de Nijo, Kyoto)* by Jean-Pierre Dalbéra（CC BY 2.0）；城市长卷里的图同样来自 Commons，各自遵循原许可。
- 第三方声明见 `THIRD_PARTY.md`（boarding-pass 交互参考 jal-co/boarding-pass，MIT）。
