/**
 * DeviceManagePage - 设备管理页（应用中心入口）
 * 原底部导航「设备」Tab 移入应用中心后的独立页面
 */
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { DeviceTab } from '../dashboard/DeviceTab'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
export struct DeviceManagePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44

  aboutToAppear(): void {
    this.loadTopSafeArea()
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 4, right: 12, top: 2, bottom: 2 })
        }
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Text('设备管理')
          .fontSize(17)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      DeviceTab({ theme: this.theme })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
