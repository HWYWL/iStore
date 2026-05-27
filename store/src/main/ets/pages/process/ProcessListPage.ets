import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 系统进程列表页面
 * 展示路由器运行中的进程，支持点击展开查看详情
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { ProcessInfo } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct ProcessListPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State processes: ProcessInfo[] = []
  @State expandedPid: number = -1
  private refreshTimerId: number = -1

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

    this.loadData()
    // 进程列表每 3 秒自动刷新
    this.refreshTimerId = setInterval(() => {
      this.loadData()
    }, 3000)
  }

  aboutToDisappear(): void {
    // 停止自动刷新定时器
    if (this.refreshTimerId !== -1) {
      clearInterval(this.refreshTimerId)
      this.refreshTimerId = -1
    }
  }

  async loadData(): Promise<void> {
    // 首次加载显示 loading，刷新时不显示（避免闪烁）
    this.isLoading = this.processes.length === 0
    this.errorText = ''
    try {
      const api = new ApiService()
      this.processes = await api.fetchProcessList()
    } catch (e) {
      // 仅在还没有数据时显示错误
      if (this.processes.length === 0) {
        this.errorText = '加载进程列表失败'
      }
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
            Text(' 系统进程')
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
              hilog.error(0x0001, 'ProcessListPage', `router.back failed: ${e}`)
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
            } else {
              Row() {
                Text('进程名')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text('PID')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .width(64)
                  .textAlign(TextAlign.Center)
                Text('CPU%')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .width(60)
                  .textAlign(TextAlign.Center)
                Text('内存')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .width(72)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .padding({ left: 12, right: 8, top: 8, bottom: 8 })
              .border({ width: { bottom: 0.5 }, color: this.theme.borderGlass })

              ForEach(this.processes, (proc: ProcessInfo, index: number) => {
                Column() {
                  Row() {
                    Text(proc.name || '(unknown)')
                      .fontSize(13)
                      .fontColor(this.theme.textPrimary)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${proc.pid}`)
                      .fontSize(12)
                      .fontColor(this.theme.textSecondary)
                      .fontFamily('monospace')
                      .width(64)
                      .textAlign(TextAlign.Center)
                    Text(`${proc.cpu.toFixed(1)}%`)
                      .fontSize(12)
                      .fontColor(proc.cpu > 50 ? this.theme.danger : proc.cpu > 10 ? this.theme.warning : this.theme.textSecondary)
                      .fontFamily('monospace')
                      .width(60)
                      .textAlign(TextAlign.Center)
                    Text(FormatUtils.formatBytes(proc.mem))
                      .fontSize(12)
                      .fontColor(this.theme.textSecondary)
                      .fontFamily('monospace')
                      .width(72)
                      .textAlign(TextAlign.End)
                  }
                  .width('100%')
                  .padding({ left: 12, right: 8, top: 10, bottom: 10 })
                  .backgroundColor(index % 2 === 0 ? this.theme.bgGlassLight : Color.Transparent)
                  .onClick(() => {
                    if (this.expandedPid === proc.pid) {
                      this.expandedPid = -1
                    } else {
                      this.expandedPid = proc.pid
                    }
                  })

                  if (this.expandedPid === proc.pid) {
                    Column() {
                      this.detailRow('PID', `${proc.pid}`)
                      this.detailRow('PPID', `${proc.ppid}`)
                      this.detailRow('用户', proc.user || '-')
                      this.detailRow('状态', proc.status || '-')
                      Row() {
                        Text('命令')
                          .fontSize(10)
                          .fontColor(this.theme.textTertiary)
                          .width(48)
                        Text(proc.command || '-')
                          .fontSize(12)
                          .fontColor(this.theme.textSecondary)
                          .fontFamily('monospace')
                          .layoutWeight(1)
                      }
                      .width('100%')
                      .margin({ top: 2 })
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 8, bottom: 12 })
                    .backgroundColor(this.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)')
                    .border({ width: { top: 0.5 }, color: this.theme.borderGlass })
                  }
                }
              }, (proc: ProcessInfo): string => `${proc.pid}`)
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

  @Builder detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontColor(this.theme.textTertiary)
        .width(48)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .fontFamily('monospace')
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 2 })
  }
}
