
import { BrandColors } from '../../common/theme/BrandColors'
import { AppState } from '../../common/store/AppState'
import {
  LIGHT_THEME,
  ThemePalette,
  cardBorder,
  pageBgColors,
  withAlpha
} from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

/** 物理网口信息 */
class EthPort {
  name: string = ''
  up: boolean = false
  speedLabel: string = ''
  mac: string = ''
  duplex: string = ''
  constructor() {}
}

@Entry
@Component
struct EthPortPageRoute {
  build() {
    Column() {
      EthPortPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct EthPortPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State ports: EthPort[] = []
  @State errorText: string = ''

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api: ApiService = new ApiService()
      const data: Object = await api.fetchEthPortStatuses()
      if (data && typeof data === 'object') {
        const rec: Record<string, Object> = data as Record<string, Object>
        const keys: string[] = Object.keys(rec)
        // DSA 固件里 eth0 只是 CPU 侧的 conduit，真正的面板口是 lan1..N / wan
        let hasDsa: boolean = false
        for (let i: number = 0; i < keys.length; i++) {
          const d: Object = rec[keys[i]]
          if (!d || typeof d !== 'object') continue
          if (((d as Record<string, Object>)['devtype'] as string) === 'dsa') hasDsa = true
        }

        const list: EthPort[] = []
        for (let i: number = 0; i < keys.length; i++) {
          const dev: Object = rec[keys[i]]
          if (!dev || typeof dev !== 'object') continue
          const devRec: Record<string, Object> = dev as Record<string, Object>
          const name: string = (devRec['name'] as string) || keys[i]
          const lower: string = name.toLowerCase()
          const devtype: string = (devRec['devtype'] as string) || ''
          if (this.isVirtualPort(lower, devtype)) continue

          // 物理口判定：DSA 端口 > lan/wan 命名 > 非 DSA 架构下的 eth*/en*
          let physical: boolean = devtype === 'dsa' || this.isLanWanName(lower)
          if (!physical && !hasDsa) physical = lower.startsWith('eth') || lower.startsWith('en')
          if (!physical) continue

          const mac: string = (devRec['mac'] as string) || ''
          let up: boolean = (devRec['up'] as boolean) === true

          let speedLabel: string = ''
          let duplex: string = ''
          const link: Object = devRec['link'] as Object
          if (link && typeof link === 'object') {
            const linkRec: Record<string, Object> = link as Record<string, Object>
            // 插线状态以 carrier 为准：lan4 这类空口 flags.up 仍为 true，但 carrier=false
            const carrier: Object = linkRec['carrier']
            if (typeof carrier === 'boolean') up = up && (carrier as boolean)
            if (up) {
              const sp: number = (linkRec['speed'] as number) || 0
              if (sp >= 10000) speedLabel = (sp / 1000).toFixed(0) + ' Gbps'
              else if (sp >= 1000) {
                const g: number = sp / 1000
                speedLabel = (g === Math.floor(g) ? g.toFixed(0) : g.toFixed(1)) + ' Gbps'
              } else if (sp >= 100) speedLabel = sp + ' Mbps'
              const dp: string = (linkRec['duplex'] as string) || ''
              duplex = dp === 'unknown' ? '' : dp
            }
          }

          const p: EthPort = new EthPort()
          p.name = name
          p.up = up
          p.speedLabel = speedLabel
          p.mac = mac
          p.duplex = duplex
          list.push(p)
        }
        list.sort((a: EthPort, b: EthPort): number => {
          const ka: string = this.portSortKey(a.name)
          const kb: string = this.portSortKey(b.name)
          if (ka === kb) return 0
          return ka < kb ? -1 : 1
        })
        this.ports = list
      }
    } catch (e) {
      this.errorText = '加载失败'
    }
    this.isLoading = false
  }

  /** 桥接 / 容器 / 隧道 / 无线等非面板接口 */
  private isVirtualPort(lower: string, devtype: string): boolean {
    if (lower === 'lo') return true
    if (lower.startsWith('br-') || lower.startsWith('bond')) return true
    if (lower.startsWith('veth') || lower.startsWith('docker') || lower.startsWith('virbr')) return true
    if (lower.startsWith('wlan') || lower.startsWith('phy') || lower.startsWith('ra')) return true
    if (lower.startsWith('ppp') || lower.startsWith('tun') || lower.startsWith('tap')) return true
    if (lower.startsWith('wg') || lower.startsWith('sit') || lower.startsWith('gre')) return true
    if (lower.startsWith('vxlan') || lower.startsWith('dummy') || lower.startsWith('ifb')) return true
    return devtype === 'bridge' || devtype === 'vlan' || devtype === 'macvlan' || devtype === 'virt'
  }

  /** lan / wan 及其编号变体（lan1、wan2…），老式 swconfig 固件的面板口命名 */
  private isLanWanName(lower: string): boolean {
    let rest: string = ''
    if (lower === 'lan' || lower === 'wan') return true
    if (lower.startsWith('lan')) rest = lower.substring(3)
    else if (lower.startsWith('wan')) rest = lower.substring(3)
    else return false
    if (rest.length === 0) return true
    for (let i: number = 0; i < rest.length; i++) {
      const c: number = rest.charCodeAt(i)
      if (c < 48 || c > 57) return false
    }
    return true
  }

