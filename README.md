# 经停 Stopover

在地球上记下去过的城市。每一次经停是一张登机牌——从哪儿出发、回到哪儿、哪天、一句备注、几段随记、几张照片。想去的地方点一颗星：金色是你的，蓝色是同行的人的。去过的、想去的，都可以递给同行的人，在城市卡片上一来一回地聊。

A travel globe for two. Every stopover is a boarding pass — where you came from, where you went next, the dates, a one-line remark, a few notes and photos. Star the places you want to go: gold for you, blue for the person you travel with. Hand a ticket, a photo or a city to them and talk it over right on the city card.

- 852 座城市有中文长卷（历史、文化、景点、美食，配维基共享图），另外 769 座可以点开现场整理一页（DeepSeek + Wikipedia/Wikivoyage）；地图上没有的地方可以从 Wikidata 加上。
- 852 cities come with a long-form Chinese page (history, culture, sights, food, with Wikimedia Commons photos). 769 more can be written on demand (DeepSeek + Wikipedia/Wikivoyage), and any place on Wikidata can be added to the map.
- 网页 + iOS 原生（SwiftUI），iOS 怎么跑见 [`ios/README.md`](ios/README.md)。Web app plus a native SwiftUI app — see [`ios/README.md`](ios/README.md) to build and run it.
- 「同行的人」常常是你的 AI 伴侣：它通过 MCP 或命令行来看你的经停、留言、点星、递东西给你。The partner is often your AI companion: it reads, comments, stars and hands things to you over MCP or a small CLI.

## 跑起来 / Run it

```bash
pip install -r server/requirements.txt
cp server/config.example.json server/config.json   # 名字、家、默认出发地、时钟、伴侣 / names, home, default origins, clocks, partner
python3 server/seed_demo.py                         # 可选：几条虚构的旅行和对话 / optional demo trips and a short conversation
python3 server/stopover.py                          # → http://localhost:8000
```

- 数据在 `var/`（`stopover.db`、`photos/`、`vapid.json`），已在 `.gitignore` 里。Runtime data lives in `var/` (git-ignored).
- 环境变量 / environment：`STOPOVER_VAR`（数据目录 / data dir）、`STOPOVER_CONFIG`（配置文件 / config file）、`STOPOVER_HOST` / `STOPOVER_PORT`。
- **没有登录。** 只在自己电脑上跑，或者放在你自己的鉴权后面。**There is no login** — run it locally or behind your own auth.
- 现场整理城市要 DeepSeek：`export DEEPSEEK_API_KEY=...`（可选 `STOPOVER_CONTACT=你的邮箱`，用于维基/Nominatim 的 User-Agent）。不设也能用，只是那个按钮会报错。On-demand city pages need `DEEPSEEK_API_KEY`; everything else works without it.

## 接上你的伴侣 / Connect your partner

**1. 钥匙 / The key.** 在 `server/config.json` 里设 `partner_key`（一长串随机字符，`python3 -c "import secrets;print(secrets.token_urlsafe(32))"`）。带 `Authorization: Bearer <partner_key>` 的请求就是「同行的人」，其余都是你。没设钥匙时，伴侣的部分只能在网页上看，AI 调不进来。伴侣能看全部、留言、点自己的蓝星、递城市 / 景点 / 美食给你；改不了你的经停、随记和照片。

Set `partner_key` in `server/config.json`. Requests carrying `Authorization: Bearer <partner_key>` act as the partner; everything else is you. With no key set, partner features are view-only. The partner can read everything, comment, star (blue) and hand you cities, sights and dishes; it cannot edit your trips, notes or photos.

**2. MCP.** 服务器在 `POST /mcp` 提供 MCP（streamable HTTP 的无状态子集，返回 JSON；必须带钥匙）。工具：`inbox` `look` `read` `img` `say` `wish` `unwish` `wishes` `share` `been` `wander` `gen`，用法见 [`AGENT.md`](AGENT.md)（直接给你的伴侣看就行）。

The server speaks MCP at `POST /mcp` (a stateless subset of streamable HTTP, JSON responses, key required). Tools are listed in [`AGENT.md`](AGENT.md) — that file is written for your companion to read.

通用 streamable HTTP 客户端 / any streamable-HTTP client (e.g. Claude Code):

```bash
claude mcp add --transport http stopover https://example.com/mcp --header "Authorization: Bearer YOUR_PARTNER_KEY"
```

