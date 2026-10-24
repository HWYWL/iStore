/**
 * TrafficReportPage - 流量统计（周报/月报）
 * 展示近 7 天 / 30 天每日下载/上传流量柱状图与汇总
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { TrafficStatStore, DayTraffic } from '../../common/store/TrafficStatStore'
import { window } from '@kit.ArkUI'

@Entry
@Component
struct TrafficReportPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State range: number = 7  // 7 天 / 30 天
  @State days: DayTraffic[] = []
  @State totalRx: number = 0
  @State totalTx: number = 0
  @State maxDayBytes: number = 1
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
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 加载流量数据 */
  loadData(): void {
    this.days = this.store.getDays(this.range)
    let rx: number = 0
    let tx: number = 0
    let max: number = 1
    for (let i = 0; i < this.days.length; i++) {
      rx += this.days[i].rx
      tx += this.days[i].tx
      const sum: number = this.days[i].rx + this.days[i].tx
      if (sum > max) max = sum
    }
    this.totalRx = rx
    this.totalTx = tx
    this.maxDayBytes = max
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
          this.getUIContext().getRouter().back()
        })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
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
            .padding({ top: 14, bottom: 14 })

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
