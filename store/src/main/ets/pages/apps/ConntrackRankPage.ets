import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ConnectedDevice } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'

/** 每个 IP 的连接统计 */
class IpRank {
  ip: string = ''
  hostname: string = ''
  mac: string = ''
  vendor: string = ''
  connCount: number = 0
  totalBytes: number = 0
  constructor() {}
}

@Entry
@Component
struct ConntrackRankPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State items: IpRank[] = []
  @State totalConns: number = 0
  @State maxConns: number = 1
  @State errorText: string = ''
  private timerId: number = -1
  private rankBadges: string[] = ['🥇', '🥈', '🥉']

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
    this.timerId = setInterval(() => this.loadData(), 5000)
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1 }
  }

  async loadData(): Promise<void> {
    try {
      if (!AppState.getInstance().isConnected()) return
      const api: ApiService = new ApiService()
      // 并行获取：conntrack 列表 + DHCP 设备列表
      const results: Object[] = await Promise.all([
        api.fetchConntrackList(),
        api.fetchConnectedDevices()
      ])
      const connList: Object[] = results[0] as Object[]
      const devices: ConnectedDevice[] = results[1] as ConnectedDevice[]

      // 按 src IP 聚合
      const ipMap: Map<string, IpRank> = new Map()
      let total: number = 0
      for (const entry of connList) {
        total++
        const rec: Record<string, Object> = entry as Record<string, Object>
        const src: string = (rec['src'] as string) || ''
        if (!src || src === '127.0.0.1') continue
        if (!ipMap.has(src)) {
          const r: IpRank = new IpRank()
          r.ip = src
          ipMap.set(src, r)
        }
        ipMap.get(src)!.connCount++
        ipMap.get(src)!.totalBytes += (rec['bytes'] as number) || 0
      }

      // 用 DHCP 数据填充设备名
      const dhcpMap: Map<string, ConnectedDevice> = new Map()
      for (const d of devices) {
        if (d.ip) dhcpMap.set(d.ip, d)
      }
      const ranked: IpRank[] = []
      for (const r of ipMap.values()) {
        const dhcp: ConnectedDevice | undefined = dhcpMap.get(r.ip)
        if (dhcp) {
          r.hostname = dhcp.hostname || ''
          r.mac = dhcp.mac || ''
          r.vendor = dhcp.vendor || ''
        }
        ranked.push(r)
      }
      ranked.sort((a, b) => b.connCount - a.connCount)
      this.items = ranked
      this.totalConns = total
      let max = 1
      for (const r of ranked) { if (r.connCount > max) max = r.connCount }
      this.maxConns = max
      this.errorText = ''
    } catch (e) {
      this.errorText = '加载失败'
    }
    this.isLoading = false
  }

  barPct(count: number): string {
    if (count <= 0 || this.maxConns <= 0) return '0%'
    return `${Math.min(100, (count / this.maxConns) * 100)}%`
  }

  barColor(count: number): string {
    if (count >= 100) return '#FF5252'
    if (count >= 30) return '#FF9800'
    if (count >= 10) return '#448AFF'
    return '#00E676'
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
        Row() {
          Row() {
            Text(' 连接排行').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => this.getUIContext().getRouter().back())

          Blank()
          Text(`共 ${this.totalConns} 条连接`).fontSize(11).fontColor(this.theme.textTertiary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorText && this.items.length === 0) {
          Column() {
            Text('⚠ ' + this.errorText).fontSize(14).fontColor(this.theme.warning).margin({ bottom: 12 })
            Text('点击重试').fontSize(14).fontColor(this.theme.primary)
              .onClick(() => { this.isLoading = true; this.loadData() })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Text('🔗 按 NAT 连接数降序，发现连接大户')
                .fontSize(11).fontColor(this.theme.textTertiary)
                .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

              ForEach(this.items, (item: IpRank, idx: number) => {
                Column() {
                  Row() {
                    Text(idx < 3 ? this.rankBadges[idx] : `#${idx + 1}`)
                      .fontSize(18).fontColor(this.theme.textPrimary).margin({ right: 10 })

                    Column() {
                      Text(item.hostname || '未知设备')
                        .fontSize(13).fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium).maxLines(1)
                      if (item.mac) {
                        Text(item.mac).fontSize(10).fontColor(this.theme.textTertiary)
                          .fontFamily('monospace').maxLines(1)
                      }
                    }.alignItems(HorizontalAlign.Start)

                    Blank()

                    Column() {
                      Text(`${item.connCount}`)
                        .fontSize(20).fontColor(this.barColor(item.connCount))
                        .fontWeight(FontWeight.Bold)
                      Text('连接').fontSize(9).fontColor(this.theme.textTertiary)
                    }.alignItems(HorizontalAlign.Center)
                  }.width('100%').margin({ bottom: 6 })

                  Row() {
                    Text(item.ip).fontSize(11).fontColor(this.theme.textSecondary)
                      .fontFamily('monospace').margin({ right: 12 })
                    if (item.vendor) {
                      Text(item.vendor).fontSize(10).fontColor(this.theme.textTertiary)
                    }
                    Blank()
                    Text(`${(item.totalBytes / 1024).toFixed(0)} KB`)
                      .fontSize(10).fontColor(this.theme.textTertiary)
                  }.width('100%').margin({ bottom: 6 })

                  Stack() {
                    Row().width('100%').height(4).borderRadius(2)
                      .backgroundColor('rgba(255,255,255,0.05)')
                    Row()
                      .width(this.barPct(item.connCount)).height(4).borderRadius(2)
                      .linearGradient({
                        angle: 90,
                        colors: [[this.barColor(item.connCount), 0], [this.barColor(item.connCount) + '44', 1]]
                      })
                  }.alignContent(Alignment.Start)
                  .width('100%').height(4)
                }
                .width('100%').padding(12).borderRadius(12)
                .margin({
                  top: 8, left: 16, right: 16,
                  bottom: idx < this.items.length - 1 ? 0 : 0
                })
                .backgroundColor('transparent')
                .border({ width: 0.5, color: this.theme.borderGlass })
              })

              if (this.items.length === 0) {
                Text('这里还很安静，等数据来报到 📭').fontSize(13).fontColor(this.theme.textTertiary)
                  .width('100%').textAlign(TextAlign.Center).padding(32)
              }
              Row().width('100%').height(100)
            }.width('100%')
          }
          .width('100%').padding({ bottom: 90 }).layoutWeight(1).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
