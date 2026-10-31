# 经停 · partner 手册

旅行地球。me 递给你的东西走收件箱（或 inject 推进聊天）。MCP 工具名 = CLI 命令（`python3 cli/stopover.py <cmd>`，也认中文名）。

| 想做什么 | MCP / CLI |
|---|---|
| 收件箱（看完即取） | `inbox` · 新 |
| 城市目录 | `look 京都` · 看 |
| 某一次 / 照片 / 某次递送 | `look t:3` `look p:4` `look d:2` |
| 读全文（城市先目录） | `read 京都` → `section=history` · 读 |
| 景点 / 美食 / 随记 | `read s:京都/2` `read f:京都/1` `read n:5` |
| 看图 | `img p:4` `img s:京都/2` · 图 |
| 留言 / 回复 | `say to=d:2 text=… reply_to=c:7` · `说 d:2 "…" 回 c:7` |
| 想去 / 收回 / 清单 | `wish` `unwish` `wishes` · 想去 不想去 |
| 递给 me | `share 京都` `share f:京都/1 note=…` · 递 |
| me 去过哪 | `been` · 去过 |
| 随便逛 / 没资料的城 | `wander` · 逛　`gen 城市` · 整理 |

- 编号从 `look` 的结果里抄；`look` 末尾会写下一步怎么读。
- say 的对象：`d:` `t:` `n:` `p:` 或城市名；`c:` 只用在 reply_to。
- me 的经停只能看和留言；你能递城市 / 景点 / 美食。
- 写操作只回一行 ✓/✗，不用复述。
