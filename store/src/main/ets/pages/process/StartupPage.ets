import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 系统启动项页面
 * 展示路由器开机自启的服务列表及其启用状态
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { StartupItem } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct StartupPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State items: StartupItem[] = []

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      this.items = await api.fetchStartupItems()
    } catch (e) {
      this.errorText = '加载启动项失败'
    }
    this.isLoading = false
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
            Text(' 启动项')
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
              hilog.error(0x0001, 'StartupPage', `router.back failed: ${e}`)
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
          Column() {
            if (this.isLoading) {
              Column() {
                LoadingProgress().width(40).height(40).color(this.theme.primary)
                Text('加载中...')
                  .fontSize(14)
                  .fontColor(this.theme.textSecondary)
                  .margin({ top: 12 })
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            } else if (this.errorText) {
              Column() {
                Text('⚠')
                  .fontSize(24)
                  .fontColor(this.theme.warning)
                  .margin({ bottom: 8 })
                Text(this.errorText)
                  .fontSize(14)
                  .fontColor(this.theme.warning)
                  .margin({ bottom: 16 })
                Row() {
                  Text('重新加载')
                    .fontSize(14)
                    .fontColor(this.theme.primary)
                    .fontWeight(FontWeight.Medium)
                }
                .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                .borderRadius(100)
                .backgroundColor(this.theme.bgCard)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .onClick(() => {
                  this.loadData()
                })
              }
              .width('100%')
              .padding(20)
              .alignItems(HorizontalAlign.Center)
            } else if (this.items.length === 0) {
              Column() {
                Text('无启动项')
                  .fontSize(14)
                  .fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            } else {
              ForEach(this.items, (item: StartupItem, index: number) => {
                Row() {
                  Column() {
                    Text(item.name)
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Bold)
                    Text(`优先级 ${item.priority}`)
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column() {
                    Row() {
                      Text(item.enabled ? '已启用' : '已禁用')
                        .fontSize(10)
                        .fontColor('#FFFFFF')
                    }
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(6)
                    .backgroundColor(item.enabled ? this.theme.success : this.theme.danger)
                    .margin({ bottom: 4 })

                    Row() {
                      Text(item.running ? '运行中' : '已停止')
                        .fontSize(10)
                        .fontColor('#FFFFFF')
                    }
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(6)
                    .backgroundColor(item.running ? this.theme.info : this.theme.textTertiary)
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .margin({ top: index === 0 ? 0 : 8 })
              }, (item: StartupItem): string => item.name)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 40 })
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
