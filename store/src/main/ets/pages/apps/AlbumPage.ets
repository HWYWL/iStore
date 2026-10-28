/**
 * AlbumPage — 相册独立页（从应用中心进入）
 * 复用 AlbumTab 组件（Immich 相册），顶部标题栏由 AlbumTab 内部提供
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AlbumTab } from '../dashboard/AlbumTab'
import { AppNav } from '../../common/utils/AppNav'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

@Entry
@Component
struct AlbumPageRoute {
  build() {
    Column() {
      AlbumPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct AlbumPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State topSafeArea: number = 44

  aboutToAppear(): void {
    // 状态栏避让
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 顶部：返回 + 状态栏避让（标题栏由 AlbumTab 内部提供）
      Row() {
        Text('‹ 返回')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 14, top: 5, bottom: 5 })
          .borderRadius(100)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => AppNav.getInstance().back())
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea - 8, bottom: 4 })

      AlbumTab({ theme: this.theme })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  /**
   * 拦截系统返回（含侧滑返回手势）
   * 相册处于子视图（详情/全屏查看器）时先返回列表，不退出页面
   */
  onBackPress(): boolean {
    if (AppState.getInstance().isAlbumSubView()) {
      AppState.getInstance().notifyAlbumBack()
      return true
    }
    return false
  }
}
