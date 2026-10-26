/**
 * SshTerminalPage - SSH 终端
 * 连接路由器 SSH（复用设备用户名/密码），执行命令查看输出
 * 终端风格：深色底 + 等宽字体 + 快捷命令
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SshService } from '../../common/ssh/SshService'
import { SavedDevice } from '../../common/store/DeviceStore'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

const DOMAIN = 0x0001
const TAG = 'SshTerminal'

/** 快捷命令 */
const QUICK_CMDS: string[] = [
  'top -n 1',
  'free -m',
  'df -h',
  'uptime',
  'cat /etc/openwrt_release',
  'iwinfo',
  'logread -l 20',
  'ps w',
  'ifconfig',
  'ls -la /tmp'
]

/** 命令执行记录 */
interface CmdRecord {
  cmd: string
  output: string
}

@Entry
@Component
export struct SshTerminalPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State connecting: boolean = true
  @State connected: boolean = false
  @State connError: string = ''
  @State keyboardUp: boolean = false  // 键盘弹出状态：收起快捷命令栏，给输出区更多空间
  @State kbCompensate: number = 0  // 键盘弹出补偿：上半部分下移量（抵消系统整页上移，顶部内容回屏）
  @State kbPad: number = 0         // 键盘弹出补偿：输出区底部压缩量（= 键盘高度）
  @State records: CmdRecord[] = []
  @State inputText: string = ''
  @State running: boolean = false
  /** 当前工作目录（App 侧维护，模拟 shell 会话状态） */
  @State cwd: string = '/root'
  private ssh: SshService = SshService.getInstance()
  private listScroller: Scroller = new Scroller()

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadTopSafeArea()
    this.doConnect()
  }

  aboutToDisappear(): void {
    // 离开页面断开连接
    this.ssh.disconnect()
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 连接路由器 */
  async doConnect(): Promise<void> {
    this.connecting = true
    this.connError = ''
    const device: SavedDevice | undefined = AppState.getInstance().getActiveDevice()
    if (!device) {
      this.connecting = false
      this.connError = '未选择路由器设备'
      return
    }
    if (!device.username || !device.password) {
      this.connecting = false
      this.connError = '设备未配置 SSH 用户名/密码，请到登录页编辑设备补充'
      return
    }
    const ok: boolean = await this.ssh.connect(device)
    this.connecting = false
    if (ok) {
      this.connected = true
      // 命令走 channel exec（Xshell 阻塞模式），输出直接随 Promise 返回，无需回调监听
      // cwd 用本地 resolveCd 模拟显示
      this.records = [{
        cmd: '',
        output: `已连接 ${device.host}（SSH 交互终端）\n输入命令开始，或点击下方快捷命令\n输入 help 查看用法`
      }]
    } else {
      this.connError = this.ssh.lastError || '连接失败：请确认路由器已开启 SSH（系统→管理→SSH 访问），且用户名密码正确'
    }
  }

  /** 解析 cd 参数（支持绝对/相对/.. / ~），返回规范化路径 */
  resolveCd(arg: string): string {
    let target: string = arg.trim()
    if (!target || target === '~') {
      target = '/root'
    } else if (target === '-' || target.startsWith('-')) {
      return this.cwd
    } else if (!target.startsWith('/')) {
      target = `${this.cwd}/${target}`
    }
    const parts: string[] = target.split('/')
    const stack: string[] = []
    for (let i = 0; i < parts.length; i++) {
      const p: string = parts[i]
      if (p === '' || p === '.') continue
      if (p === '..') {
        if (stack.length > 0) stack.pop()
      } else {
        stack.push(p)
      }
    }
    return '/' + stack.join('/')
  }

  /** 执行命令（流式交互 shell：cd 状态服务器保留，输出实时回调） */
  runCommand(cmdText: string): void {
    const cmd: string = cmdText.trim()
    if (!cmd || this.running) return
    // 本地命令
    if (cmd === 'help') {
      this.records.push({
        cmd: cmd,
        output: '快捷命令：top / free -m / df -h / uptime / iwinfo / logread -l 20 / cat /etc/openwrt_release\n支持 cd（切换目录，如 cd /tmp、cd ..、cd）\n'
      })
      this.inputText = ''
      this.scrollToBottom()
      return
    }
    if (cmd === 'clear' || cmd === 'cls') {
      this.records = []
      this.inputText = ''
      return
    }
    // cd 命令：发给服务器（真实 shell 切换）+ 本地同步显示
    const cdMatch = cmd.match(/^cd\s+(\S+)?$/)
    if (cdMatch) {
      const arg: string = cdMatch[1] || ''
      const newDir: string = this.resolveCd(arg)
      this.cwd = newDir
      this.records.push({ cmd: cmd, output: `已切换到 ${newDir}` })
      this.inputText = ''
      this.scrollToBottom()
      return
    }
    // 其他命令：exec 模式（每次独立 channel，无会话状态）→ 前缀 cd 保持目录
    this.inputText = ''
    this.running = true
    const execCmd: string = this.cwd === '/' ? cmd : `cd '${this.cwd}' && ${cmd}`
    this.ssh.sendCommand(execCmd).then((out: string) => {
      hilog.info(DOMAIN, TAG, `runCommand ok: "${cmd}" out=${out.length}B`)
      this.running = false
      // 输出到达后直接追加记录（不占位）
      this.records.push({ cmd: cmd, output: out || '（无输出）' })
      this.scrollToBottom()
    }).catch(() => {
      hilog.error(DOMAIN, TAG, `runCommand err: "${cmd}"`)
      this.running = false
      this.records.push({ cmd: cmd, output: '（执行异常）' })
      this.scrollToBottom()
    })
  }

  /** 读取键盘高度并应用补偿：上半部分下移 + 输出区压缩，输入栏保持在键盘上方 */
  private readKeyboardHeight(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD)
          const h: number = px2vp(area.bottomRect.height)
          if (h > 0) {
            this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.kbCompensate = h
              this.kbPad = h
            })
          }
        })
      }
    } catch (e) {
      hilog.error(0x0001, 'SshTerminal', `readKeyboardHeight err: ${String(e)}`)
    }
  }

  /** 滚动到底部 */
  private scrollToBottom(): void {
    try {
      setTimeout(() => {
        this.listScroller.scrollEdge(Edge.Bottom)
      }, 50)
    } catch (e) {}
  }

  /** 单条记录渲染 */
  @Builder
  recordItem(rec: CmdRecord) {
    Column() {
      if (rec.cmd) {
        Text(`$ ${rec.cmd}`)
          .fontSize(13)
          .fontColor('#00E676')
          .fontFamily('monospace')
          .width('100%')
      }
      Text(rec.output || '（无输出）')
        .fontSize(12)
        .fontColor('#D0D7DE')
        .fontFamily('monospace')
        .lineHeight(18)
        .width('100%')
        .margin({ top: rec.cmd ? 4 : 0 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
  }

  build() {
    Column() {
      // 上半部分（标题栏 + 输出区 + 快捷栏）：
      // 键盘弹出时系统整页上移，这里整体下移补偿（顶部内容回屏）+ 底部压缩输出区
      Column() {
      // 标题栏
      Row() {
        Row() {
          Text(' SSH 终端')
            .fontSize(16)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 12, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Blank()
        if (this.connected) {
          Row() {
            Circle({ width: 6, height: 6 }).fill('#00C853')
            Text(` ${this.ssh.host()}`)
              .fontSize(11).fontColor(this.theme.success)
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor('rgba(0,200,83,0.1)')
        } else {
          Text('未连接')
            .fontSize(11).fontColor(this.theme.danger)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      // 终端主体（深色）
      Column() {
        if (this.connecting) {
          Row() {
            LoadingProgress().width(16).height(16).color('#00E676')
            Text(' 正在连接 SSH…')
              .fontSize(12).fontColor('#8B949E')
              .margin({ left: 8 })
          }
          .width('100%').justifyContent(FlexAlign.Center).padding(30)
        } else if (!this.connected) {
          Column() {
            Text('⚠ SSH 未连接')
              .fontSize(13).fontColor('#FF5252')
            Text(this.connError)
              .fontSize(12).fontColor('#8B949E')
              .margin({ top: 8 })
              .lineHeight(18)
            Row() {
              Text('重新连接')
                .fontSize(12).fontColor('#FFFFFF')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(12)
                .backgroundColor('#00E676')
                .margin({ top: 16 })
                .onClick(() => { this.doConnect() })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding(30)
        } else {
          // 输出区
          List({ scroller: this.listScroller, space: 2 }) {
            ForEach(this.records, (rec: CmdRecord, idx: number) => {
              ListItem() {
                this.recordItem(rec)
              }
            }, (rec: CmdRecord, idx: number): string => `${idx}_${rec.cmd}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 4 })
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#0D1117')
      .borderRadius(14)
      .margin({ left: 12, right: 12 })
      .clip(true)

      // 快捷命令（键盘弹出时收起，输出区可显示更多）
      if (!this.keyboardUp) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(QUICK_CMDS, (c: string) => {
              Text(c)
                .fontSize(10)
                .fontColor('#00E676')
                .fontFamily('monospace')
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(10)
                .backgroundColor('rgba(0,230,118,0.1)')
                .border({ width: 0.5, color: 'rgba(0,230,118,0.3)' })
                .onClick(() => { this.runCommand(c) })
            }, (c: string): string => c)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      }
      .layoutWeight(1)
      .translate({ y: this.kbCompensate })
      .padding({ bottom: this.kbPad })

      // 输入栏
      Row() {
        Text(this.cwd === '/' ? '/ #' : `${this.cwd} #`)
          .fontSize(11)
          .fontColor('#00E676')
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '38%' })
          .margin({ left: 12, right: 6 })
        TextInput({ placeholder: '输入命令，如 top', text: this.inputText })
          .placeholderColor('#6E7681')
          .fontColor('#D0D7DE')
          .fontFamily('monospace')
          .backgroundColor('#0D1117')
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => { this.inputText = v })
          .onSubmit(() => { this.runCommand(this.inputText) })
          .onFocus(() => {
            this.keyboardUp = true
            // 等键盘布局稳定后：读取键盘高度做补偿 + 滚动到底部
            setTimeout(() => {
              this.readKeyboardHeight()
            }, 200)
            setTimeout(() => {
              this.scrollToBottom()
            }, 250)
          })
          .onBlur(() => {
            this.keyboardUp = false
            this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
              this.kbCompensate = 0
              this.kbPad = 0
            })
          })
        Row() {
          Text(this.running ? '…' : '执行')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .width(60)
        .height(40)
        .borderRadius(10)
        .backgroundColor('#00E676')
        .justifyContent(FlexAlign.Center)
        .margin({ left: 8, right: 12 })
        .opacity((this.running || !this.connected) ? 0.4 : 1)
        .onClick(() => { this.runCommand(this.inputText) })
      }
      .width('100%')
      .padding({ top: 6, bottom: this.keyboardUp ? 6 : 18 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
