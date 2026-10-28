import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { WifiApInfo, WifiClientDetail } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct WifiPageRoute {
  build() {
    Column() {
      WifiPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct WifiPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State aps: WifiApInfo[] = []
  @State clients: WifiClientDetail[] = []
  @State expandedAp: string = ''          // 当前展开的 AP（显示其客户端）
  @State isSaving: boolean = false
  @State saveMessage: string = ''
  @State saveError: string = ''
  // 编辑对话框状态
  @State showEdit: boolean = false
  @State editDevice: string = ''
  @State editSsid: string = ''
  @State editKey: string = ''
  @State editDisabled: boolean = false
  @State editChannel: string = ''
  // 踢客户端确认
  @State kickTarget: string = ''
  @State kickDevice: string = ''
  // 访客网络状态
  @State guestEnabled: boolean = false
  @State guestSsid: string = ''
  @State guestShowForm: boolean = false
  @State guestInputSsid: string = ''
  @State guestInputKey: string = ''
  @State guestBusy: boolean = false
  @State guestMsg: string = ''
  @State guestErr: string = ''

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
    this.loadGuestStatus()
  }

  /** 加载访客网络状态 */
  async loadGuestStatus(): Promise<void> {
    try {
      const api: ApiService = new ApiService()
      const info = await api.getGuestWifiStatus()
      if (info) {
        this.guestEnabled = info.enabled
        this.guestSsid = info.ssid
      } else {
        this.guestEnabled = false
        this.guestSsid = ''
      }
    } catch (e) {
      this.guestErr = '加载访客网络状态失败'
    }
  }

  /** 开启访客网络 */
  async doEnableGuest(): Promise<void> {
    if (this.guestBusy) return
    const ssid: string = this.guestInputSsid.trim()
    const key: string = this.guestInputKey.trim()
    if (!ssid) {
      this.guestErr = '请输入访客网络名称（SSID）'
      return
    }
    if (key.length < 8) {
      this.guestErr = '密码至少 8 位'
      return
    }
    this.guestBusy = true
    this.guestMsg = ''
    this.guestErr = ''
    try {
      const api: ApiService = new ApiService()
      const device: string = this.aps.length > 0 ? this.aps[0].device : 'radio0'
      const ok: boolean = await api.enableGuestWifi(ssid, key, device)
      if (ok) {
        this.guestEnabled = true
        this.guestSsid = ssid
        this.guestShowForm = false
        this.guestMsg = '访客网络已开启，配置生效中（无线会短暂重启）'
      } else {
        this.guestErr = '开启失败：接口无权限或参数无效'
      }
    } catch (e) {
      this.guestErr = '操作异常，请重试'
    }
    this.guestBusy = false
  }

  /** 关闭访客网络 */
  async doDisableGuest(): Promise<void> {
    if (this.guestBusy) return
    this.guestBusy = true
    this.guestMsg = ''
    this.guestErr = ''
    try {
      const api: ApiService = new ApiService()
      const ok: boolean = await api.disableGuestWifi()
      if (ok) {
        this.guestEnabled = false
        this.guestSsid = ''
        this.guestMsg = '访客网络已关闭'
      } else {
        this.guestErr = '关闭失败：接口无权限'
      }
    } catch (e) {
      this.guestErr = '操作异常，请重试'
    }
    this.guestBusy = false
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api: ApiService = new ApiService()
      const apList: WifiApInfo[] = await api.fetchWifiApList()
      this.aps = apList
      this.clients = await api.fetchWifiClients()
      // 展开项保持有效
      if (this.expandedAp && !this.aps.some((a: WifiApInfo) => a.device === this.expandedAp)) {
        this.expandedAp = ''
      }
      this.saveMessage = ''
      this.saveError = ''
    } catch (e) {
      this.errorText = '加载 WiFi 信息失败'
    }
    this.isLoading = false
  }

  /** 打开编辑对话框 */
  openEdit(ap: WifiApInfo): void {
    this.editDevice = ap.device
    this.editSsid = ap.ssid
    this.editKey = ''
    this.editDisabled = ap.disabled
    this.editChannel = ap.channel > 0 ? String(ap.channel) : ''
    this.saveMessage = ''
    this.saveError = ''
    this.showEdit = true
  }

  /** 保存 WiFi 配置（SSID/密码/信道/开关） */
  async saveConfig(): Promise<void> {
    if (this.isSaving) return
    this.isSaving = true
    this.saveMessage = ''
    this.saveError = ''
    try {
      const api: ApiService = new ApiService()
      const dev: string = this.editDevice
      // 1. SSID
      if (this.editSsid.trim()) {
        const ok: boolean = await api.updateWifiConfig(dev, 'ssid', this.editSsid.trim())
        if (!ok) {
          this.saveError = '保存 SSID 失败'
          this.isSaving = false
          return
        }
      }
      // 2. 密码（仅填写时修改）
      if (this.editKey.length > 0) {
        const ok: boolean = await api.updateWifiConfig(dev, 'key', this.editKey)
        if (!ok) {
          this.saveError = '保存密码失败'
          this.isSaving = false
          return
        }
      }
      // 3. 信道（仅填写时修改）
      if (this.editChannel.trim()) {
        const ch: number = parseInt(this.editChannel.trim())
        if (ch > 0) {
          const ok: boolean = await api.updateWifiConfig(dev, 'channel', String(ch))
          if (!ok) {
            this.saveError = '保存信道失败'
            this.isSaving = false
            return
          }
        }
      }
      // 4. 开关状态
      const okD: boolean = await api.updateWifiConfig(dev, 'disabled', this.editDisabled ? '1' : '0')
      if (!okD) {
        this.saveError = '保存开关状态失败'
        this.isSaving = false
        return
      }
      this.showEdit = false
      this.saveMessage = 'WiFi 配置已保存，正在应用…'
      // 应用后延迟刷新（无线重启需要时间）
      await new Promise<void>((r) => setTimeout(() => r(), 5000))
      await this.loadData()
    } catch (e) {
      hilog.error(0x0001, 'WifiPage', `saveConfig err: ${e}`)
      this.saveError = '保存异常，请重试'
    }
    this.isSaving = false
  }

  /** 踢下线客户端 */
  async confirmKick(): Promise<void> {
    if (!this.kickTarget) return
    this.saveMessage = ''
    this.saveError = ''
    try {
      const api: ApiService = new ApiService()
      const ok: boolean = await api.kickWifiClient(this.kickDevice, this.kickTarget)
      if (ok) {
        this.saveMessage = '已将该设备踢下线'
        await new Promise<void>((r) => setTimeout(() => r(), 1500))
        await this.loadData()
      } else {
        this.saveError = '踢下线失败：设备不支持或接口无权限'
      }
    } catch (e) {
      this.saveError = '操作异常，请重试'
    }
    this.kickTarget = ''
  }

  formatDuration(sec: number): string {
    if (sec <= 0) return '--'
    const h: number = Math.floor(sec / 3600)
    const m: number = Math.floor((sec % 3600) / 60)
    const s: number = sec % 60
    if (h > 0) return `${h}h ${m}m`
    if (m > 0) return `${m}m ${s}s`
    return `${s}s`
  }

  signalLabel(sig: number): string {
    if (sig >= -50) return '优秀'
    if (sig >= -60) return '良好'
    if (sig >= -70) return '一般'
    return '较弱'
  }

  signalColor(sig: number): string {
    if (sig >= -50) return '#00E676'
    if (sig >= -60) return '#448AFF'
    if (sig >= -70) return '#FF9800'
    return '#FF5252'
  }

  /** 频段标签：根据频率判断 2.4G/5G/6G */
  bandLabel(freq: number): string {
    if (freq >= 5925) return '6 GHz'
    if (freq >= 4900) return '5 GHz'
    if (freq >= 2400) return '2.4 GHz'
    return ''
  }

  /** 加密标签简化 */
  encLabel(enc: string): string {
    const e = enc.toLowerCase()
    if (e.includes('wpa3')) return 'WPA3'
    if (e.includes('wpa2')) return 'WPA2'
    if (e.includes('wpa')) return 'WPA'
    if (e.includes('none') || e === '') return '开放'
    return enc
  }

  @Builder
  apCard(ap: WifiApInfo, idx: number): void {
    Column() {
      Row() {
        Text(ap.ssid || '(未设置 SSID)')
          .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.bandLabel(ap.frequency)) {
          Text(this.bandLabel(ap.frequency))
            .fontSize(10).fontColor('#448AFF')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 }).borderRadius(8)
            .backgroundColor('rgba(68,138,255,0.12)')
            .margin({ left: 6 })
        }
        Text(ap.up ? '开启' : '关闭')
          .fontSize(10).fontColor(ap.up ? '#00E676' : '#FF5252')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 }).borderRadius(8)
          .backgroundColor(ap.up ? 'rgba(0,230,118,0.12)' : 'rgba(255,82,82,0.12)')
          .margin({ left: 6 })
      }.width('100%')

      // 状态信息网格
      Row() {
        this.metric('信道', ap.channel > 0 ? String(ap.channel) : '--')
        this.metric('加密', this.encLabel(ap.encryption))
        this.metric('客户端', String(ap.clientCount))
        this.metric('设备', ap.device)
      }.width('100%').margin({ top: 10 })

      // 操作按钮
      Row() {
        Row() {
          Image($r('app.media.app_edit'))
            .width(15).height(15)
          Text(' 编辑')
            .fontSize(12).fontColor(this.theme.primary)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(12)
        .backgroundColor('rgba(68,138,255,0.08)')
        .border({ width: 0.5, color: '#448AFF33' })
        .onClick(() => this.openEdit(ap))

        Text(this.expandedAp === ap.device ? '▾ 收起客户端' : `▸ 查看客户端 (${ap.clientCount})`)
          .fontSize(12).fontColor(this.theme.textSecondary)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 }).borderRadius(12)
          .backgroundColor(this.theme.bgGlassLight)
          .margin({ left: 10 })
          .onClick(() => {
            this.expandedAp = this.expandedAp === ap.device ? '' : ap.device
          })
      }.width('100%').margin({ top: 12 })

      // 客户端列表
      if (this.expandedAp === ap.device) {
        Column() {
          if (this.clients.filter((c: WifiClientDetail) => c.device === ap.device).length === 0) {
            Text('暂无已连接客户端').fontSize(12).fontColor(this.theme.textTertiary)
              .width('100%').textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
          } else {
            ForEach(this.clients.filter((c: WifiClientDetail) => c.device === ap.device),
              (c: WifiClientDetail, cidx: number) => {
                Row() {
                  Column() {
                    Text(c.hostname || c.mac)
                      .fontSize(12).fontColor(this.theme.textPrimary)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(c.mac)
                      .fontSize(10).fontColor(this.theme.textTertiary).fontFamily('monospace')
                      .margin({ top: 2 })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                  Text(this.signalLabel(c.signal))
                    .fontSize(10).fontColor(this.signalColor(c.signal))
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(6)
                    .backgroundColor(this.signalColor(c.signal) + '18')
                    .margin({ right: 8 })

                  Text(this.formatDuration(c.connectedTime))
                    .fontSize(10).fontColor(this.theme.textTertiary)
                    .margin({ right: 8 })

                  Text('踢下线')
                    .fontSize(11).fontColor('#FF5252')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(8)
                    .backgroundColor('rgba(255,82,82,0.10)')
                    .onClick(() => {
                      this.kickTarget = c.mac
                      this.kickDevice = ap.device
                    })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                .border({ width: { bottom: 0.5 }, color: this.theme.borderGlass })
              })
          }
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 6, bottom: 4 })
        .margin({ top: 10 })
        .borderRadius(10)
        .backgroundColor(this.theme.bgGlassLight)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .margin({ top: 10, left: 16, right: 16 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  @Builder
  metric(label: string, value: string): void {
    Column() {
      Text(label).fontSize(10).fontColor(this.theme.textTertiary)
      Text(value).fontSize(13).fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  /** 访客网络卡片 */
  @Builder
  guestCard(): void {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.wifi')).fontSize(14).fontColor(['#10B981'])
        Text(' 访客网络')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
        Blank()
        Text(this.guestEnabled ? '已开启' : '未开启')
          .fontSize(11)
          .fontColor(this.guestEnabled ? this.theme.success : this.theme.textTertiary)
      }
      .width('100%')

      Text('独立访客 SSID，访客可上网但无法访问内网设备（已隔离）')
        .fontSize(11)
        .fontColor(this.theme.textTertiary)
        .lineHeight(15)
        .width('100%')
        .margin({ top: 4, bottom: 8 })

      if (this.guestEnabled) {
        Row() {
          SymbolGlyph($r('sys.symbol.wifi')).fontSize(13).fontColor([this.theme.primary])
          Text(` ${this.guestSsid || '已开启'}`)
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(12)
            .fontColor(this.theme.danger)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(12)
            .backgroundColor('rgba(255,82,82,0.1)')
            .onClick(() => this.doDisableGuest())
        }
        .width('100%')
      } else if (this.guestShowForm) {
        Column() {
          Row() {
            TextInput({ placeholder: '访客网络名称（如 Home-Guest）', text: this.guestInputSsid })
              .placeholderColor(this.theme.textTertiary)
              .fontColor(this.theme.textPrimary)
              .backgroundColor('transparent')
              .layoutWeight(1)
              .height(44)
          }
          .width('100%').height(44).borderRadius(20)
          .backgroundColor('transparent').backdropBlur(10)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .padding({ left: 12, right: 12 })
          .margin({ bottom: 10 })

          Row() {
            TextInput({ placeholder: '密码（至少 8 位）', text: this.guestInputKey })
              .placeholderColor(this.theme.textTertiary)
              .fontColor(this.theme.textPrimary)
              .backgroundColor('transparent')
              .layoutWeight(1)
              .height(44)
          }
          .width('100%').height(44).borderRadius(20)
          .backgroundColor('transparent').backdropBlur(10)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .padding({ left: 12, right: 12 })
          .margin({ bottom: 10 })

          Row() {
            Text('取消')
              .fontSize(12).fontColor(this.theme.textTertiary)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => { this.guestShowForm = false; this.guestErr = '' })
            Blank()
            Text(this.guestBusy ? '开启中…' : '开启访客网络')
              .fontSize(12).fontColor('#FFFFFF')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(14)
              .backgroundColor(this.theme.primary)
              .opacity(this.guestBusy ? 0.5 : 1)
              .onClick(() => this.doEnableGuest())
          }
          .width('100%')
        }
        .width('100%')
      } else {
        Row() {
          Text('+ 开启访客网络')
            .fontSize(12)
            .fontColor(this.theme.primary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor('rgba(68,138,255,0.1)')
            .onClick(() => {
              this.guestShowForm = true
              this.guestErr = ''
              this.guestInputSsid = this.aps.length > 0 ? `${this.aps[0].ssid}-Guest` : 'Home-Guest'
            })
        }
        .width('100%')
      }

      if (this.guestMsg) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(12).fontColor([this.theme.success])
          Text(' ' + this.guestMsg).fontSize(11).fontColor(this.theme.success)
        }
        .width('100%').margin({ top: 8 })
      }
      if (this.guestErr) {
        Row() {
          SymbolGlyph($r('sys.symbol.warning')).fontSize(12).fontColor([this.theme.danger])
          Text(' ' + this.guestErr).fontSize(11).fontColor(this.theme.danger)
        }
        .width('100%').margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .margin({ top: 10, left: 16, right: 16 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        // 顶栏
        Row() {
          Row() {
            Text(' WiFi 管理').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => AppNav.getInstance().back())

          Blank()
          Text(`共 ${this.aps.length} 个接入点`).fontSize(11).fontColor(this.theme.textTertiary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorText) {
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.warning')).fontSize(14).fontColor([this.theme.warning])
              Text(' ' + this.errorText).fontSize(14).fontColor(this.theme.warning)
            }
            .margin({ bottom: 12 })
            Text('点击重试').fontSize(14).fontColor(this.theme.primary)
              .onClick(() => this.loadData())
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 结果提示
              if (this.saveMessage) {
                Row() {
                  SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(13).fontColor(['#00E676'])
                  Text(' ' + this.saveMessage).fontSize(12).fontColor('#00E676')
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 8 })
              }
              if (this.saveError) {
                Row() {
                  SymbolGlyph($r('sys.symbol.warning')).fontSize(13).fontColor([this.theme.danger])
                  Text(' ' + this.saveError).fontSize(12).fontColor(this.theme.danger)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 8 })
              }

              if (this.aps.length === 0) {
                Text('未检测到无线接入点')
                  .fontSize(13).fontColor(this.theme.textTertiary)
                  .width('100%').textAlign(TextAlign.Center).padding({ top: 60 })
              } else {
                ForEach(this.aps, (ap: WifiApInfo, idx: number) => {
                  this.apCard(ap, idx)
                })
              }

              // 访客网络
              this.guestCard()
            }
            .width('100%')
            .padding({ bottom: 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')

      // 编辑对话框
      if (this.showEdit) {
        Column() {
          Column() {
            Row() {
              Text('编辑 WiFi').fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              Blank()
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([this.theme.textTertiary])
                .padding(8)
                .onClick(() => { this.showEdit = false })
            }.width('100%').margin({ bottom: 12 })

            Row() {
              Text('SSID').fontSize(13).fontColor(this.theme.textSecondary).width(72)
              TextInput({ placeholder: '网络名称', text: this.editSsid })
                .fontSize(14).fontColor(this.theme.textPrimary)
                .backgroundColor('rgba(0,0,0,0.04)')
                .layoutWeight(1)
                .onChange((v: string) => this.editSsid = v)
            }.width('100%').margin({ bottom: 10 })

            Row() {
              Text('密码').fontSize(13).fontColor(this.theme.textSecondary).width(72)
              TextInput({ placeholder: '留空则不修改密码', text: this.editKey })
                .fontSize(14).fontColor(this.theme.textPrimary)
                .backgroundColor('rgba(0,0,0,0.04)')
                .layoutWeight(1)
                .type(InputType.Password)
                .onChange((v: string) => this.editKey = v)
            }.width('100%').margin({ bottom: 10 })

            Row() {
              Text('信道').fontSize(13).fontColor(this.theme.textSecondary).width(72)
              TextInput({ placeholder: '留空则不修改信道', text: this.editChannel })
                .fontSize(14).fontColor(this.theme.textPrimary)
                .backgroundColor('rgba(0,0,0,0.04)')
                .layoutWeight(1)
                .type(InputType.Number)
                .onChange((v: string) => this.editChannel = v)
            }.width('100%').margin({ bottom: 10 })

            Row() {
              Text('启用该 WiFi').fontSize(13).fontColor(this.theme.textSecondary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: !this.editDisabled })
                .selectedColor(this.theme.primary)
                .onChange((on: boolean) => this.editDisabled = !on)
            }.width('100%').margin({ bottom: 8 })

            Row() {
              SymbolGlyph($r('sys.symbol.warning')).fontSize(11).fontColor([this.theme.warning])
              Text(' 保存后无线网络将重启，已连接设备会短暂断线（约 5 秒）')
                .fontSize(10).fontColor(this.theme.warning).layoutWeight(1)
            }
            .width('100%')
            .margin({ bottom: 14 })

            Row() {
              Text('取消')
                .fontSize(14).fontColor(this.theme.textSecondary).textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 10, bottom: 10 })
                .borderRadius(10)
                .backgroundColor(this.theme.bgGlassLight)
                .onClick(() => { this.showEdit = false })
              Text(this.isSaving ? '保存中…' : '保存')
                .fontSize(14).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 10, bottom: 10 })
                .borderRadius(10)
                .backgroundColor(this.theme.primary)
                .margin({ left: 10 })
                .onClick(() => this.saveConfig())
            }.width('100%')
          }
          .width('88%')
          .padding(18)
          .borderRadius(18)
          .backgroundColor(this.theme.bgCardSolid)
          .border({ width: 0.5, color: this.theme.borderGlass })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
      }

      // 踢客户端确认
      if (this.kickTarget) {
        Column() {
          Column() {
            Text('踢下线确认').fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              .width('100%').margin({ bottom: 10 })
            Text(`确定要将 ${this.kickTarget} 踢下线吗？`)
              .fontSize(13).fontColor(this.theme.textSecondary).width('100%').margin({ bottom: 16 })
            Row() {
              Text('取消')
                .fontSize(14).fontColor(this.theme.textSecondary).textAlign(TextAlign.Center)
                .layoutWeight(1).padding({ top: 10, bottom: 10 }).borderRadius(10)
                .backgroundColor(this.theme.bgGlassLight)
                .onClick(() => { this.kickTarget = '' })
              Text('踢下线')
                .fontSize(14).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .layoutWeight(1).padding({ top: 10, bottom: 10 }).borderRadius(10)
                .backgroundColor('#FF5252').margin({ left: 10 })
                .onClick(() => this.confirmKick())
            }.width('100%')
          }
          .width('82%').padding(18).borderRadius(18)
          .backgroundColor(this.theme.bgCardSolid)
          .border({ width: 0.5, color: this.theme.borderGlass })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
      }
    }
    .width('100%').height('100%')
  }
}
