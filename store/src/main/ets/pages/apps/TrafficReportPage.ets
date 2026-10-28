/**
 * TrafficReportPage - 流量统计（周报/月报）
 * 展示近 7 天 / 30 天每日下载/上传流量柱状图与汇总
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { TrafficStatStore, DayTraffic, HourTraffic } from '../../common/store/TrafficStatStore'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct TrafficReportPageRoute {
  build() {
    Column() {
      TrafficReportPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct TrafficReportPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State range: number = 7  // 7 天 / 30 天
  @State days: DayTraffic[] = []
  @State totalRx: number = 0
  @State totalTx: number = 0
  @State maxDayBytes: number = 1
  @State hourly: HourTraffic[] = []
  @State maxHourBytes: number = 1
  // 环比 / 峰值 / 突增提示
  @State prevTotal: number = 0
  @State peakIndex: number = -1
  @State peakHour: number = -1
  @State surgeText: string = ''
  private store: TrafficStatStore = TrafficStatStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      // 必须先初始化存储再读取，否则首次进入读到空数据
      this.store.init(hostCtx as Context).then(() => {
        this.loadData()
      }).catch(() => {
        this.loadData()
      })
    } else {
      this.loadData()
    }
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 加载流量数据 */
  loadData(): void {
    // getDays 返回按日期升序（末尾是今天）：前 N 天是上一区间，后 N 天是当前区间
    const all: DayTraffic[] = this.store.getDays(this.range * 2)
    const prev: DayTraffic[] = all.slice(0, this.range)
    this.days = all.slice(this.range)

    let rx: number = 0
    let tx: number = 0
    let max: number = 1
    let peak: number = -1
    for (let i = 0; i < this.days.length; i++) {
      const sum: number = this.days[i].rx + this.days[i].tx
      rx += this.days[i].rx
      tx += this.days[i].tx
      if (sum > max) {
        max = sum
        peak = i
      }
    }
    this.totalRx = rx
    this.totalTx = tx
    this.maxDayBytes = max
    this.peakIndex = peak

    let prevSum: number = 0
    for (let i = 0; i < prev.length; i++) {
      prevSum += prev[i].rx + prev[i].tx
    }
    this.prevTotal = prevSum

    // 今日 24 小时分布（小时桶由 TrafficStatStore 落盘）
    this.hourly = this.store.getTodayHourly()
    let maxH: number = 1
    let peakH: number = -1
    for (let h = 0; h < this.hourly.length; h++) {
      const s: number = this.hourly[h].rx + this.hourly[h].tx
      if (s > maxH) {
        maxH = s
        peakH = h
      }
    }
    this.maxHourBytes = maxH
    this.peakHour = peakH

    // 异常提示：今日已是昨日 2 倍以上，且绝对值超过 100MB
    this.surgeText = ''
    if (this.days.length >= 2) {
      const n: number = this.days.length
      const todaySum: number = this.days[n - 1].rx + this.days[n - 1].tx
      const yestSum: number = this.days[n - 2].rx + this.days[n - 2].tx
      if (yestSum > 0 && todaySum >= yestSum * 2 && todaySum >= 104857600) {
        this.surgeText = `今日流量 ${this.fmt(todaySum)}，已是昨日 ${(todaySum / yestSum).toFixed(1)} 倍`
      }
    }
  }

  /** 环比文案（与上一个同长度区间对比） */
  compareText(): string {
    if (this.prevTotal <= 0) {
      return '暂无上期数据'
    }
    const cur: number = this.totalRx + this.totalTx
    const diff: number = (cur - this.prevTotal) / this.prevTotal * 100
    const sign: string = diff >= 0 ? '+' : ''
    return `${sign}${diff.toFixed(1)}%`
  }

  /** 环比颜色：涨红跌绿 */
  compareColor(): string {
    if (this.prevTotal <= 0) return this.theme.textTertiary
    const cur: number = this.totalRx + this.totalTx
    return cur > this.prevTotal ? '#E4572E' : '#2FA37A'
  }

  /** 峰值日文案 */
  peakDayText(): string {
    if (this.peakIndex < 0 || this.peakIndex >= this.days.length) {
      return '--'
    }
    const d: DayTraffic = this.days[this.peakIndex]
    return `${this.dayLabel(d.date)} · ${this.fmt(d.rx + d.tx)}`
  }

  /** 峰值时段文案 */
  peakHourText(): string {
    if (this.peakHour < 0) {
      return '暂无数据'
    }
    return `峰值 ${this.peakHour}:00`
  }

  /** 小时柱高度（vp） */
  hourBarHeight(sum: number): number {
    const h: number = (sum / this.maxHourBytes) * 120
    return Math.max(2, h)
  }

  /** 小时标签：每 6 小时标一次，避免拥挤 */
  hourLabel(hour: number): string {
    return hour % 6 === 0 ? `${hour}` : ''
  }

  /** 格式化字节 */
  fmt(v: number): string {
    if (v >= 1073741824) return `${(v / 1073741824).toFixed(2)} GB`
    if (v >= 1048576) return `${(v / 1048576).toFixed(1)} MB`
    if (v >= 1024) return `${(v / 1024).toFixed(0)} KB`
    return `${v} B`
  }

  /** 日期标签（今天/昨天/MM-DD） */
  dayLabel(date: string): string {
    const today: Date = new Date()
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`
    const todayKey: string = `${today.getFullYear()}-${p(today.getMonth() + 1)}-${p(today.getDate())}`
    const y: Date = new Date(today.getTime() - 86400000)
    const yKey: string = `${y.getFullYear()}-${p(y.getMonth() + 1)}-${p(y.getDate())}`
    if (date === todayKey) return '今天'
    if (date === yKey) return '昨天'
    return date.substring(5)
  }

  /** 柱子高度（vp） */
  barHeight(sum: number): number {
    const h: number = (sum / this.maxDayBytes) * 140
    return Math.max(3, h)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.theme.textSecondary)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 4, right: 4, top: 16, bottom: 6 })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text(' 流量统计')
            .fontSize(16)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 12, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          // 流量突增提示（今日 ≥ 昨日 2 倍且超过 100MB）
          if (this.surgeText) {
            Row() {
              Text('⚠️')
                .fontSize(13)
              Text(this.surgeText)
                .fontSize(12)
                .fontColor('#B35A00')
                .layoutWeight(1)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor('rgba(255,168,61,0.14)')
            .border({ width: 0.5, color: 'rgba(255,138,61,0.35)' })
            .margin({ bottom: 10 })
          }

          // 汇总卡片
          Column() {
            Row() {
              Column() {
                Text('总下载')
                  .fontSize(11).fontColor(this.theme.textTertiary)
                Text(this.fmt(this.totalRx))
                  .fontSize(18).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)
              Column() {
                Text('总上传')
                  .fontSize(11).fontColor(this.theme.textTertiary)
                Text(this.fmt(this.totalTx))
                  .fontSize(18).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)
              Column() {
                Text('日均')
                  .fontSize(11).fontColor(this.theme.textTertiary)
                Text(this.fmt((this.totalRx + this.totalTx) / (this.range > 0 ? this.range : 1)))
                  .fontSize(18).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 14, bottom: 8 })

            // 环比 + 峰值日
            Row() {
              Text(`较上 ${this.range} 天`)
                .fontSize(11).fontColor(this.theme.textTertiary)
              Text(this.compareText())
                .fontSize(11).fontColor(this.compareColor()).fontWeight(FontWeight.Medium)
                .margin({ left: 6 })
              Blank()
              Text('峰值日')
                .fontSize(11).fontColor(this.theme.textTertiary)
              Text(this.peakDayText())
                .fontSize(11).fontColor(this.theme.textSecondary)
                .margin({ left: 6 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })

            Divider().color(this.theme.borderGlass)

            // 柱状图（近 7/30 天每日总流量）
            Row() {
              Text('每日流量')
                .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
              Blank()
              Row() {
                Text('近 7 天')
                  .fontSize(11)
                  .fontColor(this.range === 7 ? Color.White : this.theme.textSecondary)
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .borderRadius(10)
                  .backgroundColor(this.range === 7 ? this.theme.primary : this.theme.bgGlassLight)
                  .onClick(() => {
                    this.range = 7
                    this.loadData()
                  })
                Text('近 30 天')
                  .fontSize(11)
                  .fontColor(this.range === 30 ? Color.White : this.theme.textSecondary)
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .borderRadius(10)
                  .backgroundColor(this.range === 30 ? this.theme.primary : this.theme.bgGlassLight)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.range = 30
                    this.loadData()
                  })
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 8 })

            // 柱状图区
            Row() {
              ForEach(this.days, (day: DayTraffic, idx: number) => {
                Column() {
                  Column()
                    .width(this.range === 7 ? 14 : 5)
                    .height(this.barHeight(day.rx + day.tx))
                    .borderRadius(3)
                    .backgroundColor(this.theme.primary)
                    .opacity(day.rx + day.tx > 0 ? 1 : 0.25)
                  Text(this.dayLabel(day.date))
                    .fontSize(8)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 4 })
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.End)
                .height(190)
              }, (day: DayTraffic, idx: number): string => `${this.range}_${day.date}_${idx}`)
            }
            .width('100%')
            .height(190)
            .padding({ left: 8, right: 8 })

            Row() {
              Text('■ 每日总流量（下载+上传）')
                .fontSize(10).fontColor(this.theme.textTertiary)
              Blank()
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 6, bottom: 12 })
          }
          .width('100%')
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(16)
          .clip(true)

          // 今日 24 小时分布（小时粒度留存数据）
          this.sectionTitle('今日 24 小时')
          Column() {
            Row() {
              Text('分时流量')
                .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
              Blank()
              Text(this.peakHourText())
                .fontSize(10).fontColor(this.theme.textTertiary)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 6 })

            Row() {
              ForEach(this.hourly, (item: HourTraffic, idx: number) => {
                Column() {
                  Column()
                    .width(6)
                    .height(this.hourBarHeight(item.rx + item.tx))
                    .borderRadius(3)
                    .backgroundColor(item.hour === this.peakHour ? '#F2A54E' : this.theme.primary)
                    .opacity(item.rx + item.tx > 0 ? 1 : 0.2)
                  Text(this.hourLabel(item.hour))
                    .fontSize(8)
                    .fontColor(this.theme.textTertiary)
                    .margin({ top: 4 })
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.End)
                .height(150)
              }, (item: HourTraffic, idx: number): string => `h_${item.hour}_${idx}`)
            }
            .width('100%')
            .height(150)
            .padding({ left: 8, right: 8, bottom: 8 })
          }
          .width('100%')
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(16)
          .clip(true)

          // 每日明细
          this.sectionTitle('每日明细')
          Column() {
            ForEach(this.days, (day: DayTraffic, idx: number) => {
              Row() {
                Text(this.dayLabel(day.date))
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .width(64)
                Text(`↓ ${this.fmt(day.rx)}`)
                  .fontSize(12)
                  .fontColor(this.theme.primary)
                  .layoutWeight(1)
                Text(`↑ ${this.fmt(day.tx)}`)
                  .fontSize(12)
                  .fontColor(this.theme.success)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 11, bottom: 11 })
              .border({ width: { bottom: idx < this.days.length - 1 ? 0.3 : 0 }, color: this.theme.borderGlass })
            }, (day: DayTraffic, idx: number): string => `${this.range}_d_${day.date}_${idx}`)
          }
          .width('100%')
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(16)
          .clip(true)

          Row().width('100%').height(40)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
