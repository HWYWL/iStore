import { StyleConstants } from '../constants/StyleConstants'

@Component
export struct GlassCard {
  @Prop cardWidth: string = '100%'
  @Prop cardHeight: string = 'auto'
  @Prop cardPadding: number = 16
  @Prop cardRadius: number = StyleConstants.RADIUS_LG
  @Prop showBorder: boolean = true
  @Prop glowIntensity: number = 0.08
  @Prop bgOpacity: number = 0.06
  @Prop marginTop: number = 0
  @Prop marginBottom: number = 0
  @State pressed: boolean = false
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
    .backgroundColor(`rgba(255, 255, 255, ${this.bgOpacity})`)
    .border(this.showBorder ? {
      width: 0.5,
      color: StyleConstants.BORDER_GLASS,
      style: BorderStyle.Solid
    } : {})
    .backdropBlur(20)
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
    .scale(this.pressed ? { x: 0.95, y: 0.95 } : { x: 1, y: 1 })
    .animation({ duration: 120, curve: Curve.Sharp })
    .brightness(this.pressed ? 1.3 : 1)
    .onClick(() => {
      this.pressed = true
      setTimeout(() => { this.pressed = false }, 150)
    })
  }
}
