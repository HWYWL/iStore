import { StyleConstants } from '../common/constants/StyleConstants'
import { ParticleBackground } from '../common/components/ParticleBackground'
import { GlassCard } from '../common/components/GlassCard'
import { TrafficLineChart } from '../common/components/TrafficLineChart'
import { ApiService } from '../api/ApiService'
import { SystemInfo, WanStatus, TrafficHistory } from '../models/Models'
import { FormatUtils } from '../common/utils/FormatUtils'
import { router } from '@kit.ArkUI'

@Entry
@Component
struct DashboardPage {
  @State systemInfo: SystemInfo = this.defaultSystemInfo()
  @State wanStatus: WanStatus = this.defaultWanStatus()
  @State trafficHistory: TrafficHistory[] = []
  @State isLoading: boolean = true
  @State lastUpdate: string = '--:--:--'
  private apiService: ApiService = new ApiService()
  private timerId: number = -1

  aboutToAppear(): void {
    this.loadData()
    this.timerId = setInterval(() => { this.refreshData() }, 5000)
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    try {
      this.systemInfo = await this.apiService.fetchSystemInfo()
      this.wanStatus = await this.apiService.fetchWanStatus()
      this.trafficHistory = await this.apiService.generateMockTrafficHistory()
    } catch (dashErr) {
      this.systemInfo = this.defaultSystemInfo()
      this.wanStatus = this.defaultWanStatus()
      this.trafficHistory = await this.apiService.generateMockTrafficHistory()
    }
    this.isLoading = false
    this.updateTimestamp()
  }

  async refreshData(): Promise<void> {
    try {
      this.systemInfo = await this.apiService.fetchSystemInfo()
      this.wanStatus = await this.apiService.fetchWanStatus()
      this.trafficHistory = await this.apiService.generateMockTrafficHistory()
    } catch (refErr) {
      this.trafficHistory = await this.apiService.generateMockTrafficHistory()
    }
    this.updateTimestamp()
  }

