import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 客户端设备详情页面
 * 展示单个设备的应用使用统计（访问时长、访问记录）
 * 支持三个子 Tab：基本信息/访问统计/访问记录
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { DeviceVisitTime, DeviceVisitRecord, ConnectedDevice, WirelessClient } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

interface HasMac {
  mac: string
}

@Entry
@Component
struct ClientDetailPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
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

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params) {
      this.mac = (params['mac'] as string) || ''
      this.hostname = (params['hostname'] as string) || ''
    }

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

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
    if (!this.hostname) return '💻'
    const name = this.hostname.toLowerCase()
    if (name.includes('phone') || name.includes('iphone')) return '📱'
    if (name.includes('laptop') || name.includes('macbook') || name.includes('notebook')) return '💻'
    if (name.includes('tv') || name.includes('smart tv')) return '📺'
    if (name.includes('pi') || name.includes('raspberry')) return '🖥️'
    if (name.includes('tablet') || name.includes('ipad')) return '📋'
    return '🖥️'
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
              this.getUIContext().getRouter().back()
            } catch (e) {
              hilog.error(0x0001, 'ClientDetailPage', `router.back failed: ${e}`)
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

        Row() {
          Text(this.getDeviceIcon())
            .fontSize(36)
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
          Text('⚠')
            .fontSize(16)
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
      Text('📋 DHCP 租约信息')
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
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
  WifiInfoSection() {
    Column() {
      Text('📡 无线连接信息')
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
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
          Text('⚠')
            .fontSize(16)
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
          Text('📊 应用统计')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
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
          Text('⚠')
            .fontSize(16)
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
          Text('📝 应用记录')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
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
