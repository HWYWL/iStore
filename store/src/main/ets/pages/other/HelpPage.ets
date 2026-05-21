import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { router } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

interface FaqItem {
  question: string
  answer: string
}

@Entry
@Component
struct HelpPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State expandedStates: boolean[] = [false, false, false, false, false, false]
  private faqs: FaqItem[] = [
    {
      question: '如何添加设备？',
      answer: '在设备列表页面点击右上角的 + 按钮，输入设备的 IP 地址、用户名和密码即可添加。'
    },
    {
      question: '支持哪些设备？',
      answer: '支持所有运行 OpenWrt 或 iStoreOS 系统的路由器设备。'
    },
    {
      question: '如何切换深色/浅色模式？',
      answer: '在主页面或任意详情页的右上角，点击 ☀️/🌙 图标即可切换主题。'
    },
    {
      question: '家长控制功能如何使用？',
      answer: '在应用中心进入家长控制页面，需要设备安装 OpenAppFilter 插件。可以设置应用过滤规则、时间限制和用户策略。'
    },
    {
      question: '如何查看实时流量？',
      answer: '在统计页面可以查看实时带宽和系统负载图表。'
    },
    {
      question: '设备列表数据存储在哪里？',
      answer: '设备信息加密存储在本机，不会上传到任何服务器。'
    }
  ]

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
            Text(' 帮助')
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
              router.back()
            } catch (e) {
              hilog.error(0x0001, 'HelpPage', `router.back failed: ${e}`)
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
            ForEach(this.faqs, (item: FaqItem, index: number) => {
              Column() {
                Row() {
                  Text(this.expandedStates[index] ? '▼' : '▶')
                    .fontSize(12)
                    .fontColor(this.theme.primary)
                    .width(20)
                  Text(item.question)
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 2, bottom: 2 })

                if (this.expandedStates[index]) {
                  Text(item.answer)
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .lineHeight(20)
                    .width('100%')
                    .padding({ top: 8, left: 20, bottom: 2 })
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: index === 0 ? 4 : 10 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .onClick(() => {
                const newStates: boolean[] = [...this.expandedStates]
                newStates[index] = !newStates[index]
                this.expandedStates = newStates
              })
            }, (item: FaqItem, index: number): string => `${index}`)
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
