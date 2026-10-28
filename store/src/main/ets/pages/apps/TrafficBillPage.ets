/**
 * TrafficBillPage - 流量月账单（运营商账单风）
 * 本月流量总览 + 近 7 天趋势 + 设备流量排行（实时快照推测）
 */
import { AppNav } from '../../common/utils/AppNav'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { TrafficStatStore, DayTraffic, HourTraffic } from '../../common/store/TrafficStatStore'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice } from '../../models/Models'

const DOMAIN = 0x0001
const TAG = 'TrafficBill'

@Entry
@Component
struct TrafficBillPageRoute {
  build() {
    Column() {
      TrafficBillPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct TrafficBillPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44   // 状态栏安全区高度
  @State monthTotal: number = 0        // 本月总流量（字节）
  @State monthDays: number = 0         // 本月已统计天数
  @State avgPerDay: number = 0         // 日均（字节）
  @State peakDay: string = ''          // 峰值日
  @State peakTotal: number = 0         // 峰值日流量（字节）
  @State weekData: DayTraffic[] = []   // 近 7 天
  @State devices: DeviceTop[] = []     // 设备排行
  @State loading: boolean = true
  // 上月对比 + 今日分时热点（来自小时桶）
  @State prevMonthTotal: number = 0
  @State prevMonthLabel: string = ''
  @State hourPeak: number = -1
  @State hourPeakBytes: number = 0
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      // 必须先初始化存储再读取，否则首次进入读到空数据
      TrafficStatStore.getInstance().init(hostCtx).then(() => {
        this.loadData()
      }).catch(() => {
        this.loadData()
      })
    } else {
      this.loadData()
    }
  }

