---
id: mod-state
type: module-design
status: draft
title: 模块：应用状态与持久化（common/store）
parent: istore-architecture
---

## Responsibility

全应用的内存状态与持久化。所有跨页面共享、需要落盘的东西都住在这里：当前设备与连接态、主题与皮肤、
实时速率、每日流量、通知与定时任务配置、设备备注、媒体凭据。

共同形态：`getInstance()` 单例 + `init(context)` 异步初始化 + ArkData `Preferences` 落盘（**每个域一个
存储名**）。需要响应式的地方不直接依赖单例，而是把值镜像进 `AppStorage` 给 `@StorageLink` 用。

## 分组

| 分组 | 成员 | 职责 / 存储名 |
|---|---|---|
| 会话与偏好 | `AppState` | 色板 + 材质（主题）、设备列表代理、当前设备与连接态、当前标签、宽屏与导航态；`iStore_app_settings`；向 `AppStorage` 镜像 `skinId`/`uiStyle`（页面靠 `@StorageLink` 即时重绘）；11 对 `on*/off*` 监听器（逐步淘汰） |
| | `DeviceStore` | 设备表 CRUD、最近连接排序、收藏/分组；`iStore_devices`；`token`/`password` 经 `SecureStorage` 加密；每次保存递增 `version` 以驱动 `@ObjectLink`/`@Prop` 刷新 |
| 实时与统计 | `LiveRateStore` | 全应用唯一的上下行速率心跳（`LIVE_REFRESH_MS`），`subscribe/unsubscribe/push` |
| | `TrafficStatStore` | 按天累计 rx/tx（由页面轮询差值累加），保留 60 天；`iStore_traffic` |
| | `WidgetDataStore` | 前台写入的卡片快照（速率/在线数/在线态）；`iStore_widget` |
| | `SmartGuardStore` | 每小时流量采样、夜间事件日志、周健康汇总，按设备隔离（`sg_` 前缀） |
| 通知与自动化 | `NotifyStore` | 通知总开关与各类告警开关、已知 MAC 集合、告警去重记录；`iStore_notify` |
| | `NotificationWatcher` | 前台 60 s 检测：断网/恢复、新设备、健康阈值 → 系统通知；到点执行定时任务 |
| | `AiHealthChecker` | 温度/内存/CPU/突发流量四维阈值告警，同类 24 h 去重 |
| | `ScheduleStore` | 定时重启/定时开关 WiFi 的 `enabled/time(HH:MM)/weekdays` 与 `lastExecDate` 防重复 |
| 设备本地增强 | `DeviceNoteStore` | MAC → 自定义备注名，按路由器隔离，只改本地不写路由器配置 |
| 媒体凭据 | `ImmichStore` / `JellyfinStore` | 按 `deviceId` 保存媒体服务地址与凭据（API Key / 账号） |
| 小管家 | `PetStore` / `FunStore` / `MoodEngine` / `DiaryStore` | 见 `mod-pet` |

## Boundary

- 依赖：`api/ApiService`、`models`、`common/theme`、`common/utils`（`SecureStorage`/`FormatUtils`/`RefreshRate`）。
- 与 `mod-api` 双向：`AppState` 调 ApiClient 建连，`ApiClient` 反向读 `AppState`/`DeviceStore`。
- 被依赖：几乎全部页面；`entryformability`（`WidgetDataStore`）、`storeability`（域 Store 的 init）。
- 不做：不含 UI 与布局、不发 HTTP 请求（除经 `ApiService`）、不持有页面级临时状态。

## Invariants

- **`init(context)` 由宿主调用**：`StoreAbility.onCreate` 或 `MainPage.aboutToAppear` 负责初始化；
  页面里 `getHostContext()` 可能为 `null`，不要靠它懒加载。
- **监听器必须配对**：`AppState` 的 `on*` 在 `aboutToAppear` 注册，就必须在 `aboutToDisappear` 里 `off*`，
  否则页面销毁后仍持有闭包。
- **按设备隔离的数据必须以 `deviceId` 为 key**：设备备注、媒体凭据、`SmartGuardStore` 采样都遵守；
  否则切设备会串数据。
- **落盘只经 Preferences**，每个域一个存储名；不允许一域多库或多域共库（迁移会互相牵连）。
- **主题选择用两个键**：`skinId`（色板 id，默认 `beige`）与 `uiStyle`（`solid`/`liquid`，旧值
  `classic`/`glass` 在 init 时迁移）；两者都镜像进 `AppStorage` 供页面订阅。图标包选择已下线，
  不再有 `iconPackId` 写入。
- **速率只订阅 `LiveRateStore`**，不要另建定时器（见 `istore-architecture` 不变量 5）。

## Known limitations

- `AppState` 同时承担主题、设备、连接、标签页、宽屏、导航与相册子视图，职责过宽；理解页面刷新行为
  往往要通读它。
- `common/utils/SecureStorage` 只是混淆级加密（硬编码密钥），设备凭据仅能防肉眼窥探。
- 与 `mod-api` 的回边让"状态层"和"通信层"无法独立演进；新增全局状态时优先加独立 Store，而不是继续
  往 `AppState` 里塞。
