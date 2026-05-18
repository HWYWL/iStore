import { StyleConstants } from '../common/constants/StyleConstants'
import { ParticleBackground } from '../common/components/ParticleBackground'
import { GlassCard } from '../common/components/GlassCard'
import { ApiService } from '../api/ApiService'
import { ConnectedDevice } from '../models/Models'
import { FormatUtils } from '../common/utils/FormatUtils'

@Entry
@Component
struct DevicePage {
  @State devices: ConnectedDevice[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State searchText: string = ''
  private apiService: ApiService = new ApiService()

  aboutToAppear(): void {
    this.loadDevices()
  }

  async loadDevices(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      this.devices = await this.apiService.fetchConnectedDevices()
    } catch (devErr) {
      this.errorText = '加载设备列表失败'
    }
    this.isLoading = false
  }

  getFilteredDevices(): ConnectedDevice[] {
    if (!this.searchText.trim()) {
      return this.devices
    }
    const kw: string = this.searchText.trim().toLowerCase()
    const filtered: ConnectedDevice[] = []
    for (const d of this.devices) {
      if (d.hostname.toLowerCase().includes(kw) ||
        d.ip.includes(kw) ||
        d.mac.toLowerCase().includes(kw)) {
        filtered.push(d)
      }
    }
    return filtered
  }

  getDeviceIconClass(device: ConnectedDevice): string {
    const icon: string = FormatUtils.getDeviceIcon(device.mac, device.hostname)
    const icons: Record<string, string> = {
      'phone': '📱', 'laptop': '💻', 'tv': '📺', 'server': '🖥️',
      'camera': '📷', 'printer': '🖨️', 'speaker': '🔊', 'watch': '⌚', 'device': '📡'
    }
    return icons[icon] || icons['device']
  }

  getVendorName(device: ConnectedDevice): string {
    if (device.vendor) return device.vendor
    return FormatUtils.getVendorName(device.mac)
  }

  build() {
    Stack() {
      ParticleBackground()

      Column() {
        Row() {
          Text('设备管理').fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
          Blank()
          Text(`${this.getFilteredDevices().length} 台设备`).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 4 })

        Row() {
          TextInput({ placeholder: '搜索设备名称或 IP...', text: this.searchText })
            .placeholderColor(StyleConstants.TEXT_TERTIARY)
            .fontColor(StyleConstants.TEXT_PRIMARY)
            .backgroundColor('transparent')
            .onChange((v: string) => { this.searchText = v })
            .layoutWeight(1)
            .height(40)
          Text('🔍').fontSize(14).fontColor(StyleConstants.TEXT_SECONDARY).padding({ left: 10, right: 4 })
        }
        .width('100%').height(40).borderRadius(StyleConstants.RADIUS_FULL)
        .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
        .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 8, bottom: 4 })

        Scroll() {
          Column() {
            if (this.isLoading) {
              Column() {
                LoadingProgress().width(40).height(40).color(StyleConstants.PRIMARY)
                Text('加载设备列表...').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).margin({ top: 12 })
              }
              .width('100%').height(200).justifyContent(FlexAlign.Center)
            } else if (this.errorText) {
              GlassCard({ cardWidth: '100%', marginTop: 12 }) {
                Row() {
                  Text('⚠').fontSize(20).margin({ right: 8 })
                  Text(this.errorText).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.WARNING)
                }
                .width('100%')
              }
            } else if (this.devices.length === 0) {
              GlassCard({ cardWidth: '100%', marginTop: 12 }) {
                Column() {
                  Text('📡').fontSize(48).margin({ bottom: 12 })
                  Text('暂无连接设备').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  Text('没有检测到 DHCP 客户端设备').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_TERTIARY).margin({ top: 4 })
                }
                .width('100%').padding({ top: 40, bottom: 40 }).alignItems(HorizontalAlign.Center)
              }
            } else {
              ForEach(this.getFilteredDevices(), (device: ConnectedDevice, index: number) => {
                GlassCard({ cardWidth: '100%', marginTop: 6 }) {
                  Row() {
                    Text(this.getDeviceIconClass(device)).fontSize(28).width(44).height(44).borderRadius(12).backgroundColor(StyleConstants.BG_CARD).textAlign(TextAlign.Center)

                    Column() {
                      Text(device.hostname).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        Text(FormatUtils.formatMac(device.mac)).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                        if (this.getVendorName(device) && this.getVendorName(device) !== 'Unknown') {
                          Text(` · ${this.getVendorName(device)}`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                        }
                      }
                    }
                    .margin({ left: 12 }).layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Column() {
                      Text(device.ip).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                      if (device.onlineTime) {
                        Text(device.onlineTime).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                      }
                      if (device.signalStrength > -1) {
                        Text(`${device.signalStrength} dBm`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                      }
                    }
                    .alignItems(HorizontalAlign.End)

                    Circle()
                      .width(8).height(8)
                      .fill(device.isOnline ? StyleConstants.SUCCESS : StyleConstants.TEXT_TERTIARY)
                      .shadow(device.isOnline ? { radius: 4, color: 'rgba(0,230,118,0.5)', offsetX: 0, offsetY: 0 } :
                        { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
                      .margin({ left: 8 })
                  }
                  .width('100%')
                }
              }, (item: ConnectedDevice, index: number): string => index.toString())
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
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 180, colors: [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]] })
  }
}
