/**
 * WolPage - WOL 远程开机（局域网唤醒）
 * SSH 通道执行 etherwake / wakeonlan 发送魔法包，设备列表本地存储
 */
import { AppNav } from '../../common/utils/AppNav'
import { window } from '@kit.ArkUI'
import { promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore, WolDevice } from '../../common/store/FunStore'
import { SshService } from '../../common/ssh/SshService'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice } from '../../models/Models'

const DOMAIN = 0x0001
const TAG = 'WolPage'

@Entry
@Component
export struct WolPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44   // 状态栏安全区高度
  @State devices: WolDevice[] = []
  @State newName: string = ''
  @State newMac: string = ''
  @State busy: string = ''          // 正在发送魔法包的设备名（显示转圈）
  @State statusMsg: string = ''     // 操作反馈
  private api: ApiService = new ApiService()
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      FunStore.getInstance().init(hostCtx).then(() => {
        this.devices = FunStore.getInstance().getWolDevices()
      })
    }
  }

  /** SSH 执行命令（懒连接） */
  private async sshExec(cmd: string): Promise<string> {
    try {
      if (!this.ssh.isConnected()) {
        if (this.sshTried) return ''
        this.sshTried = true
        const device = AppState.getInstance().getActiveDevice()
        if (!device || !device.username || !device.password) {
          return ''
        }
        const ok: boolean = await this.ssh.connect(device)
        if (!ok) return ''
      }
      return await this.ssh.exec(cmd)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ssh err: ${String(e)}`)
      return ''
    }
  }

  /** 校验 MAC 地址格式 */
  private validMac(mac: string): boolean {
    const m: RegExpMatchArray | null = mac.trim().match(/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)
    return m !== null
  }

  /** 添加设备 */
  private addDevice(): void {
    const name: string = this.newName.trim()
    const mac: string = this.newMac.trim()
    if (!name) {
      this.showMsg('请输入设备名称')
      return
    }
    if (!this.validMac(mac)) {
      this.showMsg('MAC 地址格式不对，示例：00:11:22:33:44:55')
      return
    }
    if (this.devices.some((d: WolDevice) => d.mac.toLowerCase() === mac.toLowerCase())) {
      this.showMsg('该 MAC 已存在')
      return
    }
    this.devices = [...this.devices, { name: name, mac: mac }]
    FunStore.getInstance().saveWolDevices(this.devices)
    this.newName = ''
    this.newMac = ''
    this.statusMsg = `✅ 已添加「${name}」`
  }

  /** 删除设备 */
  private removeDevice(index: number): void {
    this.devices.splice(index, 1)
    this.devices = [...this.devices]
    FunStore.getInstance().saveWolDevices(this.devices)
  }

  /** 一键导入在线设备（有 MAC 的前 20 台） */
  private async importOnline(): Promise<void> {
    try {
      const list: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      const online: ConnectedDevice[] = list.filter((d: ConnectedDevice) => d.mac && d.isOnline)
      if (online.length === 0) {
        this.showMsg('没有可导入的在线设备')
        return
      }
      let added: number = 0
      for (let i = 0; i < online.length; i++) {
        const d: ConnectedDevice = online[i]
        const exists: boolean = this.devices.some((w: WolDevice) => w.mac.toLowerCase() === d.mac.toLowerCase())
        if (!exists && this.devices.length < 20) {
          this.devices = [...this.devices, { name: d.hostname ? d.hostname : d.vendor ? d.vendor : d.mac, mac: d.mac }]
          added++
        }
      }
      FunStore.getInstance().saveWolDevices(this.devices)
      this.statusMsg = added > 0 ? `✅ 已导入 ${added} 台在线设备` : '在线设备都已添加过了'
    } catch (e) {
      this.showMsg('获取在线设备失败')
    }
  }

  /** 远程开机 */
  private async wake(d: WolDevice): Promise<void> {
    if (this.busy) return
    this.busy = d.name
    this.statusMsg = ''
    // 依次尝试 etherwake / wakeonlan
    let out: string = await this.sshExec(`etherwake -i br-lan ${d.mac} 2>&1 || etherwake ${d.mac} 2>&1 || wakeonlan ${d.mac} 2>&1`)
    hilog.error(DOMAIN, TAG, `wake ${d.name} out=[${out}]`)
    const ok: boolean = !out.includes('not found') && !out.includes('No such file')
    this.busy = ''
    if (ok) {
      this.statusMsg = `📡 已向「${d.name}」发送魔法包，设备应即将开机`
    } else {
      this.statusMsg = `⚠️ 发送失败：路由器缺少 etherwake/wakeonlan 命令，可 opkg install etherwake`
    }
  }

  private showMsg(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 })
    } catch (e) {}
  }

  /** 读取状态栏安全区高度（避免标题栏与状态栏重叠） */
  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.bolt')).fontSize(18).fontColor(['#F97316'])
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('WOL 远程开机').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('局域网一键唤醒设备').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
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
          // 说明卡
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(22).fontColor(['#F59E0B'])
              Column() {
                Text('支持 NAS / 电脑 / 树莓派等支持 WOL 的设备')
                  .fontSize(12).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                Text('需设备主板开启 WOL（网络唤醒）功能，且与路由器同一局域网')
                  .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
            }
            .width('100%')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 添加设备
          Column() {
            Text('添加设备').fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              .width('100%')
            TextInput({ placeholder: '设备名称（如：客厅 NAS）', text: this.newName })
              .fontSize(13).height(42).margin({ top: 10 })
              .backgroundColor('#F0EBE0')
              .borderRadius(12)
              .onChange((v: string) => { this.newName = v })
            TextInput({ placeholder: 'MAC 地址（如：00:11:22:33:44:55）', text: this.newMac })
              .fontSize(13).height(42).margin({ top: 8 })
              .backgroundColor('#F0EBE0')
              .borderRadius(12)
              .onChange((v: string) => { this.newMac = v })
            Row({ space: 10 }) {
              Row() {
                Text('＋ 添加').fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
              .layoutWeight(1).height(42).borderRadius(21)
              .backgroundColor(this.theme.primary)
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.addDevice() })

              Row() {
                Text('导入在线设备').fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
              }
              .layoutWeight(1).height(42).borderRadius(21)
              .backgroundColor('rgba(255,138,61,0.1)')
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.importOnline() })
            }
            .width('100%').margin({ top: 12 })
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(11).fontColor(this.theme.primary).margin({ top: 12 })
              .textAlign(TextAlign.Center).width('100%')
          }

          // 设备列表
          Text(`已保存设备（${this.devices.length}/20）`)
            .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
            .width('100%').margin({ top: 16 })

          if (this.devices.length === 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.moon')).fontSize(36).fontColor(['#94A3B8'])
              Text('还没有设备，添加一台试试').fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 8 })
            }
            .width('100%').padding(30).borderRadius(16).margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Center)
          } else {
            ForEach(this.devices, (d: WolDevice, idx: number) => {
              Row() {
                Column() {
                  Text(d.name).fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  Text(d.mac).fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)

                Row() {
                  Text('删除').fontSize(11).fontColor('#FF5252')
                }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(12)
                .backgroundColor('rgba(255,82,82,0.1)')
                .margin({ right: 8 })
                .onClick(() => { this.removeDevice(idx) })

                Row() {
                  if (this.busy === d.name) {
                    LoadingProgress().width(14).height(14).color('#FFFFFF')
                  } else {
                    SymbolGlyph($r('sys.symbol.bolt')).fontSize(13).fontColor(['#FFFFFF'])
                  }
                  Text(this.busy === d.name ? '  发送中' : '  开机')
                    .fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor('#00C853')
                .onClick(() => { this.wake(d) })
              }
              .width('100%').padding(12).borderRadius(14).margin({ top: 8 })
              .backgroundColor(this.theme.bgCard)
            }, (d: WolDevice): string => d.mac)
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
