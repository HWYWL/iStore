/**
 * NetworkHelperPage - 网络助手（快捷问答）
 * 本地规则引擎：快捷提问 + 自由输入，实时拉取路由器数据回答
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AiHelper, ChatMsg } from '../../common/ai/AiHelper'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

const QUICK_QUESTIONS: string[] = [
  '谁在占带宽？',
  '有多少设备在线？',
  '网络为什么卡？',
  '有没有陌生设备？',
  '路由器温度多少？',
  '下载速度多少？'
]

@Entry
@Component
struct NetworkHelperPageRoute {
  build() {
    Column() {
      NetworkHelperPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NetworkHelperPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State messages: ChatMsg[] = []
  @State inputText: string = ''
  @State aiThinking: boolean = false
  private listScroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    // 开场白
    this.messages.push({
      role: 'ai',
      text: '你好，我是 iStore 网络助手 🤖\n可以问我"谁在占带宽"、"网络为什么卡"、\n"有没有陌生设备"等问题，\n我会实时查看路由器数据回答你。'
    })
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 发送提问 */
  sendQuestion(q: string): void {
    const text: string = q.trim()
    if (!text || this.aiThinking) return
    this.messages.push({ role: 'user', text: text })
    this.inputText = ''
    this.aiThinking = true
    AiHelper.ask(text).then((answer: string) => {
      this.messages.push({ role: 'ai', text: answer })
      this.aiThinking = false
      this.scrollToBottom()
    }).catch(() => {
      this.messages.push({ role: 'ai', text: '抱歉，回答问题时出错了，请稍后再试。' })
      this.aiThinking = false
    })
  }

  /** 滚动到底部 */
  private scrollToBottom(): void {
    try {
      this.listScroller.scrollEdge(Edge.Bottom)
    } catch (e) {}
  }

  /** 消息气泡 */
  @Builder
  bubble(msg: ChatMsg, idx: number) {
    Row() {
      if (msg.role === 'user') {
        Blank()
        Column() {
          Text(msg.text)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .lineHeight(20)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(16)
            .backgroundColor(this.theme.primary)
            .constraintSize({ maxWidth: '75%' })
        }
        .alignItems(HorizontalAlign.End)
      } else {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.globe_badge_message'))
              .fontSize(15)
              .fontColor([this.theme.primary])
            Text(' 网络助手')
              .fontSize(10)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .margin({ bottom: 6 })

          Text(msg.text)
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .lineHeight(21)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .borderRadius(14)
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .constraintSize({ maxWidth: '85%' })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 10 })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 4, right: 12, top: 2, bottom: 2 })
        }
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Text('网络助手')
          .fontSize(17)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('实时诊断')
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      // 消息列表
      List({ scroller: this.listScroller, space: 2 }) {
        ForEach(this.messages, (msg: ChatMsg, idx: number) => {
          ListItem() {
            this.bubble(msg, idx)
          }
        }, (msg: ChatMsg, idx: number): string => `${idx}_${msg.role}_${msg.text.length}`)

        if (this.aiThinking) {
          ListItem() {
            Row() {
              LoadingProgress().width(16).height(16).color(this.theme.primary)
              Text(' 正在查询路由器数据…')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ top: 14 })
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 14, right: 14 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 快捷问题
      Scroll() {
        Row({ space: 8 }) {
          ForEach(QUICK_QUESTIONS, (q: string) => {
            Text(q)
              .fontSize(11)
              .fontColor(this.theme.primary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor('rgba(68,138,255,0.1)')
              .border({ width: 0.5, color: 'rgba(68,138,255,0.3)' })
              .onClick(() => { this.sendQuestion(q) })
          }, (q: string): string => q)
        }
        .padding({ left: 14, right: 14, top: 4, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // 输入栏
      Row() {
        TextInput({ placeholder: '问问网络问题…', text: this.inputText })
          .placeholderColor(this.theme.textTertiary)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(this.theme.bgCard)
          .height(42)
          .borderRadius(21)
          .layoutWeight(1)
          .onChange((v: string) => { this.inputText = v })
          .onSubmit(() => { this.sendQuestion(this.inputText) })
        Row() {
          Text('发送')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .width(64)
        .height(42)
        .borderRadius(21)
        .backgroundColor(this.theme.primary)
        .justifyContent(FlexAlign.Center)
        .margin({ left: 8 })
        .opacity(this.aiThinking ? 0.5 : 1)
        .onClick(() => { this.sendQuestion(this.inputText) })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
