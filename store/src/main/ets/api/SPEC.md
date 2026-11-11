---
id: mod-api
type: module-design
status: active
title: 模块：路由器通信层（api）
parent: istore-architecture
---

## Responsibility

把「路由器上的一堆异构接口」收敛成一套类型化业务方法。全应用的路由器数据只从这里出，页面与状态层
看到的永远是 `models/Models` 里的 DTO，而不是 JSON 字段名。

两层，各管一件事：

- **`api/ApiClient.ets`（单例，底层）**：HTTP 细节 + 连接模式选择 + ubus 动作映射 + 会话维护。
- **`api/NetProbe.ets`（静态工具，非路由器端点）**：`reachable()` HEAD 探测、`getText()` 读文本、
  `getBytes()` 读二进制（支持 Range）。这是页面访问外网/任意 HTTP 的**唯一出口**——页面不得自己
  `import @kit.NetworkKit`。
- **`api/ApiUtils.ets`**：安全字段读取 + 纯函数（`normalizeAddress` 地址规范化，登录页也用）。
- **`api/ApiService.ets`（单例，业务层）**：`fetch*/save*/set*` 约七十个方法，调 ApiClient 并用
  `ObjectHelper` 容错读取字段后组装 `Models` 类型；带静态 TTL 缓存。

## Boundary

- 依赖：`models/Models`（DTO）、`common/utils/FormatUtils`、`common/ssh/SshService`（ubus 取不到时的
  兜底通道）、`common/store/AppState` 与 `DeviceStore`（取当前设备配置）。
- **存在一条回边**：`common/store` 也 import `ApiClient`/`ApiService`（`AppState` 负责连接与切设备）。
  这不是笔误而是现状——本层不持有"当前设备"，也不该持有；两侧改动要同时看。
- 被依赖：`common/store`、`common/ai`、`common/security`、`pages`（页面只应经过 `ApiService`）。
- 不做：不渲染、不持久化业务数据（除缓存）、不直接读 Preferences。
- 路由器通道只在这里用 `@kit.NetworkKit`：`ApiClient`（ubus/LuCI）、`NetProbe`（外网探测/版本/测速）、
  媒体客户端（见 `mod-api-media`）。页面层不出现 NetworkKit。

## 连接模型

| 模式 | 何时用 | 机制 |
|---|---|---|
| `ubus`（默认） | 新设备与绝大多数固件 | POST `/ubus`，JSON-RPC `call [sessionId, obj, method, params]`；账号密码经登录换 session，`options: { timeout }` 按请求类型分档 |
| `legacy`（兼容） | 已保存的旧设备，且探测到设备没有 `/ubus` | GET `/cgi-bin/router-api?action=...&token=...`，见 `mod-router-assets` |

`connect()` 先试 ubus，`ubusMissing` 时回落 legacy；已确认 legacy 通道保留的唯一理由是**老设备平滑迁移**，
新设备不再写 token。

## 关键机制

- **超时分档**：建连 5 s、普通读 10 s、重请求（LuCI 渲染、Docker 统计）15 s。
- **重试策略**：传输层失败重试 1 次、退避 250 ms，仅当方法名匹配 `isReadonlyCall`
  （`get*`/`info*`/`status*`/`list*`/`dump*`/`board*`/`read*`/`assoclist`/`login`）。原因：写操作重试
  会重复执行（重启、安装、删除）。
- **会话维护**：`sessionId` + `sessionExpireAt` 主动续期；RPC `-32002`/`-32004` 视为会话失效 → 强制重登
  → 同请求重试一次（`allowRetry=false` 防止二次重试）；登录用 `loginInFlight` 互斥，避免并发重复登录。
- **动作映射**：`request(action)` / `ubusRequest` 用三十余个 `case` 把历史动作名（`system_info`、
  `network_rates`、`dhcp_leases`、`docker_*`、`uci_get`、`reboot`…）映射到 ubus 对象或 shell/uci 调用，
  返回统一 `RouterApiResponse {code, message, data, rates}`。这是 legacy 兼容面，也是新增数据源的入口。
- **次要通道**：LuCI 表单/cookie 登录（`luciHttp`）用于需要 LuCI 侧权限的动作；Docker Remote API 探测
  （`probeDockerApi` / `enableDockerApi`）补齐容器统计；SSH 兜底（`ubusCallFallback`、
  `loadDeviceTreeViaSsh`、`getBridgePortMap`）取 ubus 读不到的数据。
- **权限自愈**：QWRT 等固件缺 rpcd ACL 时 `qwrtAutoFix` 注入一次性任务修补授权。刻意做成探测 + 自愈，
  而不是按固件版本号分支——兼容全系 OpenWrt 的根本手段。
- **缓存**：`ApiService` 的静态 TTL 缓存，普通数据 1200 ms、bridge 端口映射 30 s；切设备必须
  `resetCache()`，否则上一台设备的数据会串台。
- **错误文案**：`describeTransport` / `describeRpcError` 把 HTTP 码与 RPC 错误码翻成中文用户可读原因，
  页面直接展示 `getLastError()`。

## Known limitations

- `ApiClient.ets` 4716 行：I/O、ubus 映射、Docker、ACL 自愈、CPU/芯片解析、shell 转义全在一个类里。
  这是已知并接受的技术债（见 `istore-architecture`），改动请局部收敛。
- 部分兼容面已无调用者：`hasCapability`、`callUbus`/`callUbusFirst` 等 shim 仍留在代码里。
- `ApiService` 的缓存是静态字段 + 时间戳，没有按设备分区，正确性完全依赖「切设备时调 `resetCache()`」
  这一条约定。
