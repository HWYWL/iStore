import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 恢复出厂设置页面
 * 调用路由器 API 执行恢复出厂设置，操作前需二次确认
 * 提供 60 秒倒计时反馈
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct FactoryResetPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State isResetting: boolean = false
  @State countdown: number = 60
  private countdownTimer: number = -1

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()
    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })
    this.loadData()
  }

  aboutToDisappear(): void {
    // 离开页面时清理倒计时定时器，防止内存泄漏
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = -1
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    // 模拟加载延迟，给用户过渡感
    await new Promise<void>((r) => setTimeout(r, 300))
    this.isLoading = false
  }

  startCountdown(): void {
    this.isResetting = true
    this.countdown = 60  // 60 秒倒计时
    // 每秒递减，归零后自动返回上一页
    this.countdownTimer = setInterval(() => {
      this.countdown--
      if (this.countdown <= 0) {
        clearInterval(this.countdownTimer)
        this.countdownTimer = -1
        this.isResetting = false
        try {
          this.getUIContext().getRouter().back()
        } catch (e) {
          hilog.error(0x0001, 'FactoryResetPage', `router.back failed: ${e}`)
        }
      }
    }, 1000)
  }

  async doFactoryReset(): Promise<void> {
    this.errorText = ''
    try {
      const api = new ApiService()
      const result = await api.factoryReset()
      if (result) {
        this.startCountdown()
      } else {
        this.errorText = '恢复出厂设置失败，请重试'
      }
    } catch (e) {
      this.errorText = '恢复出厂设置失败，请重试'
    }
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
            Text(' 恢复出厂设置')
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
              hilog.error(0x0001, 'FactoryResetPage', `router.back failed: ${e}`)
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
            Column() {
              Row() {
                Text('⚠️')
                  .fontSize(22)
                  .margin({ right: 10 })
                Text('严重警告')
                  .fontSize(16)
                  .fontColor(this.theme.danger)
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .margin({ bottom: 10 })

              Text('此操作将清除所有配置，设备将恢复到出厂状态。此操作不可撤销！')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
                .lineHeight(20)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 1, color: this.theme.danger })
            .margin({ bottom: 24 })

            Column() {
              Text('影响说明')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 8 })
                .width('100%')

              Column() {
                Row() {
                  Text('• 所有网络配置将被清除')
                    .fontSize(13)
                    .fontColor(this.theme.textSecondary)
                }
                .width('100%')
                .margin({ bottom: 6 })

                Row() {
                  Text('• 所有已安装的应用将被删除')
                    .fontSize(13)
                    .fontColor(this.theme.textSecondary)
                }
                .width('100%')
                .margin({ bottom: 6 })

                Row() {
                  Text('• 设备需要重新配置才能使用')
                    .fontSize(13)
                    .fontColor(this.theme.textSecondary)
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
            }
            .width('100%')
            .margin({ bottom: 24 })

            if (this.errorText) {
              Text(this.errorText)
                .fontSize(12)
                .fontColor(this.theme.danger)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 12 })
            }

            Button() {
              Text('确认恢复出厂设置')
                .fontSize(14)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .height(48)
            .borderRadius(14)
            .backgroundColor(this.theme.danger)
            .enabled(!this.isResetting)
            .opacity(this.isResetting ? 0.4 : 1)
            .onClick(() => {
              try {
                const dialogController: CustomDialogController = new CustomDialogController({
                  builder: FactoryResetConfirmDialog({
                    theme: this.theme,
                    onConfirm: () => this.doFactoryReset()
                  }),
                  autoCancel: true,
                  alignment: DialogAlignment.Center
                })
                dialogController.open()
              } catch (e) {
                hilog.error(0x0001, 'FactoryResetPage', `CustomDialogController.open failed: ${e}`)
              }
            })
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

      if (this.isResetting) {
        Column() {
          Column() {
            Column()
              .width(80)
              .height(80)
              .borderRadius(40)
              .border({ width: 3, color: this.theme.danger })
              .justifyContent(FlexAlign.Center)

            Text(String(this.countdown))
              .fontSize(40)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .position({ x: 0, y: 0 })
              .width(80)
              .height(80)
              .textAlign(TextAlign.Center)
              .lineHeight(80)

            Text('设备正在恢复出厂设置...')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 24 })

            Text('此过程大约需要 1 分钟')
              .fontSize(13)
              .fontColor(this.theme.textSecondary)
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.65)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}

@CustomDialog
struct FactoryResetConfirmDialog {
  controller: CustomDialogController
  theme: ThemePalette = DARK_THEME
  onConfirm: () => void = () => {}

  build() {
    Column() {
      Text('恢复出厂设置')
        .fontSize(18)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Text('此操作将清除所有配置并恢复出厂状态，确定要执行吗？')
        .fontSize(14)
        .fontColor(this.theme.textSecondary)
        .lineHeight(20)
        .margin({ bottom: 24 })

      Row() {
        Button('取消')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(this.theme.bgCard)
          .borderRadius(10)
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => this.controller.close())

        Button('确定恢复')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.theme.danger)
          .borderRadius(10)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.controller.close()
            this.onConfirm()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
  }
}
