import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 工具/应用页面
 * 以网格卡片形式展示系统工具入口列表：
 * 家长控制、路由表、系统进程、启动项、重启、恢复出厂、OpenWRT 首页
 */
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'

interface ToolEntry {
  emoji: string
  name: string
  route: string
}

@Entry
@Component
struct AppsPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  private tools: ToolEntry[] = [
    { emoji: '👨‍👩‍👧', name: '家长控制', route: 'pages/parental/ParentalControlPage' },
    { emoji: '🗺', name: '路由表', route: 'pages/network/RouteTablePage' },
    { emoji: '⚙️', name: '系统进程', route: 'pages/process/ProcessListPage' },
    { emoji: '🚀', name: '启动项', route: 'pages/process/StartupPage' },
    { emoji: '🔄', name: '重启', route: 'pages/system/RebootPage' },
    { emoji: '🔙', name: '恢复出厂', route: 'pages/system/FactoryResetPage' },
    { emoji: '🌐', name: 'OpenWRT 首页', route: 'pages/apps/WebViewPage' }
  ]

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.isDark
            ? [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]]
            : [['#E8ECF1', 0], ['#F5F7FA', 0.5], ['#E8ECF1', 1]]
        })

      Column() {
        Row() {
          Row() {
            Text('←')
              .fontSize(18)
              .fontColor(this.theme.primary)
            Text(' 应用中心')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try {
              this.getUIContext().getRouter().back()
            } catch (e) {
              hilog.error(0x0001, 'AppsPage', `router.back failed: ${e}`)
            }
          })

          Blank()

          Row() {
            Text(this.isDark ? '☀️' : '🌙')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            AppState.getInstance().toggleTheme()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Scroll() {
          Grid() {
            ForEach(this.tools, (tool: ToolEntry) => {
              GridItem() {
                Column() {
                  Text(tool.emoji)
                    .fontSize(32)
                    .width(56)
                    .height(56)
                    .borderRadius(16)
                    .backgroundColor(this.theme.bgGlassLight)
                    .textAlign(TextAlign.Center)

                  Row() {
                    Text(tool.name)
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Blank()
                    Text('→')
                      .fontSize(16)
                      .fontColor(this.theme.textTertiary)
                  }
                  .width('100%')
                  .margin({ top: 10 })
                }
                .width('100%')
                .padding(16)
                .borderRadius(16)
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .onClick(() => {
                  try {
                    this.getUIContext().getRouter().pushUrl({ url: tool.route })
                  } catch (e) {
                    hilog.error(0x0001, 'AppsPage', `pushUrl failed: ${e}`)
                  }
                })
              }
            }, (tool: ToolEntry): string => tool.route)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
