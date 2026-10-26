import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
/**
 * 帮助页面
 * FAQ 常见问题解答，支持展开/折叠查看
 */
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

interface FaqItem {
  question: string
  answer: string
}

@Entry
@Component
struct HelpPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State expandedStates: boolean[] = [false, false, false, false, false, false]
  private faqs: FaqItem[] = [
    {
      question: '如何添加设备？',
      answer: '在设备列表页面点击右上角的 + 按钮，输入设备的 IP 地址、用户名和密码即可添加。'
    },
    {
      question: '支持哪些设备？',
      answer: '支持所有运行 OpenWrt 系统的路由器设备（含 iStoreOS 等衍生版本）。'
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
      question: '设备列表数据存储在哪里？',
      answer: '设备信息加密存储在本机，不会上传到任何服务器。'
    }
  ]

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()

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
              AppNav.getInstance().back()
            } catch (e) {
              hilog.error(0x0001, 'HelpPage', `router.back failed: ${e}`)
            }
          })
          Blank()
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
