import { StyleConstants } from '../constants/StyleConstants'

@Component
export struct BottomNavBar {
  @Link currentIndex: number
  private onTabChange?: (index: number) => void

  @State tabs: NavTab[] = [
    { name: '仪表盘', icon: 'dashboard', index: 0 },
    { name: '设备', icon: 'device', index: 1 },
    { name: '网络', icon: 'network', index: 2 },
    { name: '插件', icon: 'plugin', index: 3 }
  ]

  build() {
    Row() {
      ForEach(this.tabs, (tab: NavTab) => {
        Column() {
          if (tab.icon === 'dashboard') {
            Text(this.currentIndex === tab.index ? '⊞' : '⊡')
              .fontSize(22)
              .fontColor(this.currentIndex === tab.index ? StyleConstants.PRIMARY : StyleConstants.TEXT_TERTIARY)
          }
          if (tab.icon === 'device') {
            Text(this.currentIndex === tab.index ? '⫸' : '⫷')
              .fontSize(22)
              .fontColor(this.currentIndex === tab.index ? StyleConstants.PRIMARY : StyleConstants.TEXT_TERTIARY)
          }
          if (tab.icon === 'network') {
            Text(this.currentIndex === tab.index ? '⟐' : '⟐')
              .fontSize(22)
              .fontColor(this.currentIndex === tab.index ? StyleConstants.PRIMARY : StyleConstants.TEXT_TERTIARY)
          }
          if (tab.icon === 'plugin') {
            Text(this.currentIndex === tab.index ? '⧩' : '⧨')
              .fontSize(22)
              .fontColor(this.currentIndex === tab.index ? StyleConstants.PRIMARY : StyleConstants.TEXT_TERTIARY)
          }

          Text(tab.name)
            .fontSize(11)
            .fontColor(this.currentIndex === tab.index ? StyleConstants.TEXT_PRIMARY : StyleConstants.TEXT_TERTIARY)
            .margin({ top: 2 })
            .fontWeight(this.currentIndex === tab.index ? FontWeight.Medium : FontWeight.Normal)

          if (this.currentIndex === tab.index) {
            Circle()
              .width(4)
              .height(4)
              .fill(StyleConstants.PRIMARY)
              .margin({ top: 4 })
              .shadow({
                radius: 6,
                color: 'rgba(0, 212, 255, 0.5)',
                offsetX: 0,
                offsetY: 0
              })
          } else {
            Circle()
              .width(4)
              .height(4)
              .fill('transparent')
              .margin({ top: 4 })
          }
        }
        .flexGrow(1)
        .height(60)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.currentIndex = tab.index
          if (this.onTabChange) {
            this.onTabChange(tab.index)
          }
        })
      })
    }
    .width('100%')
    .height(StyleConstants.BOTTOM_TAB_HEIGHT + 8)
    .padding({ bottom: 8, left: 8, right: 8 })
    .backgroundColor('rgba(10, 14, 39, 0.85)')
    .backdropBlur(30)
    .border({
      width: { top: 0.5 },
      color: StyleConstants.BORDER_GLASS,
      style: BorderStyle.Solid
    })
  }
}

interface NavTab {
  name: string
  icon: string
  index: number
}
