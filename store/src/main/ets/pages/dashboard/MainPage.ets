import { AppState } from '../../common/store/AppState'
import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { SystemInfo, WanStatus, ConnectedDevice, NetworkInterface, MountPoint, ConntrackInfo, WirelessClient } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { router } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

// ============================================================
// DashboardTab - 首页
// ============================================================
@Component
struct DashboardTab {
  @Prop theme: ThemePalette
  @State systemInfo: SystemInfo = this.emptySys()
  @State wanStatus: WanStatus = this.emptyWan()
  @State lanStatus: WanStatus = this.emptyWan()
  @State isLoading: boolean = true
  @State lastUpdate: string = '--:--:--'
  @State errorText: string = ''
  @State isOnline: boolean = false
  @State mountPoints: MountPoint[] = []
  @State conntrack: ConntrackInfo = { current: 0, max: 0, percent: 0 }
  @State networkInterfaces: NetworkInterface[] = []
  private timerId: number = -1

  aboutToAppear(): void {
    this.loadData()
    this.timerId = setInterval(() => {
      this.refreshData()
    }, 5000)
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      const results = await Promise.all([
        api.fetchSystemInfo(),
        api.fetchWanStatus(),
        api.fetchLanStatus(),
        api.fetchMountPoints(),
        api.fetchConntrack(),
        api.fetchNetworkInterfaces()
      ])
      this.systemInfo = results[0]
      this.wanStatus = results[1]
      this.lanStatus = results[2]
      this.mountPoints = results[3]
      this.conntrack = results[4]
      this.networkInterfaces = results[5]
      this.isOnline = true
    } catch (dashErr) {
      this.errorText = '加载数据失败'
    }
    this.isLoading = false
    this.updateTimestamp()
  }

  async refreshData(): Promise<void> {
    try {
      if (!AppState.getInstance().isConnected()) {
        return
      }
      const api = new ApiService()
      const results = await Promise.all([
        api.fetchSystemInfo(),
        api.fetchWanStatus(),
        api.fetchLanStatus(),
        api.fetchMountPoints(),
        api.fetchConntrack()
      ])
      this.systemInfo = results[0]
      this.wanStatus = results[1]
      this.lanStatus = results[2]
      this.mountPoints = results[3]
      this.conntrack = results[4]
      this.isOnline = true
    } catch (refErr) {
      // Silent fail on refresh
    }
    this.updateTimestamp()
  }

  updateTimestamp(): void {
    const now: Date = new Date()
    this.lastUpdate =
      `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`
  }

  emptySys(): SystemInfo {
    return {
      hostname: '', model: '', kernel: '', firmwareVersion: '',
      localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
      memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0,
      boardName: '', cpuModel: '', distribution: '', releaseVersion: '', releaseRevision: '', releaseTarget: ''
    }
  }

  emptyWan(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0',
      netmask: '', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '',
      proto: '', macAddr: ''
    }
  }

  getTempColor(temp: number): string {
    if (temp <= 0) {
      return this.theme.textTertiary
    }
    if (temp < 50) {
      return '#00E676'
    }
    if (temp < 65) {
      return '#FFD740'
    }
    return '#FF5252'
  }

  getCpuColor(usage: number): string {
    if (usage < 30) {
      return '#00E676'
    }
    if (usage < 60) {
      return '#FFD740'
    }
    return '#FF5252'
  }

  formatLocalTime(isoStr: string): string {
    try {
      const d: Date = new Date(isoStr)
      return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`
    } catch (e) {
      return isoStr
    }
  }

  getMemoryPct(): number {
    return this.systemInfo.memoryTotal > 0
      ? (this.systemInfo.memoryUsed / this.systemInfo.memoryTotal) * 100
      : 0
  }

  getMemoryColor(usage: number): string {
    if (usage < 40) {
      return '#00E676'
    }
    if (usage < 75) {
      return '#FFD740'
    }
    return '#FF5252'
  }

  getTypeColor(type: string): string {
    if (type === 'wan') {
      return '#FF6E40'
    }
    if (type === 'lan') {
      return '#448AFF'
    }
    if (type === 'wifi') {
      return '#00E676'
    }
    return this.theme.textTertiary
  }

  getLanInterface(): NetworkInterface | null {
    for (let i = 0; i < this.networkInterfaces.length; i++) {
      if (this.networkInterfaces[i].type === 'lan') {
        return this.networkInterfaces[i]
      }
    }
    return null
  }

  build() {
    Column() {
      // 顶部：设备名 + 在线状态 + 更新时间
      Row() {
        Column() {
          Text(this.systemInfo.hostname || 'OpenWrt')
            .fontSize(20)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Circle()
              .width(6)
              .height(6)
              .fill(this.isOnline ? this.theme.success : this.theme.danger)
            Text(this.isOnline ? '在线' : '离线')
              .fontSize(11)
              .fontColor(this.isOnline ? this.theme.success : this.theme.textTertiary)
              .margin({ left: 4 })
            Text(' · ')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
            Text(`更新 ${this.lastUpdate}`)
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
          }
          .margin({ top: 4 })
        }

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            if (this.errorText) {
              Row() {
                Text('⚠')
                  .fontSize(16)
                  .margin({ right: 8 })
                Text(this.errorText)
                  .fontSize(12)
                  .fontColor(this.theme.warning)
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: 4, bottom: 4 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
            }

            // ============ 第一行：下载/上传 两个大卡片 ============
            Row() {
              // 下载速度
              Column() {
                Text('⇩ 下载')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 6 })
                Text(FormatUtils.formatSpeed(this.wanStatus.rxRate))
                  .fontSize(22)
                  .fontColor('#00E676')
                  .fontWeight(FontWeight.Bold)
                  .fontFamily('monospace')
              }
              .width('47%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .alignItems(HorizontalAlign.Start)

              // 上传速度
              Column() {
                Text('⇧ 上传')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 6 })
                Text(FormatUtils.formatSpeed(this.wanStatus.txRate))
                  .fontSize(22)
                  .fontColor('#448AFF')
                  .fontWeight(FontWeight.Bold)
                  .fontFamily('monospace')
              }
              .width('47%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 8 })

            // ============ 第二行：CPU / 内存 / 温度 三个卡片 ============
            Row() {
              // CPU
              Column() {
                Text('CPU')
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 4 })
                Text(FormatUtils.formatPercent(this.systemInfo.cpuUsage))
                  .fontSize(16)
                  .fontColor(this.getCpuColor(this.systemInfo.cpuUsage))
                  .fontWeight(FontWeight.Bold)
                  .margin({ bottom: 6 })

                Stack() {
                  Row()
                    .width('100%')
                    .height(4)
                    .borderRadius(2)
                    .backgroundColor('rgba(255,255,255,0.1)')
                  Row()
                    .width(`${Math.max(0, Math.min(100, this.systemInfo.cpuUsage))}%`)
                    .height(4)
                    .borderRadius(2)
                    .linearGradient({
                      angle: 90,
                      colors: [
                        [this.getCpuColor(this.systemInfo.cpuUsage), 0],
                        [this.getCpuColor(this.systemInfo.cpuUsage) + '44', 1]
                      ]
                    })
                }
                .width('100%')
              }
              .width('30%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .alignItems(HorizontalAlign.Start)

              // 内存
              Column() {
                Text('内存')
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 4 })
                Text(`${this.getMemoryPct().toFixed(1)}%`)
                  .fontSize(16)
                  .fontColor(this.getMemoryColor(this.getMemoryPct()))
                  .fontWeight(FontWeight.Bold)
                  .margin({ bottom: 2 })
                Text(`${FormatUtils.formatBytes(this.systemInfo.memoryUsed)} / ${FormatUtils.formatBytes(this.systemInfo.memoryTotal)}`)
                  .fontSize(9)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 4 })

                Stack() {
                  Row()
                    .width('100%')
                    .height(4)
                    .borderRadius(2)
                    .backgroundColor('rgba(255,255,255,0.1)')
                  Row()
                    .width(`${Math.max(0, Math.min(100, this.getMemoryPct()))}%`)
                    .height(4)
                    .borderRadius(2)
                    .linearGradient({
                      angle: 90,
                      colors: [
                        [this.getMemoryColor(this.getMemoryPct()), 0],
                        [this.getMemoryColor(this.getMemoryPct()) + '44', 1]
                      ]
                    })
                }
                .width('100%')
              }
              .width('30%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .alignItems(HorizontalAlign.Start)

              // 温度
              Column() {
                Text('CPU温度')
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ bottom: 4 })
                Row() {
                  Text(this.systemInfo.cpuTemp > 0 ? this.systemInfo.cpuTemp.toFixed(1) : '--')
                    .fontSize(16)
                    .fontColor(this.getTempColor(this.systemInfo.cpuTemp))
                    .fontWeight(FontWeight.Bold)
                  Text('°C')
                    .fontSize(11)
                    .fontColor(this.theme.textTertiary)
                    .margin({ left: 2 })
                }
                .margin({ bottom: 6 })

                Stack() {
                  Row()
                    .width('100%')
                    .height(4)
                    .borderRadius(2)
                    .backgroundColor('rgba(255,255,255,0.1)')
                  Row()
                    .width(`${this.systemInfo.cpuTemp > 0 ? Math.min(100, (this.systemInfo.cpuTemp / 100) * 100) : 0}%`)
                    .height(4)
                    .borderRadius(2)
                    .linearGradient({
                      angle: 90,
                      colors: [
                        [this.getTempColor(this.systemInfo.cpuTemp), 0],
                        [this.getTempColor(this.systemInfo.cpuTemp) + '44', 1]
                      ]
                    })
                }
                .width('100%')
              }
              .width('30%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 10 })

            // ============ 系统信息卡片 ============
            Column() {
              Text('💻 系统信息')
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })
              this.infoRow('主机名', this.systemInfo.hostname || '--')
              this.infoRow('系统描述', this.systemInfo.model || '--')
              if (this.systemInfo.cpuModel) {
                this.infoRow('CPU 型号', this.systemInfo.cpuModel)
              }
              if (this.systemInfo.boardName) {
                this.infoRow('架构/主板', this.systemInfo.boardName)
              }
              if (this.systemInfo.distribution) {
                this.infoRow('发行版', this.systemInfo.distribution)
              }
              if (this.systemInfo.releaseVersion) {
                this.infoRow('固件版本', this.systemInfo.releaseRevision
                  ? `${this.systemInfo.releaseVersion} (${this.systemInfo.releaseRevision})`
                  : this.systemInfo.releaseVersion)
              } else {
                this.infoRow('固件版本', this.systemInfo.firmwareVersion || '--')
              }
              if (this.systemInfo.releaseTarget) {
                this.infoRow('目标平台', this.systemInfo.releaseTarget)
              }
              this.infoRow('内核', this.systemInfo.kernel || '--')
              this.infoRow('本地时间', this.systemInfo.localTime
                ? this.formatLocalTime(this.systemInfo.localTime)
                : '--')
              this.infoRow('运行时间', this.systemInfo.uptime > 0 ? FormatUtils.formatUptime(this.systemInfo.uptime) : '--')
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            // ============ 网络接口卡片（仅 LAN） ============
            Column() {
              Text('🌐 局域网')
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })

              if (this.getLanInterface() === null) {
                this.infoRow('IP 地址', this.lanStatus.ipAddress !== '0.0.0.0' ? this.lanStatus.ipAddress : '--')
                this.infoRow('网关', this.lanStatus.gateway || '--')
                if (this.lanStatus.dns.length > 0) {
                  this.infoRow('DNS', this.lanStatus.dns.join(', '))
                }
              } else {
                this.NetInterfaceRow(this.getLanInterface()!)
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            // ============ 磁盘使用卡片 ============
            Column() {
              Text('💾 磁盘使用')
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })

              if (this.mountPoints.length === 0) {
                Text('暂无挂载点数据')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
              } else {
                ForEach(this.mountPoints, (mp: MountPoint, idx: number) => {
                  Column() {
                    Row() {
                      Text(mp.mountPoint)
                        .fontSize(13)
                        .fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text(`${mp.usedPercent.toFixed(1)}%`)
                        .fontSize(13)
                        .fontColor(this.getCpuColor(mp.usedPercent))
                        .fontWeight(FontWeight.Bold)
                    }
                    .width('100%')

                    Row() {
                      Text(`${FormatUtils.formatBytes(mp.used)} / ${FormatUtils.formatBytes(mp.size)}`)
                        .fontSize(10)
                        .fontColor(this.theme.textTertiary)
                      Blank()
                      Text(`可用 ${FormatUtils.formatBytes(mp.available)}`)
                        .fontSize(10)
                        .fontColor(this.theme.textSecondary)
                    }
                    .width('100%')
                    .margin({ top: 2 })

                    Stack() {
                      Row()
                        .width('100%')
                        .height(4)
                        .borderRadius(2)
                        .backgroundColor('rgba(255,255,255,0.1)')
                      Row()
                        .width(`${Math.max(0, Math.min(100, mp.usedPercent))}%`)
                        .height(4)
                        .borderRadius(2)
                        .linearGradient({
                          angle: 90,
                          colors: [
                            [this.getCpuColor(mp.usedPercent), 0],
                            [this.getCpuColor(mp.usedPercent) + '44', 1]
                          ]
                        })
                    }
                    .width('100%')
                    .margin({ top: 8 })
                  }
                  .width('100%')
                  .padding({ top: idx > 0 ? 10 : 0, bottom: idx < this.mountPoints.length - 1 ? 10 : 0 })
                  .border(idx < this.mountPoints.length - 1 ? { width: { bottom: 0.3 }, color: this.theme.borderGlass } : {})
                }, (item: MountPoint): string => item.mountPoint)
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder NetInterfaceRow(iface: NetworkInterface) {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .fill(iface.status === 'up' ? this.theme.success : this.theme.textTertiary)
        .margin({ right: 6 })
      Text(iface.ipAddress || '0.0.0.0')
        .fontSize(18)
        .fontColor(this.theme.primary)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
    }
    .width('100%')
    .margin({ bottom: 8 })

    if (iface.macAddress) {
      Row() {
        Text('MAC  ')
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
        Text(iface.macAddress)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
          .fontFamily('monospace')
      }
      .width('100%')
      .margin({ top: 2 })
    }

    if (iface.gateway || iface.mtu > 0) {
      Row() {
        if (iface.gateway) {
          Text(`网关 ${iface.gateway}`)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
        }
        if (iface.gateway && iface.mtu > 0) {
          Text('  ·  ')
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
        }
        Text(`MTU ${iface.mtu}`)
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .margin({ top: 2 })
    }

    if (iface.rxBytes > 0 || iface.txBytes > 0) {
      Row() {
        Text(`↓ ${FormatUtils.formatBytes(iface.rxBytes)}`)
          .fontSize(10)
          .fontColor('#00E676')
        Text(`  ↑ ${FormatUtils.formatBytes(iface.txBytes)}`)
          .fontSize(10)
          .fontColor('#448AFF')
      }
      .width('100%')
      .margin({ top: 4 })
    }
  }

  @Builder infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(60)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}

// ============================================================
// DeviceTab - 设备列表（DHCP客户端）
// ============================================================
@Component
struct DeviceTab {
  @Prop theme: ThemePalette
  @State devices: ConnectedDevice[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State searchText: string = ''
  @State subTab: number = 0
  @State wirelessClients: WirelessClient[] = []
  @State wirelessLoading: boolean = false

  aboutToAppear(): void {
    this.loadDevices()
    this.loadWirelessData()
  }

  async loadDevices(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      this.devices = await api.fetchConnectedDevices()
    } catch (devErr) {
      this.errorText = '加载设备列表失败'
    }
    this.isLoading = false
  }

  async loadWirelessData(): Promise<void> {
    this.wirelessLoading = true
    try {
      if (!AppState.getInstance().isConnected()) {
        this.wirelessLoading = false
        return
      }
      const api = new ApiService()
      const wdevices = await api.fetchWirelessDevices()
      if (wdevices.length > 0) {
        this.wirelessClients = await api.fetchWirelessClients(wdevices[0].name)
      } else {
        this.wirelessClients = []
      }
    } catch (wlErr) {
      this.wirelessClients = []
    }
    this.wirelessLoading = false
  }

  getFilteredDevices(): ConnectedDevice[] {
    if (!this.searchText.trim()) {
      return this.devices
    }
    const kw: string = this.searchText.trim().toLowerCase()
    return this.devices.filter(d =>
      d.hostname.toLowerCase().includes(kw) ||
      d.ip.includes(kw) ||
      d.mac.toLowerCase().includes(kw)
    )
  }

  getDeviceEmoji(mac: string, hostname: string): string {
    const icon: string = FormatUtils.getDeviceIcon(mac, hostname)
    switch (icon) {
      case 'phone':
        return '📱'
      case 'laptop':
        return '💻'
      case 'tv':
        return '📺'
      case 'server':
        return '🖥'
      case 'camera':
        return '📷'
      case 'printer':
        return '🖨'
      case 'speaker':
        return '🔊'
      case 'watch':
        return '⌚'
      default:
        return '📡'
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('设备列表')
          .fontSize(20)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(`${this.getFilteredDevices().length} 台设备`)
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      // 搜索栏
      Row() {
        TextInput({ placeholder: '搜索设备名称、IP 或 MAC...', text: this.searchText })
          .placeholderColor(this.theme.textTertiary)
          .fontColor(this.theme.textPrimary)
          .backgroundColor('transparent')
          .onChange((v: string) => {
            this.searchText = v
          })
          .layoutWeight(1)
          .height(40)
        Text('🔍')
          .fontSize(16)
          .fontColor(this.theme.textSecondary)
          .padding({ left: 10, right: 4 })
      }
      .width('100%')
      .height(40)
      .borderRadius(12)
      .backgroundColor(this.theme.bgCard)
      .backdropBlur(10)
      .border({ width: 0.5, color: this.theme.borderGlass })
      .padding({ left: 14, right: 14 })
      .margin({ left: 16, right: 16, top: 8, bottom: 8 })

      // 子标签切换：DHCP / 无线
      Row() {
        Row() {
          Text('DHCP 客户端')
            .fontSize(12)
            .fontColor(this.subTab === 0 ? this.theme.textPrimary : this.theme.textTertiary)
            .fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Normal)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(100)
        .backgroundColor(this.subTab === 0 ? this.theme.bgCardHover : 'transparent')
        .border(this.subTab === 0 ? { width: 0.5, color: this.theme.primary } : {})
        .onClick(() => {
          this.subTab = 0
        })

        Row() {
          Text('📶 无线')
            .fontSize(12)
            .fontColor(this.subTab === 1 ? this.theme.textPrimary : this.theme.textTertiary)
            .fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Normal)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(100)
        .backgroundColor(this.subTab === 1 ? this.theme.bgCardHover : 'transparent')
        .border(this.subTab === 1 ? { width: 0.5, color: this.theme.primary } : {})
        .margin({ left: 10 })
        .onClick(() => {
          this.subTab = 1
        })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ bottom: 4 })

      if (this.subTab === 0) {
      Scroll() {
        Column() {
          if (this.isLoading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.theme.primary)
              Text('加载设备列表...')
                .fontSize(14)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 12 })
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          } else if (this.errorText) {
            Row() {
              Text('⚠')
                .fontSize(16)
                .margin({ right: 8 })
              Text(this.errorText)
                .fontSize(12)
                .fontColor(this.theme.warning)
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .border({ width: 0.5, color: this.theme.borderGlass })
          } else if (this.devices.length === 0) {
            Column() {
              Text('📡')
                .fontSize(48)
                .margin({ bottom: 12 })
              Text('暂无连接设备')
                .fontSize(16)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding(40)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .alignItems(HorizontalAlign.Center)
          } else {
            ForEach(this.getFilteredDevices(), (device: ConnectedDevice, index: number) => {
              Row() {
                // 设备图标
                Text(this.getDeviceEmoji(device.mac, device.hostname))
                  .fontSize(28)
                  .width(44)
                  .height(44)
                  .borderRadius(12)
                  .backgroundColor(this.theme.bgGlassLight)
                  .textAlign(TextAlign.Center)

                // 设备信息
                Column() {
                  Text(device.hostname || 'Unknown')
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(FormatUtils.formatMac(device.mac))
                      .fontSize(10)
                      .fontColor(this.theme.textTertiary)
                    if (FormatUtils.getVendorName(device.mac) !== 'Unknown') {
                      Text(` · ${FormatUtils.getVendorName(device.mac)}`)
                        .fontSize(10)
                        .fontColor(this.theme.textTertiary)
                    }
                  }
                }
                .margin({ left: 12 })
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // IP 地址
                Column() {
                  Text(device.ip)
                    .fontSize(12)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily('monospace')
                }
                .alignItems(HorizontalAlign.End)

                // 在线状态
                Circle()
                  .width(8)
                  .height(8)
                  .fill(device.isOnline ? this.theme.success : this.theme.textTertiary)
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: 6 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .onClick(() => {
                try {
                  router.pushUrl({
                    url: 'pages/devices/ClientDetailPage',
                    params: { mac: device.mac, hostname: device.hostname }
                  })
                } catch (e) {
                  hilog.error(0x0001, 'MainPage', `pushUrl failed: ${e}`)
                }
              })
            }, (item: ConnectedDevice): string => item.mac + item.ip)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 100 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      } else {
      // 无线客户端列表
      Scroll() {
        Column() {
          if (this.wirelessLoading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.theme.primary)
              Text('加载无线设备...')
                .fontSize(14)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 12 })
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          } else if (this.wirelessClients.length === 0) {
            Column() {
              Text('📶')
                .fontSize(48)
                .margin({ bottom: 12 })
              Text('暂无无线客户端')
                .fontSize(16)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding(40)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .alignItems(HorizontalAlign.Center)
          } else {
            ForEach(this.wirelessClients, (client: WirelessClient, idx: number) => {
              Row() {
                Text('📶')
                  .fontSize(28)
                  .width(44)
                  .height(44)
                  .borderRadius(12)
                  .backgroundColor(this.theme.bgGlassLight)
                  .textAlign(TextAlign.Center)

                Column() {
                  Text(client.hostname || client.mac)
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(FormatUtils.formatMac(client.mac))
                      .fontSize(10)
                      .fontColor(this.theme.textTertiary)
                    if (client.signal > 0) {
                      Text(` · 信号 ${client.signal} dBm`)
                        .fontSize(10)
                        .fontColor(this.theme.textTertiary)
                    }
                  }
                }
                .margin({ left: 12 })
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column() {
                  Text(client.rxRate > 0 || client.txRate > 0 ? `⇩ ${FormatUtils.formatSpeed(client.rxRate)}` : '--')
                    .fontSize(10)
                    .fontColor(this.theme.success)
                  Text(client.rxRate > 0 || client.txRate > 0 ? `⇧ ${FormatUtils.formatSpeed(client.txRate)}` : '--')
                    .fontSize(10)
                    .fontColor(this.theme.secondary)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: 6 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .onClick(() => {
              try {
                router.pushUrl({
                  url: 'pages/devices/ClientDetailPage',
                  params: { mac: client.mac, hostname: client.hostname || client.mac }
                })
              } catch (e) {
                hilog.error(0x0001, 'MainPage', `pushUrl failed: ${e}`)
              }
            })
          }, (item: WirelessClient): string => item.mac)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 100 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}

// ============================================================
// NetworkTab - 网络状态（简化版）
// ============================================================
@Component
struct NetworkTab {
  @Prop theme: ThemePalette
  @State interfaces: NetworkInterface[] = []
  @State wanStatus: WanStatus = this.emptyWan()
  @State lanStatus: WanStatus = this.emptyWan()
  @State isLoading: boolean = true
  @State errorText: string = ''

  aboutToAppear(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      this.wanStatus = await api.fetchWanStatus()
      this.lanStatus = await api.fetchLanStatus()
      this.interfaces = await api.fetchNetworkInterfaces()
    } catch (netErr) {
      this.errorText = '加载网络信息失败'
    }
    this.isLoading = false
  }

  emptyWan(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0',
      netmask: '', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '',
      proto: '', macAddr: ''
    }
  }

  getTypeLabel(type: string): string {
    const labels: Record<string, string> = {
      'wan': 'WAN 外网',
      'lan': 'LAN 内网',
      'wifi': 'WiFi 无线',
      'vpn': 'VPN'
    }
    return labels[type] || type
  }

  getTypeColor(type: string): string {
    const colors: Record<string, string> = {
      'wan': this.theme.warning,
      'lan': this.theme.success,
      'wifi': this.theme.primary,
      'vpn': this.theme.secondary
    }
    return colors[type] || this.theme.textTertiary
  }

  getTypeEmoji(type: string): string {
    const emojis: Record<string, string> = {
      'wan': '🌐',
      'lan': '🏠',
      'wifi': '📶',
      'vpn': '🔒'
    }
    return emojis[type] || '🔌'
  }

  build() {
    Column() {
      Row() {
        Text('网络管理')
          .fontSize(20)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(`${this.interfaces.length} 个接口`)
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      Scroll() {
        Column() {
          if (this.isLoading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.theme.primary)
              Text('加载网络信息...')
                .fontSize(14)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 12 })
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.errorText) {
              Row() {
                Text('⚠')
                  .fontSize(16)
                  .margin({ right: 8 })
                Text(this.errorText)
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

            // LAN 网络状态卡片
            Column() {
              Text('🏠 LAN 网络状态')
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 12 })

              Row() {
                Text(this.lanStatus.ipAddress)
                  .fontSize(22)
                  .fontColor(this.theme.primary)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily('monospace')
                if (this.lanStatus.netmask) {
                  Text(`/${this.lanStatus.netmask}`)
                    .fontSize(14)
                    .fontColor(this.theme.textSecondary)
                    .fontFamily('monospace')
                    .margin({ left: 2 })
                }
                Blank()
                Column() {
                  Text(`⇩ ${FormatUtils.formatSpeed(this.lanStatus.rxRate)}`)
                    .fontSize(13)
                    .fontColor(this.theme.success)
                  Text(`⇧ ${FormatUtils.formatSpeed(this.lanStatus.txRate)}`)
                    .fontSize(13)
                    .fontColor(this.theme.secondary)
                    .margin({ top: 4 })
                }
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.lanStatus.proto) {
                              this.netLine('协议', this.lanStatus.proto.toUpperCase())
              }
              if (this.lanStatus.macAddr) {
                              this.netLine('MAC', this.lanStatus.macAddr)
              }
                            this.netLine('网关', this.lanStatus.gateway || '--')
                            this.netLine('DNS', this.lanStatus.dns.length > 0 ? this.lanStatus.dns.join(', ') : '--')
                            this.netLine('接口', this.lanStatus.interface || '--')
              if (this.lanStatus.uptime > 0) {
                              this.netLine('运行时长', FormatUtils.formatUptime(this.lanStatus.uptime))
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            // 接口列表
            ForEach(this.interfaces, (iface: NetworkInterface) => {
              Column() {
                Row() {
                  Text(this.getTypeEmoji(iface.type))
                    .fontSize(24)
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor(this.theme.bgGlassLight)
                    .textAlign(TextAlign.Center)

                  Column() {
                    Text(iface.name)
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text(this.getTypeLabel(iface.type))
                      .fontSize(10)
                      .fontColor(this.getTypeColor(iface.type))
                  }
                  .margin({ left: 10 })
                  .alignItems(HorizontalAlign.Start)

                  Blank()

                  Column() {
                    Circle()
                      .width(8)
                      .height(8)
                      .fill(iface.status === 'up' ? this.theme.success : this.theme.danger)
                    Text(iface.status === 'up' ? '已连接' : '断开')
                      .fontSize(10)
                      .fontColor(iface.status === 'up' ? this.theme.success : this.theme.textTertiary)
                  }
                }
                .width('100%')

                if (iface.ipAddress || iface.macAddress) {
                  Row() {
                    if (iface.ipAddress) {
                      Text(`IP: ${iface.ipAddress}`)
                        .fontSize(10)
                        .fontColor(this.theme.textSecondary)
                      Blank()
                    }
                    if (iface.macAddress) {
                      Text(`MAC: ${FormatUtils.formatMac(iface.macAddress)}`)
                        .fontSize(10)
                        .fontColor(this.theme.textTertiary)
                    }
                  }
                  .width('100%')
                  .margin({ top: 10 })
                  .padding({ top: 10 })
                  .border({ width: { top: 0.3 }, color: this.theme.borderGlass })
                }

                Text(`↓ ${FormatUtils.formatBytes(iface.rxBytes)} | ↑ ${FormatUtils.formatBytes(iface.txBytes)}`)
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 4 })
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: 8 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
            }, (item: NetworkInterface): string => item.name)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 100 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder netLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(50)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}

// ============================================================
// MainPage - Tab 容器
// ============================================================
@Entry
@Component
struct MainPage {
  @State currentTab: number = 0
  @State theme: ThemePalette = DARK_THEME
  @State isDark: boolean = true
  @State deviceName: string = ''

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()
    const device = AppState.getInstance().getActiveDevice()
    this.deviceName = device ? (device.label || device.host) : '未连接'

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })
  }

  build() {
    Stack() {
      // 背景渐变
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
        // 顶部栏
        Row() {
          Row() {
            Text(this.deviceName)
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(' ▾')
              .fontSize(10)
              .fontColor(this.theme.textTertiary)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try {
              router.back()
            } catch (e) {
              hilog.error(0x0001, 'MainPage', `router.back failed: ${e}`)
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

        // Tab 内容区
        Stack() {
          if (this.currentTab === 0) {
            DashboardTab({ theme: this.theme })
          }
          if (this.currentTab === 1) {
            DeviceTab({ theme: this.theme })
          }
          if (this.currentTab === 2) {
            NetworkTab({ theme: this.theme })
          }
        }
        .width('100%')
        .layoutWeight(1)

        // 底部导航栏 - 5 Tab
        Row() {
          // 首页
          Column() {
            Text('📊')
              .fontSize(18)
              .opacity(this.currentTab === 0 ? 1 : 0.4)
            Text('首页')
              .fontSize(11)
              .fontColor(this.currentTab === 0 ? this.theme.primary : this.theme.textTertiary)
              .margin({ top: 2 })
              .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            if (this.currentTab === 0) {
              Circle()
                .width(4)
                .height(4)
                .fill(this.theme.primary)
                .margin({ top: 4 })
            } else {
              Circle()
                .width(4)
                .height(4)
                .fill('transparent')
                .margin({ top: 4 })
            }
          }
          .flexGrow(1)
          .height(60)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = 0
          })

          // 设备
          Column() {
            Text('📡')
              .fontSize(18)
              .opacity(this.currentTab === 1 ? 1 : 0.4)
            Text('设备')
              .fontSize(11)
              .fontColor(this.currentTab === 1 ? this.theme.primary : this.theme.textTertiary)
              .margin({ top: 2 })
              .fontWeight(this.currentTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            if (this.currentTab === 1) {
              Circle()
                .width(4)
                .height(4)
                .fill(this.theme.primary)
                .margin({ top: 4 })
            } else {
              Circle()
                .width(4)
                .height(4)
                .fill('transparent')
                .margin({ top: 4 })
            }
          }
          .flexGrow(1)
          .height(60)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = 1
          })

          // 网络
          Column() {
            Text('🌐')
              .fontSize(18)
              .opacity(this.currentTab === 2 ? 1 : 0.4)
            Text('网络')
              .fontSize(11)
              .fontColor(this.currentTab === 2 ? this.theme.primary : this.theme.textTertiary)
              .margin({ top: 2 })
              .fontWeight(this.currentTab === 2 ? FontWeight.Medium : FontWeight.Normal)
            if (this.currentTab === 2) {
              Circle()
                .width(4)
                .height(4)
                .fill(this.theme.primary)
                .margin({ top: 4 })
            } else {
              Circle()
                .width(4)
                .height(4)
                .fill('transparent')
                .margin({ top: 4 })
            }
          }
          .flexGrow(1)
          .height(60)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = 2
          })

          // 应用
          Column() {
            Text('🛠')
              .fontSize(18)
              .opacity(0.4)
            Text('应用')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .margin({ top: 2 })
            Circle()
              .width(4)
              .height(4)
              .fill('transparent')
              .margin({ top: 4 })
          }
          .flexGrow(1)
          .height(60)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            try {
              router.pushUrl({ url: 'pages/apps/AppsPage' })
            } catch (e) {
              hilog.error(0x0001, 'MainPage', `pushUrl failed: ${e}`)
            }
          })
        }
        .width('100%')
        .height(64)
        .padding({ bottom: 8, left: 8, right: 8 })
        .backgroundColor(this.isDark ? 'rgba(10, 14, 39, 0.85)' : 'rgba(255, 255, 255, 0.85)')
        .backdropBlur(30)
        .border({ width: { top: 0.5 }, color: this.theme.borderGlass })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
