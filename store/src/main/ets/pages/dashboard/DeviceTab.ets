import { AppState } from '../../common/store/AppState'
import {ThemePalette} from '../../common/theme/ThemeColors'
import { ConnectedDevice, WirelessClient } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { DeviceNoteStore } from '../../common/store/DeviceNoteStore'
import { hilog } from '@kit.PerformanceAnalysisKit'

// ============================================================
// DeviceTab - 设备列表（DHCP客户端）
// ============================================================
@Component
export struct DeviceTab {
  @Prop theme: ThemePalette
  @State devices: ConnectedDevice[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State searchText: string = ''
  @State subTab: number = 0
  @State wirelessClients: WirelessClient[] = []
  @State wirelessLoading: boolean = false
  // 设备备注名映射（mac → 备注）
  @State noteMap: Map<string, string> = new Map()
  private noteStore: DeviceNoteStore = DeviceNoteStore.getInstance()
  private lastScrollY: number = 0
  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext()
    if (ctx) {
      this.noteStore.init(ctx as Context)
    }
    this.loadDevices()
    this.loadWirelessData()
    this.loadNotes()
  }

  /** 加载当前设备的备注名映射 */
  async loadNotes(): Promise<void> {
    const device = AppState.getInstance().getActiveDevice()
    if (!device) return
    try {
      const map: Map<string, string> = new Map()
      // 从存储读取所有 mac 备注（通过遍历当前设备列表的 mac）
      for (let i = 0; i < this.devices.length; i++) {
        const note: string = await this.noteStore.getNote(device.id, this.devices[i].mac)
        if (note) {
          map.set(this.devices[i].mac.toUpperCase(), note)
        }
      }
      this.noteMap = map
    } catch (e) {
      hilog.error(0x0001, 'DeviceTab', `loadNotes err: ${JSON.stringify(e)}`)
    }
  }

  /** 设备显示名（优先备注） */
  deviceDisplayName(device: ConnectedDevice): string {
    return this.noteMap.get(device.mac.toUpperCase()) || device.hostname || device.ip || '未知设备'
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
        return ''  // 无法识别 → 使用默认 SVG 图标
    }
  }

  /** 设备双列分组（每行 2 个） */
  deviceRows(): ConnectedDevice[][] {
    const all: ConnectedDevice[] = this.getFilteredDevices()
    const rows: ConnectedDevice[][] = []
    for (let i = 0; i < all.length; i += 2) {
      rows.push(all.slice(i, i + 2))
    }
    return rows
  }

  /** 双列设备卡片（图标 + 名称 + IP + 状态，竖排布局） */
  @Builder
  deviceCard(device: ConnectedDevice) {
    Column() {
      Row() {
        // 设备图标
        Row() {
          if (this.getDeviceEmoji(device.mac, device.hostname)) {
            Text(this.getDeviceEmoji(device.mac, device.hostname))
              .fontSize(22)
          } else {
            Image($r('app.media.device'))
              .width(20).height(20).objectFit(ImageFit.Contain)
          }
        }
        .width(40)
        .height(40)
        .borderRadius(14)
        .backgroundColor(this.theme.bgGlassLight)
        .justifyContent(FlexAlign.Center)

        Blank()

        // 在线状态
        Circle()
          .width(8)
          .height(8)
          .foregroundColor(device.isOnline ? this.theme.success : this.theme.textTertiary)
      }
      .width('100%')

      // 设备名称
      Text(this.deviceDisplayName(device))
        .fontSize(14)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // IP 地址
      Text(device.ip)
        .fontSize(11)
        .fontColor(this.theme.textSecondary)
        .fontFamily('monospace')
        .width('100%')
        .margin({ top: 3 })
        .maxLines(1)

      // MAC + 厂商
      Row() {
        Text(FormatUtils.formatMac(device.mac))
          .fontSize(9)
          .fontColor(this.theme.textTertiary)
        if (FormatUtils.getVendorName(device.mac) !== 'Unknown') {
          Text(` · ${FormatUtils.getVendorName(device.mac)}`)
            .fontSize(9)
            .fontColor(this.theme.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .margin({ top: 3 })
    }
    .width('48%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      try {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/devices/ClientDetailPage',
          params: { mac: device.mac, hostname: device.hostname }
        })
      } catch (e) {
        hilog.error(0x0001, 'DeviceTab', `pushUrl failed: ${e}`)
      }
    })
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
          .height(44)
        Text('🔍')
          .fontSize(16)
          .fontColor(this.theme.textSecondary)
          .padding({ left: 10, right: 4 })
      }
      .width('100%')
      .height(44)
      .borderRadius(20)
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
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(14)
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
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(14)
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
            // 设备双列网格（每行 2 个，仿应用商店列表）
            ForEach(this.deviceRows(), (row: ConnectedDevice[], rowIdx: number) => {
              Row() {
                ForEach(row, (device: ConnectedDevice) => {
                  this.deviceCard(device)
                }, (device: ConnectedDevice): string => device.mac + device.ip)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ top: 10 })
            }, (row: ConnectedDevice[], rowIdx: number): string => `row_${rowIdx}`)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 130 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .onScroll((_x: number, y: number) => {
        const diff = y - this.lastScrollY
        this.lastScrollY = y
        if (diff > 10 && y > 120) {
          AppState.getInstance().hideNav()
        } else if (diff < -10 && y < 80) {
          AppState.getInstance().showNav()
        }
      })
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
                  .borderRadius(20)
                  .backgroundColor(this.theme.bgGlassLight)
                  .textAlign(TextAlign.Center)

                Column() {
                  Text(client.hostname || client.mac)
                    .fontSize(15)
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
              .padding(16)
              .borderRadius(20)
              .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .onClick(() => {
              try {
                this.getUIContext().getRouter().pushUrl({
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
        .padding({ left: 12, right: 12, top: 4, bottom: 130 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .onScroll((_x: number, y: number) => {
        const diff = y - this.lastScrollY
        this.lastScrollY = y
        if (diff > 10 && y > 120) {
          AppState.getInstance().hideNav()
        } else if (diff < -10 && y < 80) {
          AppState.getInstance().showNav()
        }
      })
      }
    }
    .width('100%')
    .height('100%')
  }
}
