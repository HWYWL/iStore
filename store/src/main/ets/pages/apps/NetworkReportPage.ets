/**
 * AI 网络周报
 * 汇总近 7 天流量 + 设备活跃，生成趣味周报（本地规则引擎拼装）
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { TrafficStatStore, DayTraffic, HourTraffic } from '../../common/store/TrafficStatStore'
import { FunStore } from '../../common/store/FunStore'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct NetworkReportPageRoute {
  build() {
    Column() {
      NetworkReportPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NetworkReportPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State generating: boolean = false
  @State generated: boolean = false
  @State totalGb: number = 0
  @State totalText: string = '0 B'
  @State peakDay: string = ''
  @State peakText: string = '--'
  @State deviceCount: number = 0
  @State topDevices: string[] = []
  @State comment: string = ''
  @State weekCompare: string = '--'   // 较上周
  @State activeHour: string = '--'    // 近 7 天最活跃时段
  private api: ApiService = new ApiService()
  private traffic: TrafficStatStore = TrafficStatStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
  }

  /** 字节 → 自适应大小（≥1GB 用 GB，否则 MB / KB，避免小流量显示成 0.0） */
  private fmtSize(b: number): string {
    if (b >= 1073741824) return (b / 1073741824).toFixed(1) + ' GB'
    if (b >= 1048576) return (b / 1048576).toFixed(1) + ' MB'
    if (b >= 1024) return (b / 1024).toFixed(0) + ' KB'
    return '0 B'
  }

  async generate(): Promise<void> {
    if (this.generating) return
    this.generating = true
    this.generated = false
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        await this.traffic.init(hostCtx as Context)
      }
      // 14 天流量（升序，末尾是今天）：前 7 天是上一周，后 7 天是本周
      const allDays: DayTraffic[] = this.traffic.getDays(14)
      const prevDays: DayTraffic[] = allDays.slice(0, 7)
      const days: DayTraffic[] = allDays.slice(7)
      // 情感触点：数据考古学家成就（有 3 天前的历史数据）
      if (!FunStore.getInstance().isAchieved('archaeologist')) {
        let hasOld: boolean = false
        for (let i = 3; i < days.length; i++) {
          if (days[i].rx > 0 || days[i].tx > 0) {
            hasOld = true
            break
          }
        }
        if (hasOld) {
          FunStore.getInstance().setAchieved('archaeologist')
        }
      }
      let total: number = 0
      let peak: number = 0
      let peakDate: string = ''
      for (let i = 0; i < days.length; i++) {
        const sum: number = days[i].rx + days[i].tx
        total += sum
        if (sum > peak) {
          peak = sum
          peakDate = days[i].date
        }
      }
      this.totalGb = total / 1073741824
      this.totalText = this.fmtSize(total)
      this.peakText = peak > 0 ? this.fmtSize(peak) : '--'
      this.peakDay = peakDate

      // 环比：与上周同期对比
      let prevTotal: number = 0
      for (let i = 0; i < prevDays.length; i++) {
        prevTotal += prevDays[i].rx + prevDays[i].tx
      }
      if (prevTotal > 0) {
        const diff: number = (total - prevTotal) / prevTotal * 100
        this.weekCompare = `${diff >= 0 ? '+' : ''}${diff.toFixed(1)}%`
      } else {
        this.weekCompare = '上周无数据'
      }

      // 近 7 天最活跃时段（小时桶累加）
      const trend: HourTraffic[] = this.traffic.getHourlyTrend(7)
      let ph: number = -1
      let pb: number = 0
      for (let h = 0; h < trend.length; h++) {
        const s: number = trend[h].rx + trend[h].tx
        if (s > pb) {
          pb = s
          ph = h
        }
      }
      this.activeHour = ph >= 0 ? `${ph}:00-${ph + 1}:00` : '--'
      // 在线设备
      try {
        const devs: ConnectedDevice[] = await this.api.fetchConnectedDevices()
        this.deviceCount = devs.length
        const names: string[] = []
        for (let i = 0; i < devs.length && i < 5; i++) {
          names.push(devs[i].hostname || devs[i].vendor || devs[i].ip)
        }
        this.topDevices = names
      } catch (e) {
        this.deviceCount = 0
      }
      // 趣味点评
      this.comment = this.makeComment(this.totalGb, this.deviceCount)
      this.generated = true
    } catch (e) {
      hilog.error(0x0001, 'NetReport', `generate err: ${String(e)}`)
    }
    this.generating = false
  }

  private makeComment(totalGb: number, devs: number): string {
    if (totalGb >= 500) {
      return '本周流量爆表 🔥 你家网络是个小型机房吧？建议查查有没有人偷偷开下载。'
    }
    if (totalGb >= 200) {
      return '本周相当活跃 📊 视频、游戏、下载三开，路由器表示「有点累但还能扛」。'
    }
    if (totalGb >= 50) {
      return '本周中规中矩 ✅ 网络用得不重，路由器很欣慰。'
    }
    if (totalGb > 0) {
      return '本周很养生 🍵 网络用得少，适合早睡早起（但夜猫子成就可能拿不到了）。'
    }
    if (devs === 0) {
      return '暂无流量数据 📭 记得多打开 App 让流量统计累积起来。'
    }
    return '本周流量数据还没攒够 📭 多上网多统计，下周再来看看。'
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('AI 网络周报')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          // 报告卡
          if (this.generated) {
            Column() {
              Row() {
                SymbolGlyph($r('sys.symbol.circle_grid_2x2')).fontSize(16).fontColor(['#3B82F6'])
                Text(' 本周网络周报')
                  .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              }
              Text('近 7 天（自动统计）')
                .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 2 })

              // 总流量
              Row() {
                Text(this.totalText)
                  .fontSize(30).fontColor('#FF8A3D').fontWeight(FontWeight.Bold).fontFamily('monospace')
                Text('总流量')
                  .fontSize(11).fontColor(this.theme.textTertiary).margin({ left: 8 })
              }
              .width('100%').justifyContent(FlexAlign.Center).margin({ top: 16 })

              // 峰值日 / 活跃时段 / 环比
              Column() {
                Text('最忙的一天')
                  .fontSize(11).fontColor(this.theme.textTertiary)
                Text(this.peakDay ? `${this.peakDay}（${this.peakText}）` : '--')
                  .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  .margin({ top: 4 })
                Row() {
                  Text('最活跃时段')
                    .fontSize(11).fontColor(this.theme.textTertiary)
                  Text(this.activeHour)
                    .fontSize(11).fontColor(this.theme.textSecondary).margin({ left: 6 })
                  Text('·')
                    .fontSize(11).fontColor(this.theme.textTertiary).margin({ left: 8, right: 8 })
                  Text('较上周')
                    .fontSize(11).fontColor(this.theme.textTertiary)
                  Text(this.weekCompare)
                    .fontSize(11).fontColor(this.theme.textSecondary).margin({ left: 6 })
                }
                .margin({ top: 8 })
              }
              .width('100%').padding(12).borderRadius(12)
              .backgroundColor('rgba(255,138,61,0.08)')
              .margin({ top: 12 })
              .alignItems(HorizontalAlign.Center)

              // 在线设备
              Column() {
                Text(`同时在线设备峰值约 ${this.deviceCount} 台`)
                  .fontSize(12).fontColor(this.theme.textSecondary)
                if (this.topDevices.length > 0) {
                  Text(this.topDevices.join(' · '))
                    .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 4 })
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%').margin({ top: 12 })
              .alignItems(HorizontalAlign.Center)

              // 趣味点评
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.AI_help_write')).fontSize(12).fontColor([this.theme.primary])
                  Text(' AI 点评')
                    .fontSize(11).fontColor(this.theme.primary)
                }
                Text(this.comment)
                  .fontSize(13).fontColor(this.theme.textPrimary).lineHeight(20).margin({ top: 6 })
              }
              .width('100%').padding(14).borderRadius(14)
              .border({ width: 0.5, color: 'rgba(255,138,61,0.4)' })
              .margin({ top: 14 })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%').padding(20).borderRadius(22).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Start)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
                .fontSize(44)
                .fontColor(['#94A3B8'])
              Text('生成你的网络周报')
                .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                .margin({ top: 10 })
              Text('汇总 7 天流量与设备活跃，AI 给你点评')
                .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 4 })
            }
            .width('100%').padding(30).borderRadius(22).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Center)
          }

          Row() {
            Text(this.generating ? '生成中...' : (this.generated ? '重新生成' : '生成周报'))
              .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
          .width('100%').height(48).borderRadius(24)
          .backgroundColor(this.generating ? '#C9A98A' : '#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 20 })
          .onClick(() => { this.generate() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
