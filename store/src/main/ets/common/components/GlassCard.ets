/**
 * GlassCard / GlassChip —— 主题材质容器
 *
 * 页面不再自己拼 `bgCard + border + shadow`，统一换成这两个组件，材质由
 * `theme.material` 决定：
 * - `solid`：单层卡片（背景 = theme.bgCard，细描边 + 克制投影），等价于改造前的观感；
 * - `liquid`：外层 1vp 镜面渐变描边（ArkUI 的 border 不支持渐变，用内缩一层的 Stack 实现）
 *   + 玻璃层（渐变 tint + backdropBlur + 顶部内高光 + 双层浮起投影）。
 *
 * 长列表页传 `noBlur: true`：只用 tint 与描边、不叠实时模糊（见架构规格的性能保底约定）。
 * 用法：
 *   GlassCard({ theme: this.theme }) { Text('内容') }
 */
import { LIGHT_THEME, ThemePalette } from '../theme/ThemeColors'

const GRADIENT_ANGLE: number = 150
const INNER_INSET: number = 1

@Component
export struct GlassCard {
  /** 当前主题（含材质） */
  @Prop theme: ThemePalette = LIGHT_THEME
  /** 关闭实时模糊（长列表/图表密集页保底） */
  @Prop noBlur: boolean = false
  /** 圆角覆盖，<0 表示用材质默认值 */
  @Prop radius: number = -1
  @Prop paddingTop: number = 14
  @Prop paddingRight: number = 16
  @Prop paddingBottom: number = 14
  @Prop paddingLeft: number = 16
  /** 卡片内容 */
  @BuilderParam content: () => void = this.emptyContent

  @Builder
  emptyContent() {
  }

  private radiusValue(): number {
    return this.radius >= 0 ? this.radius : this.theme.material.radiusCard
  }

  private blurValue(): number {
    if (this.noBlur) {
      return 0
    }
    return this.theme.material.blur
  }

  build() {
    if (this.theme.material.kind === 'liquid') {
      this.liquidCard()
    } else {
      this.solidCard()
    }
  }

  /** 实色材质：单层卡片 */
  @Builder
  solidCard() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding({
      top: this.paddingTop,
      right: this.paddingRight,
      bottom: this.paddingBottom,
      left: this.paddingLeft
    })
    .backgroundColor(this.theme.bgCard)
    .borderRadius(this.radiusValue())
    .border({ width: 1, color: this.theme.borderGlass })
    .shadow({
      radius: this.theme.material.elevation,
      color: this.theme.material.elevationColor,
      offsetY: this.theme.material.elevationY
    })
  }

  /** 液态玻璃材质：渐变描边层（作为 Stack 底色）+ 内缩 1vp 的玻璃层 + 顶部内高光 */
  @Builder
  liquidCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.content()
      }
      .width('100%')
      .padding({
        top: this.paddingTop,
        right: this.paddingRight,
        bottom: this.paddingBottom,
        left: this.paddingLeft
      })
      .margin({ top: INNER_INSET, right: INNER_INSET, bottom: INNER_INSET, left: INNER_INSET })
      .borderRadius(this.radiusValue() - INNER_INSET)
      .linearGradient({
        angle: 180,
        colors: [[this.theme.material.tintTop, 0], [this.theme.material.tintBottom, 1]]
      })
      .backdropBlur(this.blurValue())
      .shadow({ radius: 1, color: this.theme.material.innerGlow, offsetY: 1 })

      // 顶部内高光（模拟玻璃上沿的反光）
      Row()
        .width('88%')
        .height(1)
        .margin({ top: 2, left: '6%' })
        .backgroundColor(this.theme.material.innerGlow)
    }
    .width('100%')
    .borderRadius(this.radiusValue())
    // 渐变底色只会在内层卡片遮不住的一圈（1vp）里露出，形成镜面高光描边
    .linearGradient({
      angle: GRADIENT_ANGLE,
      colors: this.theme.material.highlightStroke
    })
    .shadow({
      radius: this.theme.material.elevation,
      color: this.theme.material.elevationColor,
      offsetY: this.theme.material.elevationY
    })
  }
}

/**
 * GlassChip —— 胶囊控件（标签/状态/分段选择）
 * 与卡片同材质但更薄：更小的模糊半径与投影。
 */
@Component
export struct GlassChip {
  @Prop theme: ThemePalette = LIGHT_THEME
  @Prop label: string = ''
  /** 选中态：主色填充 */
  @Prop active: boolean = false
  /** 关闭模糊（列表内成组出现时保底） */
  @Prop noBlur: boolean = false

  private blurValue(): number {
    if (this.noBlur) {
      return 0
    }
    return this.theme.material.blurControl
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.active ? '#FFFFFF' : this.theme.textSecondary)
    }
    .padding({ left: 11, right: 11, top: 5, bottom: 5 })
    .backgroundColor(this.active ? this.theme.primary : this.theme.material.tintTop)
    .borderRadius(this.theme.material.radiusControl)
    .border({
      width: this.theme.material.kind === 'liquid' ? 1 : 0,
      color: this.theme.material.kind === 'liquid' ? this.theme.material.borderColor : this.theme.borderGlass
    })
    .backdropBlur(this.blurValue())
    .shadow({ radius: this.theme.material.kind === 'liquid' ? 16 : 0, color: this.theme.material.elevationColor, offsetY: 6 })
  }
}
