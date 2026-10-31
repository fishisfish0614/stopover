# 经停 Stopover

在地球上记下去过的城市。每一次经停是一张登机牌——从哪儿出发、回到哪儿、哪天、一句备注、几段随记、几张照片。想去的地方点一颗星：金色是你的，蓝色是同行的人的。

A travel globe for two. Every stopover is a boarding pass — where you came from, where you went next, the dates, a one-line remark, a few notes and photos. Star the places you want to go: gold for you, blue for the person you travel with.

- 852 座城市有中文长卷（历史、文化、景点、美食，配维基共享图），另外 769 座可以点开现场整理一页（DeepSeek + Wikipedia/Wikivoyage）；地图上没有的地方可以从 Wikidata 加上。
- 852 cities come with a long-form Chinese page (history, culture, sights, food, with Wikimedia Commons photos). 769 more can be written on demand (DeepSeek + Wikipedia/Wikivoyage), and any place on Wikidata can be added to the map.
- 网页 + iOS 原生（SwiftUI，见 `ios/`）。Web app plus a native SwiftUI app (`ios/`).

## 跑起来 / Run it

```bash
pip install -r server/requirements.txt
cp server/config.example.json server/config.json   # 名字、家、默认出发地、时钟 / names, home, default origins, clocks
python3 server/seed_demo.py                         # 可选：几条虚构的旅行 / optional demo trips
python3 server/stopover.py                          # → http://localhost:8000
```

- 数据在 `var/`（`stopover.db` 和 `photos/`），已在 `.gitignore` 里。Runtime data lives in `var/` (git-ignored).
- **没有登录。** 只在自己电脑上跑，或者放在你自己的鉴权后面。**There is no login** — run it locally or behind your own auth.
- 现场整理城市要 DeepSeek：`export DEEPSEEK_API_KEY=...`（可选 `STOPOVER_CONTACT=你的邮箱`，用于维基/Nominatim 的 User-Agent）。不设也能用，只是那个按钮会报错。On-demand city pages need `DEEPSEEK_API_KEY`; everything else works without it.
- 「同行的人」的星星和随记可以直接调接口写（`PUT /api/wish/{city}` `{"by":"partner"}`），比如交给你的 AI 伙伴。The partner's stars can be written through the API, e.g. by an AI companion.

## 目录 / Layout

| | |
|---|---|
| `web/` | 单页前端（globe.gl + three.js），城市数据 `web/data/` |
| `server/` | FastAPI + SQLite 后端，也托管 `web/` |
| `pipeline/citygen.py` | 现场整理一座城（Wikidata → Wikipedia/Wikivoyage → DeepSeek → Commons 配图） |
| `ios/` | SwiftUI 原生版 |

## 许可 / License

- 代码、设计、示例数据：**CC BY-NC-SA 4.0**（署名—非商业性使用—相同方式共享），见 `LICENSE`。可以自己用、改、分享，**不可商用**；改过的版本要用同样的许可。
  Code, design and sample data: **CC BY-NC-SA 4.0** — free to use, adapt and share, **not for commercial use**, derivatives under the same license. This is a source-available project, not OSI open source.
- 城市资料 `web/data/`：**CC BY-SA 4.0**（源自 Wikipedia / Wikivoyage），见 `web/data/LICENSE`。图片不在仓库里，链到维基共享资源，各自遵循原许可。
  City texts in `web/data/`: **CC BY-SA 4.0** (derived from Wikipedia / Wikivoyage). Photos are hotlinked from Wikimedia Commons under their own licenses.
- 第三方声明见 `THIRD_PARTY.md`（boarding-pass 交互参考 jal-co/boarding-pass，MIT）。See `THIRD_PARTY.md`.
