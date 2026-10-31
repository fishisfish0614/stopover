# Stopover · iOS

**中文** · [English](README.en.md)

SwiftUI 原生版，连同一个仓库里的 `server/stopover.py`。

## 跑起来

1. 先把服务端跑起来（见[根目录 README](../README.md)）：
   ```sh
   pip install -r server/requirements.txt
   python3 server/seed_demo.py   # 可选：写几条虚构的示例旅行
   python3 server/stopover.py    # → http://localhost:8000
   ```
2. 用 Xcode 16 或更新的版本打开 `ios/Stopover.xcodeproj`，选一个 iPhone 模拟器，Run。最低支持 iOS 17。
   要装到真机的话，在 *Signing & Capabilities* 里选你自己的 Team，把 Bundle Identifier（默认 `com.example.stopover`）改成你自己的。
3. 第一次打开会问服务器地址。模拟器和服务端在同一台 Mac 上就用默认的 `http://localhost:8000`；
   真机要填电脑的局域网地址，比如 `http://192.168.1.10:8000`。之后点地球页右上角的齿轮可以改。

## 有什么

地球（蓝石 / 夜航 / 旧图三种风格，来过的红点、出发地连过来的红线和流星、想去的星星、放大显示城名）、
城市长卷（历史时间轴 / 文化 / 景点轮播 / 美食）、每一次来过一张登机牌（手撕存根进「这一次」）、
改日期备注 / 出发地 / 终点、随记、照片、想去、搜索（按国家 / 去过的 / 想去的，找不到的地方可以从 Wikidata 加上）、
骰子、给没资料的城现场整理一页（服务端要配 `DEEPSEEK_API_KEY`）。

两个人用的部分（服务端 `/api/config` 的 `features.share` 为 true 时出现，关掉就整块藏起来，只自己记）：
把一座城 / 一个景点 / 一道菜 / 一整张票 / 几段随记几张照片「递给 TA」（两分钟内连着递的合成一条送过去，送到前可以撤回）、
TA 递来的收件箱和未读红点、城市卡底部「我们的对话」（每次递送一组 + 平时说的）、回复 TA 的评论。

名字（「我」「TA」）、默认出发地、家都从服务端的 `/api/config` 读，App 里没有写死。
App 永远以「我」的身份说话，不带任何鉴权头；「TA」那一侧（比如一个 AI 伴侣）用服务端发给它的 key 调同一套接口。

## 推送（可选，默认关）

不开推送也能直接编译、在模拟器和真机上用，不需要付费开发者账号。想在 TA 递东西、回你的时候收到提醒：

1. 需要付费的 Apple Developer 账号。在 Xcode 里选你的 Team、改 Bundle Identifier，
   *Signing & Capabilities* → *+ Capability* → **Push Notifications**。
2. 服务端配置 APNs key（见[根目录 README](../README.md) / `server/config.example.json`），`/api/config` 的 `features.push_apns` 变成 true。
3. App 设置（地球页齿轮）里会多出「推送」开关，打开后向系统要通知权限，把 device token 报给 `POST /api/push/apns`。
   点推送会打开那座城（payload 的 `route` 是 `stopover`，带 `city`）。

Debug 构建报的是 sandbox 环境，Release / TestFlight 报 production。

## 资源

- `Resources/stopover_marble.jpg`：NASA Visible Earth *Blue Marble*（公有领域）
- `Resources/stopover_night.jpg`、`stopover_sky.jpg`：同 `web/tex/`（见根目录 `THIRD_PARTY.md`）
- `Resources/stopover_countries.json`：Natural Earth（公有领域）
- 字体：Instrument Serif、IBM Plex Mono，SIL Open Font License 1.1（许可原文在 `Resources/OFL-*.txt`）
- 中文衬线用系统按需下载的「宋体-简」，不打包
- 撕存根的手势参考了 jal-co/boarding-pass（MIT，见根目录 `THIRD_PARTY.md`）
