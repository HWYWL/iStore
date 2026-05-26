import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { AppFilterBase } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct ParentalBasicPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State isSaving: boolean = false
  @State errorText: string = ''
  @State successText: string = ''
  @State appFilterEnabled: boolean = false
  @State appLogEnabled: boolean = false
  @State workMode: string = 'gateway'

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
      const base: AppFilterBase = await api.fetchAppFilterBase()
      this.appFilterEnabled = base.appFilterEnabled
      this.appLogEnabled = base.appLogEnabled
      this.workMode = base.workMode
    } catch (e) {
      this.errorText = '加载设置失败'
    }
    this.isLoading = false
  }

  async doSave(): Promise<void> {
    this.isSaving = true
    this.errorText = ''
    this.successText = ''
    try {
      const api = new ApiService()
      const base: AppFilterBase = {
        appFilterEnabled: this.appFilterEnabled,
        appLogEnabled: this.appLogEnabled,
        workMode: this.workMode as 'gateway' | 'bypass'
      }
      await api.saveAppFilterBase(base)
      this.successText = '保存成功'
      setTimeout(() => { this.successText = '' }, 2000)
    } catch (e) {
      this.errorText = '保存失败'
    }
    this.isSaving = false
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
            Text(' 基础设置')
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
              hilog.error(0x0001, 'ParentalBasicPage', `router.back failed: ${e}`)
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
            } else {
              Column() {
                Text('应用过滤')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 8 })
                  .width('100%')

                Row() {
                  Column() {
                    Text('启用应用过滤')
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text('控制是否启用应用层过滤功能')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.appFilterEnabled })
                    .selectedColor(this.theme.primary)
                    .onChange((isOn: boolean) => {
                      this.appFilterEnabled = isOn
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })

                Row() {
                  Column() {
                    Text('启用应用日志')
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text('记录应用访问日志用于审计')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.appLogEnabled })
                    .selectedColor(this.theme.primary)
                    .onChange((isOn: boolean) => {
                      this.appLogEnabled = isOn
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .margin({ top: 8 })
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })

                Text('工作模式')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 18, bottom: 8 })
                  .width('100%')

                Row() {
                  Column() {
                    Text('网关模式')
                      .fontSize(14)
                      .fontColor(this.workMode === 'gateway' ? this.theme.primary : this.theme.textPrimary)
                      .fontWeight(this.workMode === 'gateway' ? FontWeight.Medium : FontWeight.Normal)
                    Text('作为网关过滤所有流量')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Radio({ value: 'gateway', group: 'workMode' })
                    .checked(this.workMode === 'gateway')
                    .radioStyle({ checkedBackgroundColor: this.theme.primary })
                    .onChange((isChecked: boolean) => {
                      if (isChecked) {
                        this.workMode = 'gateway'
                      }
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })

                Row() {
                  Column() {
                    Text('旁路模式')
                      .fontSize(14)
                      .fontColor(this.workMode === 'bypass' ? this.theme.primary : this.theme.textPrimary)
                      .fontWeight(this.workMode === 'bypass' ? FontWeight.Medium : FontWeight.Normal)
                    Text('仅监控而不阻断流量')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Radio({ value: 'bypass', group: 'workMode' })
                    .checked(this.workMode === 'bypass')
                    .radioStyle({ checkedBackgroundColor: this.theme.primary })
                    .onChange((isChecked: boolean) => {
                      if (isChecked) {
                        this.workMode = 'bypass'
                      }
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .margin({ top: 8 })
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })

                if (this.errorText) {
                  Text(this.errorText)
                    .fontSize(12)
                    .fontColor(this.theme.danger)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 16 })
                }

                if (this.successText) {
                  Text(this.successText)
                    .fontSize(12)
                    .fontColor(this.theme.success)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 16 })
                }

                Button() {
                  Text('保存设置')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Medium)
                }
                .width('100%')
                .height(48)
                .borderRadius(14)
                .margin({ top: 20 })
                .linearGradient({
                  angle: 135,
                  colors: [[this.theme.primary, 0], [this.theme.secondary, 1]]
                })
                .enabled(!this.isSaving)
                .onClick(() => {
                  this.doSave()
                })
              }
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
