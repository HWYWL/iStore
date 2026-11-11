---
id: mod-theme
type: module-design
status: active
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
- **图标**（`IconPack.ets` + `components/AppIcon.ets`）：只剩两套渲染——`hos`（鸿蒙超椭圆素材，按皮肤亮度自动切浅/暗，默认）与
  `line`（自绘几何线稿，单色可着色，仅通过 `forcePack: 'line'` 在快捷入口/工具行使用）。用户已无图标切换入口；
  `color` / `harmony` / `ios` 三套分支与 96 个 `ic_color_*` 素材已删除。

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

## 语义色

`ThemePalette.semantic` 是"状态"用的那一层：`danger / warning / success / info / neutral`。每套色板携带
自己的语义色（info 跟随该色板的主色倾向），玻璃材质直接沿用。页面里**不得再写**
`'#FF5252'`（危险）、`'#F59E0B'`（警告）、`'#00E676'`（成功）、`'#94A3B8'`（中性）。

刻意**不**进主题的是品牌/装饰色：Docker 蓝 `#3B82F6`、iStore 绿 `#10B981`、紫 `#8B5CF6`、
粉 `#EC4899`、成就徽章与设备别名池的配色、盖在有色底上的 `#FFFFFF`。

## 动效

动效是材质的一部分，只在液态玻璃下明显（实色材质只保留最小反馈）：

| 效果 | 实现 | 位置 |
|---|---|---|
| 按压反馈 | `scale 0.985` + `.animation(120ms)`，`onTouch` 驱动 | `GlassCard`、`DashboardTab` 7 张卡、`PetPage` 4 张卡 |
| 高光渐显 | 顶部 1vp 内高光行 0.25→1，900ms | `GlassCard`（液态玻璃） |
| 数字滚动 | `RollingNumber`：16ms 步进、420ms easeOutQuad | 应用中心处理器/内存/连接统计 |
| 切主题淡入 | 整屏 0.72→1，220ms 声明式 `.animation` | `MainPage` 根节点 |

**坑（已踩）**：
- `Text.contentTransition(new NumericTextTransition())` 在本机（API 26 真机）**编译通过但运行时直接退出应用**，
  且只支持正整数。改用自绘 `RollingNumber`（定时器插值）。
- 百分比高度的装饰层（如“亮带扫过”的 `height('120%')`）会把未定高的卡片撑成整屏；
  高光只能用与内容同高的元素。
- 动画一律用声明式 `.animation()`，不要在 `@Watch`/`aboutToAppear` 里调 `getUIContext().animateTo`。

## Invariants

- **颜色只从主题取**（`this.theme.<field>` / `theme.semantic.<状态>`），**形态只从材质取**（`theme.material.*`
  或五个派生函数）。调色板缺字段先扩 `ThemePalette`，不要就地硬编码。
- **半透明强调底用 `withAlpha(theme.<field>, a)`**，不要写 `rgba(255,138,61,…)`——那是米色主色的硬拷贝，
  换到薄荷青/暮紫后会残留橙色。
- **字面色只允许三种用途**：`#FFFFFF` 之类的中性白（盖在有色底上的文字）、服务/插画品牌色
  （如 Docker 蓝、iStore 绿）、插画细节（小管家形象）。其余一律走 `theme.semantic` 或色板字段。
- **`SKINS[0]` 必须是 `LIGHT_THEME`**（默认皮肤），`AppState` 的新装默认值 `skinId='beige'`、
  `uiStyle='solid'`；旧的 `classic`/`glass` 持久值在 init 时迁移为 `solid`/`liquid`。
- **图标只经 `AppIcon`**：`hos` 是默认且唯一可直接选的口径，`line` 只能由 `forcePack` 指定；`name` 是跨包
  契约，两套包都要覆盖同名资源，缺资源回退 `SymbolGlyph`，不能渲染成空白。
- **长列表页不叠实时模糊**：`material.listBlurDisabled` 为真时，密集列表（设备列表/流量排行/进程/包管理）
  只用 tint + 描边 + 圆角，靠 `GlassCard({ noBlur: true })` 或材质派生值实现。
- **新增材质 = 往 `MATERIALS` 加一条 + 在 `applyMaterial` 分支**，不改页面。

## Known limitations

- **表面与模糊已全量材质化**：`backgroundColor(bgCard)` / 卡片描边 / 硬编码 `backdropBlur(20|28|10)`
  已由 codemod 换为 `cardTint/cardBorder/cardElevation/material.blur`（57 个页面文件、368 处），现在没有任何
  页面再自己写卡片底色或模糊半径。
- **主色/警示色硬拷贝也已收敛**（2026-11 实测）：`'#FF8A3D'`/`'#E6A800'`/`'#F0EBE0'`/`'#00C853'` 共 78 处
  改为 `theme.primary/warning/progressTrack/success`（值与默认调色板一致，默认外观不变）；67 处
  `rgba(255,138,61,…)` 强调底改为 `withAlpha(theme.<field>, a)`。
- **剩下的字面色是刻意的**：约 570 处 `#RRGGBB` / 207 处 `rgba(`，头部为 `#FFFFFF` 133（盖在有色底上的
  文字）、各服务品牌蓝/紫/绿、成就徽章与别名池的装饰配色、插画细节。它们是**品牌与装饰色**，
  不随主题——改它们会改变默认主题外观，属产品决策。
  语义状态色已全部收敛（84 处 → `theme.semantic.*`）。
- **密集列表的模糊降级是白名单式**：只有 8 个明确的长列表页（设备详情/Docker/路由表/启动项/进程/
  WiFi/流量报表/仪表盘设备列表）改用 `listCardBlur()`（降到控件级）；其余含 `ForEach` 的页面仍用页级
  blur 28，若后续出现大量行列表需继续归类。
- 8 套色板 × 2 材质 = 16 种组合，没有视觉回归测试；新增色板靠人眼过主要页面。
- **动效只覆盖核心页**：按压反馈在 `GlassCard` 与两张仪表盘/管家卡片上，数字滚动只在应用中心三个统计；
  其余页面尚未接入（性能敏感页也不建议加）。
