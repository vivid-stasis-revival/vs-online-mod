# vs-online-mod

让 **vivid/stasis** 脱离 Steam、接入自定义服务器（[vs-server-go](https://github.com/vivid-stasis-revival/vs-server-go)）的联网 mod，按 [vsml](https://github.com/vivid-stasis-revival/vsml) 格式编写。

## 设计要点

- **总开关**：设置里新增「Custom Server」选项。**关闭（默认）= 完全原版 Steam 行为**；开启 = 所有联网功能走自定义服务器。所有改动都经 `vs_online_is_custom()` 这一个动态 bool 门控。
- **异步**：复用游戏自带的协程框架（`oCoroutineManager` + `CoroutineAwaitAsync("http"/"networking", cb)`）。
- **WebSocket**：纯 GML 手写（raw TCP + 握手 + 帧 + 掩码），不依赖任何 DLL 扩展。
- **成绩隔离**：自定义服务器时使用带后缀的独立存档文件，不污染原版成绩。

## 配置文件

游戏存档目录（`working_directory`）下的 **`vsonline`**（JSON，无扩展名，mod 首次运行会自动创建默认文件）：

```json
{
  "server": "http://localhost:8080"
}
```

字段：
| 字段 | 说明 |
|---|---|
| `server` | vs-server-go 的 base URL（必填） |
| `playerId` / `token` / `refresh_token` | 服务器身份（M2 起由 mod 写入） |
| `name` / `avatar` | 玩家名 / 头像（M2 起写入） |

## 目录结构

```
vs-online-mod/
├── Plan.md                     # 功能设计
├── codepatches.json            # 游戏代码补丁清单
├── codepatches/                # 补丁片段（ExternalFile）
│   ├── mod_info.gml            #   注册到 global.vml_mods + 初始化
│   ├── add_options.gml         #   define_options 注入「Custom Server」开关
│   └── send_packet.gml         #   send_packet 按 bool 分流
└── codes/                      # 新增 GML 代码条目
    └── gml_GlobalScript_vs_online_mod.gml   # mod 核心（config/开关/选项）
```

## 构建进度

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 | 骨架 + bool 开关 + vsonline 配置读取 | ✅ |
| M1 | 纯 GML WebSocket 库（raw TCP 握手/帧/掩码/ping-pong） | ✅ |
| M2 | REST 层 + 身份 + 凭据存储 + 成绩后缀隔离 + 排行榜/成就/好友 | ✅ |
| M3 | 大厅核心（REST create/join/matchmake/leave + WS 中继 + roster/control） | ✅ |
| M2 | 身份 + 凭据存储 + 成绩后缀隔离 + 排行榜/成就/好友 | ⏳ |
| M3 | 大厅（REST + WS 中继），改造 send_packet/receive_packet + o_st_handle | ⏳ |
| M4 | 谱面商店（all songs 本地包 + 服务器分页包 + 搜索 + 下载/SHA 更新）+ 头像 hash 回退 | ⏳ |

## 安装（测试）

1. 把本目录放入 `vsml/mods/` 下（路径 `vsml/mods/vs-online-mod/codepatches.json`）。
2. 运行 `vividstasisModLoader.exe` 应用补丁。
3. 游戏设置 → VS Online → Custom Server 设为开启；确认存档目录存在 `vsonline` 文件。
