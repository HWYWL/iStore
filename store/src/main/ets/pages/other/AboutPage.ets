import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 关于页面
 * 展示应用信息：版本号、技术栈、开源许可等
 */
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct AboutPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME

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
            Text(' 关于')
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
              hilog.error(0x0001, 'AboutPage', `router.back failed: ${e}`)
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
              Text('📦')
                .fontSize(48)
                .margin({ bottom: 12 })

              Text('iStore')
                .fontSize(28)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4 })

              Text('基于 OpenWrt 的设备管理工具')
                .fontSize(14)
                .fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .borderRadius(14)
            .margin({ top: 4 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .alignItems(HorizontalAlign.Center)

            Column() {
              this.infoRow('版本', '1.0.0')
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('iStore 是一款鸿蒙原生 OpenWrt 路由器管理客户端，支持设备监控、网络管理、终端查看、应用控制等功能。')
                .fontSize(12)
                .fontColor(this.theme.textSecondary)
                .lineHeight(20)
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('鸣谢')
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })

              this.infoRow('开发框架', 'HarmonyOS NEXT ArkTS')
              this.infoRow('通信协议', 'ubus JSON-RPC over HTTP')

              Row() {
                Text('开源地址')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                  .width(68)
                Text('github.com')
                  .fontSize(12)
                  .fontColor(this.theme.primary)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Text('© 2025 iStore Team')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 20, bottom: 12 })
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

  @Builder infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
