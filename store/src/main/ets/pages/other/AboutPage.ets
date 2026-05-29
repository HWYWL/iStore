import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'

const CURRENT_VERSION = '1.3.1'
const PROJECT_URL = 'https://github.com/HWYWL/iStore'

@Entry
@Component
struct AboutPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State latestVersion: string = '加载中...'
  @State isReady: boolean = false

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

    try {
      const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
      if (params && params['latestVersion']) {
        this.latestVersion = params['latestVersion'] as string
      } else {
        this.latestVersion = '未知'
      }
    } catch (_) {
      this.latestVersion = '未知'
    }
    this.isReady = true
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
          .width(36).height(36).borderRadius(18)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .justifyContent(FlexAlign.Center)
          .onClick(() => { AppState.getInstance().toggleTheme() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Scroll() {
          Column() {
            Column() {
              Image($r('app.media.logo'))
                .width(72).height(72).borderRadius(18)
                .objectFit(ImageFit.Cover)
                .margin({ bottom: 12 })

              Text('iStore')
                .fontSize(26)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4 })

              Text('基于 OpenWrt 的路由器管理工具')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .padding({ top: 20, bottom: 20 })
            .borderRadius(14)
            .margin({ top: 4 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .alignItems(HorizontalAlign.Center)

            Column() {
              Text('版本信息')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('当前版本', CURRENT_VERSION)
              this.infoRow('最新版本', this.isReady ? this.latestVersion : '加载中...',
                this.latestVersion !== '未知' && this.latestVersion !== '加载中...' ? this.theme.success : this.theme.textSecondary)
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('作者信息')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('作者', '一叶秋枫')
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('项目地址')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              Row() {
                Text(PROJECT_URL)
                  .fontSize(11)
                  .fontColor(this.theme.primary)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(' 🔗')
                  .fontSize(14)
                  .margin({ left: 6 })
              }
              .width('100%')
              .onClick(() => {
                try {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
                  ctx.openLink(PROJECT_URL)
                } catch (e) {
                  hilog.error(0x0001, 'AboutPage', `openLink failed: ${e}`)
                }
              })
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
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('开发框架', 'HarmonyOS NEXT ArkTS')
              this.infoRow('系统要求', 'HarmonyOS 6.1.0+')
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Text('© 2026 iStore Team')
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

  @Builder infoRow(label: string, value: string, valueColor?: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Text(value)
        .fontSize(12)
        .fontColor(valueColor || this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
