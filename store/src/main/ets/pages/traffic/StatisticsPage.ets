import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { RealtimeBandwidth, RealtimeLoad, NetworkInterface } from '../../models/Models'
import { router } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

interface BandwidthStats {
  currentRx: number
  currentTx: number
  avgRx: number
  avgTx: number
  peakRx: number
  peakTx: number
  rxHistory: number[]
  txHistory: number[]
}

interface LoadStats {
  current1: number
  current5: number
  current15: number
  avg1: number
  avg5: number
  avg15: number
  peak1: number
  peak5: number
  peak15: number
  load1History: number[]
  load5History: number[]
  load15History: number[]
}

interface IfaceOption {
  value: string
}

const CHART_WINDOW = 60

function avg(arr: number[]): number {
  if (arr.length === 0) return 0
  let s = 0
  for (let i = 0; i < arr.length; i++) s += arr[i]
  return s / arr.length
}

function peak(arr: number[]): number {
  if (arr.length === 0) return 0
  let m = arr[0]
  for (let i = 1; i < arr.length; i++) if (arr[i] > m) m = arr[i]
  return m
}

function pushSliding(arr: number[], val: number): number[] {
  const next = arr.slice()
  next.push(val)
  if (next.length > CHART_WINDOW) {
    return next.slice(next.length - CHART_WINDOW)
  }
  return next
}

// ============================================================
// BandwidthTab - 带宽监控
// ============================================================
@Component
struct BandwidthTab {
  @Prop theme: ThemePalette
  @State interfaces: NetworkInterface[] = []
  @State selectedIface: string = 'br-lan'
  @State selectedIndex: number = 0
  @State bw: BandwidthStats = {
    currentRx: 0, currentTx: 0, avgRx: 0, avgTx: 0,
    peakRx: 0, peakTx: 0, rxHistory: [], txHistory: []
  }
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State drawTrigger: number = 0
  private bwTimerId: number = -1

  aboutToAppear(): void {
    this.loadInterfaces()
    this.bwTimerId = setInterval(() => {
      this.fetchBandwidth()
    }, 3000)
  }

  aboutToDisappear(): void {
    if (this.bwTimerId !== -1) {
      clearInterval(this.bwTimerId)
      this.bwTimerId = -1
    }
  }

