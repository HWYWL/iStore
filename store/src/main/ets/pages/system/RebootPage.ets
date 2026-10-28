import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
/**
 * 重启设备页面
 * 调用路由器 API 执行系统重启，提供 60 秒倒计时
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct RebootPageRoute {
  build() {
    Column() {
      RebootPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct RebootPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State isRebooting: boolean = false
  @State countdown: number = 60
  private countdownTimer: number = -1

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
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
    this.isRebooting = true
    this.countdown = 60  // 60 秒倒计时，等待设备重启完成
    this.countdownTimer = setInterval(() => {
      this.countdown--
      if (this.countdown <= 0) {
        // 倒计时结束，清理定时器并返回
        clearInterval(this.countdownTimer)
        this.countdownTimer = -1
        this.isRebooting = false
        try {
          AppNav.getInstance().back()
        } catch (e) {
          hilog.error(0x0001, 'RebootPage', `router.back failed: ${e}`)
        }
      }
    }, 1000)
  }

  async doReboot(): Promise<void> {
    this.errorText = ''
    try {
      const api = new ApiService()
      const ok = await api.rebootDevice()
      if (ok) {
        this.startCountdown()
      } else {
        this.errorText = '重启失败，请重试'
      }
    } catch (e) {
      this.errorText = '重启失败，请重试'
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        Row() {
          Row() {
            Text(' 重启设备')
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
              AppNav.getInstance().back()
            } catch (e) {
              hilog.error(0x0001, 'RebootPage', `router.back failed: ${e}`)
            }
          })
          Blank()
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
                Text('警告')
                  .fontSize(16)
                  .fontColor(this.theme.danger)
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .margin({ bottom: 10 })

              Text('重启设备会导致网络暂时中断，请确认操作。')
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
              Text('设备信息')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
                .margin({ bottom: 8 })
                .width('100%')

              Row() {
                Text('重启将使设备重新引导系统内核')
                  .fontSize(13)
                  .fontColor(this.theme.textSecondary)
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
              Text('确认重启')
                .fontSize(14)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .height(48)
            .borderRadius(14)
            .backgroundColor(this.theme.danger)
            .enabled(!this.isRebooting)
            .opacity(this.isRebooting ? 0.4 : 1)
            .onClick(() => {
              this.doReboot()
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

      if (this.isRebooting) {
        Column() {
          Column() {
            Column()
              .width(80)
              .height(80)
              .borderRadius(40)
              .border({ width: 3, color: this.theme.primary })
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

            Text('设备正在重启...')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 24 })

            Text('请耐心等待设备重新上线')
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
