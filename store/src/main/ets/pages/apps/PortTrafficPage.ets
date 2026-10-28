import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { NetworkInterface, ConnectedDevice } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'
import { Poller } from '../../common/utils/Poller'

/** 接口类型图标 */
function getTypeIcon(t: string): string {
  if (t === 'wan') return '🌐'; if (t === 'lan') return '🏠'
  if (t === 'wifi') return '📶'; if (t === 'vpn') return '🔒'
  return '📡'
}
/** 接口类型颜色 */
function getTypeColor(t: string): string {
  if (t === 'wan') return '#FF9800'; if (t === 'lan') return '#448AFF'
  if (t === 'wifi') return '#00E676'; if (t === 'vpn') return '#AB47BC'
  return '#999'
}

@Entry
@Component
struct PortTrafficPageRoute {
  build() {
    Column() {
      PortTrafficPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct PortTrafficPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State interfaces: NetworkInterface[] = []
  @State errorText: string = ''
  @State maxRate: number = 1  // 用于进度条比例尺
  private poller: Poller | null = null
  private rankGolds: string[] = ['🥇', '🥈', '🥉']

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
    // 统一轮询器：3s 高频刷新，上轮未返回则跳过，避免请求堆积
    this.poller = new Poller((): Promise<void> => this.loadData(), 3000)
    this.poller.start()
  }

  aboutToDisappear(): void {
    if (this.poller) {
      this.poller.dispose()
      this.poller = null
    }
  }

  async loadData(): Promise<void> {
    try {
      if (!AppState.getInstance().isConnected()) return
      const api = new ApiService()
      const ifaces = await api.fetchNetworkInterfaces()
      // 只保留 up 的接口，按总速率降序排列
      const active = ifaces.filter(i => i.status === 'up')
      active.sort((a, b) => {
        const ta = (a.rxRate || 0) + (a.txRate || 0)
        const tb = (b.rxRate || 0) + (b.txRate || 0)
        return tb - ta
      })
      this.interfaces = active
      // 计算最大速率作为进度条比例尺
      let max = 1
      for (const iface of active) {
        const t = (iface.rxRate || 0) + (iface.txRate || 0)
        if (t > max) max = t
      }
      this.maxRate = max
      this.errorText = ''
    } catch (e) {
      this.errorText = '加载失败'
    }
    this.isLoading = false
  }

  /** 速率进度条宽度百分比 */
  ratePct(rate: number): string {
    if (rate <= 0 || this.maxRate <= 0) return '0%'
    return `${Math.min(100, (rate / this.maxRate) * 100)}%`
  }

  /** 类型标签名 */
  typeLabel(type: string): string {
    if (type === 'wan') return 'WAN'
    if (type === 'lan') return 'LAN'
    if (type === 'wifi') return 'WiFi'
    if (type === 'vpn') return 'VPN'
    return type.toUpperCase()
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
        // 顶栏
        Row() {
          Row() {
            Text(' 网口流量')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => AppNav.getInstance().back())

          Blank()
          Text(`共 ${this.interfaces.length} 个接口`)
            .fontSize(11).fontColor(this.theme.textTertiary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorText && this.interfaces.length === 0) {
          Column() {
            Text('⚠ ' + this.errorText).fontSize(14).fontColor(this.theme.warning)
              .margin({ bottom: 12 })
            Text('点击重试').fontSize(14).fontColor(this.theme.primary)
              .onClick(() => {
                this.isLoading = true
                this.loadData()
              })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // ======== 总览卡片 ========
              Column() {
                Text('📡 实时流量总览')
                  .fontSize(13).fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium).margin({ bottom: 10 })

                Row() {
                  Column() {
                    Text('⇩ 总下载').fontSize(10).fontColor(this.theme.textTertiary)
                    Text(this.fmtTotalRx())
                      .fontSize(20).fontColor('#00E676').fontWeight(FontWeight.Bold)
                      .fontFamily('monospace')
                  }.layoutWeight(1)

                  Column() {
                    Text('⇧ 总上传').fontSize(10).fontColor(this.theme.textTertiary)
                    Text(this.fmtTotalTx())
                      .fontSize(20).fontColor('#448AFF').fontWeight(FontWeight.Bold)
                      .fontFamily('monospace')
                  }.layoutWeight(1).alignItems(HorizontalAlign.End)
                }.width('100%')
              }
              .width('100%').padding(16).borderRadius(14)
              .margin({ top: 8, left: 16, right: 16 })
              .backgroundColor('transparent')
              .border({ width: 0.5, color: this.theme.borderGlass })

              // ======== 排行列表 ========
              if (this.interfaces.length === 0) {
                Column() {
                  Text('暂无活跃接口，网线都睡了吗？🔌').fontSize(13).fontColor(this.theme.textTertiary)
                }
                .width('100%').padding(32).margin({ top: 10, left: 16, right: 16 })
                .borderRadius(14).backgroundColor(this.theme.bgCard)
              } else {
                ForEach(this.interfaces, (iface: NetworkInterface, idx: number) => {
                  Column() {
                    // 排名 + 接口名 + 类型标签
                    Row() {
                      Text(idx < 3 ? this.rankGolds[idx] : `#${idx + 1}`)
                        .fontSize(18).fontColor(this.theme.textPrimary)
                        .margin({ right: 10 })

                      Column() {
                        Text(iface.name || '--')
                          .fontSize(14).fontColor(this.theme.textPrimary)
                          .fontWeight(FontWeight.Medium).maxLines(1)
                        Text(iface.macAddress || '')
                          .fontSize(10).fontColor(this.theme.textTertiary)
                          .fontFamily('monospace').maxLines(1)
                      }.alignItems(HorizontalAlign.Start)

                      Blank()

                      Text(this.typeLabel(iface.type))
                        .fontSize(10).fontColor(getTypeColor(iface.type))
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                        .borderRadius(6)
                        .backgroundColor(getTypeColor(iface.type) + '18')
                    }
                    .width('100%')
                    .margin({ bottom: 8 })

                    // 下载速率条
                    Row() {
                      Text('⇩').fontSize(11).fontColor('#00E676').width(18)
                      Text(FormatUtils.formatSpeed(iface.rxRate || 0))
                        .fontSize(12).fontColor('#00E676').fontFamily('monospace')
                        .width(82)
                      Stack() {
                        Row().width('100%').height(6).borderRadius(3)
                          .backgroundColor('rgba(255,255,255,0.08)')
                        Row()
                          .width(this.ratePct(iface.rxRate || 0))
                          .height(6).borderRadius(3)
                          .linearGradient({
                            angle: 90,
                            colors: [['#00E676', 0], ['#00E67644', 1]]
                          })
                      }
                      .alignContent(Alignment.Start)
                      .layoutWeight(1).height(6).margin({ left: 8 })
                    }
                    .width('100%')
                    .margin({ bottom: 4 })

                    // 上传速率条
                    Row() {
                      Text('⇧').fontSize(11).fontColor('#448AFF').width(18)
                      Text(FormatUtils.formatSpeed(iface.txRate || 0))
                        .fontSize(12).fontColor('#448AFF').fontFamily('monospace')
                        .width(82)
                      Stack() {
                        Row().width('100%').height(6).borderRadius(3)
                          .backgroundColor('rgba(255,255,255,0.08)')
                        Row()
                          .width(this.ratePct(iface.txRate || 0))
                          .height(6).borderRadius(3)
                          .linearGradient({
                            angle: 90,
                            colors: [['#448AFF', 0], ['#448AFF44', 1]]
                          })
                      }
                      .alignContent(Alignment.Start)
                      .layoutWeight(1).height(6).margin({ left: 8 })
                    }
                    .width('100%')
                    .margin({ bottom: 6 })

                    // 累计总量
                    Row() {
                      Text('累计').fontSize(10).fontColor(this.theme.textTertiary)
                        .width(18)
                      Text(`⇩ ${FormatUtils.formatBytes(iface.rxBytes || 0)}  ⇧ ${FormatUtils.formatBytes(iface.txBytes || 0)}`)
                        .fontSize(10).fontColor(this.theme.textTertiary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%')
                  }
                  .width('100%').padding(14).borderRadius(12)
                  .margin({
                    top: 10,
                    left: 16, right: 16,
                    bottom: idx < this.interfaces.length - 1 ? 0 : 0
                  })
                  .backgroundColor('transparent')
                  .border({ width: 0.5, color: this.theme.borderGlass })
                })
              }

              Row().width('100%').height(100)
            }
            .width('100%')
          }
          .width('100%').padding({ bottom: 90 }).layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }

  // ========== 辅助 ==========
  fmtTotalRx(): string {
    let total = 0
    for (const i of this.interfaces) total += (i.rxRate || 0)
    return FormatUtils.formatSpeed(total)
  }

  fmtTotalTx(): string {
    let total = 0
    for (const i of this.interfaces) total += (i.txRate || 0)
    return FormatUtils.formatSpeed(total)
  }
}
