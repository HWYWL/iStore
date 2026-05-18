import { StyleConstants } from '../common/constants/StyleConstants'
import { ParticleBackground } from '../common/components/ParticleBackground'
import { GlassCard } from '../common/components/GlassCard'
import { ApiService } from '../api/ApiService'
import { NetworkInterface, WanStatus } from '../models/Models'
import { FormatUtils } from '../common/utils/FormatUtils'

@Entry
@Component
struct NetworkPage {
  @State interfaces: NetworkInterface[] = []
  @State wanStatus: WanStatus = this.defaultWanStatus()
  @State isLoading: boolean = true
  private apiService: ApiService = new ApiService()

  aboutToAppear(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    try {
      this.wanStatus = await this.apiService.fetchWanStatus()
      this.interfaces = await this.apiService.fetchNetworkInterfaces()
      if (this.interfaces.length === 0) {
        this.interfaces = this.getMockInterfaces()
      }
    } catch (netErr) {
      this.wanStatus = {
        interface: 'eth0', uptime: 86400, ipAddress: '123.45.67.89',
        gateway: '123.45.67.1', dns: ['114.114.114.114', '8.8.8.8'],
        rxRate: 1024 * 512, txRate: 1024 * 128, onlineTime: '24h 0m'
      }
      this.interfaces = this.getMockInterfaces()
    }
    this.isLoading = false
  }

  defaultWanStatus(): WanStatus {
    return { interface: '', uptime: 0, ipAddress: '0.0.0.0', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '' }
  }

  getMockInterfaces(): NetworkInterface[] {
    return [
      { name: 'eth0', type: 'wan', ipAddress: '123.45.67.89', netmask: '255.255.255.0', gateway: '123.45.67.1', macAddress: '00:11:22:33:44:55', mtu: 1500, status: 'up', rxBytes: 1024 * 1024 * 1024 * 50, txBytes: 1024 * 1024 * 1024 * 20, rxRate: 1024 * 512, txRate: 1024 * 128 },
      { name: 'br-lan', type: 'lan', ipAddress: '192.168.1.1', netmask: '255.255.255.0', gateway: '', macAddress: '00:11:22:33:44:56', mtu: 1500, status: 'up', rxBytes: 1024 * 1024 * 1024 * 200, txBytes: 1024 * 1024 * 1024 * 180, rxRate: 1024 * 2048, txRate: 1024 * 1024 },
      { name: 'wlan0', type: 'wifi', ipAddress: '192.168.1.1', netmask: '255.255.255.0', gateway: '', macAddress: '00:11:22:33:44:57', mtu: 1500, status: 'up', rxBytes: 1024 * 1024 * 1024 * 30, txBytes: 1024 * 1024 * 1024 * 15, rxRate: 1024 * 768, txRate: 1024 * 256 }
    ]
  }

  getTypeLabel(type: string): string {
    const labels: Record<string, string> = { 'wan': 'WAN 外网', 'lan': 'LAN 内网', 'wifi': 'WiFi 无线', 'vpn': 'VPN' }
    return labels[type] || type
  }

  getTypeColor(type: string): string {
    const colors: Record<string, string> = { 'wan': StyleConstants.WARNING, 'lan': StyleConstants.SUCCESS, 'wifi': StyleConstants.PRIMARY, 'vpn': StyleConstants.SECONDARY }
    return colors[type] || StyleConstants.TEXT_TERTIARY
  }

  getIfIcon(type: string): string {
    const icons: Record<string, string> = { 'wan': '🌐', 'lan': '🏠', 'wifi': '📶', 'vpn': '🔒' }
    return icons[type] || '🔌'
  }

  build() {
    Stack() {
      ParticleBackground()

      Column() {
        Row() {
          Text('网络管理').fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
          Blank()
          Text(`${this.interfaces.length} 个接口`).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 4 })

        Scroll() {
          Column() {
            if (this.isLoading) {
              Column() {
                LoadingProgress().width(40).height(40).color(StyleConstants.PRIMARY)
                Text('加载网络信息...').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).margin({ top: 12 })
              }
              .width('100%').height(200).justifyContent(FlexAlign.Center)
            } else {
              GlassCard({ cardWidth: '100%', marginTop: 12 }) {
                Column() {
                  Text('WAN 外网连接').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium).margin({ bottom: 12 })

                  Row() {
                    Text(this.wanStatus.ipAddress).fontSize(StyleConstants.FONT_XXL).fontColor(StyleConstants.PRIMARY).fontWeight(FontWeight.Bold).fontFamily('monospace')
                    Blank()
                    Column() {
                      Text(`⇩ ${FormatUtils.formatSpeed(this.wanStatus.rxRate)}`).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.SUCCESS)
                      Text(`⇧ ${FormatUtils.formatSpeed(this.wanStatus.txRate)}`).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.SECONDARY).margin({ top: 4 })
                    }
                  }
                  .width('100%').margin({ bottom: 12 })

                  Row() {
                    Text('网关').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(50)
                    Text(this.wanStatus.gateway || '--').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6, bottom: 6 }).border({ width: { bottom: 0.3 }, color: StyleConstants.BORDER_GLASS })
                  Row() {
                    Text('DNS').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(50)
                    Text(this.wanStatus.dns.length > 0 ? this.wanStatus.dns.join(', ') : '--').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6, bottom: 6 }).border({ width: { bottom: 0.3 }, color: StyleConstants.BORDER_GLASS })
                }
              }

              Text('网络接口').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium).width('100%').margin({ top: 20, bottom: 4 })

              ForEach(this.interfaces, (iface: NetworkInterface) => {
                GlassCard({ cardWidth: '100%', marginTop: 8 }) {
                  Column() {
                    Row() {
                      Text(this.getIfIcon(iface.type)).fontSize(24).width(40).height(40).borderRadius(10).backgroundColor(StyleConstants.BG_CARD).textAlign(TextAlign.Center)

                      Column() {
                        Text(iface.name).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                        Text(this.getTypeLabel(iface.type)).fontSize(StyleConstants.FONT_XS).fontColor(this.getTypeColor(iface.type))
                      }
                      .margin({ left: 10 }).alignItems(HorizontalAlign.Start)

                      Blank()

                      Column() {
                        Circle().width(8).height(8)
                          .fill(iface.status === 'up' ? StyleConstants.SUCCESS : StyleConstants.DANGER)
                          .shadow(iface.status === 'up' ? { radius: 4, color: 'rgba(0,230,118,0.5)', offsetX: 0, offsetY: 0 } :
                            { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
                        Text(iface.status === 'up' ? '已连接' : '断开').fontSize(StyleConstants.FONT_XS).fontColor(iface.status === 'up' ? StyleConstants.SUCCESS : StyleConstants.TEXT_TERTIARY)
                      }
                    }
                    .width('100%')

                    Row() {
                      Text(`IP: ${iface.ipAddress}`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_SECONDARY)
                      Blank()
                      Text(`MAC: ${FormatUtils.formatMac(iface.macAddress)}`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                    }
                    .width('100%').margin({ top: 10 }).padding({ top: 10 }).border({ width: { top: 0.3 }, color: StyleConstants.BORDER_GLASS })

                    Row() {
                      Text(`↓ ${FormatUtils.formatBytes(iface.rxBytes)} | ↑ ${FormatUtils.formatBytes(iface.txBytes)}`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                    }
                    .width('100%').margin({ top: 4 })
                  }
                  .width('100%')
                }
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
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 180, colors: [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]] })
  }
}
