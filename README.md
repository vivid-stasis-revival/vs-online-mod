# vs-online-mod

让 **vivid/stasis** 脱离 Steam、接入自定义服务器（[vs-server-go](https://github.com/vivid-stasis-revival/vs-server-go)）的联网 mod，按 [vsml](https://github.com/vivid-stasis-revival/vsml) 格式编写。

## 设计要点

- **总开关**：设置里新增「Custom Server」选项。**关闭（默认）= 完全原版 Steam 行为**；开启 = 所有联网功能走自定义服务器。所有改动都经 `vs_online_is_custom()` 这一个动态 bool 门控。
- **异步**：复用游戏自带的协程框架（`oCoroutineManager` + `CoroutineAwaitAsync("http"/"networking", cb)`）。
- **WebSocket**：GameMaker 原生 `network_socket_wss` / `network_socket_ws`（TLS 由 runner 做）。
- **成绩隔离**：自定义服务器时使用带后缀的独立存档文件，不污染原版成绩。

## 配置文件

游戏存档目录（`working_directory`）下的 **`vsonline`**（JSON，无扩展名，mod 首次运行会自动创建默认文件）：

```json
{
  "server": "https://online-api.vividstasis.cn",
  "frontend": "https://online.vividstasis.cn"
}
```

字段：
| 字段 | 说明 |
|---|---|
| `server` | REST / API base URL（必填；默认 `https://online-api.vividstasis.cn`） |
| `frontend` | 账号站 / 设备流页面（默认 `https://online.vividstasis.cn`） |
| `ws` | 大厅 WebSocket 地址（可选；不写则 `https://主机` → `wss://主机`，`http://` → `ws://`） |
| `playerId` / `token` | 服务器身份（mod 自动写入） |
| `refresh_token` | OAuth2 设备流刷新令牌（30 天，启动时自动旋转刷新） |
| `email` | 账号邮箱（设备流登录时由 mod 写入） |
| `name` / `avatar` | 玩家名 / 头像（mod 自动写入） |

## 登录（OAuth2 设备流）与账号状态

设置 → VS Online 页面现在有四个选项：

| 选项 | 作用 |
|---|---|
| Custom Server | 总开关（Steam / 自定义服务器） |
| **Account Status** | 只读显示当前状态：账号/邮箱、游客提示、服务器在线/离线（描述栏实时更新） |
| **Log In** | 打开账号面板走设备流登录（显示 8 位 `user_code` + `verification_uri`，浏览器确认后自动轮询换取 token） |
| **Log Out** | 退出登录，回落到游客 |

- 登录后 access token（24h）+ refresh token（30 天）持久化；**每次启动游戏，custom server 模式下先自动刷新身份（refresh token 旋转）**，无需重新登录；失效才需要重新走设备流。
- **游客 / 未登录封锁**：自动铸造的游客身份（只有 playerId + token，无账号）**不能使用任何在线功能**——
  登录前无法浏览/下载/更新线上谱、无法开/加入大厅、无法上传/查看榜单、无法同步成就；**只能游玩已下载的本地谱**。
  登录成功后这些功能自动解锁。

## 启动自动检查更新

custom server + 已登录账号启动游戏时，身份刷新完成后会自动探测服务器连通性；
连通则调用 `POST /api/v1/charts/check-updates` 检查已记录下载是否有更新，
结果写入日志并在 `global.vs_updates_available` 记录（游客不执行该检查）。


## 目录结构

```
vs-online-mod/
├── Plan.md                     # 功能设计
├── codepatches.json            # 游戏代码补丁清单
├── codepatches/                # 补丁片段（ExternalFile）
│   ├── mod_info.gml            #   注册到 global.vml_mods + 初始化
│   ├── add_options.gml         #   define_options 注入「Custom Server」开关
│   ├── send_packet.gml         #   send_packet 按 bool 分流
│   ├── home_downloader_button.gml  # 首页「Chart Downloader」入口
│   ├── leaderboard_download.gml    #   选曲榜单走 /charts/scores
│   ├── leaderboard_friends.gml     #   好友榜走 /charts/scores/friends
│   └── bwp_*.gml                   #   吸收的 betterWP 联机增强
├── codes/                      # 新增 GML 代码条目
│   ├── gml_GlobalScript_vs_online_mod.gml   # mod 核心（config/开关/选项）
│   ├── gml_GlobalScript_vs_online_api.gml   # REST / 身份 / 成绩 / 成就 / B40
│   ├── gml_GlobalScript_vs_online_lobby.gml # 大厅 REST + WS 中继
│   ├── gml_GlobalScript_vs_ws.gml           # 原生 network_socket_wss / ws
│   ├── gml_GlobalScript_vs_localcharts.gml  # 本地谱扫描/跳转选曲/重载
│   ├── gml_GlobalScript_vs_dlmgr.gml        # 下载管理器 web 层
│   ├── gml_GlobalScript_vs_dlbr.gml         # 下载器 UI（具名脚本，避免对象匿名函数）
│   ├── gml_GlobalScript_vs_auth.gml         # 登录面板动作
│   ├── gml_GlobalScript_SuggestSongPacket.gml
│   └── gml_Object_vs_downloader_browser_*   # 下载管理器界面（只留实例变量）
├── objects/vs_downloader_browser.json
└── sprites/sp_icon_vs_local_0.png           # 首页按钮图标
```

## 谱面下载管理器（首页「Chart Downloader」）

首页 **Worldcross Play** 下面新增 **Chart Downloader** 入口，打开一个对接 vs-server-go 的**下载管理器**，双页签：

**Web 页签（默认）— 对接线上目录**
- 浏览服务器曲库目录：`/api/v1/songs` 每页 100 首，`←/→` 或 `PgUp/PgDn` 翻页，显示总数。
- **搜索**：`Tab` 进入搜索（输入任意关键字后 `Enter` 提交，走 `?q=`），`Esc/Tab` 退出。
- **筛选**：`F` 循环 **全部 / 未下载 / 已下载 / 可更新** 四种过滤（“已下载”只算本 mod 记录的下载）。
- **新旧检测**：选中谱自动做 sha1 差分；行前标记：
  `.`=未下载，`D`=已下载（有记录），`U`=可更新，`L`=本地同名谱（无下载记录，**受保护不会被覆盖**）；
  `K` = 整页检查。无记录但内容与服务器一致的本地谱会被自动补记（兼容历史下载），内容不一致的会被保护。
- **下载/更新**：`Enter` 下载/更新（只拉改动文件）；`G` = 整页批量更新所有「可更新」的谱（只动有记录的下载）。
- **重载**：`R` 重新拉目录并刷新本地状态。

## 下载记录 / 如何辨别谱的来源

- 每首**下载/更新成功**的谱，都会在自身目录写下标记 **`Custom Songs/<chartId>/.vs_download.json`**（含服务器 songId、首次下载时间、最近更新时间）。
- 全局下载流水另存于 **`working_directory/vsonline.downloads.json`**（每谱一条历史，200 条封顶）。
  > `working_directory` = 游戏的数据/存档目录（Windows 下为 `%LOCALAPPDATA%\VIVIDSTASIS\`，不是 Steam 安装目录）；
  > 官方存档 `profile`、`highscore_table`、`custom_profile`、mod 配置 `vsonline`、`Custom Songs/` 都在这里。
- 因此区分极简单：**目录下有标记 = 本 mod 下载/更新过的谱**；**目录在但没有标记 = 本地本来就有**（自制/手动放入，只是 id 相同）→
  这类谱在 Web 列表显示 `L`、Local 页签显示 `L`，**永远不会被在线下载覆盖**（若参与者想用服务器版本替换，需先备份后自行删除本地目录）。
- 启动时的自动更新检查**只检查有记录的下载**，不会把“本地同名自制谱”误判为待更新。
- 本地页签行标：`D`=有下载记录，`L`=本地未记录。

## Local 页签 — 本地自制谱辅助（`V` 切换）

- 列出 `Custom Songs/` 里的本地谱（CSM 格式，含下载器下载的谱、手动放入的自制谱），行首标 `D`/`L`。
- `Tab` 本地搜索（曲名 / 曲师 / chart_id / 曲包）；`Enter` 跳转到选曲界面该曲位置（`o_songselect_main` 的 `force_song_select`）；`R` 重新扫描。

> 说明：下载文件直接落进 `Custom Songs/<chartId>/`（与 Custom Songs Mod 共享同一边），
> 谱要能在选曲里游玩需同时启用 [Custom Songs Mod](https://github.com/vivid-stasis-revival)。
> **选曲界面里的旧「Web Charts」虚拟曲包及其浏览器已移除**（M4 遗留：50 首/页、无筛选，
> 且每次下载会触发 CustomSongReader 全量重复加载）——Web 谱图只保留本下载管理器一套。


## 构建进度

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 | 骨架 + bool 开关 + vsonline 配置读取 | ✅ |
| M1 | 大厅 WebSocket（原生 `network_socket_wss` / `ws`） | ✅ |
| M2 | REST 层 + 身份 + 凭据存储 + 成绩后缀隔离 + 排行榜/成就/好友 | ✅ |
| M3 | 大厅（REST + WS 中继 + 完整 UI 打桩 + 随机匹配 Shift+Paste） | ✅ |
| M4 | 谱面商店下载链路（REST + sha1 差分下载/更新）+ 头像 hash 回退 | ✅ |
| M5 | 首页 Chart Downloader 下载管理器（web 目录/搜索/筛选/新旧检测/整页批量更新 + Local 页签） | ✅ |
| M6 | 账号/游客策略（设置页 状态/登录/退出；游客禁止在线功能只可玩本地谱；启动自动刷新 token + 自动检查本地谱更新）、移除旧 Web Charts 曲包 | ✅ |
| M7 | 遗留收口：CSM 成绩上传、大厅进房同步、服务器 B40/Rating、黑名单、头像 URL、betterWP 吸收（Steam 全功能 / 自定义走服务器）、死代码清理 | ✅ |

REST 用 **`https://`**。大厅用原生 **`wss://`**（默认与 REST 同主机）。Cloudflare Tunnel 源站可以是 `http://localhost`，公网走 HTTPS/WSS。本地明文可写 `"ws": "ws://127.0.0.1:8226"`。旧配置里的 `"ws": "http://…"` 会当成明文 `ws://`，走 Tunnel 的话请删掉 `ws` 或改成 `wss://`。

## 安装（测试）

1. 把本目录放入 `vsml/mods/` 下（路径 `vsml/mods/vs-online-mod/codepatches.json`）。
2. 运行 `vividstasisModLoader.exe` 应用补丁。
3. 游戏设置 → VS Online → Custom Server 设为开启；确认存档目录存在 `vsonline` 文件。