  updateTimestamp(): void {
    const now: Date = new Date()
    this.lastUpdate = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`
  }

  defaultSystemInfo(): SystemInfo {
    return {
      hostname: 'iStoreOS', model: '', kernel: '', firmwareVersion: '',
      localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
      memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0
    }
  }

  defaultWanStatus(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: ''
    }
  }

  build() {
    Stack() {
      ParticleBackground()

      Column() {
        Row() {
          Column() {
            Text(this.systemInfo.hostname)
              .fontSize(StyleConstants.FONT_XL)
              .fontColor(StyleConstants.TEXT_PRIMARY)
              .fontWeight(FontWeight.Bold)
            Text(`固件: ${this.systemInfo.firmwareVersion || '--'}`)
              .fontSize(StyleConstants.FONT_XS)
              .fontColor(StyleConstants.TEXT_TERTIARY)
              .margin({ top: 2 })
          }

          Blank()

          Row() {
            Text(`◷ ${this.lastUpdate}`)
              .fontSize(StyleConstants.FONT_XS)
              .fontColor(StyleConstants.TEXT_TERTIARY)
              .margin({ right: 6 })
            Circle()
              .width(6)
              .height(6)
              .fill(StyleConstants.SUCCESS)
              .shadow({
                radius: 4,
                color: 'rgba(0, 230, 118, 0.5)',
                offsetX: 0,
                offsetY: 0
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Scroll() {
          Column() {
            GlassCard({ cardWidth: '100%', marginTop: 12 }) {
              Column() {
                Row() {
                  Text('WAN 连接信息').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  Blank()
                  Row() {
                    Text(`◷ ${this.lastUpdate}`).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).margin({ right: 6 })
                    Circle().width(6).height(6).fill(StyleConstants.SUCCESS)
                      .shadow({ radius: 4, color: 'rgba(0,230,118,0.5)', offsetX: 0, offsetY: 0 })
                  }
                }
                .width('100%')
                .margin({ bottom: 12 })

                Row() {
                  Text(this.wanStatus.ipAddress)
                    .fontSize(StyleConstants.FONT_XXL).fontColor(StyleConstants.PRIMARY)
                    .fontWeight(FontWeight.Bold).fontFamily('monospace')
                  Blank()
                  Column() {
                    Text(`⇩ ${FormatUtils.formatSpeed(this.wanStatus.rxRate)}`).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.SUCCESS)
                    Text(`⇧ ${FormatUtils.formatSpeed(this.wanStatus.txRate)}`).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.SECONDARY).margin({ top: 4 })
                  }
                }
                .width('100%')
                .margin({ bottom: 12 })

                this.DetailRow('主机名', this.systemInfo.hostname)
                this.DetailRow('固件', this.systemInfo.firmwareVersion || '--')
                this.DetailRow('网关', this.wanStatus.gateway || '--')
                this.DetailRow('DNS', this.wanStatus.dns.length > 0 ? this.wanStatus.dns.join(', ') : '--')
                this.DetailRow('运行时长', FormatUtils.formatUptime(this.systemInfo.uptime))
              }
              .width('100%')
            }

            Row() {
              GlassCard({ cardWidth: '48%', cardPadding: 12, marginTop: 12 }) {
                Column() {
                  Text('⇩ 下载').fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).margin({ bottom: 4 })
                  Text(FormatUtils.formatSpeed(this.wanStatus.rxRate)).fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.PRIMARY).fontWeight(FontWeight.Bold)
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
              GlassCard({ cardWidth: '48%', cardPadding: 12, marginTop: 12 }) {
                Column() {
                  Text('⇧ 上传').fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).margin({ bottom: 4 })
                  Text(FormatUtils.formatSpeed(this.wanStatus.txRate)).fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.SECONDARY).fontWeight(FontWeight.Bold)
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Row() {
              GlassCard({ cardWidth: '48%', cardPadding: 12 }) {
                Column() {
                  Text('⚙ 运行').fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).margin({ bottom: 4 })
                  Text(FormatUtils.formatUptime(this.systemInfo.uptime)).fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.INFO).fontWeight(FontWeight.Bold)
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
              GlassCard({ cardWidth: '48%', cardPadding: 12 }) {
                Column() {
                  Text('🌐 模式').fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).margin({ bottom: 4 })
                  Text(this.wanStatus.interface || 'DHCP').fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.ACCENT).fontWeight(FontWeight.Medium)
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            GlassCard({ cardWidth: '100%', marginTop: 16 }) {
              Column() {
                Row() {
                  Text('网络统计').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  Blank()
                  Row() {
                    Circle().width(6).height(6).fill(StyleConstants.PRIMARY).margin({ right: 3 })
                    Text('下载').fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY).margin({ right: 10 })
                    Circle().width(6).height(6).fill(StyleConstants.SECONDARY).margin({ right: 3 })
                    Text('上传').fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY)
                  }
                }
                .width('100%').margin({ bottom: 8 })
                TrafficLineChart({ data: this.trafficHistory, showLegend: false })
              }.width('100%')
            }

            GlassCard({ cardWidth: '100%', marginTop: 16, marginBottom: 100 }) {
              Column() {
                Text('网络信息').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium).margin({ bottom: 12 })
                this.DetailRow('IP 地址', this.wanStatus.ipAddress)
                this.DetailRow('子网掩码', `/24`)
                this.DetailRow('网关', this.wanStatus.gateway)
                this.DetailRow('DNS', this.wanStatus.dns.join(', ') || '--')
                this.DetailRow('协议', this.systemInfo.firmwareVersion || 'dhcp')
                this.DetailRow('状态', this.wanStatus.onlineTime ? `在线 · ${this.wanStatus.onlineTime}` : '在线')
              }.width('100%')
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
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
    .linearGradient({
      angle: 180,
      colors: [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]]
    })
  }

  @Builder DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(StyleConstants.FONT_SM)
        .fontColor(StyleConstants.TEXT_SECONDARY)
        .width(70)
      Text(value)
        .fontSize(StyleConstants.FONT_SM)
        .fontColor(StyleConstants.TEXT_PRIMARY)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 0.3 }, color: StyleConstants.BORDER_GLASS })
  }
}