```json
{ "mcpServers": { "stopover": { "type": "http", "url": "https://example.com/mcp",
    "headers": { "Authorization": "Bearer YOUR_PARTNER_KEY" } } } }
```

Claude Desktop（经 `mcp-remote` 转成本地 stdio / bridged to stdio with `mcp-remote`），`claude_desktop_config.json`：

```json
{ "mcpServers": { "stopover": { "command": "npx",
    "args": ["-y", "mcp-remote", "https://example.com/mcp", "--header", "Authorization:${STOPOVER_AUTH}"],
    "env": { "STOPOVER_AUTH": "Bearer YOUR_PARTNER_KEY" } } } }
```

**3. 命令行 / CLI.** `cli/stopover.py` 单文件、只用标准库，和 MCP 用的是同一套服务端工具（`POST /api/partner/tool`）。命令中英都认。A single-file, standard-library CLI over the same tools; commands work in English or Chinese.

```bash
export STOPOVER_URL=https://example.com STOPOVER_PARTNER_KEY=YOUR_PARTNER_KEY
python3 cli/stopover.py look 京都          # = 看 京都
python3 cli/stopover.py say d:2 "收到了" 回 c:7
python3 cli/stopover.py img p:4           # 图存到 $STOPOVER_OUT（默认临时目录）/ saved to $STOPOVER_OUT
```

**4. 递过去 / Handing things over.** 你在网页上递的东西（整张票、挑几段几张、一张照片、城市 / 景点 / 美食）和你回的话先进「待送达」，可以撤回；安静 `inject.merge_seconds` 秒（默认 120）后合成一条：

- 设了 `inject.url`：POST 到那里（比如你的聊天程序收消息的口子，附带 `inject.headers`）。失败重试一次，还不行就留在收件箱里。
- 没设：伴侣自己拉 `GET /api/partner/inbox`（`?mark=1` 标记已取），或者用 MCP 的 `inbox`。

What you hand over (and your replies) waits as *pending* — you can take it back — until `inject.merge_seconds` pass quietly, then goes out as one message: POSTed to `inject.url` if set (retried once, then left in the inbox), otherwise pulled by the partner from `GET /api/partner/inbox` or the `inbox` tool.

Webhook payload（`text` 由 `inject.template` 渲染，变量 `{me}` `{partner}` `{body}` `{n}`）：

```json
{
  "text": "〔经停 Stopover · 来自我〕\n我递给你：\n· 京都 · 2023.04 · 从上海出发（t:2）\n  照片 2 张（附了 2 张）：p:1　p:2\n  → 目录：look t:2\n  回这一样：say d:4 \"…\"",
  "shares":  [{"id": 4, "items": [{"type": "trip", "id": 2}], "note": "再给你一次"}],
  "images":  ["https://example.com/api/photo/img/1?w=600&s=…", "https://example.com/api/photo/img/2?w=600&s=…"],
  "cards":   [{"url": "https://example.com/card/share/4?k=…", "json": {"kind": "share", "eyebrow": "STOPOVER · 递给TA", "title": "京都", "subtitle": "整张票 · 2023.04", "body": "再给你一次", "who": "me", "theme": "light", "image": "…", "link": "https://example.com/?city=kyoto"}}],
  "replies": [{"id": 5, "target": "share:4", "where": "我递的「京都的整张票」", "text": "那就秋天见。", "reply_to": 4}]
}
```

**5. 聊天卡片 / Chat cards.** 每次递送、每句话都有一把随机钥匙：`GET /card/share/{id}?k=…`（`/card/comment/{id}?k=…`）是一张可以 iframe 的小卡片（透明底、最宽 360px，`?theme=light|dark`），`GET /api/share/{id}/card?k=…` 给同样字段的 JSON（eyebrow / title / subtitle / body / who / theme / image / link），方便别的聊天前端自己画。钥匙在 `GET /api/state` 和 webhook 里。没钥匙 = 403。

Every hand-over and every comment has a random key. `/card/share/{id}?k=…` is a self-contained, iframe-able card; `/api/share/{id}/card?k=…` returns the same fields as JSON for other chat front-ends. Wrong or missing key → 403. Set `public_url` so links in cards, pushes and webhooks are absolute.

