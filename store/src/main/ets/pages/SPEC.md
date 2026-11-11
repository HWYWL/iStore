---
id: mod-ui
type: module-design
status: draft
title: 模块：页面与布局（pages）
parent: istore-architecture
depends-on: [mod-api, mod-state, mod-nav, mod-theme]
---

## Responsibility

全部界面：登录、首页仪表盘、应用中心、以及几十个功能页。这里只做展示与交互编排——数据从
`common/store` 与 `api/ApiService` 拿，颜色从 `common/theme` 拿，路由走 `AppNav`。

目录按主题分（`apps/` 是功能页的集合，不是"应用商店"；`dashboard/`、`devices/`、`network/`、`system/`、
`security/`、`process/`、`pet/`、`other/`、`entry/` 各管一类）。

## 布局与形态

`pages/dashboard/MainPage` 是唯一常驻的壳（`@Entry`），不随功能页路由切换：

| 宽度 | 形态 |
|---|---|
| < 600 vp | 单栏，只有首页；功能页走全屏路由 |
| ≥ 600 vp | 两栏：首页 34% + 应用中心（内嵌） |
| ≥ 1100 vp | 三栏：首页 25% + 应用中心 30% + 右侧面板（`PageHost` 承载被打开的功能页） |

断点常量 `BP_TWO_COLUMN=600` / `BP_THREE_COLUMN=1100` 只在 `MainPage` 里（与 `AppNav.isWide()` 一致）。
`MainPage.aboutToAppear` 负责挂 `NavPathStack`、初始化 `NotificationWatcher` 等前台 watcher；
`aboutToDisappear` 负责停掉它们。

`pages/dashboard/` 下的 `DashboardTab` / `DeviceTab` / `DockerTab` / `AlbumTab` / `IStoreTabView` 是首页内部的
子视图，不是通过路由打开页面。

## Boundary

- 允许依赖：`api/ApiService`、`models`、`common/store/*`、`common/theme`、`components/*`、`AppNav`、
  `common/utils/*`、`common/ssh`（终端/文件页）、`common/ai`、`common/security`、媒体客户端。
- **不允许**：直接 import `api/ApiClient`（现存违规仅 `pages/entry/LoginPage`、`pages/apps/SmartHubPage`，
  属待收敛）、直接 import `libentry.so`、把业务逻辑写进页面却不落在 store/api 里、自己另起速率定时器。
- 页面不持久化数据：落盘一律交给 store。
- 一个页面若允许平板内嵌，必须导出 `@Component` 并在 `PageHost` 注册（见 `mod-nav`）。

## Invariants

- **主题从 `AppState.getTheme()` 取**，订阅 `onThemeChange` 刷新，不写死颜色（现状见 `mod-theme` 的限制）。
- **轮询用 `common/utils/Poller`**（可见性门控 + in-flight 锁 + `dispose`），速率只用 `LiveRateStore`；
  大页面自己写 `setInterval` 是已知的偏差来源。
- **离开页面释放资源**：定时器、监听器、`AppNav` 面板监听、`LiveRateStore` 订阅都要在 `aboutToDisappear`
  注销。
- **错误展示用 `ApiService.getLastError()`** 的既有中文文案，不另造一套。
- **空/失败状态必须有明确呈现**（"未连接/取不到数据"），不能静默留白。

## Known limitations

- 五个超大页面承担了过多逻辑：`DashboardTab`(2595)、`AppsPage`(1819)、`AlbumTab`(1724)、`PetPage`(1282)。
  已知并接受，改动时局部收敛（见 `istore-architecture`）。
- 部分页面仍自带 `setInterval`（`DashboardTab`/`AppsPage`/`PetPage`/`SmartHubPage`/`NetEcgPage`/
  `NetworkCheckPage`/`SpeedTestPage`/`RebootPage`/`FactoryResetPage`），与 `Poller` 约定不一致。
- 部分页面直接 import `@kit.NetworkKit`（`SmartHubPage` 探测、`SpeedTestPage` 测速、`AlbumTab` 图片、
  `AboutPage` 版本检查），绕过了"网络访问集中在 `api/`"的约定。
