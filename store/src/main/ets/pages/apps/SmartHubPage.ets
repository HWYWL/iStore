/**
 * SmartHubPage — 智能网络管家中心（v3 按小花创意设计稿重写）
 * 设计规范：prototype-smarthub.html / DesignSystemManifest-智能管家.md
 * 动画：曲线 stagger 生长 / 峰值环 sweep / 扫描光 / 状态灯脉冲 / 星空闪烁 / 时间线滑入 / 健康环滚动
 */
import { AppState } from '../../common/store/AppState'
import { ThemePalette } from '../../common/theme/ThemeColors'
import { SmartGuardStore, HourSample, NightEvent, DaySummary } from '../../common/store/SmartGuardStore'
import { ApiClient } from '../../api/ApiClient'
import { AiHelper } from '../../common/ai/AiHelper'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { promptAction } from '@kit.ArkUI'
import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

// 设计 Token（小花创意 DesignSystemManifest）
const NIGHT_1: string = '#3A3F6E'
const NIGHT_2: string = '#5C5284'
const TRACK: string = '#F0EBE0'
const HEALTH: string = '#2FBFA8'
const WARN_DEEP: string = '#B7791F'
const DANGER_DEEP: string = '#C0392B'

const TABS: string[] = ['预言家', '侦探', '值班员', '一句话', '周报']
const TAB_ICONS: Resource[] = [
  $r('sys.symbol.wand_and_stars'),
  $r('sys.symbol.magnifyingglass'),
  $r('sys.symbol.moon'),
  $r('sys.symbol.bolt'),
  $r('sys.symbol.circle_grid_2x2')
]

interface Forecast {
  peakHour: number
  peakLevel: number
  advice: string
  curve: number[]
}

interface DetectItem {
  name: string
  status: string
  detail: string
}

