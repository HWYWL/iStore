import { AppState } from '../../common/store/AppState'
import {
  ThemePalette,
  cardTint,
  cardBorder,
  cardElevation,
  cardRadius
} from '../../common/theme/ThemeColors'
import { SystemInfo, WanStatus, ConnectedDevice, NetworkInterface, MountPoint, ConntrackInfo, WirelessClient } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { TrafficStatStore, DayTraffic } from '../../common/store/TrafficStatStore'
import { WidgetDataStore } from '../../common/store/WidgetDataStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { promptAction } from '@kit.ArkUI'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { Whimsy } from '../../common/utils/WhimsyUtil'
import { FunStore } from '../../common/store/FunStore'
import { AppNav } from '../../common/utils/AppNav'
import { Poller } from '../../common/utils/Poller'
import { LIVE_REFRESH_MS } from '../../common/utils/RefreshRate'
import { LiveRateStore } from '../../common/store/LiveRateStore'
import { AppIcon } from '../../common/components/AppIcon'

// ============================================================
// DashboardTab - 首页
// ============================================================
@Component
export struct DashboardTab {
  @Prop @Watch('onThemeChanged') theme: ThemePalette
  /** 液态玻璃下卡片的按压反馈（实色材质不参与） */
  @State pressedCard: boolean = false

