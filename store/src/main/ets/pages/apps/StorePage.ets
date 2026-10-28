/**
 * SmallStorePage — iStore 商店（由应用中心进入）
 *
 * 原先是底部导航的一个 Tab，取消底部导航后改为独立页面：
 * - 窄屏：路由全屏打开
 * - 宽屏：作为页面挂到右侧面板（AppNav / PageHost）
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AppNav } from '../../common/utils/AppNav'
import { IStoreTabView } from '../dashboard/IStoreTabView'

@Entry
@Component
struct StorePageRoute {
  build() {
    Column() {
      StorePage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct StorePage {
  @State theme: ThemePalette = LIGHT_THEME

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
  }

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({ angle: 135, colors: this.theme.pageGradient })

      Column() {
        // 顶栏：返回
        Row() {
          Text('‹ 返回')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 12, right: 16, top: 6, bottom: 6 })
            .borderRadius(100)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .onClick(() => AppNav.getInstance().back())
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Column() {
          IStoreTabView({ theme: this.theme })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
