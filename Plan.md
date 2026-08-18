本 mod 用于给玩家提供一个在 Steam 以外的服务器代替品，包含许多增强功能和优化改善。
具体提供 api 可参考 vs-server-go。

所有改动都经 `vs_online_is_custom()` 一门控：关闭 = 原版 Steam 路径；开启 = vs-server-go。

**Steam 模式**吸收 betterWP 的全部联机增强（随机房、房间数、推荐曲、结算按分排序、encore、倒计时音、藏榜、徽标）。**自定义模式**保留同一套 UI，随机加入 / 房间数走 `POST /lobbies/matchmake` 与 `GET /lobbies`。与独立 betterWP 同时安装会弹窗后 `game_end`。自定义模式不显示绿色 Better WP 徽标。

自定义服务器时：
- 成绩存档带服务器后缀，不污染 Steam 存档
- 下载谱（`is_custom`）也上传 `/charts/scores`，B40 / Rating 读服务器投影
- 黑名单走 `GET /blacklist`；时间用本机时钟；小游戏 Steam 榜不再上传/下载
- 头像优先拉服务器 URL，失败再 hash 名字选 jacket
- 好友在网页加，游戏只读好友榜
- 已下载谱靠 Custom Songs Mod 进选曲；目录/搜索在首页 Chart Downloader（Web + Local）

异步复用 `oCoroutineManager`（init 时若不存在则创建）。大厅 WS 为 GameMaker 原生 `wss://` / `ws://`。

===== M5 落地（首页 Chart Downloader 下载管理器）=====
- Web 页签：对接 vs-server-go 目录（每页 100 首）、Tab 搜索(?q=)、F 筛选
  （全部/未下载/已下载/可更新）、选中谱自动 sha1 新旧检测、Enter 下载/更新、
  K 整页检测、G 整页批量更新。
- Local 页签：本地自制谱列表 + Tab 搜索 + 跳转选曲 + R 重载（配合 Custom Songs Mod）。
- （已移除选曲内旧「Web Charts」虚拟曲包 + vs_songstore_browser。）
