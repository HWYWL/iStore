/**
 * ShareCardPage - 装 B 分享卡
 * 网络状态（系统信息/网速/在线设备）生成小红书风卡片 → 截图 → 系统分享
 */
import { AppNav } from '../../common/utils/AppNav'
import { window } from '@kit.ArkUI'
import { componentSnapshot } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { systemShare } from '@kit.ShareKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { SystemInfo, WanStatus, ConnectedDevice, NetworkInterface } from '../../models/Models'

const DOMAIN = 0x0001
const TAG = 'ShareCard'

@Entry
@Component
struct ShareCardPageRoute {
  build() {
    Column() {
      ShareCardPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ShareCardPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44   // 状态栏安全区高度
  @State loading: boolean = true
  @State errText: string = ''
  @State sys: SystemInfo = {
    hostname: '', model: '', kernel: '', firmwareVersion: '', localTime: '', uptime: 0,
    cpuUsage: 0, memoryTotal: 0, memoryUsed: 0, memoryCached: 0, memoryAvailable: 0,
    storageTotal: 0, storageUsed: 0, cpuTemp: 0, cpuFreq: 0,
    boardName: '', cpuModel: '', distribution: '', releaseVersion: '', releaseRevision: '', releaseTarget: ''
  }
  @State rxMbps: number = 0
  @State txMbps: number = 0
  @State onlineCount: number = 0
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    this.loadData()
  }

  private async loadData(): Promise<void> {
    this.loading = true
    this.errText = ''
    try {
      const r: Object[] = await Promise.all([
        this.api.fetchSystemInfo(),
        this.api.fetchConnectedDevices()
      ])
      this.sys = r[0] as SystemInfo
      const devs: ConnectedDevice[] = r[1] as ConnectedDevice[]
      this.onlineCount = devs.filter((d: ConnectedDevice) => d.isOnline).length
      // 网速取 WAN 接口实时速率（LAN 速率在多数场景恒为 0），
      // fetchNetworkInterfaces 内部首次采样会自动补一次 1s 间隔，无需页面再等
      const api2 = new ApiService()
      const ifaces: NetworkInterface[] = await api2.fetchNetworkInterfaces()
      let rx: number = 0
      let tx: number = 0
      let wanFound: boolean = false
      for (let i = 0; i < ifaces.length; i++) {
        const n: NetworkInterface = ifaces[i]
        const lower: string = n.name.toLowerCase()
        if (n.type === 'wan' || lower.startsWith('wan') || lower.startsWith('pppoe')) {
          rx = n.rxRate
          tx = n.txRate
          wanFound = true
          break
        }
      }
      if (!wanFound || (rx === 0 && tx === 0)) {
        // 回退：所有非回环接口速率合计
        rx = 0
        tx = 0
        for (let i = 0; i < ifaces.length; i++) {
          const n: NetworkInterface = ifaces[i]
          if (n.name !== 'lo') {
            rx += n.rxRate
            tx += n.txRate
          }
        }
      }
      this.rxMbps = rx > 0 ? (rx * 8) / 1000000 : 0
      this.txMbps = tx > 0 ? (tx * 8) / 1000000 : 0
    } catch (e) {
      this.errText = '获取数据失败，请确认设备已连接'
    }
    this.loading = false
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms))
  }

  /** 内存占用百分比 */
  private memPercent(): number {
    if (this.sys.memoryTotal <= 0) return 0
    return Math.round((this.sys.memoryUsed / this.sys.memoryTotal) * 100)
  }

  /** 运行天数 */
  private upDays(): number {
    const u: number = this.sys.uptime
    if (u <= 0) return 0
    return Math.floor(u / 86400)
  }

  /** 卡片上的状态文案 */
  private cardTag(): string {
    const cpu: number = this.sys.cpuUsage
    if (cpu >= 85) return '火力全开 🔥'
    if (cpu >= 50) return '状态不错 ✨'
    return '稳如老狗 🐶'
  }

  /** 截图分享 */
  private async shareCard(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) return
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().get('shareCard')
      const packer: image.ImagePacker = image.createImagePacker()
      const buf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 })
      packer.release()
      const filePath: string = `${ctx.cacheDir}/share_card.png`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, buf)
      fs.closeSync(file)
      const uri: string = fileUri.getUriFromPath(filePath)
      const record: systemShare.SharedRecord = {
        uri: uri,
        title: '我的路由器装 B 卡',
        description: 'iStore 路由管家',
        utd: 'general.image'
      }
      const data: systemShare.SharedData = new systemShare.SharedData(record)
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      await controller.show(ctx, {})
    } catch (e) {
      hilog.error(DOMAIN, TAG, `share err: ${String(e)}`)
    }
  }

  /** 读取状态栏安全区高度（避免标题栏与状态栏重叠） */
  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.ranking')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('装 B 分享卡').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('一键生成网络状态分享图').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)

        Text('返回')
          .fontSize(13).fontColor(this.theme.primary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('rgba(255,138,61,0.1)')
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%').padding({ left: 16, right: 16, top: this.topSafeArea + 4 })

      Scroll() {
        Column() {
          if (this.loading) {
            Column() {
              LoadingProgress().width(36).height(36).color(this.theme.primary)
              Text('正在获取网络数据...').fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 12 })
            }
            .width('100%').padding(50).alignItems(HorizontalAlign.Center)
          } else if (this.errText) {
            Column() {
              SymbolGlyph($r('sys.symbol.warning')).fontSize(36).fontColor(['#EF4444'])
              Text(this.errText).fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 8 })
            }
            .width('100%').padding(40).alignItems(HorizontalAlign.Center)
          } else {
            // ===== 分享卡片（外层米色容器保证截图四角不透明）=====
            Column() {
              Column() {
                // 顶部
                Row() {
                  Column() {
                    Text(this.sys.hostname ? this.sys.hostname : 'iStore 路由器')
                      .fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                    Text('连续运行 ' + (this.upDays() > 0 ? `${this.upDays()} 天` : '稳定运行中'))
                      .fontSize(10).fontColor('rgba(255,255,255,0.7)').margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('iStore')
                    .fontSize(12).fontColor('#FFFFFF')
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(12)
                    .backgroundColor('rgba(255,255,255,0.18)')
                }
                .width('100%')

                // 网速大字
                Row() {
                  Column() {
                    Text(this.rxMbps.toFixed(1))
                      .fontSize(40).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
                    Text('下载 Mbps').fontSize(10).fontColor('rgba(255,255,255,0.7)')
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Center)

                  Column() {
                    Text(this.txMbps.toFixed(1))
                      .fontSize(40).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
                    Text('上传 Mbps').fontSize(10).fontColor('rgba(255,255,255,0.7)')
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Center)
                }
                .width('100%').margin({ top: 18 })

                Row()
                  .width('100%').height(0.6)
                  .backgroundColor('rgba(255,255,255,0.35)')
                  .margin({ top: 16 })

                // 数据格子 2x2
                Row({ space: 10 }) {
                  this.statCell('CPU', `${Math.round(this.sys.cpuUsage)}%`)
                  this.statCell('内存', `${this.memPercent()}%`)
                  this.statCell('温度', this.sys.cpuTemp > 0 ? `${this.sys.cpuTemp}°C` : '--')
                  this.statCell('在线设备', `${this.onlineCount} 台`)
                }
                .width('100%').margin({ top: 14 })

                // 状态文案
                Text(this.cardTag())
                  .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                  .margin({ top: 18 })
                Text('# 我家路由器 # 网络稳如老狗 # iStore')
                  .fontSize(10).fontColor('rgba(255,255,255,0.75)').margin({ top: 10 })
              }
              .width('100%').padding(22)
              .borderRadius(24)
              .linearGradient({
                angle: 135,
                colors: [['#FF9A5C', 0], ['#FF8A3D', 0.55], ['#FF7043', 1]]
              })
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%').padding(16).backgroundColor('#F6F2EA')
            .id('shareCard')

            // 分享按钮
            Row() {
              SymbolGlyph($r('sys.symbol.share')).fontSize(16).fontColor(['#FFFFFF'])
              Text('  分享这张卡').fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            }
            .width('100%').height(46).borderRadius(23).margin({ top: 16 })
            .backgroundColor('#FF8A3D')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.shareCard() })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(15).fontColor(['#FF8A3D'])
              Text('  刷新数据').fontSize(13).fontColor('#FF8A3D').fontWeight(FontWeight.Medium)
            }
            .width('100%').height(44).borderRadius(22).margin({ top: 10 })
            .backgroundColor('#FFF3E7')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.loadData() })
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }

  @Builder
  statCell(label: string, value: string) {
    Column() {
      Text(value).fontSize(17).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
      Text(label).fontSize(9).fontColor('rgba(255,255,255,0.65)').margin({ top: 3 })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor('rgba(255,255,255,0.12)')
    .alignItems(HorizontalAlign.Center)
  }
}
