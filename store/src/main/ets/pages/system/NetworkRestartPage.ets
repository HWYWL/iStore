/**
 * NetworkRestartPage - 网络服务重启
 * /etc/init.d/network restart 只重启网络服务不动整机（OpenWrt 24.x/25.x 通用）
 * 重启后自动 ping 网关验证恢复
 */
import { window, promptAction } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SshService } from '../../common/ssh/SshService'

const DOMAIN = 0x0001
const TAG = 'NetRst'

@Entry
@Component
struct NetworkRestartPageRoute {
  build() {
    Column() {
      NetworkRestartPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NetworkRestartPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State busy: boolean = false
  @State statusMsg: string = ''
  @State resultOk: number = -1     // -1 未执行 / 0 失败 / 1 成功
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
  }

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

  private async sshExec(cmd: string): Promise<string> {
    try {
      if (!this.ssh.isConnected()) {
        if (this.sshTried) return ''
        this.sshTried = true
        const device = AppState.getInstance().getActiveDevice()
        if (!device || !device.username || !device.password) return ''
        const ok: boolean = await this.ssh.connect(device)
        if (!ok) return ''
      }
      return await this.ssh.exec(cmd)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ssh err: ${String(e)}`)
      return ''
    }
  }

  /** 确认并重启网络 */
  private confirmRestart(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '重启网络服务',
        message: '将重启路由器网络服务（约 10~30 秒），期间网络会短暂中断，是否继续？',
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '确认重启', color: '#FF8A3D' }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          this.doRestart()
        }
      })
    } catch (e) {}
  }

  /** 执行网络重启 */
  private async doRestart(): Promise<void> {
    if (this.busy) return
    this.busy = true
    this.resultOk = -1
    this.statusMsg = '正在重启网络服务...'
    // /etc/init.d/network restart 在 OpenWrt 24.x / 25.x 均为标准服务管理方式
    const out: string = await this.sshExec('/etc/init.d/network restart 2>&1')
    hilog.error(DOMAIN, TAG, `restart out=[${out}]`)
    // 等待网络重建
    this.statusMsg = '网络服务已重启，正在验证连通性...'
    await this.sleep(8000)
    // 验证：读取默认网关并 ping
    const gw: string = await this.sshExec("ip route show default | awk '{print $3}' | head -1")
    const gwt: string = gw.trim()
    hilog.error(DOMAIN, TAG, `gateway=[${gwt}]`)
    let ok: boolean = false
    if (gwt) {
      const pingOut: string = await this.sshExec(`ping -c 2 -W 2 ${gwt} 2>&1`)
      ok = pingOut.includes('bytes from') || pingOut.includes('64 bytes')
    } else {
      // 无默认网关也尝试 ping 局域网回环方式判断网络栈
      const pingOut: string = await this.sshExec('ping -c 2 -W 2 192.168.1.1 2>&1')
      ok = pingOut.includes('bytes from') || pingOut.includes('64 bytes')
    }
    this.resultOk = ok ? 1 : 0
    this.statusMsg = ok ? '✅ 网络服务已重启并恢复连通' : '⚠️ 网络已重启，但网关连通验证未通过（可能仍在恢复中）'
    this.busy = false
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms))
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.network_mgmt')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('网络重启').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('只重启网络，不动整机').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
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

      Scroll() {
        Column() {
          // 状态大卡
          Column() {
            SymbolGlyph(this.resultOk === -1 ? $r('sys.symbol.globe_badge_message')
              : (this.resultOk === 1 ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.warning')))
              .fontSize(52)
              .fontColor([this.resultOk === 1 ? '#10B981' : (this.resultOk === -1 ? this.theme.primary : '#F59E0B')])
            Text(this.busy ? '重启中...' : (this.resultOk === -1 ? '网络服务待命' : (this.resultOk === 1 ? '网络已恢复' : '验证未通过')))
              .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold).margin({ top: 10 })
            Text('断网、拨号失败、DNS 异常时，先试试只重启网络服务')
              .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 6 }).textAlign(TextAlign.Center)
          }
          .width('100%').padding({ top: 30, bottom: 28 }).borderRadius(24).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Center)

          // 说明卡
          Column() {
            Row() {
            SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(14).fontColor(['#F59E0B'])
            Text(' 与「重启路由器」的区别').fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          }
              .width('100%')
            Text('· 重启路由器：整机重启，耗时 1~3 分钟，全部服务中断\n· 网络重启：只重启网络相关服务，约 10~30 秒，其他服务不受影响')
              .fontSize(11).fontColor(this.theme.textSecondary).lineHeight(20).margin({ top: 10 })
              .width('100%')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 执行按钮
          Row() {
            if (this.busy) {
              LoadingProgress().width(20).height(20).color('#FFFFFF')
              Text('  重启中...').fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            } else {
              Text('重启网络服务').fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            }
          }
          .width('100%').height(48).borderRadius(24).margin({ top: 16 })
          .backgroundColor(this.busy ? '#C9A98A' : '#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.confirmRestart() })

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(11).fontColor(this.resultOk === 1 ? '#00C853' : this.theme.primary)
              .margin({ top: 12 }).textAlign(TextAlign.Center).width('100%')
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