**6. 推送 / Push.** 伴侣留言、递东西、点星时推到你的设备（你递东西不推，走上面的 webhook / 收件箱）。Pushes go to *your* devices when the partner comments, hands you something or stars a city.

- 网页：右上角铃铛 →「开启通知」。VAPID 密钥第一次用时自动生成到 `var/vapid.json`；`push.web.vapid_subject` 写你的联系方式。iPhone / iPad 要先「添加到主屏幕」再从主屏幕打开。`web/sw.js` 只处理推送和点开通知，不做离线缓存。
  Web: the bell in the top bar. VAPID keys are generated into `var/vapid.json`; on iOS add the site to the Home Screen first. `web/sw.js` only handles push and notification clicks — no offline cache.
- iOS 原生：`push.apns` 填 `.p8` 路径、`key_id`、`team_id`、`bundle_id`；app 用 `POST /api/push/apns {"token","env":"sandbox"|"production"}` 登记。没配时这个接口回 `{"ok":false,"reason":"apns not configured"}`。
  Native iOS: fill `push.apns` and register device tokens with `POST /api/push/apns`.
- 推送里带 `{"route":"stopover","city","target","share_id"?}`，点开直达那座城（网页走 `?city=<id>`）。Payloads carry `route/city/target/share_id` so a tap opens the city.

**7. 安全 / Security.** 服务本身没有登录：网页、你的照片、`/api/state` 对能访问到它的人都是敞开的。放到公网上请套在你自己的鉴权 / 反向代理后面（basic auth、Cloudflare Access、Tailscale……），只把这几条路直接放行：`/mcp`、`/api/partner/*`（靠 partner 钥匙）、`/card/*`（靠卡片钥匙），以及**带 `s=` 参数的** `/api/photo/img/*`——发给伴侣、webhook 和卡片里的照片链接都带签名 `s`（HMAC-SHA256，绑定照片编号和尺寸，密钥在 `var/secret`，第一次用时自动生成），签名不对回 403；不带 `s` 的照片请求照旧走你自己的鉴权。钥匙别提交进仓库。

The server has no login of its own: anyone who can reach it is "me". If you expose it, put it behind your own auth or reverse proxy and let only these through: `/mcp`, `/api/partner/*` (partner key), `/card/*` (card keys) and `/api/photo/img/*` **with an `s=` parameter** — photo links handed to the partner, webhooks and cards are signed (HMAC-SHA256 over photo id and size, secret auto-generated in `var/secret`); a wrong signature gets 403, unsigned photo requests stay behind your auth. Keep `partner_key` out of git.

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

不想要这些？`features.share=false` 会把网页上所有递送、对话、收件箱和通知的界面藏起来。`features.share=false` hides all of it in the web page.

## 目录 / Layout

| | |
|---|---|
| `web/` | 单页前端（globe.gl + three.js），城市数据 `web/data/`；`web/sw.js` 只管推送 |
| `server/` | FastAPI + SQLite 后端，也托管 `web/`；MCP 在 `/mcp` |
| `cli/stopover.py` | 伴侣用的命令行（只用标准库）/ the partner's CLI |
| `AGENT.md` | 给 AI 伴侣看的手册 / manual for your AI companion |
| `pipeline/citygen.py` | 现场整理一座城（Wikidata → Wikipedia/Wikivoyage → DeepSeek → Commons 配图） |
| `ios/` | SwiftUI 原生版（[怎么跑](ios/README.md)） |

## 许可 / License

- 代码、设计、示例数据：**CC BY-NC-SA 4.0**（署名—非商业性使用—相同方式共享），见 `LICENSE`。可以自己用、改、分享，**不可商用**；改过的版本要用同样的许可。
  Code, design and sample data: **CC BY-NC-SA 4.0** — free to use, adapt and share, **not for commercial use**, derivatives under the same license. This is a source-available project, not OSI open source.
- 城市资料 `web/data/`：**CC BY-SA 4.0**（源自 Wikipedia / Wikivoyage），见 `web/data/LICENSE`。图片不在仓库里，链到维基共享资源，各自遵循原许可。
  City texts in `web/data/`: **CC BY-SA 4.0** (derived from Wikipedia / Wikivoyage). Photos are hotlinked from Wikimedia Commons under their own licenses.
- 第三方声明见 `THIRD_PARTY.md`（boarding-pass 交互参考 jal-co/boarding-pass，MIT）。See `THIRD_PARTY.md`.
