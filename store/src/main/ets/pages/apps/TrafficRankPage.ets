import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ConnectedDevice } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'

@Entry
@Component
struct TrafficRankPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State devices: ConnectedDevice[] = []
  @State maxRate: number = 1
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
      const api = new ApiService()
      const all = await api.fetchConnectedDevices()
      // 按总速率降序排列
      const sorted = [...all].sort((a, b) => {
        const ta = (a.rxRate || 0) + (a.txRate || 0)
        const tb = (b.rxRate || 0) + (b.txRate || 0)
        return tb - ta
      })
      this.devices = sorted
      let max = 1
      for (const d of sorted) {
        const t = (d.rxRate || 0) + (d.txRate || 0)
        if (t > max) max = t
      }
      this.maxRate = max
      this.errorText = ''
    } catch (e) {
      this.errorText = '加载失败'
    }
    this.isLoading = false
  }

  /** 是否 WiFi 设备（通过接口名判断） */
  isWireless(dev: ConnectedDevice): boolean {
    const ifLower: string = (dev.interface || '').toLowerCase()
    return ifLower.startsWith('wlan') || ifLower.startsWith('phy') ||
      ifLower.startsWith('radio') || ifLower.startsWith('wl')
  }

  /** 是否有 WiFi 信号数据 */
  hasWirelessStats(dev: ConnectedDevice): boolean {
    return this.isWireless(dev) && (dev.signalStrength !== 0 || dev.rxRate !== 0 || dev.txRate !== 0)
  }

  /** WiFi 信号评级 */
  sigLabel(s: number): string {
    if (s >= -45) return '极好'
    if (s >= -60) return '良好'
    if (s >= -75) return '一般'
    return '弱'
  }
  sigColor(s: number): string {
    if (s >= -45) return '#00E676'
    if (s >= -60) return '#76FF03'
    if (s >= -75) return '#FFC107'
    return '#FF5252'
  }

  /** 速率进度条宽度 */
  ratePct(r: number): string {
    if (r <= 0 || this.maxRate <= 0) return '0%'
    return `${Math.min(100, (r / this.maxRate) * 100)}%`
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
            Text(' 流量排行').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => this.getUIContext().getRouter().back())

          Blank()
          Text(`共 ${this.devices.length} 个设备`).fontSize(11).fontColor(this.theme.textTertiary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorText && this.devices.length === 0) {
          Column() {
            Text('⚠ ' + this.errorText).fontSize(14).fontColor(this.theme.warning).margin({ bottom: 12 })
            Text('点击重试').fontSize(14).fontColor(this.theme.primary)
              .onClick(() => { this.isLoading = true; this.loadData() })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 说明
              Text('📶 按实时下载+上传速率降序排列')
                .fontSize(11).fontColor(this.theme.textTertiary)
                .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

              ForEach(this.devices, (dev: ConnectedDevice, idx: number) => {
                Column() {
                  // 排名 + 设备名 + 标签
                  Row() {
                    Text(idx < 3 ? this.rankBadges[idx] : `#${idx + 1}`)
                      .fontSize(18).fontColor(this.theme.textPrimary).margin({ right: 10 })

                    Column() {
                      Text(dev.hostname || '未知设备')
                        .fontSize(13).fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium).maxLines(1)
                      Text(dev.mac || '--')
                        .fontSize(10).fontColor(this.theme.textTertiary)
                        .fontFamily('monospace').maxLines(1)
                    }.alignItems(HorizontalAlign.Start)

                    Blank()

                    Column() {
                      Image(this.isWireless(dev) ? $r('app.media.wifi_icon') : $r('app.media.green_network_port'))
                        .width(16).height(16)
                      Text(this.isWireless(dev) ? 'WiFi' : '有线').fontSize(9)
                        .fontColor(this.theme.textTertiary)
                    }.alignItems(HorizontalAlign.Center)
                  }.width('100%').margin({ bottom: 6 })

                  // IP + 在线状态 + WiFi 信号
                  Row() {
                    Text(dev.ip || '--').fontSize(11).fontColor(this.theme.textSecondary)
                      .fontFamily('monospace').margin({ right: 12 })
                    Row() {
                      Circle({ width: 6, height: 6 })
                        .foregroundColor(dev.isOnline ? '#00E676' : '#9E9E9E')
                      Text(dev.isOnline ? ' 在线' : ' 离线')
                        .fontSize(10).fontColor(dev.isOnline ? '#00E676' : '#9E9E9E')
                    }

                    if (this.hasWirelessStats(dev)) {
                      Blank()
                      Text(this.sigLabel(dev.signalStrength))
                        .fontSize(10).fontColor(this.sigColor(dev.signalStrength))
                      Text(`  ${dev.signalStrength} dBm`)
                        .fontSize(10).fontColor(this.theme.textTertiary).fontFamily('monospace')
                    }
                  }.width('100%').margin({ bottom: 6 })

                  // 速率条
                  if ((dev.rxRate || 0) + (dev.txRate || 0) > 0) {
                    Row() {
                      Text('⇩').fontSize(10).fontColor('#00E676').width(14)
                      Text(FormatUtils.formatSpeed(dev.rxRate || 0))
                        .fontSize(10).fontColor('#00E676').fontFamily('monospace').width(68)
                      Text('⇧').fontSize(10).fontColor('#448AFF').width(14).margin({ left: 6 })
                      Text(FormatUtils.formatSpeed(dev.txRate || 0))
                        .fontSize(10).fontColor('#448AFF').fontFamily('monospace').width(68)

                      Stack() {
                        Row().width('100%').height(4).borderRadius(2)
                          .backgroundColor('rgba(255,255,255,0.06)')
                        Row()
                          .width(this.ratePct((dev.rxRate || 0) + (dev.txRate || 0))).height(4).borderRadius(2)
                          .linearGradient({
                            angle: 90,
                            colors: [['#448AFF', 0], ['#00E676', 1]]
                          })
                      }.alignContent(Alignment.Start)
                      .layoutWeight(1).height(4).margin({ left: 8 })
                    }.width('100%').margin({ bottom: 2 })
                  }

                  // 归属接口
                  if (dev.interface) {
                    Text(`接口: ${dev.interface}`)
                      .fontSize(9).fontColor(this.theme.textTertiary)
                  }

                  // 厂商
                  if (dev.vendor) {
                    Text(dev.vendor)
                      .fontSize(9).fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                }
                .width('100%').padding(12).borderRadius(12)
                .margin({
                  top: 8, left: 16, right: 16,
                  bottom: idx < this.devices.length - 1 ? 0 : 0
                })
                .backgroundColor('transparent')
                .border({ width: 0.5, color: this.theme.borderGlass })
              })

              if (this.devices.length === 0) {
                Text('暂无已连接设备').fontSize(13).fontColor(this.theme.textTertiary)
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
