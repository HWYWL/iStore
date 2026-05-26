import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { RouteEntry } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct RouteTablePage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State routes: RouteEntry[] = []

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
      this.routes = await api.fetchRoutes()
    } catch (e) {
      this.errorText = '加载路由表失败'
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
            Text(' 路由表')
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
              hilog.error(0x0001, 'RouteTablePage', `router.back failed: ${e}`)
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
            } else if (this.routes.length === 0) {
              Column() {
                Text('无路由条目')
                  .fontSize(14)
                  .fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            } else {
              ForEach(this.routes, (route: RouteEntry, index: number) => {
                Column() {
                  Row() {
                    Text(route.destination || 'default')
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Bold)
                    Blank()
                    if (route.table) {
                      Row() {
                        Text('table ')
                          .fontSize(10)
                          .fontColor(this.theme.textTertiary)
                        Text(route.table)
                          .fontSize(11)
                          .fontColor(this.theme.primary)
                      }
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(8)
                      .backgroundColor(this.theme.bgGlassLight)
                      .border({ width: 0.5, color: this.theme.borderGlass })
                    }
                  }
                  .width('100%')

                  if (route.gateway || route.device || route.source) {
                    Row() {
                      if (route.gateway) {
                        Column() {
                          Text('网关')
                            .fontSize(9)
                            .fontColor(this.theme.textTertiary)
                          Text(route.gateway)
                            .fontSize(12)
                            .fontColor(this.theme.textSecondary)
                            .fontFamily('monospace')
                            .margin({ top: 2 })
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }
                      if (route.device) {
                        Column() {
                          Text('设备')
                            .fontSize(9)
                            .fontColor(this.theme.textTertiary)
                          Text(route.device)
                            .fontSize(12)
                            .fontColor(this.theme.textSecondary)
                            .fontFamily('monospace')
                            .margin({ top: 2 })
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }
                      if (route.source) {
                        Column() {
                          Text('源地址')
                            .fontSize(9)
                            .fontColor(this.theme.textTertiary)
                          Text(route.source)
                            .fontSize(12)
                            .fontColor(this.theme.textSecondary)
                            .fontFamily('monospace')
                            .margin({ top: 2 })
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }
                    }
                    .width('100%')
                    .margin({ top: 6 })
                  }

                  if (route.scope) {
                    Row() {
                      Text('Scope: ')
                        .fontSize(11)
                        .fontColor(this.theme.textTertiary)
                      Text(route.scope)
                        .fontSize(12)
                        .fontColor(this.theme.info)
                    }
                    .width('100%')
                    .margin({ top: 4 })
                  }
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .margin({ top: index === 0 ? 0 : 8 })
              }, (route: RouteEntry, index: number): string => `${route.destination}_${route.table}_${index}`)
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
