import { AppState } from '../../common/store/AppState'
import {ThemePalette} from '../../common/theme/ThemeColors'
import { SystemInfo, WanStatus, ConnectedDevice, NetworkInterface, MountPoint, ConntrackInfo, WirelessClient } from '../../models/Models'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { ApiService } from '../../api/ApiService'
import { TrafficStatStore } from '../../common/store/TrafficStatStore'
import { WidgetDataStore } from '../../common/store/WidgetDataStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { promptAction } from '@kit.ArkUI'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { Whimsy } from '../../common/utils/WhimsyUtil'
import { FunStore } from '../../common/store/FunStore'

// ============================================================
// DashboardTab - 首页
// ============================================================
@Component
export struct DashboardTab {
  @Prop theme: ThemePalette
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
  @State networkInterfaces: NetworkInterface[] = []
  @State boomShow: boolean = false     // 满速彩蛋显示
  @State boomTick: number = 0          // 彩蛋动画节拍
  private boomTimer: number = -1       // 彩蛋定时器
  private lastBoomTime: number = 0     // 上次彩蛋时间（冷却）
  @State onlineClientCount: number = 0
  private lastScrollY: number = 0
  private timerId: number = -1
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

  aboutToAppear(): void {
    // 底部导航占位（适配手势条 + 悬浮导航，随机型变化实时更新）
    this.bottomInset = AppState.getInstance().getBottomNavInset()
    this.navInsetListener = (inset: number) => {
      this.bottomInset = inset
    }
    AppState.getInstance().onBottomNavInsetChange(this.navInsetListener)
    // 流量统计存储初始化
    const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      TrafficStatStore.getInstance().init(hostCtx as Context)
      WidgetDataStore.init(hostCtx as Context)
    }
    // 前台感知：仅当本 Tab（首页 index 0）可见时轮询
    this.isVisible = AppState.getInstance().getCurrentTab() === 0
    this.tabChangeListener = (tab: number) => {
      const visible: boolean = tab === 0
      if (visible && !this.isVisible) {
        this.isVisible = true
        // 回到本 Tab 时立即刷新一次，然后恢复轮询
        this.refreshData()
        if (this.timerId === -1) {
          this.timerId = setInterval(() => { this.refreshData() }, 5000)
        }
      } else if (!visible && this.isVisible) {
        this.isVisible = false
        if (this.timerId !== -1) {
          clearInterval(this.timerId)
          this.timerId = -1
        }
      }
    }
    AppState.getInstance().onTabChange(this.tabChangeListener)
    // 首次加载数据，然后启动 5 秒轮询刷新
    this.loadData()
    if (this.isVisible) {
      this.timerId = setInterval(() => {
        this.refreshData()
      }, 5000)
    }
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    if (this.gaugeAnimTimer !== -1) {
      clearInterval(this.gaugeAnimTimer)
      this.gaugeAnimTimer = -1
    }
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
      const api = new ApiService()
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
      this.mountPoints = results[2]
      this.conntrack = results[3]
      this.networkInterfaces = results[4]
      this.onlineClientCount = this.countOnlineClients(results[5])
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
      const api = new ApiService()
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
      this.mountPoints = results[2]
      this.conntrack = results[3]
      this.onlineClientCount = this.countOnlineClients(results[4])
      this.isOnline = true
      // 流量统计：累计字节增量记入当天
      this.recordTraffic()
      // 设备作息采样：每整点记录一次在线设备，供 24h 热力图使用
      this.recordDeviceActivity(results[4] as ConnectedDevice[])
      // 桌面小组件数据同步（下载/上传速率 + 在线设备数）
      this.syncWidgetData()
      // CPU 历史采样（处理器卡片折线图）
      this.recordCpuHistory()
      this.handleConnectMoments()
    } catch (refErr) {
      // 刷新失败静默处理，不打断用户操作
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
        ip: this.wanStatus.ipAddress
      })
    } catch (e) {
      // 同步失败不影响主流程
    }
  }

  /** 累计当日流量（WAN 累计字节差值） */
  private async recordTraffic(): Promise<void> {
    try {
      const api = new ApiService()
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

  /** 记录 CPU 采样（折线图数据，保留 30 点） */
  recordCpuHistory(): void {
    this.cpuHistory.push(this.systemInfo.cpuUsage)
    if (this.cpuHistory.length > 30) {
      this.cpuHistory.shift()
    }
    this.drawCpuChart()
  }

  /** 绘制 CPU 折线趋势图（无坐标轴极简曲线） */
  private drawCpuChart(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.cpuChartCtx
      const w: number = 140
      const h: number = 44
      ctx.clearRect(0, 0, w, h)
      if (this.cpuHistory.length < 2) {
        // 数据就绪前的占位：画一条浅色横条
        ctx.fillStyle = 'rgba(255,138,61,0.18)'
        ctx.fillRect(0, h / 2 - 2, w, 4)
        return
      }
      const data: number[] = this.cpuHistory
      ctx.beginPath()
      const step: number = w / (data.length - 1)
      for (let i = 0; i < data.length; i++) {
        const x: number = i * step
        const y: number = h - 3 - (Math.min(100, data[i]) / 100) * (h - 6)
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.strokeStyle = this.theme.chartColors[0]
      ctx.lineWidth = 2
      ctx.lineJoin = 'round'
      ctx.lineCap = 'round'
      ctx.stroke()
    } catch (e) {}
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
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
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

  /** 快捷功能图标项（2 行 5 列，圆形马卡龙色底 + 白色线性图标） */
  @Builder
  quickItem(name: string, route: string, bg: string, icon: Resource) {
    Column() {
      Row() {
        Image(icon)
          .width(24)
          .height(24)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(bg)
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
      if (route.startsWith('tab:')) {
        // 切换主 Tab（iStore 商店 / Docker）
        const idx: number = Number(route.substring(4))
        AppState.getInstance().setCurrentTab(idx)
      } else {
        this.getUIContext().getRouter().pushUrl({ url: route })
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
    .backgroundColor(this.cardBg())
    .shadow(this.cardShadow())
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      // ========== 顶部标题栏（仪表盘 + 副标题 + 铃铛角标） ==========
      Row() {
        // 左侧仪表盘图标（AppScope SVG）
        Row() {
          Image($r('app.media.dashboard'))
            .width(22)
            .height(22)
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(this.theme.accentSoft)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (Whimsy.tap('dash_logo', 5)) {
            this.whimsyShake = true
            setTimeout(() => { this.whimsyShake = false }, 900)
            promptAction.showToast({ message: '小管在，别慌 🎩', duration: 1500 })
          }
        })
        .rotate({ angle: this.whimsyShake ? -8 : 0 })
        .animation({ duration: 60, iterations: 6, curve: Curve.EaseInOut })

        Column() {
          Text('仪表盘')
            .fontSize(20)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Bold)
          Text(`${this.deviceLabel()}${this.isOnline ? ' · 已连接' : ' · 未连接'}${this.festivalTag.length > 0 ? ' · ' + this.festivalTag : ''}`)
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })

        Blank()

        // 右侧：铃铛（无角标）
        Stack() {
          Image($r('app.media.app_bell'))
            .width(22)
            .height(22)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.theme.accentSoft)
        .alignContent(Alignment.Center)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/apps/NotifySettingsPage' })
        })

        // 右侧：皮肤管理
        Stack() {
          Image($r('app.media.skin_icon'))
            .width(22)
            .height(22)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.theme.accentSoft)
        .alignContent(Alignment.Center)
        .margin({ left: 8 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/apps/SkinManagePage' })
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 4, bottom: 10 })

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
            if (this.errorText) {
              Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
                Text('⚠')
                  .fontSize(16)
                  .margin({ right: 8 })
                Text(this.whimsyFish ? '🐟 网络在养鱼（真的断网了），连上设备我就能干活啦' : this.errorText)
                  .fontSize(12)
                  .fontColor(this.theme.warning)
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .margin({ top: 4, bottom: 4 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
              .onClick(() => {
                if (Whimsy.tap('fish', 5)) {
                  this.whimsyFish = true
                  setTimeout(() => { this.whimsyFish = false }, 3000)
                }
              })
            }

            // ===== 情感触点：时段问候 + 状态播报条 =====
            if (this.isOnline && (this.greetText.length > 0 || this.summaryText.length > 0)) {
              Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center }) {
                Text('💬')
                  .fontSize(13)
                  .margin({ right: 6 })
                Column() {
                  if (this.greetText.length > 0) {
                    Text(this.greetText)
                      .fontSize(12)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                  }
                  if (this.summaryText.length > 0) {
                    Text(this.summaryText)
                      .fontSize(10)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .margin({ top: 4, bottom: 4 })
              .backgroundColor(this.theme.bgCard)
              .backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
            }

            // ============ ① 设备总览大卡片 ============
            Row() {
              Column() {
                Text('ⓘ 系统信息')
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                Text(this.deviceLabel())
                  .fontSize(18)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Bold)
                  .margin({ top: 6 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row() {
                  Circle()
                    .width(6)
                    .height(6)
                    .foregroundColor(this.isOnline ? this.theme.success : this.theme.danger)
                  Text(this.isOnline ? '已连接' : '未连接')
                    .fontSize(12)
                    .fontColor(this.isOnline ? this.theme.success : this.theme.danger)
                    .fontWeight(FontWeight.Medium)
                    .margin({ left: 5 })
                }
                .margin({ top: 5 })
                // 情感触点：设备拟人状态
                if (this.moodText.length > 0) {
                  Text(this.moodText)
                    .fontSize(10)
                    .fontColor(this.theme.textSecondary)
                    .margin({ top: 3 })
                }
                Text(`版本 ${this.systemInfo.releaseVersion || this.systemInfo.firmwareVersion || '--'}`)
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 5 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`运行 ${this.systemInfo.uptime > 0 ? FormatUtils.formatUptime(this.systemInfo.uptime) : '--'}`)
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 右侧 NAS 机箱插图
              Image($r('app.media.nas'))
                .width(92)
                .height(92)
                .objectFit(ImageFit.Contain)
                .opacity(0.9)
            }
            .width('100%')
            .padding(18)
            .borderRadius(24)
            .backgroundColor(this.cardBg())
            .shadow(this.cardShadow())
            .margin({ top: 4 })

            // ============ 2 快捷功能区（2 行 5 列，直接浮在主背景上，无卡片框） ============
            Column() {
              Row() {
                this.quickItem('文件', 'pages/apps/FileManagerPage', '#A8C8A0', $r('app.media.folder_file'))
                this.quickItem('网络助手', 'pages/apps/NetworkHelperPage', '#B8A6E8', $r('app.media.ai_chat'))
                this.quickItem('Docker', 'tab:3', '#9FB8E8', $r('app.media.docker'))
                this.quickItem('SSH', 'pages/apps/SshTerminalPage', '#A0B8D8', $r('app.media.terminal'))
                this.quickItem('应用中心', 'pages/apps/AppsPage', '#FFB37A', $r('app.media.app_center'))
              }
              .width('100%')
              Row() {
                this.quickItem('排行', 'pages/apps/TrafficRankPage', '#F2D08A', $r('app.media.ranking'))
                this.quickItem('WiFi', 'pages/apps/WifiPage', '#8FB8E8', $r('app.media.wifi_icon'))
                this.quickItem('相册', 'pages/apps/AlbumPage', '#E8A8C0', $r('app.media.folder_file'))
                this.quickItem('体检', 'pages/apps/NetworkCheckPage', '#8FD6A5', $r('app.media.app_health'))
                this.quickItem('商店', 'tab:2', '#F0A8C0', $r('app.media.app_store'))
              }
              .width('100%')
              .margin({ top: 2 })
            }
            .width('100%')
            .margin({ top: 14 })

            // ============ 3 核心数据卡片区（2×2 四宫格） ============
            Row() {
              // 卡片1：处理器（大字 CPU% + 折线趋势 + 型号）
              Column() {
                Row() {
                  Image($r('app.media.cpu')).width(16).height(16)
                  Text('处理器').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                  Text('›').fontSize(14).fontColor(this.theme.textTertiary)
                }
                .width('100%')
                Row() {
                  Text(`${this.systemInfo.cpuUsage.toFixed(0)}%`)
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.primary)
                    .fontFamily('monospace')
                  Column() {
                    Text(this.systemInfo.cpuTemp > 0 ? `温度 ${this.systemInfo.cpuTemp.toFixed(0)}°C` : '温度 --')
                      .fontSize(10).fontColor(this.theme.textTertiary)
                    Text(`频率 ${this.systemInfo.cpuFreq} MHz`)
                      .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 10 })
                }
                .width('100%')
                .margin({ top: 8 })
                Canvas(this.cpuChartCtx)
                  .width(140)
                  .height(38)
                  .margin({ top: 4 })
                  .onReady(() => {
                    this.drawCpuChart()
                  })
                Text(this.systemInfo.cpuModel ? `${this.systemInfo.cpuModel}` : '--')
                  .fontSize(9)
                  .fontColor(this.theme.textTertiary)
                  .width('100%')
                  .margin({ top: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('48%')
              .height(158)
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)

              // 卡片2：系统资源（进度条列表：内存/硬盘/存储/日志）
              Column() {
                Row() {
                  Image($r('app.media.system_resources')).width(16).height(16)
                  Text('系统资源').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                  Text('›').fontSize(14).fontColor(this.theme.textTertiary)
                }
                .width('100%')
                this.resBar('内存', this.memoryPercent(), this.theme.success)
                this.resBar('硬盘', this.diskPercent(), this.theme.primary)
                this.resBar('日志', this.logPercent(), '#B8A6E8')
              }
              .width('48%')
              .height(158)
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 12 })

            Row() {
              // 卡片3：主板（型号大字 + 制造商/版本键值）
              Column() {
                Row() {
                  Image($r('app.media.motherboard')).width(16).height(16)
                  Text('主板').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                  Text('›').fontSize(14).fontColor(this.theme.textTertiary)
                }
                .width('100%')
                Text(this.systemInfo.boardName || this.systemInfo.model || '--')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.textPrimary)
                  .width('100%')
                  .margin({ top: 14 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                this.kvRow('制造商', this.systemInfo.model || '--')
                this.kvRow('版本', this.systemInfo.releaseVersion || this.systemInfo.firmwareVersion || '--')
                this.kvRow('内核', this.systemInfo.kernel || '--')
              }
              .width('48%')
              .height(158)
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)

              // 卡片4：网络（状态 + 实时速率）
              Column() {
                Row() {
                  Image($r('app.media.network')).width(16).height(16)
                  Text('网络').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                  Text('›').fontSize(14).fontColor(this.theme.textTertiary)
                }
                .width('100%')
                Row() {
                  Circle()
                    .width(6)
                    .height(6)
                    .foregroundColor(this.isOnline ? this.theme.success : this.theme.danger)
                  Text(this.wanStatus.interface || 'WAN')
                    .fontSize(12)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .margin({ left: 5 })
                  Blank()
                  Text(this.isOnline ? '已连接' : '未连接')
                    .fontSize(10)
                    .fontColor(this.isOnline ? this.theme.success : this.theme.danger)
                }
                .width('100%')
                .margin({ top: 8 })
                Row() {
                  Text('↑ 上行').fontSize(10).fontColor(this.theme.textTertiary)
                  Blank()
                  Text(FormatUtils.formatSpeed(this.wanStatus.rxRate))
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.theme.primary).fontFamily('monospace')
                }
                .width('100%')
                .margin({ top: 8 })
                Row() {
                  Text('↓ 下行').fontSize(10).fontColor(this.theme.textTertiary)
                  Blank()
                  Text(FormatUtils.formatSpeed(this.wanStatus.txRate))
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.theme.success).fontFamily('monospace')
                }
                .width('100%')
                .margin({ top: 6 })
              }
              .width('48%')
              .height(158)
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 12 })
            Row() {
              Column() {
                Row() {
                  Image($r('app.media.online_devices')).width(16).height(16)
                  Text('在线设备').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                }
                .width('100%')
                Text(`${this.onlineClientCount}`)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.primary)
                  .fontFamily('monospace')
                  .width('100%')
                  .margin({ top: 6 })
                Text('台设备当前在线')
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .width('100%')
                  .margin({ top: 2 })
              }
              .width('48%')
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)

              Column() {
                Row() {
                  Image($r('app.media.active_connections')).width(16).height(16)
                  Text('连接数').fontSize(12).fontColor(this.theme.textTertiary).margin({ left: 5 })
                  Blank()
                }
                .width('100%')
                Text(`${this.conntrack.current}`)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.conntrack.percent > 80 ? this.theme.warning : this.theme.success)
                  .fontFamily('monospace')
                  .width('100%')
                  .margin({ top: 6 })
                Text(`上限 ${this.conntrack.max}`)
                  .fontSize(10)
                  .fontColor(this.theme.textTertiary)
                  .width('100%')
                  .margin({ top: 2 })
              }
              .width('48%')
              .padding(16)
              .borderRadius(20)
              .backgroundColor(this.cardBg())
              .shadow(this.cardShadow())
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 12 })

            // ============ 磁盘详情 ============
            Column() {
              Row() {
                Image($r('app.media.disk'))
                  .width(16)
                  .height(16)
                Text('磁盘使用')
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 5 })
              }
                .width('100%')
                .margin({ bottom: 10 })
              if (this.mountPoints.length === 0) {
                Text('暂无挂载点数据')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .width('100%')
              } else {
                ForEach(this.mountPoints, (mp: MountPoint, idx: number) => {
                  Column() {
                    Row() {
                      Text(mp.mountPoint)
                        .fontSize(13)
                        .fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text(`${mp.usedPercent.toFixed(1)}%`)
                        .fontSize(13)
                        .fontColor(this.diskColor(mp.usedPercent))
                        .fontWeight(FontWeight.Bold)
                    }
                    .width('100%')
                    Row() {
                      Text(`${FormatUtils.formatBytes(mp.used)} / ${FormatUtils.formatBytes(mp.size)}`)
                        .fontSize(11)
                        .fontColor(this.theme.textTertiary)
                      Blank()
                      Text(`可用 ${FormatUtils.formatBytes(mp.available)}`)
                        .fontSize(11)
                        .fontColor(this.theme.textSecondary)
                    }
                    .width('100%')
                    .margin({ top: 2 })
                    Stack() {
                      Row()
                        .width('100%')
                        .height(4)
                        .borderRadius(2)
                        .backgroundColor(this.theme.progressTrack)
                      Row()
                        .width(`${Math.max(0, Math.min(100, mp.usedPercent))}%`)
                        .height(4)
                        .borderRadius(2)
                        .backgroundColor(this.diskColor(mp.usedPercent))
                    }
                    .width('100%')
                    .alignContent(Alignment.Start)
                    .margin({ top: 8 })
                  }
                  .width('100%')
                  .padding({ top: idx > 0 ? 10 : 0, bottom: idx < this.mountPoints.length - 1 ? 10 : 0 })
                  .border(idx < this.mountPoints.length - 1 ? { width: { bottom: 0.3 }, color: this.theme.borderGlass } : {})
                }, (item: MountPoint): string => item.mountPoint)
              }
            }
            .width('100%')
            .padding(16)
            .borderRadius(22)
            .backgroundColor(this.cardBg())
            .shadow(this.cardShadow())
            .margin({ top: 12 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: this.bottomInset })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onScroll((_x: number, y: number) => {
          const diff = y - this.lastScrollY
          this.lastScrollY = y
          if (diff > 10 && y > 120) {
            AppState.getInstance().hideNav()
          } else if (diff < -10 && y < 80) {
            AppState.getInstance().showNav()
          }
        })
      }

      // 满速彩蛋层（全屏覆盖，不拦截触摸）
      this.boomLayer()
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
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
