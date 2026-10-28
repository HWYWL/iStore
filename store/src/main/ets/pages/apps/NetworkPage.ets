import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { NetworkInterface, WanStatus } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'

// ============================================================
// NetworkPage - 网络管理（独立页面，从应用中心进入）
// ============================================================
@Entry
@Component
struct NetworkPageRoute {
  build() {
    Column() {
      NetworkPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NetworkPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State interfaces: NetworkInterface[] = []
  @State wanStatus: WanStatus = this.emptyWan()
  @State lanStatus: WanStatus = this.emptyWan()
  @State isLoading: boolean = true
  @State errorText: string = ''

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      this.lanStatus = await api.fetchLanStatus()
      this.interfaces = await api.fetchNetworkInterfaces()
    } catch (netErr) {
      this.errorText = '加载网络信息失败'
    }
    this.isLoading = false
  }

  emptyWan(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0',
      netmask: '', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '',
      proto: '', macAddr: ''
    }
  }

  getTypeLabel(type: string): string {
    const labels: Record<string, string> = {
      'wan': 'WAN 外网',
      'lan': 'LAN 内网',
      'wifi': 'WiFi 无线',
      'vpn': 'VPN'
    }
    return labels[type] || type
  }

  getTypeColor(type: string): string {
    const colors: Record<string, string> = {
      'wan': this.theme.warning,
      'lan': this.theme.success,
      'wifi': this.theme.primary,
      'vpn': this.theme.secondary
    }
    return colors[type] || this.theme.textTertiary
  }

  getTypeSymbol(type: string): Resource {
    if (type === 'wan') return $r('sys.symbol.globe_badge_message')
    if (type === 'lan') return $r('sys.symbol.house')
    if (type === 'wifi') return $r('sys.symbol.wifi')
    if (type === 'vpn') return $r('sys.symbol.lock')
    return $r('sys.symbol.link')
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
            Text(' 网络管理').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => AppNav.getInstance().back())

          Blank()
          Text(`${this.interfaces.length} 个接口`)
            .fontSize(11)
            .fontColor(this.theme.textSecondary)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Scroll() {
          Column() {
            if (this.isLoading) {
              Column() {
                LoadingWhimsy({ message: '正在读网络信息…' })
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            } else {
              if (this.errorText) {
                Row() {
                  SymbolGlyph($r('sys.symbol.warning'))
                    .fontSize(16)
                    .fontColor([this.theme.warning])
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
              }

              // LAN 网络状态卡片
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.house'))
                    .fontSize(15)
                    .fontColor(['#10B981'])
                  Text(' LAN 网络状态')
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                }
                .margin({ bottom: 12 })

                Row() {
                  Text(this.lanStatus.ipAddress)
                    .fontSize(22)
                    .fontColor(this.theme.primary)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                  if (this.lanStatus.netmask) {
                    Text(`/${this.lanStatus.netmask}`)
                      .fontSize(14)
                      .fontColor(this.theme.textSecondary)
                      .fontFamily('monospace')
                      .margin({ left: 2 })
                  }
                  Blank()
                  Column() {
                    Text(`⇩ ${FormatUtils.formatSpeed(this.lanStatus.rxRate)}`)
                      .fontSize(13)
                      .fontColor(this.theme.success)
                    Text(`⇧ ${FormatUtils.formatSpeed(this.lanStatus.txRate)}`)
                      .fontSize(13)
                      .fontColor(this.theme.secondary)
                      .margin({ top: 4 })
                  }
                }
                .width('100%')
                .margin({ bottom: 12 })

                if (this.lanStatus.proto) {
                  this.netLine('协议', this.lanStatus.proto.toUpperCase())
                }
                if (this.lanStatus.macAddr) {
                  this.netLine('MAC', this.lanStatus.macAddr)
                }
                this.netLine('网关', this.lanStatus.gateway || '--')
                this.netLine('DNS', this.lanStatus.dns.length > 0 ? this.lanStatus.dns.join(', ') : '--')
                this.netLine('接口', this.lanStatus.interface || '--')
                if (this.lanStatus.uptime > 0) {
                  this.netLine('运行时长', FormatUtils.formatUptime(this.lanStatus.uptime))
                }
              }
              .width('100%')
              .padding(20)
              .borderRadius(24)
              .margin({ top: 8 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })

              // 接口列表
              ForEach(this.interfaces, (iface: NetworkInterface) => {
                Column() {
                  Row() {
                    Row() {
                      SymbolGlyph(this.getTypeSymbol(iface.type))
                        .fontSize(20)
                        .fontColor([this.getTypeColor(iface.type)])
                    }
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor(this.theme.bgGlassLight)
                    .justifyContent(FlexAlign.Center)

                    Column() {
                      Text(iface.name)
                        .fontSize(14)
                        .fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium)
                      Text(this.getTypeLabel(iface.type))
                        .fontSize(10)
                        .fontColor(this.getTypeColor(iface.type))
                    }
                    .margin({ left: 10 })
                    .alignItems(HorizontalAlign.Start)

                    Blank()

                    Column() {
                      Circle()
                        .width(8)
                        .height(8)
                        .foregroundColor(iface.status === 'up' ? this.theme.success : this.theme.danger)
                      Text(iface.status === 'up' ? '已连接' : '断开')
                        .fontSize(10)
                        .fontColor(iface.status === 'up' ? this.theme.success : this.theme.textTertiary)
                    }
                  }
                  .width('100%')

                  if (iface.ipAddress || iface.macAddress) {
                    Row() {
                      if (iface.ipAddress) {
                        Text(`IP: ${iface.ipAddress}`)
                          .fontSize(10)
                          .fontColor(this.theme.textSecondary)
                        Blank()
                      }
                      if (iface.macAddress) {
                        Text(`MAC: ${FormatUtils.formatMac(iface.macAddress)}`)
                          .fontSize(10)
                          .fontColor(this.theme.textTertiary)
                      }
                    }
                    .width('100%')
                    .margin({ top: 10 })
                    .padding({ top: 10 })
                    .border({ width: { top: 0.3 }, color: this.theme.borderGlass })
                  }

                  Text(`↓ ${FormatUtils.formatBytes(iface.rxBytes)} | ↑ ${FormatUtils.formatBytes(iface.txBytes)}`)
                    .fontSize(10)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(20)
                .margin({ top: 12 })
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
              }, (item: NetworkInterface): string => item.name)
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }

  @Builder netLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(50)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
