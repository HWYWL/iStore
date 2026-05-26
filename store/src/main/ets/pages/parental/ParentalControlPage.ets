import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { OafStatus } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct ParentalControlPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State subTab: number = 0
  @State isLoading: boolean = true
  @State oafStatus: OafStatus = {
    pluginVersion: '', engineVersion: '', kernelVersion: '',
    configStatus: '', filterStatus: '', engineStatus: '', versionTooHigh: false
  }
  @State errorText: string = ''

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

    this.loadStatus()
  }

  async loadStatus(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      this.oafStatus = await api.fetchOafStatus()
    } catch (e) {
      this.errorText = '加载状态失败'
    }
    this.isLoading = false
  }

  getStatusColor(status: string): string {
    if (!status) {
      return this.theme.textTertiary
    }
    if (status === 'running' || status === 'active' || status === 'enabled') {
      return this.theme.success
    }
    return this.theme.danger
  }

  getStatusLabel(status: string): string {
    if (!status) {
      return '未知'
    }
    if (status === 'running' || status === 'active' || status === 'enabled') {
      return '正常'
    }
    return '异常'
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
            Text(' 家长控制')
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
              hilog.error(0x0001, 'ParentalControlPage', `router.back failed: ${e}`)
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

        Row() {
          Row() {
            Text('状态')
              .fontSize(13)
              .fontColor(this.subTab === 0 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 0 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 0 })

          Row() {
            Text('设置')
              .fontSize(13)
              .fontColor(this.subTab === 1 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 1 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 1 })
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(12)
        .backgroundColor(this.theme.bgCard)
        .margin({ left: 16, right: 16, bottom: 8 })

        Scroll() {
          Column() {
            if (this.subTab === 0) {
              this.StatusTab()
            }
            if (this.subTab === 1) {
              this.SettingsTab()
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

  @Builder
  StatusTab() {
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
        Row() {
          Text('⚠')
            .fontSize(16)
            .margin({ right: 8 })
          Text(this.errorText)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        Column() {
          Text('重试')
            .fontSize(14)
            .fontColor(this.theme.primary)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { this.loadStatus() })
      } else {
        Column() {
          Text('🚦 运行状态')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 12 })
            .width('100%')

          this.statusRow('插件版本', this.oafStatus.pluginVersion || '--')
          this.statusRow('引擎版本', this.oafStatus.engineVersion || '--')
          this.statusRow('内核版本', this.oafStatus.kernelVersion || '--')

          Text('状态指示器')
            .fontSize(12)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 14, bottom: 8 })
            .width('100%')

          this.statusIndicatorRow('配置状态', this.oafStatus.configStatus)
          this.statusIndicatorRow('过滤状态', this.oafStatus.filterStatus)
          this.statusIndicatorRow('引擎状态', this.oafStatus.engineStatus)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })

        if (this.oafStatus.versionTooHigh) {
          Row() {
            Text('⚠️')
              .fontSize(18)
              .margin({ right: 10 })
            Text('检测到插件版本过高，可能无法正常使用。建议降级至 3.2.x 版本。')
              .fontSize(12)
              .fontColor(this.theme.warning)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .margin({ top: 10 })
          .backgroundColor('rgba(255, 215, 64, 0.08)')
          .border({ width: 0.5, color: this.theme.warning })
        }
      }
    }
    .width('100%')
  }

  @Builder
  SettingsTab() {
    Column() {
      this.settingsItem('⚙️ 基础设置', '启用/禁用应用过滤、日志和工作模式', 'pages/parental/ParentalBasicPage')
      this.settingsItem('📋 应用过滤规则', '管理应用分类、过滤规则和黑白名单', 'pages/parental/ParentalFilterPage')
      this.settingsItem('🔧 高级设置', 'OAF 引擎高级配置选项', 'pages/parental/ParentalAdvancedPage')
    }
    .width('100%')
  }

  @Builder
  settingsItem(title: string, desc: string, route: string) {
    Column() {
      Row() {
        Column() {
          Text(title)
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
          Text(desc)
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('→')
          .fontSize(18)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding(16)
      .borderRadius(14)
      .margin({ top: 8 })
      .backgroundColor(this.theme.bgCard)
      .backdropBlur(20)
      .border({ width: 0.5, color: this.theme.borderGlass })
      .onClick(() => {
        try {
          this.getUIContext().getRouter().pushUrl({ url: route })
        } catch (e) {
          hilog.error(0x0001, 'ParentalControlPage', `pushUrl failed: ${e}`)
        }
      })
    }
    .width('100%')
  }

  @Builder
  statusRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .fontFamily('monospace')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }

  @Builder
  statusIndicatorRow(label: string, status: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Circle()
        .width(8)
        .height(8)
        .fill(this.getStatusColor(status))
        .margin({ right: 6 })
      Text(this.getStatusLabel(status))
        .fontSize(12)
        .fontColor(this.getStatusColor(status))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