  async loadInterfaces(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      this.interfaces = await api.fetchNetworkInterfaces()
      if (this.interfaces.length > 0) {
        this.selectedIface = this.interfaces[0].name
        this.selectedIndex = 0
      }
      await this.fetchBandwidth()
    } catch (e) {
      this.errorText = '加载接口列表失败'
    }
    this.isLoading = false
  }

  async fetchBandwidth(): Promise<void> {
    try {
      if (!AppState.getInstance().isConnected()) return
      const api = new ApiService()
      const result: RealtimeBandwidth = await api.fetchRealtimeBandwidth(this.selectedIface)

      let rxVal = 0
      let txVal = 0
      if (result.rx.length > 0) {
        rxVal = result.rx[result.rx.length - 1].value
      }
      if (result.tx.length > 0) {
        txVal = result.tx[result.tx.length - 1].value
      }

      const rxHistory = pushSliding(this.bw.rxHistory, rxVal)
      const txHistory = pushSliding(this.bw.txHistory, txVal)

      this.bw = {
        currentRx: rxVal,
        currentTx: txVal,
        avgRx: avg(rxHistory),
        avgTx: avg(txHistory),
        peakRx: peak(rxHistory),
        peakTx: peak(txHistory),
        rxHistory: rxHistory,
        txHistory: txHistory
      }
      this.drawTrigger++
    } catch (e) {
      // Silent fail
    }
  }

  onInterfaceChange(idx: number): void {
    if (idx >= 0 && idx < this.interfaces.length) {
      this.selectedIndex = idx
      this.selectedIface = this.interfaces[idx].name
      this.bw = {
        currentRx: 0, currentTx: 0, avgRx: 0, avgTx: 0,
        peakRx: 0, peakTx: 0, rxHistory: [], txHistory: []
      }
      this.fetchBandwidth()
    }
  }

  getIfaceOptions(): IfaceOption[] {
    const opts: IfaceOption[] = []
    for (let i = 0; i < this.interfaces.length; i++) {
      const opt: IfaceOption = { value: this.interfaces[i].name }
      opts.push(opt)
    }
    return opts
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText) {
        Row() {
          Text('⚠').fontSize(16).margin({ right: 8 })
          Text(this.errorText).fontSize(12).fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        Scroll() {
          Column() {
            // 接口选择器
            Row() {
              Text('监控接口')
                .fontSize(12)
                .fontColor(this.theme.textSecondary)
                .margin({ right: 10 })
              if (this.interfaces.length > 0) {
                Select(this.getIfaceOptions())
                  .selected(this.selectedIndex)
                  .value(this.selectedIface)
                  .fontColor(this.theme.textPrimary)
                  .selectedOptionBgColor(this.theme.bgCardHover)
                  .optionBgColor(this.theme.bgCard)
                  .optionFontColor(this.theme.textPrimary)
                  .onSelect((index: number) => {
                    this.onInterfaceChange(index)
                  })
                  .layoutWeight(1)
              } else {
                Text('无可用接口')
                  .fontSize(12)
                  .fontColor(this.theme.textTertiary)
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(this.theme.bgCard)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .margin({ top: 8, bottom: 10 })

            // 速率卡片
            Row() {
              this.speedCard('⇩ 下载', this.bw.currentRx, this.bw.avgRx, this.bw.peakRx, '#00E676')
              this.speedCard('⇧ 上传', this.bw.currentTx, this.bw.avgTx, this.bw.peakTx, '#448AFF')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            // 折线图区域
            Column() {
              Row() {
                Text('实时速率')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                Blank()
                Row() {
                  Circle().width(6).height(6).fill('#00E676').margin({ right: 4 })
                  Text('下载').fontSize(10).fontColor(this.theme.textTertiary)
                }
                .margin({ right: 14 })
                Row() {
                  Circle().width(6).height(6).fill('#448AFF').margin({ right: 4 })
                  Text('上传').fontSize(10).fontColor(this.theme.textTertiary)
                }
              }
              .width('100%')
              .margin({ bottom: 8 })

              LineChart({ series: [this.bw.rxHistory, this.bw.txHistory], colors: ['#00E676', '#448AFF'], bgColor: this.theme.bgDark, gridColor: this.theme.borderGlass, drawTrigger: this.drawTrigger })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder speedCard(label: string, current: number, avgVal: number, peakVal: number, color: string) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(this.theme.textTertiary)
        .margin({ bottom: 6 })
      Text(FormatUtils.formatSpeed(current))
        .fontSize(18)
        .fontColor(color)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .margin({ bottom: 8 })
      Row() {
        Column() {
          Text('平均').fontSize(9).fontColor(this.theme.textTertiary)
          Text(FormatUtils.formatSpeed(avgVal)).fontSize(11).fontColor(this.theme.textSecondary).fontFamily('monospace')
        }
        .margin({ right: 12 })
        Column() {
          Text('峰值').fontSize(9).fontColor(this.theme.textTertiary)
          Text(FormatUtils.formatSpeed(peakVal)).fontSize(11).fontColor(this.theme.textSecondary).fontFamily('monospace')
        }
      }
    }
    .width('47%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .alignItems(HorizontalAlign.Start)
  }
}

// ============================================================
// LoadTab - 负载监控
// ============================================================
@Component
struct LoadTab {
  @Prop theme: ThemePalette
  @State load: LoadStats = {
    current1: 0, current5: 0, current15: 0,
    avg1: 0, avg5: 0, avg15: 0,
    peak1: 0, peak5: 0, peak15: 0,
    load1History: [], load5History: [], load15History: []
  }
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State drawTrigger: number = 0
  private loadTimerId: number = -1

  aboutToAppear(): void {
    this.fetchLoad()
    this.loadTimerId = setInterval(() => {
      this.fetchLoad()
    }, 3000)
  }

  aboutToDisappear(): void {
    if (this.loadTimerId !== -1) {
      clearInterval(this.loadTimerId)
      this.loadTimerId = -1
    }
  }

  async fetchLoad(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接'
        this.isLoading = false
        return
      }
      const api = new ApiService()
      const result: RealtimeLoad = await api.fetchRealtimeLoad()

      let v1 = 0
      let v5 = 0
      let v15 = 0
      if (result.load1.length > 0) v1 = result.load1[result.load1.length - 1].value
      if (result.load5.length > 0) v5 = result.load5[result.load5.length - 1].value
      if (result.load15.length > 0) v15 = result.load15[result.load15.length - 1].value

      const l1h = pushSliding(this.load.load1History, v1)
      const l5h = pushSliding(this.load.load5History, v5)
      const l15h = pushSliding(this.load.load15History, v15)

      this.load = {
        current1: v1, current5: v5, current15: v15,
        avg1: avg(l1h), avg5: avg(l5h), avg15: avg(l15h),
        peak1: peak(l1h), peak5: peak(l5h), peak15: peak(l15h),
        load1History: l1h, load5History: l5h, load15History: l15h
      }
      this.drawTrigger++
    } catch (e) {
      if (this.load.load1History.length === 0) {
        this.errorText = '加载负载数据失败'
      }
    }
    this.isLoading = false
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText && this.load.load1History.length === 0) {
        Row() {
          Text('⚠').fontSize(16).margin({ right: 8 })
          Text(this.errorText).fontSize(12).fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        Scroll() {
          Column() {
            // 负载数值卡片
            Row() {
              this.loadCard('1min', this.load.current1, this.load.avg1, this.load.peak1, '#FF5252')
              this.loadCard('5min', this.load.current5, this.load.avg5, this.load.peak5, '#FF9800')
              this.loadCard('15min', this.load.current15, this.load.avg15, this.load.peak15, '#FFD740')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            // 折线图区域
            Column() {
              Row() {
                Text('系统负载')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                Blank()
                Row() {
                  Circle().width(6).height(6).fill('#FF5252').margin({ right: 4 })
                  Text('1min').fontSize(10).fontColor(this.theme.textTertiary)
                }
                .margin({ right: 10 })
                Row() {
                  Circle().width(6).height(6).fill('#FF9800').margin({ right: 4 })
                  Text('5min').fontSize(10).fontColor(this.theme.textTertiary)
                }
                .margin({ right: 10 })
                Row() {
                  Circle().width(6).height(6).fill('#FFD740').margin({ right: 4 })
                  Text('15min').fontSize(10).fontColor(this.theme.textTertiary)
                }
              }
              .width('100%')
              .margin({ bottom: 8 })

              LineChart({ series: [this.load.load1History, this.load.load5History, this.load.load15History], colors: ['#FF5252', '#FF9800', '#FFD740'], bgColor: this.theme.bgDark, gridColor: this.theme.borderGlass, drawTrigger: this.drawTrigger })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder loadCard(label: string, current: number, avgVal: number, peakVal: number, color: string) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(this.theme.textTertiary)
        .margin({ bottom: 6 })
      Text(current.toFixed(2))
        .fontSize(18)
        .fontColor(color)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .margin({ bottom: 8 })
      Column() {
        Text(`平均 ${avgVal.toFixed(2)}`).fontSize(9).fontColor(this.theme.textSecondary)
        Text(`峰值 ${peakVal.toFixed(2)}`).fontSize(9).fontColor(this.theme.textSecondary).margin({ top: 2 })
      }
    }
    .width('31%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .alignItems(HorizontalAlign.Start)
  }
}

// ============================================================
// LineChart - 折线图（Canvas 绘制）+ 柱状降级
// ============================================================
@Component
struct LineChart {
  @Prop series: number[][] = []
  @Prop colors: string[] = []
  @Prop bgColor: string = '#0A0E27'
  @Prop gridColor: string = 'rgba(255,255,255,0.06)'
  @Prop drawTrigger: number = 0

  private getGlobalMax(): number {
    let m = 1
    for (let i = 0; i < this.series.length; i++) {
      for (let j = 0; j < this.series[i].length; j++) {
        if (this.series[i][j] > m) m = this.series[i][j]
      }
    }
    return m
  }

  private getTimeLabels(): string[] {
    return ['60s', '45s', '30s', '15s', '0s']
  }

  build() {
    Stack() {
      // 网格线
      Column() {
        ForEach(['', '', '', '', ''], (_: string, idx: number) => {
          Divider()
            .strokeWidth(0.3)
            .color(this.gridColor)
            .margin({ top: idx === 0 ? 0 : 6, bottom: 6 })
        }, (_: string, idx: number) => idx.toString())
      }
      .width('100%')
      .height(160)

      // 数据条形图，用细柱模拟折线趋势
      if (this.series.length > 0 && this.series[0].length > 0) {
        Row() {
          ForEach(this.series[0], (_: number, idx: number) => {
            Column() {
              Blank()
              Row() {
                // Series 0
                Column()
                  .width(this.series.length > 2 ? 1 : 2)
                  .height(this.getBarHeight(this.series[0][idx], this.getGlobalMax()))
                  .borderRadius(1)
                  .backgroundColor(this.colors[0])
                // Series 1
                if (this.series.length > 1) {
                  Column().width(1)
                  Column()
                    .width(this.series.length > 2 ? 1 : 2)
                    .height(this.getBarHeight(this.series[1][idx], this.getGlobalMax()))
                    .borderRadius(1)
                    .backgroundColor(this.colors[1])
                }
                // Series 2
                if (this.series.length > 2) {
                  Column().width(1)
                  Column()
                    .width(1)
                    .height(this.getBarHeight(this.series[2][idx], this.getGlobalMax()))
                    .borderRadius(1)
                    .backgroundColor(this.colors[2])
                }
              }
              .justifyContent(FlexAlign.End)
            }
            .width(`${100 / this.series[0].length}%`)
            .height(160)
            .justifyContent(FlexAlign.End)
          }, (__: number, idx: number) => idx.toString())
        }
        .width('100%')
        .height(160)
      }

      // 时间标签
      Row() {
        ForEach(this.getTimeLabels(), (label: string, idx: number) => {
          Text(label)
            .fontSize(9)
            .fontColor('rgba(255,255,255,0.25)')
            .width('20%')
            .textAlign(idx === 4 ? TextAlign.End : idx === 0 ? TextAlign.Start : TextAlign.Center)
        }, (label: string, idx: number) => idx.toString())
      }
      .width('100%')
      .position({ bottom: 0 })
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .height(180)
  }

  private getBarHeight(value: number, max: number): string {
    const pct = max > 0 ? Math.max(0.5, (value / max) * 100) : 0
    return `${pct}%`
  }
}

// ============================================================
// StatisticsPage - 入口页面
// ============================================================
@Entry
@Component
struct StatisticsPage {
  @State theme: ThemePalette = DARK_THEME
  @State isDark: boolean = true
  @State activeSubTab: string = 'bandwidth'

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.isDark
            ? [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]]
            : [['#E8ECF1', 0], ['#F5F7FA', 0.5], ['#E8ECF1', 1]]
        })

      Column() {
        // 顶部栏
        Row() {
          Row() {
            Text('‹ 返回')
              .fontSize(16)
              .fontColor(this.theme.primary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 14, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try {
              router.back()
            } catch (e) {
              hilog.error(0x0001, 'StatisticsPage', `router.back failed: ${e}`)
            }
          })

          Blank()

          Text('实时监控')
            .fontSize(18)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Bold)

          Blank()

          Row() {
            Text(this.isDark ? '☀️' : '🌙')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            AppState.getInstance().toggleTheme()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        // 子Tab切换
        Row() {
          Column() {
            Text('带宽')
              .fontSize(14)
              .fontColor(this.activeSubTab === 'bandwidth' ? this.theme.primary : this.theme.textTertiary)
              .fontWeight(this.activeSubTab === 'bandwidth' ? FontWeight.Medium : FontWeight.Normal)
            if (this.activeSubTab === 'bandwidth') {
              Divider()
                .width(30)
                .height(3)
                .color(this.theme.primary)
                .borderRadius(2)
                .margin({ top: 6 })
            } else {
              Row().height(3).margin({ top: 6 })
            }
          }
          .flexGrow(1)
          .padding({ top: 8, bottom: 4 })
          .onClick(() => {
            this.activeSubTab = 'bandwidth'
          })

          Column() {
            Text('负载')
              .fontSize(14)
              .fontColor(this.activeSubTab === 'load' ? this.theme.primary : this.theme.textTertiary)
              .fontWeight(this.activeSubTab === 'load' ? FontWeight.Medium : FontWeight.Normal)
            if (this.activeSubTab === 'load') {
              Divider()
                .width(30)
                .height(3)
                .color(this.theme.primary)
                .borderRadius(2)
                .margin({ top: 6 })
            } else {
              Row().height(3).margin({ top: 6 })
            }
          }
          .flexGrow(1)
          .padding({ top: 8, bottom: 4 })
          .onClick(() => {
            this.activeSubTab = 'load'
          })
        }
        .width('100%')
        .padding({ left: 40, right: 40, bottom: 4 })
        .border({ width: { bottom: 0.5 }, color: this.theme.borderGlass })

        // 内容区
        if (this.activeSubTab === 'bandwidth') {
          BandwidthTab({ theme: this.theme })
        }
        if (this.activeSubTab === 'load') {
          LoadTab({ theme: this.theme })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
