---
id: mod-ui
type: module-design
status: active
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
- **不允许**：直接 import `api/ApiClient`（现为零）、直接 import `@kit.NetworkKit`（现仅 `AlbumTab` 的分享
  下载为已批准例外）、直接 import `libentry.so`、把业务逻辑写进页面却不落在 store/api 里、自己另起速率定时器。
  非路由器端点（外网探测/版本检查/测速下载）统一走 `api/NetProbe`。
- 页面不持久化数据：落盘一律交给 store。
- 一个页面若允许平板内嵌，必须导出 `@Component` 并在 `PageHost` 注册（见 `mod-nav`）。

## Invariants

- **主题从 `AppState.getTheme()` 取**（色板 × 材质）：颜色用 `this.theme.*`，形态用 `theme.material.*` 或
  `cardTint/cardBorder/cardElevation/cardRadius`，新代码的卡片优先用 `GlassCard`。
- **切主题靠 AppStorage 驱动**：页面声明 `@StorageLink('skinId')` / `@StorageLink('uiStyle')` + `@Watch`
  重算 `theme`，不依赖手工注册 `onThemeChange`（现有监听器逐步淘汰）。
- **嵌入页面的滚动内容要显式撑满并顶部对齐**：`Scroll` 里那层内容 `Column` 必须写
  `.constraintSize({ minHeight: '100%' })` + `.justifyContent(FlexAlign.Start)`。只写 padding 时，内容比视口短
  就会**整体垂直居中**（表现为"页面从中间开始显示"），在窄侧栏里尤其明显。用 `constraintSize` 而不是
  `height('100%')`，是为了不破坏长内容的滚动。
- **分栏内嵌页面不画自己的背景**：可嵌栏页面（`AppNav.EMBEDDABLE` 白名单）的根背景用
  `pageBgColors(theme, AppNav.getInstance().isWide())`——平板分栏时返回透明，让 `MainPage` 那一块
  背景直接透出。两个渐变各自从自己的左上角起算，不透明就会在分栏边界形成一道色差接缝。
  不能嵌栏的页面（登录/应用中心/设备详情/路由表/WebView/播放页/帮助）仍画自己的页面渐变。
- **长列表不叠实时模糊**：密集列表页传 `noBlur` 或直接用 tint + 描边（见 `mod-theme` 的性能保底约定）。
- **数据轮询一律用 `common/utils/Poller`**（可见性门控 + in-flight 锁 + `dispose`），速率只用
  `LiveRateStore`；`setInterval` 只允许用于**动画与倒计时**（它们不该被可见性门控或无谓地加锁）。
  目前已迁移：`AppsPage`（Bento 指标 10s、磁贴指标 60s）、`SmartHubPage`（夜间采样 60s）、
  `PetPage`（路由器体征 30s）。仍在用 `setInterval` 的是 `DashboardTab`/`PetPage`/`MileStonePage`/
  `NetEcgPage`/`NetworkCheckPage`/`SpeedTestPage`/`RebootPage`/`FactoryResetPage` 的呼吸、眨眼、
  波形、进度与倒计时动画——这些都是刻意保留的。
- **离开页面释放资源**：定时器、监听器、`AppNav` 面板监听、`LiveRateStore` 订阅都要在 `aboutToDisappear`
  注销。
- **错误展示用 `ApiService.getLastError()`** 的既有中文文案，不另造一套。
- **空/失败状态必须有明确呈现**（"未连接/取不到数据"），不能静默留白。

## Known limitations

- 五个超大页面承担了过多逻辑：`DashboardTab`(2595)、`AppsPage`(1819)、`AlbumTab`(1724)、`PetPage`(1282)。
  已知并接受，改动时局部收敛（见 `istore-architecture`）。
- **材质已全量覆盖**：57 个页面文件的卡片底色/描边/模糊半径已改为材质派生值，所以切到液态玻璃时
  **每个页面的表面都会变**；剩余偏差是页面内的语义色与插画色（见 `mod-theme` 的限制）。
- 另有一处口径偏差：PetPage 的「心情小话」8s 轮播与各页动画仍用 `setInterval`，属刻意保留（纯本地
  渲染节奏，无网络请求）；如果以后要在后台/分屏下省电，可以再评估给它们加可见性门控。
- `AlbumTab` 仍直接 import `@kit.NetworkKit`：分享需要**可取消**的长下载（60s 上限、中途 `destroy`），
  `NetProbe` 目前只提供一次性请求，属已批准例外；若要收敛，需给 `NetProbe` 加可取消句柄。
