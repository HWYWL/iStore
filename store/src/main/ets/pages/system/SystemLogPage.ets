/**
 * SystemLogPage - 系统日志查看器
 * SSH logread 实时查看 + 关键字过滤 + 自动刷新（OpenWrt 24.x/25.x 通用）
 */
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SshService } from '../../common/ssh/SshService'
import { Poller } from '../../common/utils/Poller'

const DOMAIN = 0x0001
const TAG = 'SysLog'

@Entry
@Component
struct SystemLogPageRoute {
  build() {
    Column() {
      SystemLogPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SystemLogPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State logs: string[] = []
  @State filter: string = ''
  @State autoRefresh: boolean = true
  @State loading: boolean = false
  @State errorText: string = ''
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false
  private poller: Poller | null = null

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    this.loadLogs()
    // 每 3 秒自动刷新：autoRefresh 关闭时由 Poller 的可见性回调直接跳过
    this.poller = new Poller((): Promise<void> => this.loadLogs(), 3000, (): boolean => this.autoRefresh)
    this.poller.start()
  }

  aboutToDisappear(): void {
    if (this.poller) {
      this.poller.dispose()
      this.poller = null
    }
  }

  /** 读取状态栏安全区高度 */
  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** SSH 执行命令（懒连接） */
  private async sshExec(cmd: string): Promise<string> {
    try {
      if (!this.ssh.isConnected()) {
        if (this.sshTried) return ''
        this.sshTried = true
        const device = AppState.getInstance().getActiveDevice()
        if (!device || !device.username || !device.password) {
          this.errorText = '未保存设备凭据，无法连接 SSH'
          return ''
        }
        const ok: boolean = await this.ssh.connect(device)
        if (!ok) {
          this.errorText = 'SSH 连接失败'
          return ''
        }
      }
      return await this.ssh.exec(cmd)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ssh err: ${String(e)}`)
      return ''
    }
  }

  /** 加载日志 */
  private async loadLogs(): Promise<void> {
    if (this.loading) return
    this.loading = true
    // logread 在 OpenWrt 24.x/25.x 均为 busybox logd 标准命令
    const out: string = await this.sshExec('logread | tail -300')
    if (out) {
      const lines: string[] = out.split('\n')
      // 去空行、去重复（自动刷新时避免闪烁）
      const clean: string[] = lines.filter((l: string) => l.length > 0)
      this.logs = clean
      this.errorText = ''
    } else if (!this.errorText) {
      this.errorText = '未获取到日志（SSH 未连接或设备不支持）'
    }
    this.loading = false
  }

  /** 过滤后的日志 */
  private filtered(): string[] {
    const f: string = this.filter.trim().toLowerCase()
    if (!f) return this.logs
    return this.logs.filter((l: string) => l.toLowerCase().includes(f))
  }

  /** 日志行颜色 */
  private lineColor(l: string): string {
    if (l.includes('error') || l.includes('Error') || l.includes('ERR')) return '#FF5252'
    if (l.includes('warn') || l.includes('Warn') || l.includes('WARNING')) return '#E6A800'
    if (l.includes('docker') || l.includes('ppp') || l.includes('network')) return this.theme.primary
    return this.theme.textSecondary
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.app_info')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('系统日志').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('实时查看路由器运行日志').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)

        Text('返回')
          .fontSize(13).fontColor(this.theme.primary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('rgba(255,138,61,0.1)')
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%').padding({ left: 16, right: 16, top: this.topSafeArea + 4 })

      // 过滤与刷新栏
      Row({ space: 8 }) {
        TextInput({ placeholder: '过滤关键字（如 ppp / error / docker）', text: this.filter })
          .fontSize(12).height(38).layoutWeight(1)
          .backgroundColor('#FFFFFF').borderRadius(12)
          .onChange((v: string) => { this.filter = v })

        Row() {
          Text('刷新').fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .borderRadius(16).backgroundColor('#FF8A3D')
        .onClick(() => { this.loadLogs() })
      }
      .width('100%').padding({ left: 16, right: 16, top: 10 })

      // 自动刷新开关
      Row() {
        Text('自动刷新（3 秒）').fontSize(11).fontColor(this.theme.textSecondary)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.autoRefresh })
          .selectedColor('#FF8A3D')
          .onChange((on: boolean) => { this.autoRefresh = on })
      }
      .width('100%').padding({ left: 16, right: 16, top: 8 })

      if (this.errorText && this.logs.length === 0) {
        Column() {
          Text('⚠️').fontSize(30)
          Text(this.errorText).fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 6 })
        }
        .width('100%').padding(40).alignItems(HorizontalAlign.Center)
      }

      // 日志列表
      Scroll() {
        Column() {
          if (this.filtered().length === 0) {
            Text(this.logs.length > 0 ? '没有匹配的日志' : '暂无日志，点击刷新')
              .fontSize(11).fontColor(this.theme.textTertiary).padding({ top: 30 }).width('100%')
              .textAlign(TextAlign.Center)
          } else {
            ForEach(this.filtered(), (l: string, idx: number) => {
              Text(l)
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor(this.lineColor(l))
                .width('100%')
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                .borderRadius(8)
                .backgroundColor(idx % 2 === 0 ? 'rgba(255,255,255,0.55)' : 'rgba(255,255,255,0.25)')
            }, (l: string, idx: number): string => `${idx}_${l}`)
          }
        }
        .width('100%').padding({ left: 8, right: 8, bottom: 30 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
      .margin({ top: 6 })
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