  /** 自然排序键：保证 lan2 排在 lan10 之前 */
  private portSortKey(name: string): string {
    const n: string = name.toLowerCase()
    let i: number = 0
    while (i < n.length && (n.charCodeAt(i) < 48 || n.charCodeAt(i) > 57)) i++
    const prefix: string = n.substring(0, i)
    const numStr: string = n.substring(i)
    const num: number = numStr.length > 0 ? parseInt(numStr) : 0
    return prefix + ('000000' + (isNaN(num) ? 0 : num)).slice(-6)
  }

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: pageBgColors(this.theme, AppNav.getInstance().isWide())
        })

      Column() {
        // 顶栏
        Row() {
          Row() {
            AppIcon({ name: 'square_grid_3x1_below_line_grid_1x2', iconSize: 15, colors: [BrandColors.blue] })
            Text(' 物理网口').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border(cardBorder(this.theme))
          .onClick(() => AppNav.getInstance().back())

          Blank()
          Text(`共 ${this.ports.length} 个`).fontSize(11).fontColor(this.theme.textTertiary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorText) {
          Column() {
            Row() {
              AppIcon({ name: 'warning', iconSize: 14, colors: [this.theme.warning] })
              Text(' ' + this.errorText).fontSize(14).fontColor(this.theme.warning)
            }
            .margin({ bottom: 12 })
            Text('点击重试').fontSize(14).fontColor(this.theme.primary)
              .onClick(() => this.loadData())
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 说明
              Row() {
                AppIcon({ name: 'link', iconSize: 12, colors: [this.theme.textTertiary] })
                Text(' 按 lan / wan / eth 自然顺序展示物理网口，已过滤桥接与虚拟接口')
                  .fontSize(11).fontColor(this.theme.textTertiary).layoutWeight(1)
              }
              .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })

              ForEach(this.ports, (port: EthPort, idx: number) => {
                Column() {
                  // 端口图标 + 名称 + 状态
                  Row() {
                    Row() {
                      AppIcon({
                        name: 'link',
                        iconSize: 16,
                        colors: [port.up ? '#22C55E' : this.theme.textTertiary]
                      })
                    }
                    .width(34).height(34)
                    .borderRadius(11)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(port.up ? 'rgba(34,197,94,0.10)' : 'rgba(117,117,117,0.08)')
                    Column() {
                      Text(port.name).fontSize(16).fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Bold)
                      if (port.mac) {
                        Text(port.mac).fontSize(11).fontColor(this.theme.textTertiary)
                          .fontFamily('monospace')
                      }
                    }.alignItems(HorizontalAlign.Start).margin({ left: 12 })

                    Blank()

                    Row() {
                      Circle({ width: 8, height: 8 })
                        .foregroundColor(port.up ? this.theme.semantic.success : '#757575')
                        .margin({ right: 6 })
                      Text(port.up ? '已连接' : '未连接')
                        .fontSize(12).fontColor(port.up ? this.theme.semantic.success : '#757575')
                    }
                  }.width('100%').margin({ bottom: 10 })

                  // 速率 + 双工
                  if (port.speedLabel || port.duplex) {
                    Row() {
                      if (port.speedLabel) {
                        Column() {
                          Text('速率').fontSize(10).fontColor(this.theme.textTertiary)
                          Text(port.speedLabel).fontSize(14).fontColor(BrandColors.blueSoft)
                            .fontWeight(FontWeight.Bold)
                        }.alignItems(HorizontalAlign.Center)
                        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                        .borderRadius(10)
                        .backgroundColor(port.up ? withAlpha(this.theme.info, 0.08) : 'rgba(117,117,117,0.06)')
                        .border({ width: 0.5, color: withAlpha(port.up ? BrandColors.blueSoft : BrandColors.gray, 0.2) })
                      }

                      if (port.duplex) {
                        Column() {
                          Text('双工').fontSize(10).fontColor(this.theme.textTertiary)
                          Text(port.duplex).fontSize(14).fontColor(this.theme.textPrimary)
                        }.alignItems(HorizontalAlign.Center).margin({ left: 10 })
                        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                        .borderRadius(10)
                        .backgroundColor(port.up ? 'rgba(255,255,255,0.04)' : 'rgba(117,117,117,0.04)')
                        .border(cardBorder(this.theme))
                      }
                    }.width('100%')
                  }
                }
                .width('100%').padding(16).borderRadius(14)
                .margin({
                  top: 8, left: 16, right: 16,
                  bottom: idx < this.ports.length - 1 ? 6 : 0
                })
                .backgroundColor(port.up ? this.theme.bgCard : 'rgba(117,117,117,0.04)')
                .backdropBlur(this.theme.material.blur)
                .border({
                  width: port.up ? 0.5 : 0,
                  color: port.up ? this.theme.borderGlass : Color.Transparent
                })
              })

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
