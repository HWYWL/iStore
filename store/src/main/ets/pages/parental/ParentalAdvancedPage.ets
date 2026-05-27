import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 家长控制 - 高级设置
 * 管理自动加载引擎、禁用 NAT 等高级选项
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct ParentalAdvancedPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State isLoading: boolean = true
  @State isSaving: boolean = false
  @State errorText: string = ''
  @State successText: string = ''
  @State autoLoadEngine: boolean = true
  @State disableNat: boolean = false
  @State lanIfname: string = 'br-lan'

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
      // 从 API 获取高级配置对象
      const adv: ESObject = await api.fetchAppFilterAdv()
      if (adv && typeof adv === 'object') {
        // 安全读取自动加载引擎开关
        const autoVal: Object | undefined = adv['auto_load_engine']
        if (autoVal !== undefined) {
          this.autoLoadEngine = Boolean(autoVal)
        }
        // 安全读取禁用 NAT 开关
        const natVal: Object | undefined = adv['disable_nat']
        if (natVal !== undefined) {
          this.disableNat = Boolean(natVal)
        }
        // 安全读取 LAN 网络接口名称
        const ifnameVal: Object | undefined = adv['lan_ifname']
        if (ifnameVal !== undefined && ifnameVal !== null) {
          this.lanIfname = String(ifnameVal)
        }
      }
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
      // 构造参数字典，键名与路由器 API 保持一致
      const advParams: Record<string, Object> = {}
      advParams['auto_load_engine'] = this.autoLoadEngine
      advParams['disable_nat'] = this.disableNat
      advParams['lan_ifname'] = this.lanIfname
      await api.saveAppFilterAdv(advParams)
      this.successText = '保存成功'
      setTimeout(() => {
        this.successText = ''  // 2 秒后隐藏成功提示
      }, 2000)
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
            Text(' 高级设置')
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
              hilog.error(0x0001, 'ParentalAdvancedPage', `router.back failed: ${e}`)
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
                Text('引擎配置')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 8 })
                  .width('100%')

                Row() {
                  Column() {
                    Text('自动加载引擎')
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text('系统启动时自动加载应用过滤引擎')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.autoLoadEngine })
                    .selectedColor(this.theme.primary)
                    .onChange((isOn: boolean) => {
                      this.autoLoadEngine = isOn
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
                    Text('禁用 NAT 加速')
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text('关闭硬件 NAT 加速以启用深度包检测')
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.disableNat })
                    .selectedColor(this.theme.primary)
                    .onChange((isOn: boolean) => {
                      this.disableNat = isOn
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .margin({ top: 8 })
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })

                Text('网络接口')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 18, bottom: 8 })
                  .width('100%')

                Column() {
                  Text('LAN 接口名称')
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .margin({ bottom: 8 })

                  TextInput({ text: this.lanIfname })
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .placeholderColor(this.theme.textTertiary)
                    .backgroundColor(this.theme.bgDark)
                    .borderRadius(10)
                    .border({ width: 0.5, color: this.theme.borderGlass })
                    .padding({ left: 12, right: 12 })
                    .onChange((value: string) => {
                      this.lanIfname = value
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
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
