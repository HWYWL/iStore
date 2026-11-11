---
id: mod-theme
type: module-design
status: draft
title: 模块：主题、皮肤与图标体系
parent: istore-architecture
---

## Responsibility

主题由**两个正交维度**相乘而成，本模块同时提供这两半和它们的派生值：

- **色板**（`common/theme/ThemeColors.ets`）：`ThemePalette` 的 26 个颜色字段。8 套注册在 `SKINS`
  （`beige` 米色经典= `LIGHT_THEME`、`white` 纯净白、`ivory` 雾霭白、`apricot` 杏子暖、`mint` 薄荷青、
  `dusk` 暮紫、`coral` 珊瑚、`steel` 黛青），`getSkinById()` 找不到时回落 `SKINS[0]`。
- **材质**（同一文件的 `ThemeMaterial`）：`solid` 实色 / `liquid` 液态玻璃，决定"长什么样"而不是
  "什么颜色"——模糊半径、玻璃 tint、镜面高光描边、内高光、圆角、浮起阴影、长列表是否降级。
- **派生值**：`cardTint` / `cardBorder` / `cardElevation` / `cardRadius` 四个函数，是页面画卡片的唯一入口；
  页面不得自己拼 `rgba` 或阴影常量。
- **图标**（`IconPack.ets` + `components/AppIcon.ets`）：5 套图标包资源，但**用户已不能选择**，应用固定
  `hos`（鸿蒙超椭圆）包；其余 4 套分支保留供调试（`forcePack`）。

## Boundary

- 依赖：只有系统 `Resource` 与（`AppIcon` 的）`AppStorage`；不依赖 store/api。调色板由调用方传入。
- 被依赖：全部页面、`PageRegistry`（磁贴图标名）、`mod-pet`（管家配色取 `theme.primary`）。
- 不做：不持久化选择（`mod-state` 的 `AppState` 负责）、不渲染布局、不知道自己在哪个页面。

## 主题如何组装

`AppState.getTheme()` → `applyMaterial(getSkin().theme, currentUiStyle)`：

- `solid`：原样返回色板，`material = SOLID_MATERIAL`（卡片用 `bgCard` + 细描边 + 克制投影）。
- `liquid`：`toLiquidGlassTheme()` 保留主色/语义色/文本/图表色，把背景换成半透明白、描边换成镜面白、
  `pageGradient` 换成 5 段多色柔光渐变（**玻璃要有可折射的东西**），并挂上 `LIQUID_MATERIAL`
  （blur 28 / 控件 blur 16 / tint 0.44→0.22 / 圆角 26 / 浮起 48·Y22）。

液态玻璃的镜面描边不能用 ArkUI 的 `border`（不支持渐变），由
`common/components/GlassCard.ets` 实现：外层 `Stack` 铺渐变底色 → 内层卡片 `margin` 1vp 并用玻璃 tint
盖住中间，只留一圈 1vp 渐变环；再叠 `backdropBlur` + 内高光 + 浮起投影。`GlassChip` 是同材质的胶囊控件。

## Invariants

- **颜色只从色板取**（`this.theme.<field>`），**形态只从材质取**（`theme.material.*` 或四个派生函数）。
  调色板缺字段先扩 `ThemePalette`，不要就地硬编码。
- **`SKINS[0]` 必须是 `LIGHT_THEME`**（默认皮肤），`AppState` 的新装默认值 `skinId='beige'`、
  `uiStyle='solid'`；旧的 `classic`/`glass` 持久值在 init 时迁移为 `solid`/`liquid`。
- **图标只经 `AppIcon`**，包固定 `hos`；`name` 是跨包契约，五种包必须覆盖同名资源并有回退。
- **长列表页不叠实时模糊**：`material.listBlurDisabled` 为真时，密集列表（设备列表/流量排行/进程/包管理）
  只用 tint + 描边 + 圆角，靠 `GlassCard({ noBlur: true })` 或材质派生值实现。
- **新增材质 = 往 `MATERIALS` 加一条 + 在 `applyMaterial` 分支**，不改页面。

## Known limitations

- **表面与模糊已全量材质化，剩颜色字面量**：`backgroundColor(bgCard)` / 卡片描边 / 硬编码 `backdropBlur(20|28|10)`
  已由 codemod 换为 `cardTint/cardBorder/cardElevation/material.blur`（57 个页面文件、368 处），现在没有任何
  页面再自己写卡片底色或模糊半径。但仍有 **732 处 `#RRGGBB` / 274 处 `rgba(`**，集中在
  `PetPage`(79)、`AppsPage`(75)、`DeviceAliasPage`(36)、`SmartHubPage`(34)、`AlbumTab`(28)、
  `FileManagerPage`(24)；其中相当一部分是语义色（状态点/图表序列）与插画色（小管家形象、磁贴徽标），
  必须逐处判断能不能换主题值，不能批量替换。
- **密集列表的模糊降级是白名单式**：只有 8 个明确的长列表页（设备详情/Docker/路由表/启动项/进程/
  WiFi/流量报表/仪表盘设备列表）改用 `listCardBlur()`（降到控件级）；其余含 `ForEach` 的页面仍用页级
  blur 28，若后续出现大量行列表需继续归类。
- 8 套色板 × 2 材质 = 16 种组合，没有视觉回归测试；新增色板靠人眼过主要页面。
- `IconPack` 的另外 4 套渲染分支与 ~380 个图标资源仍随包发布，属待清理死重量（只删了选择入口）。