  private async loadData(): Promise<void> {
    this.loading = true
    // 近 60 天流量（本月聚合 + 上月对比都要用）
    const days: DayTraffic[] = TrafficStatStore.getInstance().getDays(60)
    // 本月聚合（取近 60 天内属于本月的）
    const now: Date = new Date()
    const ym: string = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}`
    let total: number = 0
    let cnt: number = 0
    let peakD: string = ''
    let peakT: number = 0
    for (let i = 0; i < days.length; i++) {
      const d: DayTraffic = days[i]
      if (d.date.startsWith(ym)) {
        total += d.rx + d.tx
        cnt++
        const t: number = d.rx + d.tx
        if (t > peakT) {
          peakT = t
          peakD = d.date
        }
      }
    }
    this.monthTotal = total
    this.monthDays = cnt
    this.avgPerDay = cnt > 0 ? total / cnt : 0
    this.peakDay = peakD
    this.peakTotal = peakT

    // 上月总量（60 天窗口内的上个月）
    const prevDate: Date = new Date(now.getFullYear(), now.getMonth() - 1, 1)
    const prevYm: string = `${prevDate.getFullYear()}-${(prevDate.getMonth() + 1).toString().padStart(2, '0')}`
    let prevTotal: number = 0
    for (let i = 0; i < days.length; i++) {
      if (days[i].date.startsWith(prevYm)) {
        prevTotal += days[i].rx + days[i].tx
      }
    }
    this.prevMonthTotal = prevTotal
    this.prevMonthLabel = `${prevDate.getMonth() + 1} 月`

    // 今日分时热点（小时桶）
    const hours: HourTraffic[] = TrafficStatStore.getInstance().getTodayHourly()
    let ph: number = -1
    let pb: number = 0
    for (let h = 0; h < hours.length; h++) {
      const s: number = hours[h].rx + hours[h].tx
      if (s > pb) {
        pb = s
        ph = h
      }
    }
    this.hourPeak = ph
    this.hourPeakBytes = pb
    // 近 7 天（getDays 已是时间正序，末尾是今天）
    const week: DayTraffic[] = days.slice(-7)
    this.weekData = week
    // 设备排行（实时快照）
    try {
      const list: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      const tops: DeviceTop[] = []
      for (let i = 0; i < list.length; i++) {
        const d: ConnectedDevice = list[i]
        const rate: number = (d.rxRate || 0) + (d.txRate || 0)
        if (rate > 0) {
          tops.push({ name: d.hostname ? d.hostname : (d.vendor ? d.vendor : d.mac), mac: d.mac, rate: rate })
        }
      }
      tops.sort((a: DeviceTop, b: DeviceTop) => b.rate - a.rate)
      this.devices = tops.slice(0, 5)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `devices err: ${String(e)}`)
    }
    this.loading = false
  }

  /** 字节 → 自适应数值（≥1GB 用 GB，否则 MB / KB，避免小流量被显示成 0.0） */
  private val(bytes: number): string {
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1)
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1)
    if (bytes >= 1024) return (bytes / 1024).toFixed(0)
    return '0'
  }

  private unit(bytes: number): string {
    if (bytes >= 1073741824) return 'GB'
    if (bytes >= 1048576) return 'MB'
    if (bytes >= 1024) return 'KB'
    return 'B'
  }

  /** 近 7 天柱高（0~1） */
  private barHeight(idx: number): number {
    let max: number = 1
    for (let i = 0; i < this.weekData.length; i++) {
      const t: number = this.weekData[i].rx + this.weekData[i].tx
      if (t > max) max = t
    }
    const t: number = this.weekData[idx].rx + this.weekData[idx].tx
    return Math.max(0.08, t / max)
  }

  private barLabel(idx: number): string {
    const d: DayTraffic = this.weekData[idx]
    const day: string = d.date.slice(8, 10)
    return `${day}日`
  }

  /** 较上月（同为本月累计值对比本月之前的整月） */
  private monthCompareText(): string {
    if (this.prevMonthTotal <= 0) {
      return '上月无数据'
    }
    const diff: number = (this.monthTotal - this.prevMonthTotal) / this.prevMonthTotal * 100
    const sign: string = diff >= 0 ? '+' : ''
    return `${sign}${diff.toFixed(1)}%`
  }

  private monthCompareColor(): string {
    if (this.prevMonthTotal <= 0) return this.theme.textTertiary
    return this.monthTotal > this.prevMonthTotal ? '#E4572E' : '#2FA37A'
  }

  /** 今日流量高峰时段 */
  private hourPeakText(): string {
    if (this.hourPeak < 0) {
      return '今日暂无数据'
    }
    return `${this.hourPeak}:00-${this.hourPeak + 1}:00 · ${this.val(this.hourPeakBytes)} ${this.unit(this.hourPeakBytes)}`
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
          Image($r('app.media.flow_monitoring')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('流量月账单').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('流量也有账单的样子').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
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
              Text('正在计算账单...').fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 12 })
            }
            .width('100%').padding(50).alignItems(HorizontalAlign.Center)
          } else {
            // 账单头卡
            Column() {
              Text('本月已用流量').fontSize(12).fontColor('rgba(255,255,255,0.85)')
              Row() {
                Text(this.val(this.monthTotal))
                  .fontSize(62).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
                Text(` ${this.unit(this.monthTotal)}`).fontSize(18).fontColor('rgba(255,255,255,0.85)').margin({ bottom: 14 })
              }
              .alignItems(VerticalAlign.Bottom)
              Text(this.monthDays > 0 ? `已统计 ${this.monthDays} 天 · 日均 ${this.val(this.avgPerDay)} ${this.unit(this.avgPerDay)}` : '本月的流量数据还在积累中')
                .fontSize(11).fontColor('rgba(255,255,255,0.8)').margin({ top: 2 })
            }
            .width('100%').padding({ top: 26, bottom: 24 }).borderRadius(24).margin({ top: 12 })
            .linearGradient({
              angle: 135,
              colors: [['#FF9A5C', 0], ['#FF8A3D', 0.55], ['#FF7043', 1]]
            })
            .alignItems(HorizontalAlign.Center)

            // 上月对比 + 今日流量高峰（均基于本地留存数据）
            Column() {
              Row() {
                Text(`较上月（${this.prevMonthLabel}）`)
                  .fontSize(13).fontColor(this.theme.textSecondary)
                Blank()
                Text(this.monthCompareText())
                  .fontSize(13).fontColor(this.monthCompareColor()).fontWeight(FontWeight.Medium)
              }
              .width('100%')

              Divider().color(this.theme.borderGlass).margin({ top: 10, bottom: 10 })

              Row() {
                Text('今日流量高峰')
                  .fontSize(13).fontColor(this.theme.textSecondary)
                Blank()
                Text(this.hourPeakText())
                  .fontSize(13).fontColor(this.theme.textPrimary)
              }
              .width('100%')
            }
            .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
            .backgroundColor(this.theme.bgCard)

            // 峰值日
            if (this.peakTotal > 0) {
              Column() {
                Row() {
                  Row() {
            SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(13).fontColor(['#3B82F6'])
            Text(' 本月峰值日').fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
          }
                  Text(this.peakDay).fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 8 })
                  Blank()
                  Text(`${this.val(this.peakTotal)} ${this.unit(this.peakTotal)}`).fontSize(14).fontColor(this.theme.primary).fontWeight(FontWeight.Bold).fontFamily('monospace')
                }
                .width('100%')
              }
              .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
              .backgroundColor(this.theme.bgCard)
            }

            // 近 7 天趋势
            Column() {
              Text('近 7 天趋势').fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                .width('100%')
              Row() {
                ForEach(this.weekData, (d: DayTraffic, idx: number) => {
                  Column() {
                    // 柱状
                    Column()
                      .width('100%')
                      .height(70 * this.barHeight(idx))
                      .borderRadius(6)
                      .linearGradient({
                        angle: 180,
                        colors: [['#FF8A3D', 0], ['rgba(255,138,61,0.45)', 1]]
                      })
                    Text(this.barLabel(idx))
                      .fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 6 })
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.End)
                  .height(100)
                }, (d: DayTraffic, idx: number): string => d.date + '_' + idx)
              }
              .width('100%').margin({ top: 12 })
              .alignItems(VerticalAlign.Bottom)
            }
            .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
            .backgroundColor(this.theme.bgCard)

            // 设备排行
            Column() {
              Text('当前流量大户 TOP5').fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                .width('100%')
              Text('基于实时速率快照，仅作参考')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 }).width('100%')

              if (this.devices.length === 0) {
                Text('暂无活跃设备，稍后再来看看').fontSize(11).fontColor(this.theme.textTertiary)
                  .width('100%').padding({ top: 14, bottom: 6 })
              } else {
                ForEach(this.devices, (d: DeviceTop, idx: number) => {
                  Row() {
                    if (idx < 3) {
                      SymbolGlyph(this.rankSymbol(idx)).fontSize(16).fontColor([this.rankColor(idx)]).width(26)
                    } else {
                      Text(`${idx + 1}`).fontSize(12).fontColor(this.theme.textTertiary).width(26)
                    }
                    Column() {
                      Text(d.name).fontSize(12).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.speedText(d.rate)).fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 8 })
                  }
                  .width('100%').padding({ top: 9, bottom: 9 })
                  .border({ width: 0.5, color: 'rgba(180,160,120,0.15)' })
                  .borderRadius(12)
                  .margin({ top: 8 })
                }, (d: DeviceTop): string => d.mac)
              }
            }
            .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
            .backgroundColor(this.theme.bgCard)
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

  /** 前三名奖牌图标 */
  private rankSymbol(idx: number): Resource {
    if (idx === 0) return $r('sys.symbol.star_trophy')
    return $r('sys.symbol.medal')
  }

  /** 前三名奖牌配色 */
  private rankColor(idx: number): string {
    if (idx === 0) return '#F59E0B'
    if (idx === 1) return '#94A3B8'
    return '#B45309'
  }

  private speedText(rate: number): string {
    if (rate >= 1024 * 1024) {
      return `${(rate / 1024 / 1024).toFixed(1)} MB/s`
    }
    return `${Math.round(rate / 1024)} KB/s`
  }
}

/** 设备流量排行项 */
interface DeviceTop {
  name: string
  mac: string
  rate: number
}
