import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
/**
 * 客户端设备详情页面
 * 展示单个设备的应用使用统计（访问时长、访问记录）
 * 支持三个子 Tab：基本信息/访问统计/访问记录
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { DeviceVisitTime, DeviceVisitRecord, ConnectedDevice, WirelessClient } from '../../models/Models'
import { DeviceNoteStore } from '../../common/store/DeviceNoteStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

interface HasMac {
  mac: string
}

@Entry
@Component
struct ClientDetailPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State subTab: number = 0
  @State mac: string = ''
  @State hostname: string = ''

  @State isLoadingBasic: boolean = true
  @State isLoadingStats: boolean = true
  @State isLoadingRecords: boolean = true

  @State dhcpDevice: ConnectedDevice | null = null
  @State wifiClient: WirelessClient | null = null
  @State visitTimes: DeviceVisitTime[] = []
  @State visitRecords: DeviceVisitRecord[] = []
  @State basicError: string = ''
  @State statsError: string = ''
  @State recordsError: string = ''
  // 设备管理增强
  @State note: string = ''
  @State noteInput: string = ''
  @State editingNote: boolean = false
  @State isDenied: boolean = false
  @State managing: boolean = false
  @State manageMsg: string = ''
  @State dhcpBound: boolean = false
  @State showIpInput: boolean = false
  @State ipInput: string = ''
  @State bindingIp: string = ''
  private noteStore: DeviceNoteStore = DeviceNoteStore.getInstance()
  private deviceId: string = ''

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()

    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params) {
      this.mac = (params['mac'] as string) || ''
      this.hostname = (params['hostname'] as string) || ''
    }

    // 初始化设备备注存储（懒初始化）
    const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      this.noteStore.init(hostCtx as Context)
    }
    const activeDevice = AppState.getInstance().getActiveDevice()
    this.deviceId = activeDevice ? activeDevice.id : ''
    this.loadNote()
    this.loadDenyState()
    this.loadDhcpState()

    
    this.loadAll()
  }

  async loadAll(): Promise<void> {
    this.loadBasic()
    this.loadStats()
    this.loadRecords()
  }

  async loadBasic(): Promise<void> {
    this.isLoadingBasic = true
    this.basicError = ''
    try {
      const api = new ApiService()
      const results = await Promise.all([
        api.fetchConnectedDevices(),
        api.fetchWirelessClients()
      ])
      const dhcpDevices: ConnectedDevice[] = results[0]
      const wifiClients: WirelessClient[] = results[1]

      this.dhcpDevice = this.findByMac(dhcpDevices, this.mac)
      this.wifiClient = this.findByMac(wifiClients, this.mac)

      if (!this.dhcpDevice && !this.wifiClient) {
        this.basicError = '未找到该设备信息'
      }
    } catch (e) {
      this.basicError = '加载基本信息失败'
    }
    this.isLoadingBasic = false
  }

  private findByMac<T extends HasMac>(list: T[], mac: string): T | null {
    const target = mac.toLowerCase()
    for (let i = 0; i < list.length; i++) {
      if (list[i].mac.toLowerCase() === target) {
        return list[i]
      }
    }
    return null
  }

  // ===== 设备管理 =====

  /** 加载设备备注名 */
  async loadNote(): Promise<void> {
    if (!this.deviceId || !this.mac) return
    try {
      this.note = await this.noteStore.getNote(this.deviceId, this.mac)
      this.noteInput = this.note
    } catch (e) {
      hilog.error(0x0001, 'ClientDetailPage', `loadNote err: ${JSON.stringify(e)}`)
    }
  }

  /** 保存设备备注名 */
  async saveNote(): Promise<void> {
    if (!this.deviceId || !this.mac) return
    try {
      await this.noteStore.saveNote(this.deviceId, this.mac, this.noteInput)
      this.note = this.noteInput.trim()
      this.editingNote = false
    } catch (e) {
      hilog.error(0x0001, 'ClientDetailPage', `saveNote err: ${JSON.stringify(e)}`)
    }
  }

  /** 加载禁用联网状态 */
  async loadDenyState(): Promise<void> {
    if (!this.mac) return
    try {
      const api = new ApiService()
      this.isDenied = await api.isDeviceDenied(this.mac)
    } catch (e) {
      hilog.error(0x0001, 'ClientDetailPage', `loadDenyState err: ${JSON.stringify(e)}`)
    }
  }

  /** 加载 DHCP 静态绑定状态 */
  async loadDhcpState(): Promise<void> {
    if (!this.mac) return
    try {
      const api = new ApiService()
      const list = await api.listDhcpBindings()
      const macUpper: string = this.mac.toUpperCase()
      for (let i = 0; i < list.length; i++) {
        if (list[i].mac.toUpperCase() === macUpper) {
          this.dhcpBound = true
          this.bindingIp = list[i].ip
          return
        }
      }
      this.dhcpBound = false
      this.bindingIp = ''
    } catch (e) {
      hilog.error(0x0001, 'ClientDetailPage', `loadDhcpState err: ${JSON.stringify(e)}`)
    }
  }

  /** 保存 DHCP 静态绑定（固定 IP） */
  async saveDhcpBinding(): Promise<void> {
    if (this.managing || !this.mac) return
    const ip: string = this.ipInput.trim()
    if (!ip) {
      this.manageMsg = '请输入固定 IP 地址'
      return
    }
    this.managing = true
    this.manageMsg = ''
    try {
      const api = new ApiService()
      const name: string = this.note || this.hostname || this.mac
      const ok: boolean = await api.addDhcpBinding(this.mac, ip, name)
      if (ok) {
        this.dhcpBound = true
        this.bindingIp = ip
        this.showIpInput = false
        this.manageMsg = '已固定 IP，设备重启后地址保持不变'
      } else {
        this.manageMsg = '固定 IP 失败：接口无权限或参数无效'
      }
    } catch (e) {
      this.manageMsg = '操作异常，请重试'
    }
    this.managing = false
  }

  /** 解除 DHCP 静态绑定 */
  async removeDhcpBinding(): Promise<void> {
    if (this.managing || !this.mac) return
    this.managing = true
    this.manageMsg = ''
    try {
      const api = new ApiService()
      const ok: boolean = await api.removeDhcpBinding(this.mac)
      if (ok) {
        this.dhcpBound = false
        this.bindingIp = ''
        this.manageMsg = '已解除固定 IP'
      } else {
        this.manageMsg = '解除失败：接口无权限'
      }
    } catch (e) {
      this.manageMsg = '操作异常，请重试'
    }
    this.managing = false
  }

  /** 切换禁用/恢复联网 */
  async toggleDeny(): Promise<void> {
    if (this.managing || !this.mac) return
    this.managing = true
    this.manageMsg = ''
    try {
      const api = new ApiService()
      const ok: boolean = this.isDenied
        ? await api.allowDeviceNet(this.mac)
        : await api.denyDeviceNet(this.mac)
      if (ok) {
        this.isDenied = !this.isDenied
        this.manageMsg = this.isDenied ? '已禁用该设备联网' : '已恢复该设备联网'
      } else {
        this.manageMsg = '操作失败：设备不支持或接口无权限'
      }
    } catch (e) {
      this.manageMsg = '操作异常，请重试'
    }
    this.managing = false
  }

  /** 踢下线 */
  async kickDevice(): Promise<void> {
    if (this.managing || !this.mac) return
    this.managing = true
    this.manageMsg = ''
    try {
      const api = new ApiService()
      // 需要无线接口名（从 wifiClient 获取），无则尝试 DHCP 接口
      let devName: string = ''
      if (this.wifiClient && this.wifiClient.interface) {
        devName = this.wifiClient.interface
      }
      const ok: boolean = await api.kickWifiClient(devName, this.mac)
      if (ok) {
        this.manageMsg = '已将该设备踢下线'
      } else {
        this.manageMsg = '踢下线失败：设备不支持或接口无权限'
      }
    } catch (e) {
      this.manageMsg = '操作异常，请重试'
    }
    this.managing = false
  }

  async loadStats(): Promise<void> {
    this.isLoadingStats = true
    this.statsError = ''
    try {
      const api = new ApiService()
      this.visitTimes = await api.fetchDeviceVisitTime(this.mac)
      if (this.visitTimes.length === 0) {
        this.statsError = '暂无应用统计数据'
      }
    } catch (e) {
      this.statsError = '加载统计数据失败'
    }
    this.isLoadingStats = false
  }

  async loadRecords(): Promise<void> {
    this.isLoadingRecords = true
    this.recordsError = ''
    try {
      const api = new ApiService()
      this.visitRecords = await api.fetchDeviceVisitList(this.mac)
      if (this.visitRecords.length === 0) {
        this.recordsError = '暂无访问记录'
      }
    } catch (e) {
      this.recordsError = '加载访问记录失败'
    }
    this.isLoadingRecords = false
  }

  getDeviceIcon(): string {
    if (!this.hostname) return 'display'
    const name = this.hostname.toLowerCase()
    if (name.includes('phone') || name.includes('iphone')) return 'phone'
    if (name.includes('laptop') || name.includes('macbook') || name.includes('notebook')) return 'display'
    if (name.includes('tv') || name.includes('smart tv')) return 'display'
    if (name.includes('pi') || name.includes('raspberry')) return 'externaldrive'
    if (name.includes('tablet') || name.includes('ipad')) return 'display'
    return 'display'
  }

  /** 设备图标配色 */
  getDeviceIconColor(): string {
    if (!this.hostname) return '#64748B'
    const name = this.hostname.toLowerCase()
    if (name.includes('phone') || name.includes('iphone')) return '#3B82F6'
    if (name.includes('laptop') || name.includes('macbook') || name.includes('notebook')) return '#8B5CF6'
    if (name.includes('tv') || name.includes('smart tv')) return '#F59E0B'
    if (name.includes('pi') || name.includes('raspberry')) return '#0891B2'
    return '#64748B'
  }

  formatDuration(seconds: number): string {
    return FormatUtils.formatUptime(seconds)
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
            Text(` ${this.hostname || '设备详情'}`)
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 4 })
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
              hilog.error(0x0001, 'ClientDetailPage', `router.back failed: ${e}`)
            }
          })
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Row() {
          AppIcon({ name: this.getDeviceIcon(), iconSize: 34, colors: [this.getDeviceIconColor()] })
          Column() {
            Text(this.hostname || '未知设备')
              .fontSize(18)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(FormatUtils.formatMac(this.mac))
              .fontSize(12)
              .fontColor(this.theme.textTertiary)
              .fontFamily('monospace')
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })

        Row() {
          Row() {
            Text('基本信息')
              .fontSize(13)
              .fontColor(this.subTab === 0 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 0 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 0 })

          Row() {
            Text('应用统计')
              .fontSize(13)
              .fontColor(this.subTab === 1 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 1 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 1 })

          Row() {
            Text('应用记录')
              .fontSize(13)
              .fontColor(this.subTab === 2 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 2 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 2 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 2 })
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(12)
        .backgroundColor(this.theme.bgCard)
        .margin({ left: 16, right: 16, bottom: 8 })

        Scroll() {
          Column() {
            if (this.subTab === 0) {
              this.BasicInfoTab()
            }
            if (this.subTab === 1) {
              this.AppStatsTab()
            }
            if (this.subTab === 2) {
              this.AppRecordsTab()
            }
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

  @Builder
  BasicInfoTab() {
    Column() {
      if (this.isLoadingBasic) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.basicError && !this.dhcpDevice && !this.wifiClient) {
        Row() {
          AppIcon({ name: 'warning', iconSize: 16, colors: [this.theme.warning] })
            .margin({ right: 8 })
          Text(this.basicError)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        if (this.dhcpDevice) {
          this.DhcpInfoSection()
        }

        if (this.wifiClient) {
          this.WifiInfoSection()
        }

        // 设备管理卡片（备注名/禁用联网/踢下线）
        this.DeviceManageSection()

        if (!this.dhcpDevice && !this.wifiClient) {
          Row() {
            Text('⚠')
              .fontSize(16)
              .margin({ right: 8 })
            Text('未找到该设备信息')
              .fontSize(12)
              .fontColor(this.theme.warning)
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
        }
      }
    }
    .width('100%')
  }

  @Builder
  DhcpInfoSection() {
    Column() {
      Row() {
        AppIcon({ name: 'doc_plaintext', iconSize: 14, colors: ['#3B82F6'] })
        Text(' DHCP 租约信息')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
      }
      .margin({ bottom: 12 })
      .width('100%')

      this.infoRow('设备名称', this.dhcpDevice!.hostname || this.hostname || '--')
      this.infoRow('MAC 地址', FormatUtils.formatMac(this.dhcpDevice!.mac || this.mac))
      this.infoRow('IP 地址', FormatUtils.formatIp(this.dhcpDevice!.ip))
      this.infoRow('在线状态', this.dhcpDevice!.isOnline ? '在线' : '离线',
        this.dhcpDevice!.isOnline ? this.theme.success : this.theme.danger)
      this.infoRow('网络接口', this.dhcpDevice!.interface || '--')
      if (this.dhcpDevice!.onlineTime) {
        this.infoRow('租约时间', this.dhcpDevice!.onlineTime)
      }
      if (this.dhcpDevice!.vendor) {
        this.infoRow('厂商', this.dhcpDevice!.vendor)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .margin({ top: 8 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  @Builder
  DeviceManageSection() {
    Column() {
      Row() {
        AppIcon({ name: 'gearshape', iconSize: 14, colors: ['#8B5CF6'] })
        Text(' 设备管理')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
      }
      .margin({ bottom: 4 })
      .width('100%')

      // 备注名
      Row() {
        Text('备注名')
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
          .width(68)
        if (this.editingNote) {
          TextInput({ placeholder: '给设备起个名字', text: this.noteInput })
            .placeholderColor(this.theme.textTertiary)
            .fontColor(this.theme.textPrimary)
            .backgroundColor('transparent')
            .layoutWeight(1)
            .height(36)
            .onChange((v: string) => { this.noteInput = v })
        } else {
          Text(this.note || '未设置')
            .fontSize(12)
            .fontColor(this.note ? this.theme.textPrimary : this.theme.textTertiary)
            .fontWeight(this.note ? FontWeight.Medium : FontWeight.Normal)
            .layoutWeight(1)
        }
        if (this.editingNote) {
          Row() {
            Text('取消')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => { this.editingNote = false; this.noteInput = this.note })
            Text('保存')
              .fontSize(11)
              .fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.theme.primary)
              .margin({ left: 6 })
              .onClick(() => this.saveNote())
          }
        } else {
          Text('编辑')
            .fontSize(11)
            .fontColor(this.theme.primary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor('rgba(68,138,255,0.1)')
            .onClick(() => { this.editingNote = true })
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })

      // 操作按钮行
      Row() {
        // 禁用/恢复联网
        Row() {
          AppIcon({ name: this.isDenied ? 'lock_open' : 'xmark_circle', iconSize: 13, colors: [this.isDenied ? this.theme.success : this.theme.danger] })
          Text(this.isDenied ? ' 恢复联网' : ' 禁用联网')
            .fontSize(12)
            .fontColor(this.isDenied ? this.theme.success : this.theme.danger)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor(this.isDenied ? 'rgba(0,230,118,0.1)' : 'rgba(255,82,82,0.1)')
        .border({ width: 0.5, color: this.isDenied ? '#00E67644' : '#FF525244' })
        .onClick(() => this.toggleDeny())

        // 踢下线
        Row() {
          AppIcon({ name: 'arrow_up_right', iconSize: 13, colors: [this.theme.warning] })
          Text(' 踢下线')
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor('rgba(255,152,0,0.1)')
        .border({ width: 0.5, color: '#FF980044' })
        .margin({ left: 10 })
        .onClick(() => this.kickDevice())
      }
      .width('100%')
      .padding({ top: 6, bottom: 2 })

      // 固定 IP（DHCP 静态绑定）
      Row() {
        if (this.showIpInput) {
          TextInput({ placeholder: '输入固定 IP，如 192.168.1.100', text: this.ipInput })
            .placeholderColor(this.theme.textTertiary)
            .fontColor(this.theme.textPrimary)
            .backgroundColor('transparent')
            .layoutWeight(1)
            .height(34)
            .onChange((v: string) => { this.ipInput = v })
          Text('取消')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ left: 6 })
            .onClick(() => { this.showIpInput = false })
          Text('确定')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(this.theme.primary)
            .margin({ left: 6 })
            .onClick(() => this.saveDhcpBinding())
        } else if (this.dhcpBound) {
          Row() {
            AppIcon({ name: 'pin', iconSize: 12, colors: [this.theme.success] })
            Text(` 已固定 IP：${this.bindingIp}`)
              .fontSize(12)
              .fontColor(this.theme.success)
          }
          .layoutWeight(1)
          Text('解除')
            .fontSize(11)
            .fontColor(this.theme.danger)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor('rgba(255,82,82,0.1)')
            .onClick(() => this.removeDhcpBinding())
        } else {
          Row() {
            AppIcon({ name: 'pin', iconSize: 12, colors: [this.theme.primary] })
            Text(' 固定 IP')
              .fontSize(12)
              .fontColor(this.theme.primary)
          }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor('rgba(68,138,255,0.1)')
            .border({ width: 0.5, color: '#448AFF44' })
            .onClick(() => {
              this.showIpInput = true
              this.ipInput = this.dhcpDevice ? this.dhcpDevice.ip : ''
            })
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 2 })

      // 操作结果提示
      if (this.manageMsg) {
        Text(this.manageMsg)
          .fontSize(11)
          .fontColor(this.manageMsg.includes('已') ? this.theme.success : this.theme.warning)
          .width('100%')
          .margin({ top: 6 })
      }
      if (this.managing) {
        Row() {
          LoadingProgress().width(16).height(16).color(this.theme.primary)
          Text(' 处理中…').fontSize(11).fontColor(this.theme.textTertiary)
        }.width('100%').margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .margin({ top: 8 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  @Builder
  WifiInfoSection() {
    Column() {
      Row() {
        AppIcon({ name: 'wifi', iconSize: 14, colors: ['#10B981'] })
        Text(' 无线连接信息')
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
      }
      .margin({ bottom: 12 })
      .width('100%')

      this.infoRow('接入接口', this.wifiClient!.interface || '--')
      this.infoRow('信号强度', `${this.wifiClient!.signal} dBm`, this.getSignalColor(this.wifiClient!.signal))
      this.infoRow('信号质量', this.getSignalLevel(this.wifiClient!.signal))
      this.infoRow('RX 速率', FormatUtils.formatSpeed(this.wifiClient!.rxRate))
      this.infoRow('TX 速率', FormatUtils.formatSpeed(this.wifiClient!.txRate))
      if (this.wifiClient!.connectedTime > 0) {
        this.infoRow('已连接时长', FormatUtils.formatUptime(this.wifiClient!.connectedTime))
      }
      if (this.wifiClient!.inactiveTime > 0) {
        this.infoRow('非活跃时长', FormatUtils.formatUptime(this.wifiClient!.inactiveTime))
      }
      if (this.wifiClient!.isMesh) {
        this.infoRow('组网方式', 'Mesh')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .margin({ top: 8 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  getSignalColor(signal: number): string {
    if (signal >= -50) return this.theme.success
    if (signal >= -65) return this.theme.warning
    return this.theme.danger
  }

  getSignalLevel(signal: number): string {
    if (signal >= -45) return '▂▄▆█ 优秀'
    if (signal >= -55) return '▂▄▆_ 良好'
    if (signal >= -65) return '▂▄__ 一般'
    if (signal >= -75) return '▂___ 较差'
    return '____ 很差'
  }

  @Builder
  AppStatsTab() {
    Column() {
      if (this.isLoadingStats) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.statsError && this.visitTimes.length === 0) {
        Row() {
          AppIcon({ name: 'warning', iconSize: 16, colors: [this.theme.warning] })
            .margin({ right: 8 })
          Text(this.statsError)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        Column() {
          Row() {
            AppIcon({ name: 'circle_grid_2x2', iconSize: 14, colors: ['#F59E0B'] })
            Text(' 应用统计')
              .fontSize(14)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .margin({ bottom: 12 })
            .width('100%')

          ForEach(this.visitTimes, (item: DeviceVisitTime, index: number) => {
            this.AppStatItem(item, index)
          }, (item: DeviceVisitTime, index: number): string => `${item.appId}_${index}`)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
      }
    }
    .width('100%')
  }

  @Builder
  AppStatItem(item: DeviceVisitTime, index: number) {
    Column() {
      Row() {
        Column() {
          Text(item.appName || `应用 ${item.appId}`)
            .fontSize(13)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatDuration(item.totalSeconds))
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${item.percent.toFixed(1)}%`)
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
      }
      .width('100%')

      Stack() {
        Row()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor('rgba(255,255,255,0.08)')
        Row()
          .width(`${Math.max(0, Math.min(100, item.percent))}%`)
          .height(6)
          .borderRadius(3)
          .linearGradient({
            angle: 90,
            colors: [
              [this.theme.primary, 0],
              [this.theme.secondary, 1]
            ]
          })
      }
      .width('100%')
      .alignContent(Alignment.End)
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: index < this.visitTimes.length - 1 ? 0.3 : 0 }, color: this.theme.borderGlass })
  }

  @Builder
  AppRecordsTab() {
    Column() {
      if (this.isLoadingRecords) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.recordsError && this.visitRecords.length === 0) {
        Row() {
          AppIcon({ name: 'warning', iconSize: 16, colors: [this.theme.warning] })
            .margin({ right: 8 })
          Text(this.recordsError)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        Column() {
          Row() {
            AppIcon({ name: 'list_bullet', iconSize: 14, colors: ['#EC4899'] })
            Text(' 应用记录')
              .fontSize(14)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .margin({ bottom: 12 })
          .width('100%')

          Row() {
            Text('应用')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .layoutWeight(2)
            Text('开始时间')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .layoutWeight(2.5)
            Text('时长')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .layoutWeight(1.5)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ bottom: 8 })
          .border({ width: { bottom: 0.5 }, color: this.theme.borderGlass })

          ForEach(this.visitRecords, (item: DeviceVisitRecord, index: number) => {
            Row() {
              Text(item.appName || `应用 ${item.appId}`)
                .fontSize(12)
                .fontColor(this.theme.textPrimary)
                .layoutWeight(2)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.startTime)
                .fontSize(11)
                .fontColor(this.theme.textSecondary)
                .layoutWeight(2.5)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.formatDuration(item.duration))
                .fontSize(11)
                .fontColor(this.theme.textSecondary)
                .layoutWeight(1.5)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .padding({ top: 9, bottom: 9 })
            .border({ width: { bottom: index < this.visitRecords.length - 1 ? 0.3 : 0 }, color: this.theme.borderGlass })
          }, (item: DeviceVisitRecord, index: number): string => `${item.appId}_${item.startTime}_${index}`)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
      }
    }
    .width('100%')
  }

  @Builder
  infoRow(label: string, value: string, valueColor?: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Text(value)
        .fontSize(12)
        .fontColor(valueColor || this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
