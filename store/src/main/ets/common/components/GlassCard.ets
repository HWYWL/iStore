/**
 * 毛玻璃卡片组件
 * 提供统一的半透明毛玻璃效果卡片容器，支持自定义宽高、边距和点击动画
 * 使用 @BuilderParam 插槽模式接收子组件内容
 */
import { StyleConstants } from '../constants/StyleConstants'

@Component
export struct GlassCard {
  // ========== 外观配置 ==========
  @Prop cardWidth: string = '100%'                              // 卡片宽度
  @Prop cardHeight: string = 'auto'                              // 卡片高度
  @Prop cardPadding: number = 16                                 // 内边距
  @Prop cardRadius: number = StyleConstants.RADIUS_LG            // 圆角半径
  @Prop showBorder: boolean = true                               // 是否显示边框
  @Prop glowIntensity: number = 0.08                             // 发光强度（阴影透明度）
  @Prop bgOpacity: number = 0.06                                 // 背景透明度

  // ========== 间距配置 ==========
  @Prop marginTop: number = 0                                    // 顶部外边距
  @Prop marginBottom: number = 0                                 // 底部外边距

  // ========== 交互状态 ==========
  @State pressed: boolean = false                                // 点击按下状态（触发缩放+亮度动画）

  // ========== 内容插槽（由父组件传入） ==========
  @BuilderParam content: () => void = this.EmptyContent

  @Builder EmptyContent() {}

  build() {
    Column() {
      this.content()
    }
    .width(this.cardWidth)
    .height(this.cardHeight)
    .padding(this.cardPadding)
    .borderRadius(this.cardRadius)
    .margin({ top: this.marginTop, bottom: this.marginBottom })
    // 半透明背景 + 毛玻璃效果
    .backgroundColor(`rgba(255, 255, 255, ${this.bgOpacity})`)
    .border(this.showBorder ? {
      width: 0.5,
      color: StyleConstants.BORDER_GLASS,
      style: BorderStyle.Solid
    } : {})
    .backdropBlur(20)
    // 按下时：增强阴影 + 主题色发光
    .shadow(this.pressed ? {
      radius: 24,
      color: `rgba(0, 212, 255, 0.25)`,
      offsetX: 0,
      offsetY: 2
    } : {
      radius: 16,
      color: `rgba(0, 212, 255, ${this.glowIntensity})`,
      offsetX: 0,
      offsetY: 4
    })
    // 按下时缩小 5%，释放后恢复
    .scale(this.pressed ? { x: 0.95, y: 0.95 } : { x: 1, y: 1 })
    .animation({ duration: 120, curve: Curve.Sharp })
    .brightness(this.pressed ? 1.3 : 1)
    .onClick(() => {
      this.pressed = true
      // 150ms 后自动恢复，产生"点击反馈"效果
      setTimeout(() => { this.pressed = false }, 150)
    })
  }
}
