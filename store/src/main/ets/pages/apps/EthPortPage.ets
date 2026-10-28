import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'

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
        const keys: string[] = Object.keys(rec).sort()
        const list: EthPort[] = []
        for (let i: number = 0; i < keys.length; i++) {
          const dev: Object = rec[keys[i]]
          if (!dev || typeof dev !== 'object') continue
          const devRec: Record<string, Object> = dev as Record<string, Object>
          const name: string = (devRec['name'] as string) || keys[i]
          const lower: string = name.toLowerCase()
          if (!lower.startsWith('eth') && !lower.startsWith('en')) continue

          const up: boolean = (devRec['up'] as boolean) === true
          const mac: string = (devRec['mac'] as string) || ''

          let speedLabel: string = ''
          let duplex: string = ''
          const link: Object = devRec['link'] as Object
          if (link && typeof link === 'object') {
            const linkRec: Record<string, Object> = link as Record<string, Object>
            const sp: number = (linkRec['speed'] as number) || 0
            if (sp >= 10000) speedLabel = (sp / 1000).toFixed(0) + ' Gbps'
            else if (sp >= 1000) {
              const g: number = sp / 1000
              speedLabel = (g === Math.floor(g) ? g.toFixed(0) : g.toFixed(1)) + ' Gbps'
            } else if (sp >= 100) speedLabel = sp + ' Mbps'
            duplex = (linkRec['duplex'] as string) || ''
          }

          const p: EthPort = new EthPort()
          p.name = name
          p.up = up
          p.speedLabel = speedLabel
          p.mac = mac
          p.duplex = duplex
          list.push(p)
        }
        this.ports = list
      }
    } catch (e) {
      this.errorText = '加载失败'
    }
    this.isLoading = false
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
            SymbolGlyph($r('sys.symbol.square_grid_3x1_below_line_grid_1x2'))
              .fontSize(15).fontColor(['#3B82F6'])
            Text(' 物理网口').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
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
              SymbolGlyph($r('sys.symbol.warning')).fontSize(14).fontColor([this.theme.warning])
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
                SymbolGlyph($r('sys.symbol.link')).fontSize(12).fontColor([this.theme.textTertiary])
                Text(' 以 eth0 → eth1 → ... 顺序展示物理网口状态')
                  .fontSize(11).fontColor(this.theme.textTertiary).layoutWeight(1)
              }
              .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })

              ForEach(this.ports, (port: EthPort, idx: number) => {
                Column() {
                  // 端口图标 + 名称 + 状态
                  Row() {
                    Image(port.up ? $r('app.media.green_network_port') : $r('app.media.grey_network_port'))
                      .width(28).height(28)
                      .objectFit(ImageFit.Contain)
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
                        .foregroundColor(port.up ? '#00E676' : '#757575')
                        .margin({ right: 6 })
                      Text(port.up ? '已连接' : '未连接')
                        .fontSize(12).fontColor(port.up ? '#00E676' : '#757575')
                    }
                  }.width('100%').margin({ bottom: 10 })

                  // 速率 + 双工
                  if (port.speedLabel || port.duplex) {
                    Row() {
                      if (port.speedLabel) {
                        Column() {
                          Text('速率').fontSize(10).fontColor(this.theme.textTertiary)
                          Text(port.speedLabel).fontSize(14).fontColor('#448AFF')
                            .fontWeight(FontWeight.Bold)
                        }.alignItems(HorizontalAlign.Center)
                        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                        .borderRadius(10)
                        .backgroundColor(port.up ? 'rgba(68,138,255,0.08)' : 'rgba(117,117,117,0.06)')
                        .border({ width: 0.5, color: port.up ? '#448AFF33' : '#75757533' })
                      }

                      if (port.duplex) {
                        Column() {
                          Text('双工').fontSize(10).fontColor(this.theme.textTertiary)
                          Text(port.duplex).fontSize(14).fontColor(this.theme.textPrimary)
                        }.alignItems(HorizontalAlign.Center).margin({ left: 10 })
                        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                        .borderRadius(10)
                        .backgroundColor(port.up ? 'rgba(255,255,255,0.04)' : 'rgba(117,117,117,0.04)')
                        .border({ width: 0.5, color: this.theme.borderGlass })
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
                .backdropBlur(20)
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