@Entry
@Component
export struct SmartHubPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State topSafeArea: number = 44
  @State tab: number = 0

  // 预言家
  @State forecast: Forecast = { peakHour: 20, peakLevel: 0, advice: '正在学习网络规律…', curve: [] }
  @State oracleLoading: boolean = false
  @State ringAnim: boolean = false
  @State ringVal: number = 0
  // 侦探
  @State detectItems: DetectItem[] = []
  @State detectRunning: boolean = false
  @State detectDone: boolean = false
  // 值班员
  @State nightEvents: NightEvent[] = []
  @State nightDate: string = ''
  @State starPhase: boolean = false
  // 一句话
  @State commandText: string = ''
  @State cmdResult: string = ''
  @State cmdBusy: boolean = false
  // 周报
  @State days: DaySummary[] = []
  @State weekScore: number = 0
  @State scoreAnim: boolean = false
  @State scoreNum: number = 0
  @State weekInsight: string = ''
  @State weekBarsAnim: boolean = false

  private deviceId: string = ''
  private store: SmartGuardStore = SmartGuardStore.getInstance()
  private contentScroller: Scroller = new Scroller()
  private sampleTimer: number = -1
  private scoreTimer: number = -1

  aboutToAppear(): void {
    // 进入页面后回到顶部（避免从中间开始显示）
    setTimeout(() => {
      this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 })
    }, 200)
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.store.init(hostCtx)
      const dev = AppState.getInstance().getActiveDevice()
      this.deviceId = dev ? dev.id : ''
      this.store.setDevice(this.deviceId)
      this.initAll()
    }
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) {
        window.getLastWindow(ctx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  aboutToDisappear(): void {
    if (this.sampleTimer >= 0) {
      clearInterval(this.sampleTimer)
      this.sampleTimer = -1
    }
    if (this.scoreTimer >= 0) {
      clearInterval(this.scoreTimer)
      this.scoreTimer = -1
    }
  }

  async initAll(): Promise<void> {
    await this.collectSample()
    this.sampleTimer = setInterval(() => { this.collectSample() }, 60000)
    await this.runOracle()
    await this.loadNight()
    await this.loadWeek()
  }

  async collectSample(): Promise<void> {
    if (!this.deviceId) return
    try {
      const api = ApiClient.getInstance()
      if (!api.getConnected()) return
      const now: Date = new Date()
      const traffic: number[] = await api.getWanTrafficBytes()
      let devCount: number = 0
      try {
        const st: Object = await api.getNetworkDeviceStats('')
        const obj: Record<string, Object> = st as Record<string, Object>
        devCount = Number(obj['count'] || 0)
      } catch (e) {}
      const s: HourSample = { hour: now.getHours(), rx: traffic[0] || 0, tx: traffic[1] || 0, devices: devCount }
      await this.store.addSample(s)
    } catch (e) {
      hilog.error(0x0001, 'SmartHub', `collectSample err: ${String(e)}`)
    }
  }

  async runOracle(): Promise<void> {
    this.oracleLoading = true
    try {
      const samples: HourSample[] = await this.store.getSamples()
      if (samples.length < 6) {
        this.forecast = { peakHour: 20, peakLevel: 0, advice: '数据积累中，再等几小时就能预测啦', curve: [] }
        return
      }
      const hourTotal: number[] = new Array<number>(24).fill(0)
      const hourCnt: number[] = new Array<number>(24).fill(0)
      for (let i = 0; i < samples.length; i++) {
        const s: HourSample = samples[i]
        hourTotal[s.hour] += (s.rx + s.tx)
        hourCnt[s.hour] += 1
      }
      const curve: number[] = new Array<number>(24).fill(0)
      let maxVal: number = 0
      for (let h = 0; h < 24; h++) {
        if (hourCnt[h] > 0) {
          curve[h] = hourTotal[h] / hourCnt[h]
          if (curve[h] > maxVal) maxVal = curve[h]
        }
      }
      for (let h = 0; h < 24; h++) {
        if (maxVal > 0) curve[h] = Math.min(100, Math.round(curve[h] / maxVal * 100))
      }
      const nowHour: number = new Date().getHours()
      let peak: number = 0
      let peakLevel: number = 0
      for (let h = 0; h < 24; h++) {
        if (curve[h] > peakLevel) {
          peakLevel = curve[h]
          peak = h
        }
      }
      let advice: string = ''
      if (peakLevel >= 80) {
        advice = `预测 ${peak}:00 前后网络较忙，建议避开大文件下载`
      } else if (peakLevel >= 55) {
        advice = `预测 ${peak}:00 前后有小高峰，可正常使用`
      } else {
        advice = '今天网络预计很轻松，放心用！'
      }
      if (peak <= nowHour) advice = '峰值时段已过，当前网络预计平稳'
      this.forecast = { peakHour: peak, peakLevel: peakLevel, advice: advice, curve: curve }
      // 触发环 sweep 动画
      this.ringVal = 0
      this.ringAnim = false
      setTimeout(() => {
        this.ringVal = peakLevel
        this.ringAnim = true
      }, 50)
    } catch (e) {
      hilog.error(0x0001, 'SmartHub', `oracle err: ${String(e)}`)
    } finally {
      this.oracleLoading = false
    }
  }

  async runDetective(): Promise<void> {
    this.detectRunning = true
    this.detectDone = false
    this.detectItems = []
    const api = ApiClient.getInstance()
    this.detectItems.push({ name: '网关连通性', status: 'running', detail: '检测中…' })
    const gateways: string[] = ['192.168.1.1', '192.168.200.1']
    let gwOk: boolean = false
    for (let i = 0; i < gateways.length; i++) {
      if (await this.ping(gateways[i])) {
        gwOk = true
        break
      }
    }
    this.detectItems[0] = { name: '网关连通性', status: gwOk ? 'ok' : 'fail', detail: gwOk ? '内网正常' : '网关不可达！检查网线' }
    this.detectItems.push({ name: '外网连通性', status: 'running', detail: '检测中…' })
    const extOk: boolean = await this.ping('119.29.29.29')
    this.detectItems[1] = { name: '外网连通性', status: extOk ? 'ok' : 'fail', detail: extOk ? '公网可达' : '外网断开，联系运营商' }
    this.detectItems.push({ name: 'DNS 解析', status: 'running', detail: '检测中…' })
    const dnsOk: boolean = await this.httpProbe()
    this.detectItems[2] = { name: 'DNS 解析', status: dnsOk ? 'ok' : 'fail', detail: dnsOk ? '域名解析正常' : 'DNS 异常，尝试 119.29.29.29' }
    this.detectItems.push({ name: 'WAN 流量', status: 'running', detail: '检测中…' })
    let wanOk: boolean = false
    try {
      const t: number[] = await api.getWanTrafficBytes()
      wanOk = (t[0] > 0 || t[1] > 0)
    } catch (e) {}
    this.detectItems[3] = { name: 'WAN 流量', status: wanOk ? 'ok' : 'warn', detail: wanOk ? '有流量流动' : '无流量，可能闲置或故障' }
    this.detectDone = true
    this.detectRunning = false
  }

  async ping(host: string): Promise<boolean> {
    const req = http.createHttp()
    try {
      const resp = await req.request(`http://${host}/`, {
        method: http.RequestMethod.HEAD,
        connectTimeout: 3000,
        readTimeout: 3000
      })
      return resp.responseCode >= 0
    } catch (e) {
      return false
    } finally {
      req.destroy()
    }
  }

  async httpProbe(): Promise<boolean> {
    const req = http.createHttp()
    try {
      const resp = await req.request('http://www.baidu.com/', {
        method: http.RequestMethod.HEAD,
        connectTimeout: 4000,
        readTimeout: 4000
      })
      return resp.responseCode >= 0
    } catch (e) {
      return false
    } finally {
      req.destroy()
    }
  }

  async loadNight(): Promise<void> {
    try {
      const events: NightEvent[] = await this.store.getNightEvents()
      const lastDate: string = await this.store.getLastNightDate()
      const today: string = this.dateStr()
      if (lastDate !== today) {
        const samples: HourSample[] = await this.store.getSamples()
        const night: NightEvent[] = []
        let nightTraffic: number = 0
        let nightDevices: number = 0
        for (let i = 0; i < samples.length; i++) {
          const s: HourSample = samples[i]
          if (s.hour >= 22 || s.hour <= 5) {
            nightTraffic += (s.rx + s.tx)
            if (s.devices > nightDevices) nightDevices = s.devices
          }
        }
        if (nightTraffic > 0) {
          night.push({ time: '夜间', type: 'summary', text: `夜间总流量 ${this.fmtBytes(nightTraffic)}，最多 ${nightDevices} 台设备在线` })
        }
        if (nightDevices >= 1 && nightDevices <= 2) {
          night.push({ time: '深夜', type: 'offline', text: '深夜只有零星设备在线，网络安静' })
        }
        if (night.length === 0) {
          night.push({ time: '夜间', type: 'summary', text: '没有异常事件，路由器睡了个好觉' })
        }
        await this.store.saveNightEvents(night)
        await this.store.saveLastNightDate(today)
        this.nightEvents = night
        this.nightDate = today
      } else {
        this.nightEvents = events
        this.nightDate = lastDate
      }
      // 星空闪烁
      setTimeout(() => { this.starPhase = true }, 100)
    } catch (e) {
      hilog.error(0x0001, 'SmartHub', `night err: ${String(e)}`)
    }
  }

  dateStr(): string {
    const d: Date = new Date()
    return `${d.getMonth() + 1}-${d.getDate()}`
  }

  async runCommand(): Promise<void> {
    const cmd: string = this.commandText.trim()
    if (!cmd || this.cmdBusy) return
    this.cmdBusy = true
    this.cmdResult = ''
    try {
      const api = ApiClient.getInstance()
      if (cmd.includes('重启')) {
        promptAction.showDialog({
          title: '重启路由器',
          message: '确定要重启吗？所有设备会短暂断网（约 1-2 分钟）。',
          buttons: [{ text: '取消', color: '#8A8378' }, { text: '重启', color: '#FF8A3D' }]
        }).then(() => {
          api.reboot().then((ok: boolean) => {
            this.cmdResult = ok ? '✅ 重启指令已下发，路由器正在重启…' : '❌ 重启失败'
          })
        }).catch(() => {})
      } else if (cmd.includes('在线') || cmd.includes('谁在') || cmd.includes('设备')) {
        const ans: string = await AiHelper.ask(`列出当前在线设备，用简短中文回答`)
        this.cmdResult = ans
      } else if (cmd.includes('流量') || cmd.includes('多少')) {
        const t: number[] = await api.getWanTrafficBytes()
        this.cmdResult = `📊 WAN 口累计：下载 ${this.fmtBytes(t[0])} / 上传 ${this.fmtBytes(t[1])}`
      } else if (cmd.includes('限速') || cmd.includes('断网') || cmd.includes('拉黑')) {
        this.cmdResult = '⚠️ 限速/拉黑设备需要指定设备（如"限速电视"）。此操作请在设备列表中操作。'
      } else {
        const ans: string = await AiHelper.ask(cmd)
        this.cmdResult = ans
      }
    } catch (e) {
      this.cmdResult = `执行出错：${String(e)}`
    } finally {
      this.cmdBusy = false
    }
  }

  async loadWeek(): Promise<void> {
    try {
      const days: DaySummary[] = await this.store.getDaySummaries()
      this.days = days
      if (days.length === 0) {
        this.weekScore = 0
        this.weekInsight = '数据积累中，多使用几天就能生成周报了'
        return
      }
      let score: number = 90
      let totalRx: number = 0
      for (let i = 0; i < days.length; i++) {
        totalRx += days[i].rx
        score -= days[i].anomalyCount * 3
      }
      if (score < 40) score = 40
      this.weekScore = score
      const gb: number = totalRx / 1024 / 1024 / 1024
      this.weekInsight = `近 ${days.length} 天累计下载 ${gb.toFixed(1)}GB，网络状态${score >= 80 ? '良好' : score >= 60 ? '一般' : '需关注'}`
      this.playScoreAnim(score)
    } catch (e) {
      hilog.error(0x0001, 'SmartHub', `week err: ${String(e)}`)
    }
  }

  /** 健康分数字滚动 + 圆环动画 */
  playScoreAnim(score: number): void {
    if (this.scoreTimer >= 0) {
      clearInterval(this.scoreTimer)
      this.scoreTimer = -1
    }
    this.scoreNum = 0
    this.scoreAnim = false
    setTimeout(() => {
      this.scoreAnim = true
      const step: number = Math.max(1, Math.ceil(score / 30))
      this.scoreTimer = setInterval(() => {
        this.scoreNum += step
        if (this.scoreNum >= score) {
          this.scoreNum = score
          if (this.scoreTimer >= 0) {
            clearInterval(this.scoreTimer)
            this.scoreTimer = -1
          }
        }
      }, 28)
    }, 50)
  }

  async recordTodaySummary(): Promise<void> {
    try {
      const samples: HourSample[] = await this.store.getSamples()
      if (samples.length === 0) return
      const today: string = this.dateStr()
      let rx: number = 0
      let tx: number = 0
      let maxDev: number = 0
      let peakHour: number = 0
      let peakVal: number = 0
      for (let i = 0; i < samples.length; i++) {
        const s: HourSample = samples[i]
        rx += s.rx
        tx += s.tx
        if (s.devices > maxDev) maxDev = s.devices
        if (s.rx + s.tx > peakVal) {
          peakVal = s.rx + s.tx
          peakHour = s.hour
        }
      }
      const summary: DaySummary = { date: today, rx: rx, tx: tx, maxDevices: maxDev, peakHour: peakHour, anomalyCount: 0 }
      await this.store.addDaySummary(summary)
      await this.loadWeek()
    } catch (e) {}
  }

  fmtBytes(n: number): string {
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + 'G'
    if (n >= 1048576) return (n / 1048576).toFixed(0) + 'M'
    if (n >= 1024) return (n / 1024).toFixed(0) + 'K'
    return '' + n
  }

  barColor(p: number): string {
    if (p >= 80) return '#FF5252'
    if (p >= 55) return '#E6A800'
    return '#2FBFA8'
  }

  statusColor(st: string): string {
    if (st === 'ok') return '#00C853'
    if (st === 'warn') return '#E6A800'
    if (st === 'fail') return '#FF5252'
    return '#C9C2B4'
  }

  // ================= UI =================
  build() {
    Column() {
      // 胶囊标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('智能管家')
            .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .shadow({ radius: 8, color: 'rgba(180,160,120,0.14)', offsetY: 3 })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
        Text('预知 · 守护 · 执行')
          .fontSize(11).fontColor(this.theme.textTertiary)
          .margin({ right: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 10 })

      // 5 Tab 分段导航
      Row() {
        ForEach(TABS, (t: string, idx: number) => {
          Column() {
            SymbolGlyph(TAB_ICONS[idx])
              .fontSize(13)
              .fontColor([this.tab === idx ? '#FFFFFF' : this.theme.textSecondary])
            Text(t)
              .fontSize(10)
              .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.tab === idx ? '#FFFFFF' : this.theme.textSecondary)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .padding({ top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor(this.tab === idx ? this.theme.primary : Color.Transparent)
            .shadow(this.tab === idx ? { radius: 6, color: 'rgba(255,138,61,0.3)', offsetY: 2 } : { radius: 0 })
            .animation({ duration: 240, curve: Curve.EaseOut })
            .onClick(() => {
              this.tab = idx
              // 每次切换回到顶部（避免从中间开始显示）
              this.contentScroller.scrollEdge(Edge.Top)
            })
        }, (t: string) => t)
      }
      .width('100%')
      .padding(4)
      .margin({ left: 16, right: 16 })
      .borderRadius(18)
      .backgroundColor('rgba(235,229,216,0.7)')

      Scroll(this.contentScroller) {
        Column() {
          if (this.tab === 0) {
            this.oracleView()
          } else if (this.tab === 1) {
            this.detectiveView()
          } else if (this.tab === 2) {
            this.nightView()
          } else if (this.tab === 3) {
            this.commandView()
          } else {
            this.weekView()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  // ===== 预言家 =====
  @Builder
  oracleView() {
    Column() {
      // 预测主卡：峰值结论 + 拥挤度环（sweep 动画）
      Column() {
        Row() {
          Column() {
            Text('今日网络预测').fontSize(11).fontColor(this.theme.textTertiary)
            Row() {
              Text(`${this.forecast.peakHour}`)
                .fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.theme.primary)
              Text(':00')
                .fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            }
            .margin({ top: 2 })
            Text('预测峰值时段').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 拥挤度环
          Stack() {
            Circle()
              .width(76).height(76)
              .fill('rgba(246,242,234,0.6)')
            Circle()
              .width(76).height(76)
              .fill(Color.Transparent)
              .stroke(this.theme.primary)
              .strokeWidth(6)
              .strokeDashArray(this.ringAnim ? [this.ringVal * 2.4, 240] : [0, 240])
              .rotate({ angle: -90 })
              .animation({ duration: 800, curve: Curve.EaseInOut })
            Column() {
              Text(`${this.ringVal}`)
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.primary)
              Text('拥挤度').fontSize(8).fontColor(this.theme.textTertiary).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .width(76).height(76)
        }
        .width('100%')

        Text(this.forecast.advice)
          .fontSize(12).fontColor(this.theme.textPrimary)
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor('rgba(255,138,61,0.08)')
          .margin({ top: 12 })
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor(this.theme.bgCard)
      .shadow({ radius: 14, color: 'rgba(180,160,120,0.14)', offsetY: 6 })

      // 24h 趋势曲线（stagger 生长动画）
      if (this.forecast.curve.length === 24) {
        Column() {
          Text('24 小时趋势').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .width('100%').margin({ top: 2, bottom: 10 })

          Row() {
            ForEach(this.forecast.curve, (v: number, idx: number) => {
              Column() {
                Column()
                  .width('100%')
                  .height(`${Math.max(4, v)}%`)
                  .borderRadius(3)
                  .backgroundColor(idx === this.forecast.peakHour ? this.theme.primary : '#F0D9B8')
                  .scale({ y: this.weekBarsAnim ? 1 : 0.01 })
                  .animation({ duration: 500, curve: Curve.EaseOut, delay: idx * 30 })
              }
              .width('100%')
              .height(96)
              .justifyContent(FlexAlign.End)
              .layoutWeight(1)
              .margin({ right: 2 })
            }, (v: number, idx: number) => `${idx}`)
          }
          .width('100%')
          .height(96)
          .padding({ left: 4, right: 4 })

          Row() {
            Text('0时').fontSize(9).fontColor(this.theme.textTertiary)
            Blank()
            Text(`${this.forecast.peakHour}时 ↑`).fontSize(9).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
            Blank()
            Text('24时').fontSize(9).fontColor(this.theme.textTertiary)
          }
          .width('100%').margin({ top: 4 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(20)
        .backgroundColor(this.theme.bgCard)
        .shadow({ radius: 14, color: 'rgba(180,160,120,0.14)', offsetY: 6 })
        .margin({ top: 12 })
        .onAppear(() => {
          setTimeout(() => { this.weekBarsAnim = true }, 100)
        })
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.wifi')).fontSize(36).fontColor(['#94A3B8'])
          Text(this.forecast.advice).fontSize(12).fontColor(this.theme.textSecondary).margin({ top: 10 })
        }
        .width('100%')
        .padding(30)
        .borderRadius(20)
        .backgroundColor(this.theme.bgCard)
        .margin({ top: 12 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
  }

  // ===== 侦探 =====
  @Builder
  detectiveView() {
    Column() {
      // 说明卡
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor(['#8B5CF6'])
        Column() {
          Text('AI 网络侦探').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text('断网/卡顿时一键排查，自动生成案发报告').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
        Text(this.detectRunning ? '排查中…' : '开始排查')
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .borderRadius(14)
          .backgroundColor(this.theme.primary)
          .opacity(this.detectRunning ? 0.7 : 1)
          .enabled(!this.detectRunning)
          .onClick(() => { this.runDetective() })
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor(this.theme.bgCard)
      .shadow({ radius: 12, color: 'rgba(180,160,120,0.14)', offsetY: 4 })

      if (this.detectItems.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.security_shield')).fontSize(40).fontColor(['#10B981'])
          Text('一切正常时也会安静待命').fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 8 })
        }
        .width('100%').padding({ top: 40, bottom: 40 }).alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.detectItems, (item: DetectItem, idx: number) => {
          Row() {
            // 状态灯
            Column()
              .width(10).height(10).borderRadius(5)
              .backgroundColor(this.statusColor(item.status))
              .opacity(item.status === 'running' ? 0.5 : 1)
              .animation({ duration: 400, curve: Curve.EaseOut, iterations: item.status === 'running' ? -1 : 1, playMode: PlayMode.Alternate })
            Column() {
              Text(item.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
              Text(item.detail).fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
            if (item.status === 'ok') {
              Text('正常').fontSize(10).fontColor(HEALTH).fontWeight(FontWeight.Bold)
            } else if (item.status === 'fail') {
              Text('异常').fontSize(10).fontColor(DANGER_DEEP).fontWeight(FontWeight.Bold)
            } else if (item.status === 'warn') {
              Text('注意').fontSize(10).fontColor(WARN_DEEP).fontWeight(FontWeight.Bold)
            } else {
              LoadingProgress().width(14).height(14).color(this.theme.primary)
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(this.theme.bgCard)
          .shadow({ radius: 10, color: 'rgba(180,160,120,0.10)', offsetY: 3 })
          .margin({ top: 10 })
          .opacity(1)
          .animation({ duration: 300, curve: Curve.EaseOut, delay: idx * 60 })
        }, (item: DetectItem, idx: number) => `${idx}:${item.status}`)

        if (this.detectDone) {
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor(['#FFFFFF'])
            Text('排查完成，可根据结果判断问题').fontSize(12).fontColor('#FFFFFF').margin({ left: 8 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(14)
          .backgroundColor('#00C853')
          .margin({ top: 12 })
          .transition(TransitionEffect.opacity(0.1).combine(TransitionEffect.translate({ y: 10 })))
          .animation({ duration: 300, curve: Curve.EaseOut })
        }
      }
    }
    .width('100%')
  }

  // ===== 值班员 =====
  @Builder
  nightView() {
    Column() {
      // 星空值班卡（深靛蓝渐变 + 星星闪烁）
      Stack() {
        // 星星
        ForEach([0, 1, 2, 3, 4, 5, 6], (i: number) => {
          Circle()
            .width(i % 3 === 0 ? 4 : 3)
            .height(i % 3 === 0 ? 4 : 3)
            .fill('#FFFFFF')
            .opacity(this.starPhase ? 0.9 : 0.15)
            .animation({ duration: 2000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate, delay: i * 250 })
            .position({
              x: 16 + ((i * 53) % 200),
              y: 12 + ((i * 37) % 34)
            })
        }, (i: number) => `s${i}`)

        Row() {
          SymbolGlyph($r('sys.symbol.moon')).fontSize(22).fontColor(['#FFFFFF'])
          Column() {
            Text('深夜值班员').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            Text('你在睡觉，路由器在守夜').fontSize(10).fontColor('rgba(255,255,255,0.7)').margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
          Text(this.nightDate)
            .fontSize(11).fontColor('rgba(255,255,255,0.9)').fontWeight(FontWeight.Bold)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(9)
            .backgroundColor('rgba(255,255,255,0.15)')
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .linearGradient({ angle: 135, colors: [[NIGHT_1, 0], [NIGHT_2, 1]] })
      .shadow({ radius: 14, color: 'rgba(90,80,130,0.25)', offsetY: 6 })
      .height(96)

      if (this.nightEvents.length === 0) {
        Text('今夜值班报告生成中…（打开页面时自动采集）')
          .fontSize(12).fontColor(this.theme.textSecondary).width('100%').padding({ top: 30, bottom: 30 }).textAlign(TextAlign.Center)
      } else {
        ForEach(this.nightEvents, (ev: NightEvent, idx: number) => {
          Row() {
            Column() {
              SymbolGlyph(ev.type === 'summary' ? $r('sys.symbol.moon')
                : (ev.type === 'new_device' ? $r('sys.symbol.plus_circle')
                : (ev.type === 'attack' ? $r('sys.symbol.security_shield') : $r('sys.symbol.moon'))))
                .fontSize(18)
                .fontColor([ev.type === 'attack' ? '#EF4444' : '#6366F1'])
              Text(ev.time).fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .width(44).alignItems(HorizontalAlign.Center)
            Text(ev.text)
              .fontSize(12).fontColor(this.theme.textPrimary).lineHeight(18)
              .layoutWeight(1).margin({ left: 8 })
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(this.theme.bgCard)
          .shadow({ radius: 10, color: 'rgba(180,160,120,0.10)', offsetY: 3 })
          .margin({ top: 10 })
          .opacity(this.starPhase ? 1 : 0.3)
          .animation({ duration: 300, curve: Curve.EaseOut, delay: 150 + idx * 120 })
        }, (ev: NightEvent, idx: number) => `${idx}:${ev.type}`)
      }
    }
    .width('100%')
  }

  // ===== 一句话 =====
  @Builder
  commandView() {
    Column() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.bolt')).fontSize(22).fontColor(['#F59E0B'])
          Text('一句话搞定网络').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).margin({ left: 8 })
        }
        .width('100%')

        Row() {
          TextInput({ placeholder: '例如：重启路由器 / 谁在线 / 流量多少', text: this.commandText })
            .fontSize(13).height(44).borderRadius(12)
            .backgroundColor('rgba(246,242,234,0.9)').placeholderColor(this.theme.textTertiary)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
            .onChange((v: string) => { this.commandText = v })
            .onSubmit(() => { this.runCommand() })
          Text(this.cmdBusy ? '…' : '执行')
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            .padding({ left: 18, right: 18, top: 11, bottom: 11 })
            .borderRadius(12)
            .backgroundColor(this.theme.primary)
            .margin({ left: 8 })
            .enabled(!this.cmdBusy)
            .onClick(() => { this.runCommand() })
        }
        .width('100%').margin({ top: 12 })

        Row({ space: 8 }) {
          ForEach(['重启路由器', '谁在线', '今日流量'], (s: string) => {
            Text(s)
              .fontSize(10).fontColor(this.theme.primary)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(8)
              .backgroundColor('rgba(255,138,61,0.08)')
              .onClick(() => {
                this.commandText = s
                this.runCommand()
              })
          }, (s: string) => s)
        }
        .width('100%').margin({ top: 10 })
      }
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor(this.theme.bgCard)
      .shadow({ radius: 14, color: 'rgba(180,160,120,0.14)', offsetY: 6 })

      if (this.cmdResult) {
        Column() {
          Text(this.cmdResult)
            .fontSize(13).fontColor(this.theme.textPrimary).lineHeight(20).width('100%')
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(this.theme.bgCard)
        .shadow({ radius: 10, color: 'rgba(180,160,120,0.10)', offsetY: 3 })
        .margin({ top: 12 })
        .transition(TransitionEffect.opacity(0.1).combine(TransitionEffect.translate({ y: 10 })))
      }
    }
    .width('100%')
  }

  // ===== 周报 =====
  @Builder
  weekView() {
    Column() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.circle_grid_2x2')).fontSize(22).fontColor(['#3B82F6'])
          Text('家庭健康周报').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).margin({ left: 8 })
          Blank()
          Text('生成今日')
            .fontSize(11).fontColor(this.theme.primary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(8)
            .backgroundColor('rgba(255,138,61,0.08)')
            .onClick(() => { this.recordTodaySummary() })
        }
        .width('100%')

        // 健康分双环（滚动动画）
        Stack() {
          Circle()
            .width(110).height(110)
            .fill('rgba(246,242,234,0.6)')
          Circle()
            .width(110).height(110)
            .fill(Color.Transparent)
            .stroke('#F0D9B8')
            .strokeWidth(10)
          Circle()
            .width(110).height(110)
            .fill(Color.Transparent)
            .stroke(this.barColor(this.weekScore))
            .strokeWidth(10)
            .strokeDashArray(this.scoreAnim ? [this.weekScore * 3.45, 345] : [0, 345])
            .rotate({ angle: -90 })
            .animation({ duration: 900, curve: Curve.EaseOut })
          Column() {
            Text(`${this.scoreNum}`)
              .fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            Text('网络健康分').fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').padding({ top: 16, bottom: 12 })
        .alignContent(Alignment.Center)

        Text(this.weekInsight)
          .fontSize(12).fontColor(this.theme.textPrimary).width('100%').lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor(this.theme.bgCard)
      .shadow({ radius: 14, color: 'rgba(180,160,120,0.14)', offsetY: 6 })

      if (this.days.length > 0) {
        Column() {
          Text('近 7 天流量').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .width('100%').margin({ top: 2, bottom: 10 })
          Row() {
            ForEach(this.days.slice(-7), (d: DaySummary, idx: number) => {
              Column() {
                Column()
                  .width('100%')
                  .height(`${Math.min(100, 25 + d.rx / 1024 / 1024 / 8)}%`)
                  .borderRadius(4)
                  .backgroundColor(this.theme.primary)
                  .scale({ y: this.weekBarsAnim ? 1 : 0.01 })
                  .animation({ duration: 500, curve: Curve.EaseOut, delay: idx * 60 })
                Text(d.date).fontSize(8).fontColor(this.theme.textTertiary).margin({ top: 4 })
              }
              .layoutWeight(1)
              .height(96)
              .justifyContent(FlexAlign.End)
              .margin({ right: 4 })
            }, (d: DaySummary) => d.date)
          }
          .width('100%')
          .height(96)
        }
        .width('100%')
        .padding(16)
        .borderRadius(20)
        .backgroundColor(this.theme.bgCard)
        .shadow({ radius: 14, color: 'rgba(180,160,120,0.14)', offsetY: 6 })
        .margin({ top: 12 })
        .onAppear(() => {
          setTimeout(() => { this.weekBarsAnim = true }, 100)
        })
      }
    }
    .width('100%')
  }
}
