---
id: mod-theme
type: module-design
status: draft
title: 模块：主题、皮肤与图标体系
parent: istore-architecture
---

## Responsibility

让"换一套皮肤"能一次性改变全应用的观感，而不是逐页改代码。两件事各管一半，互不重叠：

- **配色（`common/theme/ThemeColors.ets`）**：`ThemePalette` 调色板接口（primary/secondary/accent +
  语义色 + 背景/卡片/文字/描边等）→ `LIGHT_THEME`（默认米色经典）→ `SKINS` 皮肤表（15 套）→
  `getSkinById()`。另有两个与皮肤**正交**的维度：`UI_STYLES`（`classic` 实色 / `glass` 薄玻璃）与
  `toGlassTheme()`（把任意皮肤转成半透明 + 提亮描边 + 收敛投影的原生薄玻璃版本）。
- **图标（`common/theme/IconPack.ets` + `common/components/AppIcon.ets`）**：5 种图标包
  （`hos` 鸿蒙超椭圆 / `color` 彩色渐变 / `line` 几何线稿 / `harmony` SymbolGlyph 原生多色 / `ios` 圆角底），
  每包一套 `name → Resource` 映射；`AppIcon({ name, iconSize, colors })` 是唯一渲染入口，读
  `AppStorage('iconPackId')` 决定用哪包，切换后已渲染页面即时刷新。

## Boundary

- 依赖：只有系统 `Resource` 与 `AppStorage`，**不依赖** `AppState`（由调用方传入调色板）、不依赖任何 store/api。
- 被依赖：几乎全部页面（页面持 `@State theme: ThemePalette = LIGHT_THEME`，在 `AppState.onThemeChange`
  里换成当前皮肤）、`PageRegistry`（磁贴图标名）、`mod-pet` 的装扮（复用 `SKINS` id）。
- 不做：不持久化选择（`AppState` 负责）、不渲染布局、不知道自己在哪个页面。

## Invariants

- **颜色只从调色板取**：页面用 `this.theme.xxx`，不写 `#RRGGBB`。新增视觉元素时若调色板缺字段，先扩
  `ThemePalette` 与 `LIGHT_THEME`，再在皮肤里补齐——不要就地硬编码。
- **新增皮肤 = 往 `SKINS` 追加一条**（id/name/desc/preview 2–3 个代表色/theme），不改页面；`beige`
  必须保持第一项且等于 `LIGHT_THEME`（默认值）。
- **图标只经 `AppIcon`**：`name` 是跨包契约，五种包都要覆盖同一个名字；缺资源时必须有回退（`hasColorRes`/
  `hasLineRes` 的判定），不能让某个图标包下出现空白。
- **图标包与皮肤是两个独立维度**：换皮肤不换图标包，反之亦然；两者都经 `AppStorage` 镜像保持跨页面一致。
- `UI_STYLES` 只经 `toGlassTheme` 影响材质，不允许改主色。

## Known limitations

- **约定未完全落实**：仍有大量页面内硬编码色值（`PetPage` 70 处、`AppsPage` 46 处、`SmartHubPage` 32 处），
  换皮肤时这些地方不会跟随；属于已知待收敛项，不是设计意图。
- 15 套皮肤 × 2 种 UI 风格 × 5 种图标包 = 150 种组合，没有视觉回归测试，新增皮肤靠人眼过一遍主要页面。
- `SKINS` 与 `IconPack` 的资源命名是手工维护的字符串契约，新增图标名漏掉某个包不会报错。