  private setCardPressed(down: boolean): void {
    if (this.theme.material.kind !== 'liquid') {
      return
    }
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.pressedCard = down
    })
  }

  /** 三栏模式下压矮顶栏（标题与连接状态同行），保证各栏首个模块顶边对齐 */
  @Prop compactHeader: boolean = false
  @State systemInfo: SystemInfo = this.emptySys()
  @State wanStatus: WanStatus = this.emptyWan()
  @State lanStatus: WanStatus = this.emptyWan()
  @State isLoading: boolean = true
  @State lastUpdate: string = '--:--:--'
  @State errorText: string = ''
  @State isOnline: boolean = false
  @State whimsyShake: boolean = false
  @State whimsyFish: boolean = false
  @State bottomInset: number = 134
  @State greetText: string = ''
  @State moodText: string = ''
  @State summaryText: string = ''
  @State festivalTag: string = ''
  @State mountPoints: MountPoint[] = []
  @State conntrack: ConntrackInfo = { current: 0, max: 0, percent: 0 }
  // 今日累计流量（网络卡片展示）
  @State todayRx: number = 0
  @State todayTx: number = 0
  @State networkInterfaces: NetworkInterface[] = []
  @State boomShow: boolean = false     // 满速彩蛋显示
  @State boomTick: number = 0          // 彩蛋动画节拍
  private boomTimer: number = -1       // 彩蛋定时器
  private lastBoomTime: number = 0     // 上次彩蛋时间（冷却）
  @State onlineClientCount: number = 0
  // 在线设备（设备旋转视图：一台设备一个光点 + 名称）
  @State orbitDevices: ConnectedDevice[] = []
  private lastScrollY: number = 0
  private poller: Poller | null = null
  private isVisible: boolean = false
  private tabChangeListener: ((tab: number) => void) | null = null
  private navInsetListener: ((inset: number) => void) | null = null
  private wasOffline: boolean = false   // 断网恢复庆祝
  private firstConnectShown: boolean = false
  private anniversaryShown: boolean = false
  // 仪表盘 Canvas 上下文（每个仪表独立）
  private gaugeCtx0: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private gaugeCtx1: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private gaugeCtx2: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private gaugeCtx3: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  // 仪表动画状态（当前显示值 → 目标值，丝滑过渡）
  private gaugeCurrent: number[] = [0, 0, 0, 0]
  private gaugeTarget: number[] = [0, 0, 0, 0]
  private gaugeAnimTimer: number = -1
  // 流量统计（WAN 累计字节快照）
  private lastWanBytes: number[] | null = null
  // 设备作息采样去重（日期_小时）
  private lastActivityKey: string = ''
  // CPU 历史采样（处理器卡片折线图，最多 30 点）
  @State cpuHistory: number[] = []
  // 处理器折线图画布
  private cpuChartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  // 下行速率采样（首页玻璃卡折线，最多 24 点）
  @State netHistory: number[] = []
  private netChartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private netMiniCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  // 实时速率卡片：「设备旋转」视图（≒ 切换），默认开启
  @State orbitMode: boolean = true
  private orbitCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private orbitTimer: number = -1
  private orbitTick: number = 0
  // CPU 半环仪表画布
  private cpuArcCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  aboutToAppear(): void {
    // 恢复「设备旋转」视图开关：持久化到本地，退出重进 / 重启应用后保持上次选择
    // 默认使用设备旋转视图（首次安装即为此视图，用户手动切到折线后仍会被记住）
    PersistentStorage.persistProp('dashboardOrbitModeV2', true)
    const savedOrbit: boolean = AppStorage.get<boolean>('dashboardOrbitModeV2') ?? true
    this.orbitMode = savedOrbit
    if (savedOrbit) {
      this.startOrbit()
    }
    // 底部导航占位（适配手势条 + 悬浮导航，随机型变化实时更新）
    this.bottomInset = AppState.getInstance().getBottomNavInset()
    this.navInsetListener = (inset: number) => {
      this.bottomInset = inset
    }
    AppState.getInstance().onBottomNavInsetChange(this.navInsetListener)
    // 流量统计存储初始化
    const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      TrafficStatStore.getInstance().init(hostCtx as Context).then(() => {
        const t: DayTraffic = TrafficStatStore.getInstance().getDays(1)[0]
        this.todayRx = t.rx
        this.todayTx = t.tx
      }).catch(() => {})
      WidgetDataStore.init(hostCtx as Context)
    }
    // 前台感知：仅当本 Tab（首页 index 0）可见时轮询
    this.isVisible = AppState.getInstance().getCurrentTab() === 0
    // 统一轮询器：自带「上轮未回来则跳过」保护，避免弱网下请求叠加
    this.poller = new Poller((): Promise<void> => this.refreshData(), LIVE_REFRESH_MS)
    this.tabChangeListener = (tab: number) => {
      const visible: boolean = tab === 0
      if (visible && !this.isVisible) {
        this.isVisible = true
        // 回到本 Tab 时立即刷新一次，然后恢复轮询
        if (this.poller) {
          this.poller.trigger()
          this.poller.start()
        }
      } else if (!visible && this.isVisible) {
        this.isVisible = false
        if (this.poller) {
          this.poller.stop()
        }
      }
    }
    AppState.getInstance().onTabChange(this.tabChangeListener)
    // 首次加载数据，然后启动 5 秒轮询刷新
    this.loadData()
    if (this.isVisible && this.poller) {
      this.poller.start()
    }
  }

  aboutToDisappear(): void {
    if (this.poller) {
      this.poller.dispose()
      this.poller = null
    }
    if (this.gaugeAnimTimer !== -1) {
      clearInterval(this.gaugeAnimTimer)
      this.gaugeAnimTimer = -1
    }
    this.stopOrbit()
    if (this.tabChangeListener) {
      AppState.getInstance().offTabChange(this.tabChangeListener)
      this.tabChangeListener = null
    }
    if (this.navInsetListener) {
      AppState.getInstance().offBottomNavInsetChange(this.navInsetListener)
      this.navInsetListener = null
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      // 检查连接状态，未连接则直接返回
      if (!AppState.getInstance().isConnected()) {
        this.errorText = '设备未连接，外面的线被拔了？连上我就能干活了 🔌'
        this.isLoading = false
        return
      }
      const api: ApiService = ApiService.getInstance()
      // 并行请求，减少总加载时间
      const results = await Promise.all([
        api.fetchSystemInfo(),
        api.fetchLanStatus(),
        api.fetchMountPoints(),
        api.fetchConntrack(),
        api.fetchNetworkInterfaces(),
        api.fetchConnectedDevices()
      ])
      // 按 Promise.all 顺序解包结果
      this.systemInfo = results[0]
      this.lanStatus = results[1]
      this.wanStatus = results[1]
      // 广播实时速率：应用中心 / 小管家订阅同一份数据，数字与首页保持一致
      LiveRateStore.getInstance().push(results[1].rxRate, results[1].txRate)
      this.mountPoints = results[2]
      this.conntrack = results[3]
      this.networkInterfaces = results[4]
      const devs1: ConnectedDevice[] = results[5] as ConnectedDevice[]
      this.onlineClientCount = this.countOnlineClients(devs1)
      this.orbitDevices = devs1.filter((d: ConnectedDevice): boolean => d.isOnline)
      this.isOnline = true
      // ===== 情感触点：首次连接 / 断网恢复 / 周年纪念 / 状态播报 =====
      this.handleConnectMoments()
      // 满速彩蛋：下载速率超过 30MB/s（约 240Mbps）且冷却 30 秒后触发
      const rx: number = this.wanStatus.rxRate
      if (rx >= 30 * 1024 * 1024 && Date.now() - this.lastBoomTime > 30000) {
        this.triggerBoom()
      }
    } catch (dashErr) {
      this.wasOffline = true
      this.errorText = '加载数据失败'
    }
    this.isLoading = false
    this.updateTimestamp()
    this.redrawGauges()
  }

  countOnlineClients(devices: ConnectedDevice[]): number {
    let count = 0
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].isOnline) {
        count++
      }
    }
    return count
  }

  async refreshData(): Promise<void> {
    try {
      // 断开连接后停止刷新
      if (!AppState.getInstance().isConnected()) {
        return
      }
      const api: ApiService = ApiService.getInstance()
      const results = await Promise.all([
        api.fetchSystemInfo(),
        api.fetchLanStatus(),
        api.fetchMountPoints(),
        api.fetchConntrack(),
        api.fetchConnectedDevices()
      ])
      this.systemInfo = results[0]
      this.lanStatus = results[1]
      this.wanStatus = results[1]
      LiveRateStore.getInstance().push(results[1].rxRate, results[1].txRate)
      this.mountPoints = results[2]
      this.conntrack = results[3]
      const devs2: ConnectedDevice[] = results[4] as ConnectedDevice[]
      this.onlineClientCount = this.countOnlineClients(devs2)
      this.orbitDevices = devs2.filter((d: ConnectedDevice): boolean => d.isOnline)
      this.isOnline = true
      // 流量统计：累计字节增量记入当天
      this.recordTraffic()
      // 设备作息采样：每整点记录一次在线设备，供 24h 热力图使用
      this.recordDeviceActivity(results[4] as ConnectedDevice[])
      // 桌面小组件数据同步（下载/上传速率 + 在线设备数）
      this.syncWidgetData()
      // CPU 历史采样（处理器卡片折线图）
      this.recordCpuHistory()
      // 下行速率采样（首页玻璃卡折线）
      this.recordNetHistory()
      this.handleConnectMoments()
    } catch (refErr) {
      // 静默刷新失败不打断用户操作，但要留痕便于排查（弱网/权限问题）
      hilog.warn(0x0001, 'DashboardTab', `refresh failed: ${String(refErr)} lastError=${ApiService.getInstance().getLastError()}`)
    }
    this.updateTimestamp()
    this.redrawGauges()
  }


  // ========== 情感触点辅助方法 ==========
  /** 时段问候 */
  greeting(): string {
    const h: number = new Date().getHours()
    if (h >= 5 && h < 11) return '早上好，小管昨晚看了一整夜的门 🌅'
    if (h >= 11 && h < 18) return '下午好，小管帮你盯着家里' + (this.onlineClientCount > 0 ? ` ${this.onlineClientCount} 台设备` : '的设备') + ' ☕'
    if (h >= 18 && h < 24) return '晚上好，夜生活开始，网速跟得上吗 🌙'
    return '都这个点了还在？设备我盯着，你早点睡 🛏️'
  }

  /** 设备拟人状态 */
  deviceMood(): string {
    if (!this.isOnline) return '小管失联了…'
    const cpu: number = this.systemInfo.cpuUsage
    const temp: number = this.systemInfo.cpuTemp
    if (temp >= 75) return '小管在冒汗 🥵'
    if (cpu >= 80) return '小管有点忙'
    if (cpu >= 50) return '小管挺精神'
    return '小管很轻松'
  }

  /** 状态播报（加载完成后一句总结） */
  buildSummary(): string {
    if (!this.isOnline) return ''
    const cpu: number = this.systemInfo.cpuUsage
    if (cpu < 50 && this.systemInfo.cpuTemp < 60) return '一切正常，小管在岗 🫡'
    if (this.systemInfo.cpuTemp >= 75) return '有点烫手，小管建议透透气 🥵'
    if (cpu >= 80) return 'CPU 快忙不过来了，看看谁在跑 ⚙️'
    return '网络平稳，设备都在线 ✅'
  }

  /** 节日彩蛋标签 */
  festival(): string {
    const d: Date = new Date()
    const m: number = d.getMonth() + 1
    const day: number = d.getDate()
    if (m === 1 && (day === 1 || day === 28 || day === 29)) return '🧧 新年好'
    if (m === 2 && day === 29) return '🎂 闰年快乐'
    if (m === 6 && day === 1) return '🎈 六一快乐'
    if (m === 10 && day === 1) return '🎆 国庆快乐'
    if (m === 12 && (day === 24 || day === 25)) return '🎄 圣诞快乐'
    return ''
  }

  /** 连接时刻处理：首次欢迎 / 断网恢复 / 周年纪念 */
  handleConnectMoments(): void {
    const fun = FunStore.getInstance()
    // 首次连接欢迎
    if (!this.firstConnectShown && fun.getFirstDate() === '') {
      fun.setFirstDate(new Date().toISOString().slice(0, 10))
      this.firstConnectShown = true
      this.greetText = '欢迎回家，我是小管 🏠'
      setTimeout(() => { this.greetText = this.greeting() }, 3000)
      return
    }
    // 断网恢复庆祝
    if (this.wasOffline && this.isOnline) {
      this.wasOffline = false
      this.greetText = '满血复活！刚才那一下差点吓到小管 🟢'
      setTimeout(() => { this.greetText = this.greeting() }, 2500)
      return
    }
    // 周年纪念（30/100/365 天）
    if (!this.anniversaryShown) {
      const days: number = fun.getLevelUpDays()
      if (days === 30) {
        this.anniversaryShown = true
        this.greetText = '我们认识一个月了，这 30 天我守住了你的网 🎂'
        setTimeout(() => { this.greetText = this.greeting() }, 3000)
      } else if (days === 365) {
        this.anniversaryShown = true
        this.greetText = '周年快乐！这一年在守护你家的 365 个夜晚 🎉'
        setTimeout(() => { this.greetText = this.greeting() }, 3000)
      }
    }
    // 首次连接后每天：时段问候 + 播报（只在 greetText 空时）
    if (this.greetText === '') {
      this.greetText = this.greeting()
    }
    this.moodText = this.deviceMood()
    this.summaryText = this.buildSummary()
    this.festivalTag = this.festival()
  }

  /** 同步数据到桌面小组件 */
  private syncWidgetData(): void {
    try {
      const device = AppState.getInstance().getActiveDevice()
      let memPct: number = 0
      if (this.systemInfo.memoryTotal > 0) {
        memPct = Math.round(this.systemInfo.memoryUsed / this.systemInfo.memoryTotal * 100)
      }
      WidgetDataStore.save({
        rxRate: this.wanStatus.rxRate,
        txRate: this.wanStatus.txRate,
        deviceCount: this.onlineClientCount,
        online: this.isOnline,
        deviceName: device ? (device.label || device.host) : 'iStore 路由管家',
        cpuUsage: this.systemInfo.cpuUsage,
        memPercent: memPct,
        ip: this.wanStatus.ipAddress,
        todayTraffic: TrafficStatStore.getInstance().getTodayTotal()
      })
    } catch (e) {
      // 同步失败不影响主流程
    }
  }

  /** 累计当日流量（WAN 累计字节差值） */
  private async recordTraffic(): Promise<void> {
    try {
      const api: ApiService = ApiService.getInstance()
      const bytes: number[] = await api.fetchWanTrafficBytes()
      if (bytes[0] === 0 && bytes[1] === 0) {
        hilog.info(0x0001, 'Dashboard', 'recordTraffic: 累计字节为 0（数据源不可用）')
      }
      if (this.lastWanBytes) {
        const drx: number = bytes[0] - this.lastWanBytes[0]
        const dtx: number = bytes[1] - this.lastWanBytes[1]
        // 计数器重置（路由器重启）时跳过本次
        if (drx >= 0 && dtx >= 0 && (drx > 0 || dtx > 0)) {
          TrafficStatStore.getInstance().addToday(drx, dtx)
        }
      }
      this.lastWanBytes = bytes
      // 同步今日累计流量到网络卡片
      const today: DayTraffic = TrafficStatStore.getInstance().getDays(1)[0]
      this.todayRx = today.rx
      this.todayTx = today.tx
    } catch (e) {
      // 统计失败不影响主流程
    }
  }

  /** 设备作息采样：每小时记录一次在线设备，供 24h 活跃热力图使用 */
  private recordDeviceActivity(devs: ConnectedDevice[]): void {
    try {
      const now: Date = new Date()
      const key: string = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}_${now.getHours()}`
      if (key === this.lastActivityKey) {
        return
      }
      const macs: string[] = []
      for (let i = 0; i < devs.length; i++) {
        const d: ConnectedDevice = devs[i]
        if (d.mac && d.isOnline) {
          macs.push(d.mac)
        }
      }
      FunStore.getInstance().addActivity(macs)
      this.lastActivityKey = key
    } catch (e) {
      // 采样失败不影响主流程
    }
  }

  updateTimestamp(): void {
    const now: Date = new Date()
    this.lastUpdate =
      `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`
  }

  /** 触发满速彩蛋：3.5 秒粒子动画后自动消失 */
  private triggerBoom(): void {
    this.lastBoomTime = Date.now()
    this.boomShow = true
    this.boomTick = 0
    if (this.boomTimer !== -1) {
      clearInterval(this.boomTimer)
    }
    this.boomTimer = setInterval(() => {
      this.boomTick = this.boomTick + 1
      if (this.boomTick >= 70) {
        clearInterval(this.boomTimer)
        this.boomTimer = -1
        this.boomShow = false
      }
    }, 50)
  }

  private boomProgress(i: number): number {
    const phase: number = (this.boomTick + i * 7) % 40
    return phase / 40
  }

  private boomSize(i: number): number {
    return 10 + this.boomProgress(i) * 30
  }

  private boomColor(i: number): string {
    const colors: string[] = this.theme.chartColors
    return colors[i % colors.length]
  }

  private boomX(i: number): number {
    const base: number = 90 + (i % 4) * 120
    return base + Math.cos(i * 0.52) * this.boomProgress(i) * 150
  }

  private boomY(i: number): number {
    return 260 + Math.sin(i * 0.52) * this.boomProgress(i) * 190
  }

  /** 满速彩蛋粒子层 */
  @Builder
  boomLayer() {
    if (this.boomShow) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .backgroundColor(this.tint(this.theme.bgCard, 0.06))
        ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], (i: number) => {
          Circle({ width: this.boomSize(i), height: this.boomSize(i) })
            .fill(this.boomColor(i))
            .opacity(1 - this.boomProgress(i))
            .position({
              x: this.boomX(i),
              y: this.boomY(i)
            })
        }, (i: number): string => `b${i}`)
        Column() {
          Text('⚡ 满速时刻！')
            .fontSize(26).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
          Text('网速起飞，恭喜！')
            .fontSize(12).fontColor(this.theme.textSecondary).margin({ top: 4 })
        }
        .position({ x: 0, y: 240 }).width('100%').alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  emptySys(): SystemInfo {
    return {
      hostname: '', model: '', kernel: '', firmwareVersion: '',
      localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
      memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0, cpuFreq: 0,
      boardName: '', cpuModel: '', distribution: '', releaseVersion: '', releaseRevision: '', releaseTarget: ''
    }
  }

  emptyWan(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0',
      netmask: '', gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '',
      proto: '', macAddr: ''
    }
  }

  getCpuColor(usage: number): string {
    if (usage < 30) {
      // < 30%：低负载（绿色）
      return this.theme.success
    }
    if (usage < 60) {
      // 30-60%：中等负载（黄色）
      return this.theme.warning
    }
    // ≥ 60%：高负载（红色）
    return this.theme.danger
  }

  /** 磁盘使用色阶：≤35 绿 / 36-60 蓝 / 61-80 黄 / >80 红 */
  diskColor(usage: number): string {
    if (usage <= 35) {
      return this.theme.success
    }
    if (usage <= 60) {
      return this.theme.info
    }
    if (usage <= 80) {
      return this.theme.warning
    }
    return this.theme.danger
  }

  /** 内存使用率（%） */
  memoryPercent(): number {
    return this.systemInfo.memoryTotal > 0
      ? Math.min(100, Math.round(this.systemInfo.memoryUsed * 100 / this.systemInfo.memoryTotal))
      : 0
  }

  /**
   * 磁盘占用率（跨固件稳定方案）
   * 不依赖 device 命名（/dev/root、mtdblock、PARTUUID 等各衍生版差异大），
   * 按「挂载点语义 + 类型过滤」统计：
   *   - 只统计真实块设备（/dev/ 开头，排除 tmpfs/overlay/squashfs/mtd/loop）
   *   - 排除系统保留挂载点（/boot /rom /overlay /tmp /proc /sys 等）
   *   - 剩余 = 根分区 + 用户数据盘 → 每块硬盘的真实总占用
   */
  diskPercent(): number {
    if (this.mountPoints.length === 0) {
      return 0
    }
    let totalSize: number = 0
    let totalUsed: number = 0
    const seenDevices: Set<string> = new Set()
    for (let i = 0; i < this.mountPoints.length; i++) {
      const m = this.mountPoints[i]
      const dev: string = m.device
      // 排除虚拟/只读设备：非 /dev/ 开头（tmpfs/overlay/squashfs/rootfs）或 mtd/loop
      if (!dev.startsWith('/dev/') || dev.indexOf('/mtd') >= 0 || dev.indexOf('/loop') >= 0) {
        continue
      }
      // 排除系统保留挂载点（同一物理盘的分区碎片，避免重复统计）
      // 保留：/（根分区）与 /mnt、/media 等用户数据挂载
      const mp: string = m.mountPoint
      if (mp === '/overlay' || mp === '/boot' || mp === '/rom' ||
        mp.startsWith('/overlay') || mp.startsWith('/boot') || mp.startsWith('/rom')) {
        continue
      }
      // 同一设备多次挂载只统计一次
      if (seenDevices.has(dev)) {
        continue
      }
      seenDevices.add(dev)
      totalSize += m.size
      totalUsed += m.used
    }
    return totalSize > 0 ? Math.min(100, Math.round(totalUsed * 100 / totalSize)) : 0
  }

  /** 设备显示名（优先用户标签） */
  deviceLabel(): string {
    const d = AppState.getInstance().getActiveDevice()
    if (d) {
      return d.label || d.host
    }
    return this.systemInfo.hostname || '路由器'
  }

  /** 仪表盘卡片背景（随皮肤） */
  cardBg(): string {
    return this.theme.bgCard
  }

  /** 卡片阴影（柔和投影，随皮肤） */
  cardShadow(): ShadowOptions {
    return { radius: this.theme.cardShadowRadius, color: this.theme.cardShadow, offsetX: 0, offsetY: 4 }
  }

  /** 皮肤切换后重绘全部 Canvas（画布内容不会随主题状态自动刷新） */
  onThemeChanged(): void {
    this.drawNetChart()
    this.drawNetMini()
    this.drawCpuChart()
    this.drawCpuArc()
  }

  /** 记录 CPU 采样（折线图数据，保留 30 点） */
  recordCpuHistory(): void {
    this.cpuHistory.push(this.systemInfo.cpuUsage)
    if (this.cpuHistory.length > 30) {
      this.cpuHistory.shift()
    }
    this.drawCpuChart()
    this.drawCpuArc()
  }

  /** 记录下行速率采样（首页折线，保留 24 点） */
  recordNetHistory(): void {
    this.netHistory.push(this.wanStatus.rxRate)
    if (this.netHistory.length > 24) {
      this.netHistory.shift()
    }
    this.drawNetChart()
    this.drawNetMini()
  }

  /** 内存占用率（%） */
  memPercent(): number {
    if (this.systemInfo.memoryTotal <= 0) {
      return 0
    }
    return Math.min(100, Math.round(this.systemInfo.memoryUsed * 100 / this.systemInfo.memoryTotal))
  }

  /** 运行时长文本 */
  uptimeText(): string {
    return this.systemInfo.uptime > 0 ? FormatUtils.formatUptime(this.systemInfo.uptime) : '--'
  }

  /** 页面渐变：薄玻璃模式交给 MainPage（带柔光斑），自身透明以透出背景 */
  private pageBgColors(): Array<[ResourceColor, number]> {
    if (AppState.getInstance().isGlass()) {
      return [[Color.Transparent, 0], [Color.Transparent, 1]]
    }
    return this.theme.pageGradient
  }

  /** 卡片填充：材质决定（实色=bgCard，液态玻璃=材质 tint 渐变） */
  private cardFill(): Array<[ResourceColor, number]> {
    if (this.theme.material.kind !== 'liquid') {
      return [[this.theme.bgCard, 0], [this.theme.bgCard, 1]]
    }
    return [[this.theme.material.tintTop, 0], [this.theme.material.tintBottom, 1]]
  }

  /** 卡片实时模糊半径（材质决定，实色为 0） */
  private cardBlur(_base: number): number {
    return this.theme.material.blur
  }

  /** 卡片描边：玻璃时顶部高光、底部渐隐，营造玻璃厚度感 */
  private cardBorder(): BorderOptions {
    if (this.theme.material.kind === 'liquid') {
      return {
        width: { top: 1, right: 0.7, bottom: 0.7, left: 0.7 },
        color: {
          top: this.theme.material.innerGlow,
          right: this.theme.material.borderColor,
          bottom: this.theme.material.bottomGlow,
          left: this.theme.material.borderColor
        }
      }
    }
    return { width: 0.5, color: this.theme.borderGlass }
  }

  /** 版本文本：版本号（如有修订号则附带展示），缺省显示 -- */
  boardVersionText(): string {
    const version: string = this.systemInfo.releaseVersion
    if (version.length === 0) {
      return '--'
    }
    const revision: string = this.systemInfo.releaseRevision
    return revision.length > 0 ? `${version} (${revision})` : version
  }

  /** 速率拆成「数值 / 单位」两段，供大字排版使用 */
  private speedValue(bytesPerSec: number): string {
    const parts: string[] = FormatUtils.formatBytes(bytesPerSec).split(' ')
    return parts.length > 0 ? parts[0] : '0'
  }

  private speedUnit(bytesPerSec: number): string {
    const parts: string[] = FormatUtils.formatBytes(bytesPerSec).split(' ')
    return parts.length > 1 ? `${parts[1]}/s` : 'B/s'
  }

  /** 下行折线（渐变面积 + 渐变描边 + 末端圆点），首页主卡与网络小卡共用 */
  private drawSpark(ctx: CanvasRenderingContext2D, withDot: boolean, lineStops: string[]): void {
    const w: number = ctx.width
    const h: number = ctx.height
    if (w <= 0 || h <= 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)
    let data: number[] = this.netHistory
    if (data.length < 2) {
      data = [0, 0]
    }
    let peak: number = 0
    for (let i = 0; i < data.length; i++) {
      if (data[i] > peak) {
        peak = data[i]
      }
    }
    // 量程随峰值走并留 60% 余量，曲线保持在卡片中部而不是贴顶
    const max: number = Math.max(peak * 1.6, 2048)
    const n: number = data.length
    const step: number = w / (n - 1)
    const top: number = 4
    const span: number = h - top - 4

    // 渐变面积
    const area: CanvasGradient = ctx.createLinearGradient(0, 0, 0, h)
    area.addColorStop(0, this.tint(this.theme.info, 0.3))
    area.addColorStop(1, this.tint(this.theme.info, 0))
    ctx.beginPath()
    ctx.moveTo(0, h)
    for (let i = 0; i < n; i++) {
      ctx.lineTo(i * step, top + span - (data[i] / max) * span)
    }
    ctx.lineTo(w, h)
    ctx.closePath()
    ctx.fillStyle = area
    ctx.fill()

    // 渐变描边
    const line: CanvasGradient = ctx.createLinearGradient(0, 0, w, 0)
    for (let i = 0; i < lineStops.length; i++) {
      line.addColorStop(lineStops.length > 1 ? i / (lineStops.length - 1) : 0, lineStops[i])
    }
    ctx.beginPath()
    ctx.moveTo(0, top + span - (data[0] / max) * span)
    for (let i = 1; i < n; i++) {
      ctx.lineTo(i * step, top + span - (data[i] / max) * span)
    }
    ctx.strokeStyle = line
    ctx.lineWidth = 2
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'
    ctx.stroke()

    // 末端圆点
    if (withDot) {
      ctx.beginPath()
      ctx.arc((n - 1) * step, top + span - (data[n - 1] / max) * span, 3.2, 0, Math.PI * 2)
      ctx.fillStyle = this.theme.bgCardSolid
      ctx.fill()
      ctx.strokeStyle = this.theme.info
      ctx.lineWidth = 2
      ctx.stroke()
    }
  }

  /** 首页主卡折线 */
  private drawNetChart(): void {
    try {
      this.drawSpark(this.netChartCtx, true, [this.theme.primary, this.theme.info, this.theme.success])
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `drawNetChart failed: ${e}`)
    }
  }

  /** 网络小卡折线（单色） */
  private drawNetMini(): void {
    try {
      this.drawSpark(this.netMiniCtx, false, [this.tint(this.theme.info, 0.55), this.theme.info])
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `drawNetMini failed: ${e}`)
    }
  }

  // ================= 实时速率卡片：设备旋转视图 =================

  /** ≒ 切换：折线 ↔ 设备旋转 */
  private toggleOrbit(): void {
    this.orbitMode = !this.orbitMode
    // 记忆选择，下次进入直接是上次的视图
    AppStorage.setOrCreate('dashboardOrbitModeV2', this.orbitMode)
    if (this.orbitMode) {
      this.orbitTick = 0
      this.startOrbit()
    } else {
      this.stopOrbit()
      setTimeout(() => {
        this.drawNetChart()
      }, 40)
    }
  }

  private startOrbit(): void {
    this.stopOrbit()
    this.orbitTimer = setInterval(() => {
      this.orbitTick += 0.02
      this.drawOrbit()
    }, 40)
  }

  private stopOrbit(): void {
    if (this.orbitTimer !== -1) {
      clearInterval(this.orbitTimer)
      this.orbitTimer = -1
    }
  }

  /** 设备旋转视图：核心刻度环 + 双椭圆轨道 + 设备节点（参考 neural 仪表盘） */
  private drawOrbit(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.orbitCtx
      const w: number = ctx.width
      const h: number = ctx.height
      if (w <= 0 || h <= 0) {
        return
      }
      ctx.clearRect(0, 0, w, h)
      const cx: number = w / 2
      const cy: number = h / 2
      const t: number = this.orbitTick
      const base: number = Math.min(w, h) * 0.34

      // 大气光（跟随皮肤主色，不铺深色底）
      const glow: CanvasGradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, base * 2.4)
      glow.addColorStop(0, this.tint(this.theme.primary, 0.16))
      glow.addColorStop(0.35, this.tint(this.theme.primary, 0.05))
      glow.addColorStop(1, this.tint(this.theme.primary, 0))
      ctx.fillStyle = glow
      ctx.fillRect(0, 0, w, h)

      // 主环
      ctx.strokeStyle = this.tint(this.theme.primary, 0.28)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.arc(cx, cy, base * 0.62, 0, Math.PI * 2)
      ctx.stroke()

      // 刻度（底部亮、顶部淡）
      for (let i = 0; i < 48; i++) {
        const ang: number = (i / 48) * Math.PI * 2 - Math.PI / 2
        const major: boolean = i % 6 === 0
        const len: number = major ? 6 : 3
        const mod: number = Math.max(0, Math.sin(ang + Math.PI / 2))
        const a: number = 0.06 + 0.4 * mod * mod
        const r0: number = base * 0.65
        ctx.strokeStyle = this.tint(this.theme.primary, a)
        ctx.lineWidth = major ? 1.4 : 1
        ctx.beginPath()
        ctx.moveTo(cx + Math.cos(ang) * r0, cy + Math.sin(ang) * r0)
        ctx.lineTo(cx + Math.cos(ang) * (r0 + len), cy + Math.sin(ang) * (r0 + len))
        ctx.stroke()
      }

      // 扫描弧
      const sc: number = (t * 1.2) % (Math.PI * 2) - Math.PI / 2
      for (let k = 0; k < 9; k++) {
        const aa: number = sc - k * 0.06
        const r1: number = base * 0.66
        const r2: number = base * 0.82
        ctx.strokeStyle = this.tint(this.theme.primary, 0.5 * (1 - k / 9))
        ctx.lineWidth = 1.5
        ctx.beginPath()
        ctx.moveTo(cx + Math.cos(aa) * r1, cy + Math.sin(aa) * r1)
        ctx.lineTo(cx + Math.cos(aa) * r2, cy + Math.sin(aa) * r2)
        ctx.stroke()
      }

      // 虚线外环（反向旋转）
      ctx.save()
      ctx.translate(cx, cy)
      ctx.rotate(-t * 0.5)
      ctx.setLineDash([2.4, 8])
      ctx.strokeStyle = this.tint(this.theme.primary, 0.32)
      ctx.lineWidth = 1.1
      ctx.beginPath()
      ctx.arc(0, 0, base * 0.92, 0, Math.PI * 2)
      ctx.stroke()
      ctx.setLineDash([])
      ctx.restore()

      // 双椭圆轨道
      const orbits: number[] = [base * 1.02, base * 1.22]
      const ryRatio: number[] = [0.44, 0.92]
      const spins: number[] = [0.5, -0.32]
      const rots: number[] = [-0.19, 0.28]
      for (let o = 0; o < orbits.length; o++) {
        const rx: number = orbits[o]
        const ry: number = rx * ryRatio[o]
        const rot: number = rots[o] + t * spins[o]
        ctx.beginPath()
        ctx.ellipse(cx, cy, rx, ry, rot, Math.PI, Math.PI * 2)
        ctx.strokeStyle = this.tint(this.theme.primary, 0.1)
        ctx.lineWidth = 1
        ctx.stroke()
        ctx.beginPath()
        ctx.ellipse(cx, cy, rx, ry, rot, 0, Math.PI)
        ctx.strokeStyle = this.tint(this.theme.primary, 0.26)
        ctx.lineWidth = 1.3
        ctx.stroke()
      }

      // 设备节点：每台在线设备一个光点，并在旁边标注设备名称
      const devs: ConnectedDevice[] = this.orbitDevices
      const count: number = devs.length
      const half: number = Math.ceil(count / 2)
      for (let i = 0; i < count; i++) {
        const o: number = i < half ? 0 : 1
        const idxInOrbit: number = o === 0 ? i : i - half
        const perOrbit: number = o === 0 ? half : (count - half)
        const rx: number = orbits[o]
        const ry: number = rx * ryRatio[o]
        const rot: number = rots[o] + t * spins[o]
        const baseAng: number = perOrbit > 0 ? (idxInOrbit / perOrbit) * Math.PI * 2 : 0
        const th: number = baseAng + t * 0.26 * (o === 0 ? 1 : -1)
        const lx: number = Math.cos(th) * rx
        const ly: number = Math.sin(th) * ry
        const c: number = Math.cos(rot)
        const s: number = Math.sin(rot)
        const px: number = cx + lx * c - ly * s
        const py: number = cy + lx * s + ly * c
        const depth: number = 0.34 + 0.66 * (Math.sin(th) * 0.5 + 0.5)
        const rad: number = 1.8 + 2.6 * depth

        // 节点光晕
        const hg: CanvasGradient = ctx.createRadialGradient(px, py, 0, px, py, rad * 7)
        hg.addColorStop(0, this.tint(this.theme.primary, 0.45 * depth))
        hg.addColorStop(0.35, this.tint(this.theme.primary, 0.14 * depth))
        hg.addColorStop(1, this.tint(this.theme.primary, 0))
        ctx.fillStyle = hg
        ctx.beginPath()
        ctx.arc(px, py, rad * 7, 0, Math.PI * 2)
        ctx.fill()

        // 节点本体
        ctx.fillStyle = this.tint(this.theme.primary, 0.35 + 0.65 * depth)
        ctx.beginPath()
        ctx.arc(px, py, rad, 0, Math.PI * 2)
        ctx.fill()

        // 连接核心的弧线
        const dx: number = px - cx
        const dy: number = py - cy
        const dl: number = Math.sqrt(dx * dx + dy * dy) || 1
        const ux: number = dx / dl
        const uy: number = dy / dl
        const sx0: number = cx + ux * base * 0.6
        const sy0: number = cy + uy * base * 0.6
        const lg: CanvasGradient = ctx.createLinearGradient(cx, cy, px, py)
        lg.addColorStop(0, this.tint(this.theme.primary, 0.08 + 0.32 * depth))
        lg.addColorStop(1, this.tint(this.theme.info, 0.2))
        ctx.strokeStyle = lg
        ctx.lineWidth = 0.55 + 0.75 * depth
        ctx.beginPath()
        ctx.moveTo(sx0, sy0)
        ctx.quadraticCurveTo((sx0 + px) / 2 + dy * 0.11, (sy0 + py) / 2 - dx * 0.11, px, py)
        ctx.stroke()

        // 设备名称
        const dev: ConnectedDevice = devs[i]
        const rawName: string = dev.hostname.length > 0
          ? dev.hostname : (dev.ip.length > 0 ? dev.ip : dev.mac)
        if (rawName.length > 0) {
          const label: string = rawName.length > 9 ? rawName.substring(0, 9) + '…' : rawName
          let tx: number = px + ux * (rad + 9)
          let ty: number = py + uy * (rad + 11)
          if (ty < 9) {
            ty = 9
          }
          if (ty > h - 9) {
            ty = h - 9
          }
          ctx.font = '500 9px sans-serif'
          ctx.textBaseline = 'middle'
          if (ux > 0.3) {
            ctx.textAlign = 'left'
          } else if (ux < -0.3) {
            ctx.textAlign = 'right'
          } else {
            ctx.textAlign = 'center'
          }
          // 贴边时换到另一侧，避免文字被裁掉
          if (ctx.textAlign === 'left' && tx + 52 > w) {
            ctx.textAlign = 'right'
            tx = px - ux * (rad + 9)
          } else if (ctx.textAlign === 'right' && tx - 52 < 0) {
            ctx.textAlign = 'left'
            tx = px - ux * (rad + 9)
          }
          ctx.fillStyle = this.theme.textSecondary
          ctx.fillText(label, tx, ty)
        }
      }

      // 中心核
      const core: CanvasGradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, base * 0.5)
      core.addColorStop(0, this.tint(this.theme.primary, 0.2))
      core.addColorStop(0.55, this.tint(this.theme.primary, 0.06))
      core.addColorStop(1, this.tint(this.theme.primary, 0))
      ctx.fillStyle = core
      ctx.beginPath()
      ctx.arc(cx, cy, base * 0.5, 0, Math.PI * 2)
      ctx.fill()

      // 没有在线设备时给个提示
      if (count === 0) {
        ctx.font = '500 10px sans-serif'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillStyle = this.theme.textTertiary
        ctx.fillText('暂无在线设备', cx, cy + base * 0.9)
      }
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `drawOrbit failed: ${e}`)
    }
  }

  /** 处理器半环仪表（低负载也看得出刻度） */
  private drawCpuArc(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.cpuArcCtx
      const w: number = ctx.width
      const h: number = ctx.height
      if (w <= 0 || h <= 0) {
        return
      }
      ctx.clearRect(0, 0, w, h)
      const cx: number = w / 2
      const cy: number = h - 4
      const r: number = Math.min(w / 2 - 7, h - 12)
      // 刻度环
      ctx.beginPath()
      ctx.arc(cx, cy, r + 5, Math.PI, Math.PI * 2)
      ctx.strokeStyle = this.theme.textTertiary
      ctx.globalAlpha = 0.35
      ctx.lineWidth = 1
      ctx.setLineDash([1, 7])
      ctx.stroke()
      ctx.setLineDash([])
      ctx.globalAlpha = 1
      // 轨道
      ctx.beginPath()
      ctx.arc(cx, cy, r, Math.PI, Math.PI * 2)
      ctx.strokeStyle = this.theme.progressTrack
      ctx.lineWidth = 8
      ctx.lineCap = 'round'
      ctx.stroke()
      // 进度
      const p: number = Math.max(0, Math.min(100, this.systemInfo.cpuUsage)) / 100
      if (p > 0.01) {
        const g: CanvasGradient = ctx.createLinearGradient(cx - r, 0, cx + r, 0)
        g.addColorStop(0, '#FFC49B')
        g.addColorStop(1, this.theme.primary)
        ctx.beginPath()
        ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * p)
        ctx.strokeStyle = g
        ctx.stroke()
      }
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `drawCpuArc failed: ${e}`)
    }
  }

  /** 绘制 CPU 折线趋势图（按峰值自适应量程，低负载也能看出走势） */
  private drawCpuChart(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.cpuChartCtx
      const w: number = ctx.width
      const h: number = ctx.height
      if (w <= 0 || h <= 0) {
        return
      }
      ctx.clearRect(0, 0, w, h)
      if (this.cpuHistory.length < 2) {
        // 数据就绪前的占位：画一条浅色横条
        ctx.fillStyle = this.tint(this.theme.primary, 0.18)
        ctx.fillRect(0, h / 2 - 2, w, 4)
        return
      }
      const data: number[] = this.cpuHistory
      let peak: number = 0
      for (let i = 0; i < data.length; i++) {
        if (data[i] > peak) {
          peak = data[i]
        }
      }
      // 量程：峰值上浮 50%，最低 20%，低负载时曲线也落在波形中部
      const scale: number = Math.max(peak * 1.5, 20)
      const step: number = w / (data.length - 1)

      // 面积
      const area: CanvasGradient = ctx.createLinearGradient(0, 0, 0, h)
      area.addColorStop(0, this.tint(this.theme.primary, 0.30))
      area.addColorStop(1, this.tint(this.theme.primary, 0))
      ctx.beginPath()
      ctx.moveTo(0, h)
      for (let i = 0; i < data.length; i++) {
        ctx.lineTo(i * step, h - 2 - (data[i] / scale) * (h - 6))
      }
      ctx.lineTo(w, h)
      ctx.closePath()
      ctx.fillStyle = area
      ctx.fill()

      // 折线
      ctx.beginPath()
      for (let i = 0; i < data.length; i++) {
        const x: number = i * step
        const y: number = h - 2 - (data[i] / scale) * (h - 6)
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.strokeStyle = this.theme.chartColors[0]
      ctx.lineWidth = 1.8
      ctx.lineJoin = 'round'
      ctx.lineCap = 'round'
      ctx.stroke()
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `drawCpuChart failed: ${e}`)
    }
  }

  /** 内存已用/总量文本（如 256MB / 1.9GB） */
  memoryUsedText(): string {
    if (this.systemInfo.memoryTotal <= 0) {
      return '--'
    }
    return FormatUtils.formatBytes(this.systemInfo.memoryUsed)
  }

  /** 内存颜色（按使用率） */
  /** 由语义色生成半透明色（随皮肤切换） */
  tint(hex: string, alpha: number): string {
    let c: string = hex
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    let r: number = 0
    let g: number = 0
    let b: number = 0
    try {
      r = parseInt(c.substring(0, 2), 16)
      g = parseInt(c.substring(2, 4), 16)
      b = parseInt(c.substring(4, 6), 16)
    } catch (e) {
      return 'rgba(0,0,0,0.08)'
    }
    return `rgba(${r},${g},${b},${alpha})`
  }

  /** 由主色生成更深的同色系颜色（渐变底色用） */
  deepTint(hex: string): string {
    let c: string = hex
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    let r: number = 0
    let g: number = 0
    let b: number = 0
    try {
      r = parseInt(c.substring(0, 2), 16)
      g = parseInt(c.substring(2, 4), 16)
      b = parseInt(c.substring(4, 6), 16)
    } catch (e) {
      return hex
    }
    const k: number = 0.72
    return `rgb(${Math.round(r * k)},${Math.round(g * k)},${Math.round(b * k)})`
  }

  /** 图标投影色（同色系淡投影） */
  shadowTint(hex: string): string {
    return this.tint(hex, 0.32)
  }

  getMemColor(usage: number): string {
    if (usage < 60) return this.theme.info
    if (usage < 85) return this.theme.warning
    return this.theme.danger
  }

  /** 温度 → 仪表进度（0-100%），>90°C 视为满 */
  tempPercent(temp: number): number {
    if (temp <= 0) return 0
    return Math.min(100, Math.max(0, Math.round(temp * 100 / 90)))
  }

  /** 统一仪表颜色：绿(<30%)/蓝(<60%)/黄(<70%)/红(≥70%)，返回 [浅色, 深色] 渐变对 */
  getGaugeGradient(percent: number): string[] {
    if (percent < 30) {
      return [this.tint(this.theme.success, 0.55), this.theme.success]  // 绿色渐变（浅→深）
    }
    if (percent < 60) {
      return ['#90CAF9', '#1E88E5']  // 蓝色渐变（浅→深）
    }
    if (percent < 70) {
      return ['#FFE082', '#FFB300']  // 黄色渐变（浅→深）
    }
    return [this.tint(this.theme.danger, 0.55), this.theme.danger]    // 红色渐变（浅→深）
  }

  /** 温度仪表配色：绿(<30°C) / 蓝(<60°C) / 黄(<70°C) / 红(≥70°C)，返回 [浅色, 深色] */
  getTempGaugeGradient(temp: number): string[] {
    if (temp <= 0) {
      return [this.tint(this.theme.textTertiary, 0.4), this.theme.textTertiary]  // 无温度数据：灰色渐变
    }
    if (temp < 30) {
      return [this.tint(this.theme.success, 0.55), this.theme.success]  // 绿色渐变（浅→深）
    }
    if (temp < 60) {
      return ['#90CAF9', '#1E88E5']  // 蓝色渐变（浅→深）
    }
    if (temp < 70) {
      return ['#FFE082', '#FFB300']  // 黄色渐变（浅→深）
    }
    return [this.tint(this.theme.danger, 0.55), this.theme.danger]    // 红色渐变（浅→深）
  }

  /** 环形仪表卡片（Canvas 渐变圆弧） */
  @Builder
  gaugeCard(label: string, valueText: string, percent: number, color: string, ctx: CanvasRenderingContext2D, gradientOverride: string[]) {
    Column() {
      // 环形仪表（Canvas 渐变）
      Canvas(ctx)
        .width(76).height(76)
        .onReady(() => {
          // 首次绘制当前目标值（传入渐变对覆盖时用覆盖配色）
          this.drawGauge(ctx, Math.max(0, Math.min(100, percent)), color, gradientOverride)
        })
      // 中心数值（叠加在 Canvas 上方，数值与说明字号一致 10）
      Column() {
        Text(valueText)
          .fontSize(10)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(label)
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
      }
      .width(76).height(76)
      .position({ x: 0, y: 0 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .borderRadius(16)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(20))
    .border(this.cardBorder())
    .alignItems(HorizontalAlign.Center)
    .margin({ left: 3, right: 3 })
  }

  /** 数据更新后平滑动画过渡到新值（丝滑渐变） */
  private redrawGauges(): void {
    const cpu: number = Math.max(0, Math.min(100, this.systemInfo.cpuUsage))
    const mem: number = this.memoryPercent()
    const temp: number = this.tempPercent(this.systemInfo.cpuTemp)
    // 更新目标值：CPU / 内存 / 内存占用 / 温度
    this.gaugeTarget[0] = cpu
    this.gaugeTarget[1] = mem
    this.gaugeTarget[2] = mem
    this.gaugeTarget[3] = temp
    // 启动动画循环（若未运行）
    if (this.gaugeAnimTimer === -1) {
      this.gaugeAnimTimer = setInterval(() => {
        this.gaugeAnimTick()
      }, 16)
    }
  }

  /** 动画帧：当前值向目标值插值逼近，重绘 4 个仪表 */
  private gaugeAnimTick(): void {
    try {
      let done: boolean = true
      for (let i = 0; i < 4; i++) {
        const cur: number = this.gaugeCurrent[i]
        const tgt: number = this.gaugeTarget[i]
        if (Math.abs(tgt - cur) < 0.3) {
          this.gaugeCurrent[i] = tgt
        } else {
          // 每帧向目标靠近 18%（指数趋近，先快后慢，丝滑）
          this.gaugeCurrent[i] = cur + (tgt - cur) * 0.18
          done = false
        }
      }
      // 重绘（用插值后的当前值；注意 ctx 与 UI 布局顺序对应：CPU ctx0 / 内存 ctx1 / 内存占用 ctx3 / 温度 ctx2）
      this.drawGauge(this.gaugeCtx0, this.gaugeCurrent[0], this.getGaugeGradient(this.gaugeTarget[0])[0])
      this.drawGauge(this.gaugeCtx1, this.gaugeCurrent[1], this.getGaugeGradient(this.gaugeTarget[1])[0])
      this.drawGauge(this.gaugeCtx3, this.gaugeCurrent[2], this.getGaugeGradient(this.gaugeTarget[2])[0])
      // 温度仪表：按温度值分档配色（绿<30°C / 蓝<60°C / 黄<70°C / 红≥70°C）
      const tempColors: string[] = this.getTempGaugeGradient(this.systemInfo.cpuTemp)
      this.drawGauge(this.gaugeCtx2, this.gaugeCurrent[3], tempColors[0], tempColors)
      // 全部到位后停止动画
      if (done) {
        if (this.gaugeAnimTimer !== -1) {
          clearInterval(this.gaugeAnimTimer)
          this.gaugeAnimTimer = -1
        }
      }
    } catch (e) {
      hilog.error(0x0001, 'DashboardTab', `gaugeAnimTick err: ${JSON.stringify(e)}`)
      if (this.gaugeAnimTimer !== -1) {
        clearInterval(this.gaugeAnimTimer)
        this.gaugeAnimTimer = -1
      }
    }
  }

  /** 绘制渐变圆弧仪表 */
  private drawGauge(ctx: CanvasRenderingContext2D, percent: number, color: string, colorsOverride: string[] = []): void {
    try {
      const w: number = 76
      const h: number = 76
      const cx: number = w / 2
      const cy: number = h / 2
      const r: number = 30
      const startAngle: number = -Math.PI / 2  // 12 点方向
      const endAngle: number = startAngle + Math.PI * 2  // 整圆

      ctx.clearRect(0, 0, w, h)

      // 底环（灰色）
      ctx.strokeStyle = 'rgba(255,255,255,0.08)'
      ctx.lineWidth = 8
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()

      // 进度渐变圆弧：从起始点（12点）浅色 → 沿弧线均匀过渡到深色
      // 用分段绘制实现精确可控的弧线渐变（圆锥渐变角度语义不可靠）
      const colors: string[] = colorsOverride.length > 0 ? colorsOverride : this.getGaugeGradient(percent)
      const angle: number = Math.PI * 2 * Math.max(0, Math.min(100, percent)) / 100
      const segments: number = 24
      ctx.lineWidth = 8
      ctx.lineCap = 'round'
      for (let i = 0; i < segments; i++) {
        const t: number = i / segments  // 0（起始点浅色）→ 1（终点深色）
        const a0: number = startAngle + angle * i / segments
        const a1: number = startAngle + angle * (i + 1) / segments
        ctx.strokeStyle = this.lerpColor(colors[0], colors[1], t)
        ctx.beginPath()
        ctx.arc(cx, cy, r, a0, a1)
        ctx.stroke()
      }
    } catch (e) {
      hilog.error(0x0001, 'DashboardTab', `drawGauge err: ${JSON.stringify(e)}`)
    }
  }

  /** 两个 #RRGGBB 颜色按 t(0-1) 线性插值 */
  private lerpColor(c1: string, c2: string, t: number): string {
    try {
      const r1: number = parseInt(c1.substring(1, 3), 16)
      const g1: number = parseInt(c1.substring(3, 5), 16)
      const b1: number = parseInt(c1.substring(5, 7), 16)
      const r2: number = parseInt(c2.substring(1, 3), 16)
      const g2: number = parseInt(c2.substring(3, 5), 16)
      const b2: number = parseInt(c2.substring(5, 7), 16)
      const r: number = Math.round(r1 + (r2 - r1) * t)
      const g: number = Math.round(g1 + (g2 - g1) * t)
      const b: number = Math.round(b1 + (b2 - b1) * t)
      return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
    } catch (e) {
      return c1
    }
  }

  formatLocalTime(isoStr: string): string {
    try {
      // 将 ISO 格式时间字符串转为本地友好格式
      const d: Date = new Date(isoStr)
      return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`
    } catch (e) {
      // 解析失败时返回原始字符串兜底
      return isoStr
    }
  }

  getTypeColor(type: string): string {
    if (type === 'wan') {
      return this.theme.primary  // WAN 用主题主色
    }
    if (type === 'lan') {
      return this.theme.info  // LAN 用信息蓝
    }
    if (type === 'wifi') {
      return this.theme.success  // WiFi 用成功绿
    }
    return this.theme.textTertiary
  }

  getLanInterface(): NetworkInterface | null {
    // 遍历网络接口列表查找第一个 LAN 类型接口
    for (let i = 0; i < this.networkInterfaces.length; i++) {
      if (this.networkInterfaces[i].type === 'lan') {
        return this.networkInterfaces[i]
      }
    }
    return null
  }

  getLanIP(): string {
    const lanIf = this.getLanInterface()
    if (lanIf && lanIf.ipAddress) {
      return lanIf.ipAddress
    }
    return this.lanStatus.ipAddress !== '0.0.0.0' ? this.lanStatus.ipAddress : '--'
  }

  /** 快捷功能图标项（2 行 5 列，彩色实心图标直接浮在主背景上，不套圆底） */
  @Builder
  quickItem(name: string, route: string, bg: string, icon: string) {
    Column() {
      Row() {
        AppIcon({ name: icon, iconSize: 40 })
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      Text(name)
        .fontSize(10)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 5 })
    }
    .width('20%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
    .onClick(() => {
      if (route === 'apps:') {
        // 应用中心：分栏常驻中栏，点击即收起右侧应用；手机端全屏打开
        AppNav.getInstance().showApps()
      } else {
        AppNav.getInstance().open(route)
      }
    })
  }

  /** 系统资源进度条行（文字标签 + 细进度条 + 百分比） */
  @Builder
  resBar(label: string, percent: number, color: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
        Blank()
        Text(`${Math.round(percent)}%`)
          .fontSize(10)
          .fontColor(this.theme.textSecondary)
          .fontFamily('monospace')
      }
      .width('100%')

      Stack() {
        Row()
          .width('100%')
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.theme.progressTrack)
        Row()
          .width(`${Math.max(0, Math.min(100, percent))}%`)
          .height(4)
          .borderRadius(2)
          .backgroundColor(color)
      }
      .width('100%')
      .alignContent(Alignment.Start)
      .margin({ top: 4 })
    }
    .width('100%')
    .margin({ top: 10 })
  }

  /** 键值对行（主板卡） */
  @Builder
  kvRow(label: string, value: string) {
    Row() {
      Text(`${label}：`)
        .fontSize(10)
        .fontColor(this.theme.textTertiary)
      Text(value)
        .fontSize(10)
        .fontColor(this.theme.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 4 })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  /** 日志占用率（挂载点含 log 优先，否则第二个挂载点，无则 0） */
  logPercent(): number {
    if (this.mountPoints.length === 0) {
      return 0
    }
    for (let i = 0; i < this.mountPoints.length; i++) {
      if (this.mountPoints[i].mountPoint.indexOf('log') >= 0) {
        return Math.min(100, this.mountPoints[i].usedPercent)
      }
    }
    if (this.mountPoints.length > 1) {
      return Math.min(100, this.mountPoints[1].usedPercent)
    }
    return 0
  }

  /** 数据面板卡片（2×2） */
  @Builder
  dataCard(title: string, icon: string, value: string, sub: string, barPercent: number, barColor: string) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(13)
        Text(title)
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 5 })
        Blank()
      }
      .width('100%')

      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(barColor)
        .fontFamily('monospace')
        .width('100%')
        .margin({ top: 8 })
        .maxLines(1)

      Text(sub)
        .fontSize(10)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .margin({ top: 3 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (barPercent >= 0) {
        Stack() {
          Row()
            .width('100%')
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.theme.progressTrack)
          Row()
            .width(`${Math.max(0, Math.min(100, barPercent))}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(barColor)
        }
        .width('100%')
        .alignContent(Alignment.Start)
        .margin({ top: 10 })
      }
    }
    .width('48%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(cardTint(this.theme))
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
  }

  // ============================================================
  // 新版首页 UI（液态玻璃）：大数字主视觉 + 玻璃卡分层 + 告警前置
  // ============================================================

  /** 运行时长简写（10天14时 / 6时12分） */
  private uptimeShort(): string {
    const s: number = this.systemInfo.uptime
    if (s <= 0) {
      return '--'
    }
    const d: number = Math.floor(s / 86400)
    const h: number = Math.floor((s % 86400) / 3600)
    if (d > 0) {
      return `${d}天${h}时`
    }
    const m: number = Math.floor((s % 3600) / 60)
    return h > 0 ? `${h}时${m}分` : `${Math.floor(s / 60)}分`
  }

  /** CPU 采样峰值 */
  private cpuPeak(): number {
    let peak: number = 0
    for (let i = 0; i < this.cpuHistory.length; i++) {
      if (this.cpuHistory[i] > peak) {
        peak = this.cpuHistory[i]
      }
    }
    return Math.round(peak > 0 ? peak : this.systemInfo.cpuUsage)
  }

  /** 区块标题：中文 + 英文小注 + 右侧动作 */
  @Builder
  sectionHead(title: string, en: string, right: string) {
    Row() {
      Row() {
        Text(title)
          .fontSize(12.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(0.6)
        Text(en)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(1.4)
          .opacity(0.75)
          .margin({ left: 6 })
      }
      .alignItems(VerticalAlign.Bottom)

      Blank()

      if (right.length > 0) {
        Text(right)
          .fontSize(10.5)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width('100%')
    .padding({ left: 3, right: 3 })
    .margin({ top: 18, bottom: 9 })
  }

  /** 顶栏图标按钮（无底板，只有图标；三栏紧凑模式略小，压矮顶栏） */
  @Builder
  glassBtn(icon: string, badge: boolean, route: string) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        AppIcon({ name: icon, iconSize: this.compactHeader ? 16 : 19 })
      }
      .width(this.compactHeader ? 30 : 38)
      .height(this.compactHeader ? 30 : 38)
      .borderRadius(this.compactHeader ? 11 : 13)
      .justifyContent(FlexAlign.Center)

      if (badge) {
        Circle()
          .width(6)
          .height(6)
          .fill(this.theme.danger)
          .margin({ top: 7, right: 7 })
      }
    }
    .width(this.compactHeader ? 30 : 38)
    .height(this.compactHeader ? 30 : 38)
    .onClick(() => {
      AppNav.getInstance().open(route)
    })
  }

  /** 登出按钮（无底板，只有图标） */
  @Builder
  logoutBtn() {
    Row() {
      AppIcon({ name: 'power', iconSize: this.compactHeader ? 16 : 19 })
    }
    .width(this.compactHeader ? 30 : 38)
    .height(this.compactHeader ? 30 : 38)
    .borderRadius(this.compactHeader ? 11 : 13)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.logout()
    })
  }

  /** 登出：断开当前设备并退回设备列表 */
  private logout(): void {
    try {
      AppState.getInstance().requestSwitchDevice()
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/entry/LoginPage' })
    } catch (e) {
      hilog.error(0x0001, 'Dashboard', `logout nav err: ${String(e)}`)
    }
  }

  /** 卡片标题行（小图标 + 名称 + 右侧胶囊） */
  @Builder
  cardHead(icon: string, title: string, tag: string, tagColor: string) {
    Row() {
      AppIcon({ name: icon, iconSize: 19 })
      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textSecondary)
        .margin({ left: 7 })
      Blank()
      if (tag.length > 0) {
        Text(tag)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(tagColor)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .borderRadius(99)
          .backgroundColor(this.tint(tagColor, 0.13))
      }
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  /** 主视觉玻璃卡：下行大字 + 折线 + 三项指标 */
  @Builder
  heroCard() {
    Column() {
      Row() {
        Text('实时速率')
          .fontSize(10.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.primary)
          .letterSpacing(0.4)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(99)
          .backgroundColor(this.tint(this.theme.primary, 0.12))

        // 链路状态紧跟在「实时速率」右侧
        Row() {
          Circle()
            .width(5)
            .height(5)
            .fill(this.isOnline ? this.theme.success : this.theme.textTertiary)
          Text(this.isOnline ? '链路正常' : '未连接')
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isOnline ? this.theme.success : this.theme.textTertiary)
            .margin({ left: 5 })
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(99)
        .backgroundColor(this.tint(this.isOnline ? this.theme.success : this.theme.textTertiary, 0.12))
        .margin({ left: 6 })

        // 在线设备数
        Text(`${this.onlineClientCount} 台设备`)
          .fontSize(10.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.info)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(99)
          .backgroundColor(this.tint(this.theme.info, 0.12))
          .margin({ left: 6 })

        Blank()

        // ≒ 切换：折线图 ↔ 设备旋转视图
        Text('≒')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.orbitMode ? this.theme.primary : this.theme.textTertiary)
          .width(30)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.orbitMode ? this.tint(this.theme.primary, 0.12) : Color.Transparent)
          .onClick(() => {
            this.toggleOrbit()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.orbitMode) {
        // 设备旋转视图：核心刻度环 + 双椭圆轨道，速率读数居中
        Stack({ alignContent: Alignment.Center }) {
          Canvas(this.orbitCtx)
            .width('100%')
            .height(196)
            .onReady(() => {
              this.drawOrbit()
            })
          Column() {
            Text(this.speedValue(this.wanStatus.rxRate))
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.textPrimary)
              .letterSpacing(-1.5)
              .fontFamily('monospace')
            Row() {
              Text(this.speedUnit(this.wanStatus.rxRate))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textTertiary)
              Text(`↓ ${FormatUtils.formatSpeed(this.wanStatus.rxRate)} · ↑ ${FormatUtils.formatSpeed(this.wanStatus.txRate)}`)
                .fontSize(10)
                .fontColor(this.theme.success)
                .margin({ left: 6 })
                .maxLines(1)
            }
            .alignItems(VerticalAlign.Center)
            .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height(196)
        .margin({ top: 4 })
        .borderRadius(20)
        .clip(true)
      } else {
        Row() {
          Text(this.speedValue(this.wanStatus.rxRate))
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.textPrimary)
            .letterSpacing(-2)
            .fontFamily('monospace')
          Text(this.speedUnit(this.wanStatus.rxRate))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textTertiary)
            .margin({ left: 6, bottom: 9 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: 4 })

        Text() {
          Span('当前下行 · 上行 ')
            .fontSize(11.5)
            .fontColor(this.theme.textTertiary)
          Span(FormatUtils.formatSpeed(this.wanStatus.txRate))
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.success)
        }
        .width('100%')
        .margin({ top: 1 })

        Canvas(this.netChartCtx)
          .width('100%')
          .height(44)
          .margin({ top: 2 })
          .onReady(() => {
            this.drawNetChart()
          })
      }

      // 运行时长（原分割线以下的指标已移除，改为小字展示实际时长）
      Text(`运行时长：${this.uptimeText()}`)
        .fontSize(10.5)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: 17, right: 17, top: 15, bottom: 13 })
    .borderRadius(26)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.theme.material.blur)
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 10 })
  }

  /** 快捷操作项（一行 5 个）：去掉彩色底板，改为细边框 + 线条图标 */
  @Builder
  shortcutItem(name: string, route: string, icon: string) {
    Column() {
      Row() {
        AppIcon({ name: icon, iconSize: 22, forcePack: 'line', colors: [this.theme.textSecondary] })
      }
      .width(46)
      .height(46)
      .borderRadius(15)
      .justifyContent(FlexAlign.Center)
      .border(cardBorder(this.theme))
      Text(name)
        .fontSize(10.5)
        .fontColor(this.theme.textSecondary)
        .maxLines(1)
        .margin({ top: 6 })
    }
    .width('20%')
    .padding({ top: 2, bottom: 2 })
    .onClick(() => {
      if (route === 'apps:') {
        AppNav.getInstance().showApps()
      } else {
        AppNav.getInstance().open(route)
      }
    })
  }

  /** 处理器：半环仪表 + 参数 + 历史波形 */
  @Builder
  cpuCard() {
    Column() {
      this.cardHead('cpu', '处理器', this.systemInfo.cpuUsage < 30 ? '空闲' : '负载',
        this.systemInfo.cpuUsage < 30 ? this.theme.success : this.theme.warning)

      Row() {
        Stack({ alignContent: Alignment.Bottom }) {
          Canvas(this.cpuArcCtx)
            .width(118)
            .height(70)
            .onReady(() => {
              this.drawCpuArc()
            })
          Column() {
            Row() {
              Text(`${Math.round(this.systemInfo.cpuUsage)}`)
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textPrimary)
                .fontFamily('monospace')
              Text('%')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textSecondary)
                .margin({ left: 1, bottom: 3 })
            }
            .alignItems(VerticalAlign.Bottom)
            Text('LOAD')
              .fontSize(8.5)
              .fontColor(this.theme.textTertiary)
              .letterSpacing(1.4)
              .margin({ top: 1 })
          }
          .alignItems(HorizontalAlign.Center)
          .margin({ bottom: 4 })
        }
        .width(118)
        .height(70)

        Column() {
          this.cpuStat('温度', this.systemInfo.cpuTemp > 0 ? `${this.systemInfo.cpuTemp.toFixed(0)} °C` : '--')
          this.cpuStat('频率', this.systemInfo.cpuFreq > 0 ? `${this.systemInfo.cpuFreq} MHz` : '--')
          this.cpuStat('型号', this.systemInfo.cpuModel.length > 0 ? this.systemInfo.cpuModel : '--')
        }
        .layoutWeight(1)
        .margin({ left: 10 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Canvas(this.cpuChartCtx)
        .width('100%')
        .height(34)
        .margin({ top: 6 })
        .onReady(() => {
          this.drawCpuChart()
        })

      Row() {
        Text('近 30 次采样')
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
        Blank()
        Text(`峰值 ${this.cpuPeak()}%`)
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding(13)
    .borderRadius(cardRadius(this.theme))
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(22))
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cpuStat(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(10.5)
        .fontColor(this.theme.textSecondary)
      Blank()
      Text(value)
        .fontSize(11.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  /** 系统资源：内存 / 硬盘 / 日志 */
  @Builder
  resCard() {
    Column() {
      this.cardHead('square_stack_3d', '系统资源', '', '')
      this.resBar('内存', this.memPercent(), this.theme.success)
      this.resBar('硬盘', this.diskPercent(), this.theme.info)
      this.resBar('日志', this.logPercent(), this.theme.primary)
      Row() {
        Text(`已用 ${this.memoryUsedText()}`)
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
        Blank()
        Text(`共 ${FormatUtils.formatBytes(this.systemInfo.memoryTotal)}`)
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .margin({ top: 9 })
    }
    .width('48%')
    .padding(13)
    .borderRadius(cardRadius(this.theme))
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(22))
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
  }

  /** 网络：上下行速率 */
  @Builder
  netCard() {
    Column() {
      this.cardHead('wifi', '网络', this.isOnline ? '已连接' : '离线',
        this.isOnline ? this.theme.success : this.theme.textTertiary)

      Row() {
        Circle()
          .width(4.5)
          .height(4.5)
          .fill(this.theme.success)
        Text(this.lanStatus.interface.length > 0 ? this.lanStatus.interface : 'br-lan')
          .fontSize(9)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 4 })
        Blank()
        Text('实时')
          .fontSize(9)
          .fontColor(this.theme.success)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      // 实时下行折线（与预览图一致的迷你波形）
      Canvas(this.netMiniCtx)
        .width('100%')
        .height(30)
        .margin({ top: 2 })
        .onReady(() => {
          this.drawNetMini()
        })

      Row() {
        Column() {
          Row() {
            Text(this.speedValue(this.wanStatus.txRate))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.success)
              .fontFamily('monospace')
            Text(this.speedUnit(this.wanStatus.txRate))
              .fontSize(9)
              .fontColor(this.theme.textTertiary)
              .margin({ left: 2, bottom: 2 })
          }
          .alignItems(VerticalAlign.Bottom)
          Text('↑ 上行')
            .fontSize(8.5)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Column() {
          Row() {
            Text(this.speedValue(this.wanStatus.rxRate))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.info)
              .fontFamily('monospace')
            Text(this.speedUnit(this.wanStatus.rxRate))
              .fontSize(9)
              .fontColor(this.theme.textTertiary)
              .margin({ left: 2, bottom: 2 })
          }
          .alignItems(VerticalAlign.Bottom)
          Text('↓ 下行')
            .fontSize(8.5)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .margin({ top: 4 })

      // 今日累计流量
      Row() {
        Text('今日')
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
        Text(` ↓ ${FormatUtils.formatBytes(this.todayRx)}`)
          .fontSize(8.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.info)
        Text(` ↑ ${FormatUtils.formatBytes(this.todayTx)}`)
          .fontSize(8.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.success)
          .margin({ left: 6 })
      }
      .width('100%')
      .margin({ top: 10 })

      // WAN 地址
      Row() {
        Text('IP')
          .fontSize(8.5)
          .fontColor(this.theme.textTertiary)
        Text(` ${this.wanStatus.ipAddress.length > 0 ? this.wanStatus.ipAddress : '--'}`)
          .fontSize(8.5)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 2 })
        Blank()
      }
      .width('100%')
      .margin({ top: 3 })
    }
    .width('48%')
    .padding(13)
    .borderRadius(cardRadius(this.theme))
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(22))
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
  }

  /** 主板信息 */
  @Builder
  boardCard() {
    Column() {
      this.cardHead('cpu', '主板', '', '')
      Text(this.systemInfo.boardName.length > 0 ? this.systemInfo.boardName : '--')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 4 })
      this.boardKv('发行版', this.systemInfo.distribution.length > 0 ? this.systemInfo.distribution : '--')
      this.boardKv('版本', this.boardVersionText())
      this.boardKv('内核', this.systemInfo.kernel.length > 0 ? this.systemInfo.kernel : '--')
    }
    .width('100%')
    .padding(13)
    .borderRadius(cardRadius(this.theme))
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(22))
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .margin({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  boardKv(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(9.5)
        .fontColor(this.theme.textTertiary)
      Blank()
      Text(value)
        .fontSize(9.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 3.5, bottom: 3.5 })
    .border({ width: { top: 0.3 }, color: this.theme.borderGlass })
  }

  /** 磁盘使用（危险分区整行高亮） */
  @Builder
  diskCard() {
    Column() {
      if (this.mountPoints.length === 0) {
        Text('暂无挂载点数据')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .width('100%')
          .padding({ top: 6, bottom: 6 })
      } else {
        ForEach(this.mountPoints, (mp: MountPoint, idx: number) => {
          Column() {
            Row() {
              Text(mp.mountPoint)
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(mp.usedPercent >= 95 ? this.theme.textPrimary : this.theme.textSecondary)
                .fontFamily('monospace')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(`${mp.usedPercent.toFixed(1)}%`)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(mp.usedPercent >= 95 ? this.theme.danger : this.theme.textSecondary)
                .fontFamily('monospace')
                .margin({ left: 8 })
            }
            .width('100%')

            Stack() {
              Row()
                .width('100%')
                .height(5)
                .borderRadius(2.5)
                .backgroundColor(mp.usedPercent >= 95 ? this.tint(this.theme.danger, 0.2) : this.theme.progressTrack)
              Row()
                .width(`${Math.max(1.2, Math.min(100, mp.usedPercent))}%`)
                .height(5)
                .borderRadius(2.5)
                .backgroundColor(this.diskColor(mp.usedPercent))
            }
            .width('100%')
            .alignContent(Alignment.Start)
            .margin({ top: 6 })

            Row() {
              Text(`${FormatUtils.formatBytes(mp.used)} / ${FormatUtils.formatBytes(mp.size)}`)
                .fontSize(9)
                .fontColor(this.theme.textTertiary)
              Blank()
              Text(`可用 ${FormatUtils.formatBytes(mp.available)}`)
                .fontSize(9)
                .fontWeight(mp.available <= 0 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(mp.available <= 0 ? this.theme.danger : this.theme.textTertiary)
            }
            .width('100%')
            .margin({ top: 5 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(mp.usedPercent >= 95 ? 14 : 0)
          .backgroundColor(mp.usedPercent >= 95 ? this.tint(this.theme.danger, 0.08) : Color.Transparent)
          .margin({ top: idx > 0 ? 2 : 0 })
        }, (item: MountPoint): string => `disk_${item.mountPoint}`)
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(cardRadius(this.theme))
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(22))
    .border(this.cardBorder())
    .shadow(cardElevation(this.theme))
    .scale({ x: this.pressedCard ? 0.985 : 1, y: this.pressedCard ? 0.985 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setCardPressed(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setCardPressed(false)
      }
    })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column() {
        // ========== 顶栏：标题 + 图标按钮 ==========
        Row() {
          if (this.compactHeader) {
            // 三栏模式：标题与连接状态同行，压矮顶栏，让首个模块与其它栏顶边齐平
            Row() {
              Text('仪表盘')
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textPrimary)
              Row() {
                Circle()
                  .width(5.5)
                  .height(5.5)
                  .fill(this.isOnline ? this.theme.success : this.theme.textTertiary)
                Text(`${this.deviceLabel()} · ${this.isOnline ? '已连接' : '未连接'}`)
                  .fontSize(11)
                  .fontColor(this.theme.textSecondary)
                  .margin({ left: 5 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .margin({ left: 8 })
              .layoutWeight(1)
            }
            .layoutWeight(1)
          } else {
            Column() {
              Text('仪表盘')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textPrimary)
              Row() {
                Circle()
                  .width(5.5)
                  .height(5.5)
                  .fill(this.isOnline ? this.theme.success : this.theme.textTertiary)
                Text(`${this.deviceLabel()} · ${this.isOnline ? '已连接' : '未连接'}`)
                  .fontSize(11.5)
                  .fontColor(this.theme.textSecondary)
                  .margin({ left: 6 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }

          this.glassBtn('bell', !this.isOnline, 'pages/apps/NotifySettingsPage')
          Row().width(8)
          this.glassBtn('paintbrush', false, 'pages/apps/SkinManagePage')
          Row().width(8)
          this.logoutBtn()
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.compactHeader ? 2 : 4,
          bottom: this.compactHeader ? 6 : 10
        })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // ========== 告警 / 错误（首屏第一条） ==========
              if (this.errorText.length > 0) {
                Row() {
                  Row() {
                    Text('!')
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                  .width(30)
                  .height(30)
                  .borderRadius(10)
                  .linearGradient({ angle: 145, colors: [['#FF7A5C', 0.0], ['#E8341F', 1.0]] })
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 10 })

                  Column() {
                    Text(this.whimsyFish ? '🐟 网络在养鱼（真的断网了）' : '设备连接异常')
                      .fontSize(12.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme.textPrimary)
                    Text(this.errorText)
                      .fontSize(11)
                      .fontColor(this.theme.textSecondary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text('重试')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .padding({ left: 11, right: 11, top: 7, bottom: 7 })
                    .borderRadius(99)
                    .backgroundColor(this.theme.primary)
                    .onClick(() => {
                      this.loadData()
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 11, bottom: 11 })
                .borderRadius(19)
                .margin({ top: 10 })
                .linearGradient({
                  angle: 112,
                  colors: [[this.tint(this.theme.warning, 0.18), 0.0], [this.tint(this.theme.warning, 0.05), 0.6],
                    [this.theme.bgCard, 1.0]]
                })
                .border({ width: 0.5, color: this.tint(this.theme.warning, 0.35) })
                .onClick(() => {
                  if (Whimsy.tap('fish', 5)) {
                    this.whimsyFish = true
                    setTimeout(() => {
                      this.whimsyFish = false
                    }, 3000)
                  }
                })
              }

              // ========== 主视觉：下行速率 ==========
              this.heroCard()

              // ========== 快捷操作 ==========
              this.sectionHead('快捷操作', 'Actions', '全部')
              Row() {
                this.shortcutItem('文件', 'pages/apps/FileManagerPage', 'folder')
                this.shortcutItem('网络助手', 'pages/apps/NetworkHelperPage', 'AI_help_write')
                this.shortcutItem('Docker', 'pages/apps/DockerPage', 'docker')
                this.shortcutItem('SSH', 'pages/apps/SshTerminalPage', 'code_square')
                this.shortcutItem('应用中心', 'apps:', 'square_grid_2x2')
              }
              .width('100%')

              Row() {
                this.shortcutItem('排行', 'pages/apps/TrafficRankPage', 'arrow_up_right')
                this.shortcutItem('小管家', 'pages/pet/PetPage', 'heart')
                this.shortcutItem('相册', 'pages/apps/AlbumPage', 'ohos_photo')
                this.shortcutItem('OpenWRT', 'pages/apps/WebViewPage', 'wifi_router')
                this.shortcutItem('商店', 'pages/apps/StorePage', 'bag')
              }
              .width('100%')
              .margin({ top: 4 })

              // ========== 运行状态 ==========
              this.sectionHead('运行状态', 'Status', '')
              this.cpuCard()

              Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween,
                alignItems: ItemAlign.Stretch }) {
                this.resCard()
                this.netCard()
              }
              .width('100%')
              .margin({ top: 10 })

              this.boardCard()

              // ========== 磁盘使用 ==========
              this.sectionHead('磁盘使用', 'Storage', `${this.mountPoints.length} 个挂载点`)
              this.diskCard()
            }
            .width('100%')
            .padding({ left: 14, right: 14, bottom: this.bottomInset })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onDidScroll((y: number, _state: ScrollState) => {
            const diff = y - this.lastScrollY
            this.lastScrollY = y
            if (diff > 10 && y > 120) {
              AppState.getInstance().hideNav()
            } else if (diff < -10 && y < 80) {
              AppState.getInstance().showNav()
            }
          })
        }
      }
      .width('100%')
      .height('100%')

      // 满速彩蛋层（全屏覆盖，不拦截触摸）
      this.boomLayer()
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.pageBgColors()
    })
  }

  @Builder NetInterfaceRow(iface: NetworkInterface) {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .foregroundColor(iface.status === 'up' ? this.theme.success : this.theme.textTertiary)
        .margin({ right: 6 })
      Text(iface.ipAddress || '0.0.0.0')
        .fontSize(14)
        .fontColor(this.theme.primary)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: 8 })

    if (iface.macAddress) {
      Row() {
        Text('MAC  ')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
        Text(iface.macAddress)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
          .fontFamily('monospace')
      }
      .width('100%')
      .margin({ top: 2 })
    }

    if (iface.gateway || iface.mtu > 0) {
      Row() {
        if (iface.gateway) {
          Text(`网关 ${iface.gateway}`)
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
        }
        if (iface.gateway && iface.mtu > 0) {
          Text('  ·  ')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
        }
        Text(`MTU ${iface.mtu}`)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .margin({ top: 2 })
    }

    if (iface.rxBytes > 0 || iface.txBytes > 0) {
      Row() {
        Text(`↓ ${FormatUtils.formatBytes(iface.rxBytes)}`)
          .fontSize(11)
          .fontColor(this.theme.success)
        Text(`  ↑ ${FormatUtils.formatBytes(iface.txBytes)}`)
          .fontSize(11)
          .fontColor(this.theme.info)
      }
      .width('100%')
      .margin({ top: 4 })
    }
  }

  @Builder infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor(this.theme.textSecondary)
        .width(60)
      Text(value)
        .fontSize(11)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
