---
id: mod-nav
type: module-design
status: draft
title: 模块：导航与页面注册
parent: istore-architecture
---

## Responsibility

在**同一份页面代码**上支持两种形态：手机上 `router.pushUrl` 全屏跳转，平板上把页面嵌入侧栏
`NavPathStack` / `NavDestination`。并集中管理"有哪些页面"这件事。

| 文件 | 职责 |
|---|---|
| `resources/base/profile/main_pages.json` | 系统侧路由表（60 条），第一项是登录页，`MainPage` 是唯一常驻入口 |
| `common/utils/AppNav.ets` | 双形态路由门面：`open()` 按宽度决定全屏还是嵌栏、`openFullscreen()` 强制全屏、`back()`、`titleOf()`、最近访问列表、面板显示监听；`PAGE_TITLES`（路由→中文标题）+ `EMBEDDABLE` 白名单（57 条） |
| `common/components/PageHost.ets` | 侧栏宿主：URL → 组件的 `if (url === ...)` 分支（50 个页面），非白名单 URL 显示"建议全屏"回退卡 |
| `common/nav/PageRegistry.ets` | 应用中心磁贴与全局搜索的数据源：`PAGE_REGISTRY`（route/title/desc/icon/group/py/metric）+ `PAGE_GROUP_ORDER`（我的/网络/多媒体/趣味/管理/系统）+ `findPage`/`getPageGroups`/`searchPages` |

## Boundary

- 依赖：`AppState`（宽屏与导航态）、`common/theme`、`components/AppIcon`；`PageRegistry` **不依赖任何模块**
  （纯数据，这样搜索不必触碰页面）。
- 被依赖：`MainPage`（`attachStack`/`setUIContext`）、`AppsPage`（磁贴与搜索）、所有调用 `AppNav.open()` 的页面。
- 不做：不渲染页面内容、不发请求、不持久化业务数据（最近访问是内存态）。

## Invariants

- **新增一个功能页要改四处**，缺一处都不会编译报错，只会静默坏掉：
  1. `pages` 下新建页面（`@Entry` 用于手机全屏，需要嵌栏时另导出 `@Component`）；
  2. `main_pages.json` 追加路由（否则手机端路由不存在）；
  3. `PageRegistry.PAGE_REGISTRY` 追加登记（含拼音首字母 `py`，否则搜不到/无磁贴）；
  4. `AppNav.PAGE_TITLES` 补标题；若允许嵌栏，还要 `EMBEDDABLE` + `PageHost` 分支。
- **`PageRegistry` 顶部注释（"新增页面只改这一个文件"）与实际不符**，以本规格的四点清单为准。
- **嵌栏页面必须是 `@Component export struct`**，且不自己包 `NavDestination`；`PageHost` 负责外壳。
- **路由字符串是全应用契约**：`PageRegistry.route`、`main_pages.json`、`AppNav` 标题、`PageHost` 分支
  必须逐字一致；`PetStore.TASK_ROUTES`（见 `mod-pet`）也按页面字符串匹配，改名要全库搜。
- 宽度判断只在 `AppNav.isWide()` 一处（600 vp 断点），页面不要自己判断"能不能嵌栏"。

## Known limitations

- 四处登记 + 字符串匹配是当前最容易出错的地方（静默失败），暂时没有生成式校验或测试兜住。
- `AppNav`、`PageHost` 各存一份页面清单（标题表 / 分支表），信息重复；新增页面成本随页面数线性增长。
