/**
 * DockerPage — Docker 管理（由应用中心进入）
 *
 * 原先是底部导航的一个 Tab，取消底部导航后改为独立页面：
 * - 窄屏：路由全屏打开
 * - 宽屏：作为页面挂到右侧面板（AppNav / PageHost）
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AppNav } from '../../common/utils/AppNav'
import { DockerTab } from '../dashboard/DockerTab'

@Entry
@Component
export struct DockerPage {
  @State theme: ThemePalette = LIGHT_THEME

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    // DockerTab 以前台感知 Tab 索引决定是否轮询：Docker 对应 index 3
    AppState.getInstance().setCurrentTab(3)
  }

  aboutToDisappear(): void {
    AppState.getInstance().setCurrentTab(0)
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
          DockerTab({ theme: this.theme })
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
