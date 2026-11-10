import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getAppVersionText } from '../../common/utils/AppVersion'
import { ApiService } from '../../api/ApiService'
import {
  AppClass, ConnectedDevice, ConntrackInfo, DockerOverview, IStoreApp, MountPoint,
  NetworkInterface, OafStatus, ProcessInfo, StartupItem, SystemInfo, WanStatus, WifiApInfo
} from '../../models/Models'
import { AppNav } from '../../common/utils/AppNav'
import { LIVE_REFRESH_MS } from '../../common/utils/RefreshRate'
import { LiveRateStore, RateListener } from '../../common/store/LiveRateStore'
import { AppIcon } from '../../common/components/AppIcon'
import { findPage, getPageGroups, PageEntry, PageGroupDef, searchPages } from '../../common/nav/PageRegistry'
import { curves } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { PetState, PetStore } from '../../common/store/PetStore'
import { DayTraffic, TrafficStatStore } from '../../common/store/TrafficStatStore'
import { DiaryStore } from '../../common/store/DiaryStore'
import { FunStore } from '../../common/store/FunStore'
import { NotifyStore } from '../../common/store/NotifyStore'
import { ScheduleStore, ScheduleTask } from '../../common/store/ScheduleStore'
import { WidgetDataStore } from '../../common/store/WidgetDataStore'
import { ImmichStore } from '../../common/store/ImmichStore'
import { JellyfinStore } from '../../common/store/JellyfinStore'
import { SecurityHistory, SecurityHubEngine } from '../../common/security/SecurityHubEngine'


interface ToolEntry {
  icon: string      // 系统符号图标（sys.symbol.*），全局统一线稿风格
  name: string
  desc: string
  route: string
  /** 磁贴底部实时指标：'pet' 显示饱食/能量/心情，'store' 显示已装插件数 */
  metric?: string
  /** 品牌图（有则替代线稿图标，如 Docker 官方 logo） */
  logo?: Resource
}

/** 分类分组 */
interface ToolGroup {
  title: string
  items: ToolEntry[]
}

/** 把 PageRegistry 的扁平清单还原成应用中心的磁贴分组（单一数据源） */
function buildToolGroups(): ToolGroup[] {
  const defs: PageGroupDef[] = getPageGroups()
  const out: ToolGroup[] = []
  for (let i = 0; i < defs.length; i++) {
    const items: ToolEntry[] = []
    for (let j = 0; j < defs[i].items.length; j++) {
      const p: PageEntry = defs[i].items[j]
      const tool: ToolEntry = { icon: p.icon, name: p.title, desc: p.desc, route: p.route }
      if (p.metric !== undefined) {
        tool.metric = p.metric
      }
      items.push(tool)
    }
    const group: ToolGroup = { title: defs[i].title, items: items }
    out.push(group)
  }
  return out
}

/** 图标底色渐变 */
interface IconGradient {
  angle: number
  colors: Array<[ResourceColor, number]>
}

/** 磁贴指标胶囊 */
class MetricChip {
  label: string = ''
  value: string = ''
  color: string = '#2E7BFF'
  bg: string = 'rgba(46,123,255,0.12)'
  constructor(label: string, value: string, color: string, bg: string) {
    this.label = label
    this.value = value
    this.color = color
    this.bg = bg
  }
}

@Entry
@Component
struct AppsPageRoute {
  build() {
    Column() {
      AppsPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct AppsPage {
  /** 嵌入分栏时透明背景，与其它栏共用同一块底 */
  @Prop embedded: boolean = false
  /** 顶栏上留白（三栏时由外部收紧，保证各栏首个模块顶边对齐） */
  @Prop topInset: number = 48
  @State theme: ThemePalette = LIGHT_THEME
  @State itemSlides: number[] = []
  @State deviceName: string = '未连接设备'
  @State deviceHost: string = ''
  @State deviceConnected: boolean = false
  @State versionText: string = getAppVersionText()
  @State savedCount: number = 0
  @State upText: string = '--'       // 运行时长（保持卡片样式不变，仅新增数据）
  // ===== Bento 顶部主卡实时数据 =====
  @State rateDown: number = 0        // 下行速率（B/s）
  @State rateUp: number = 0          // 上行速率（B/s）
  @State cpuPct: number = 0          // 处理器占用
  @State memPct: number = 0          // 内存占用
  @State connCount: number = 0       // 连接数
  @State rateSamples: number[] = []  // 下行速率采样（主卡迷你折线）
  @State cpuReady: boolean = false   // 处理器 / 内存是否已拿到数据
  @State connReady: boolean = false  // 连接数是否已拿到数据
  // ===== 磁贴实时指标：小管家（宠物状态）/ iStore 商店（已装插件数）=====
  @State petFull: number = 80        // 饱食度
  @State petEnergy: number = 50      // 能量
  @State petMood: number = 85        // 心情
  @State pluginCount: number = -1    // -1 = 尚未取到
  @State updatableCount: number = -1 // 商店里可更新的插件数
  // ===== Docker 磁贴：版本 + 容器数量 =====
  @State dockerVersion: string = ''
  @State dockerRunning: number = 0
  @State dockerTotal: number = -1    // -1 = 尚未取到
  @State dockerDaemon: string = ''
  private storeTimer: number = -1
  // ===== 磁贴通用指标（各应用胶囊共用的一批轻量数据）=====
  @State onlineDevices: number = -1
  @State totalDevices: number = -1
  @State wifiClients: number = -1
  @State ssidCount: number = -1
  @State wanIp: string = ''
  @State ifaceCount: number = -1
  @State connPercent: number = 0
  @State ethTotal: number = -1
  @State ethUp: number = -1
  @State todayTraffic: number = -1
  @State weekTraffic: number = -1
  @State processCount: number = -1
  @State startupTotal: number = -1
  @State startupEnabled: number = -1
  @State diskPercent: number = -1
  @State mountCount: number = -1
  @State oafRunning: boolean = false
  @State oafRules: number = -1
  @State securityScore: number = -1
  @State securityScans: number = 0
  @State notifyOn: boolean = false
  @State notifyHistory: number = 0
  @State scheduleCount: number = 0
  @State nextSchedule: string = ''
  @State skinName: string = ''
  @State fwVersion: string = ''
  @State kernelVersion: string = ''
  @State upDays: number = 0
  @State petLevel: number = 1
  @State petTasksDone: number = 0
  @State diaryDays: number = -1
  @State wolCount: number = -1
  @State usedDays: number = 0
  @State albumConfigured: boolean = false
  @State jellyfinConfigured: boolean = false
  @State widgetMetric: string = ''
  // ===== 全局搜索（标题 / 拼音首字母 / 最近使用）=====
  @State searchText: string = ''
  @State searchFocused: boolean = false
  private overviewTimer: number = -1
  private rateListener: RateListener | null = null
  private sparkCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  /** 左侧分类栏当前宽度（0 = 收起，RAIL_W = 完全展开）；拖动时逐帧更新，松手用弹簧补间 */
  @State railW: number = 0
  /** 分类栏是否处于展开态（仅供选中高亮 / 语义判断） */
  @State railOpen: boolean = false
  /** 当前高亮的分类下标（随滚动 / 点击更新） */
  @State activeGroup: number = 0
  private readonly RAIL_W: number = 92
  private dragBase: number = 0        // 本次拖动开始时的 railW
  private dragFromEdge: boolean = false
  private scroller: Scroller = new Scroller()
  private groupTops: number[] = []    // 各分组在滚动内容中的 y 偏移，用于分类跳转
  private api: ApiService = new ApiService()
  // 皮肤切换监听：应用中心是嵌在主页面里的常驻 Panel，不订阅的话换肤后背景/卡片会停留在旧配色
  private themeListener: (() => void) | null = null

  /** 磁贴分组：统一从 PageRegistry 生成，新增页面只改 PageRegistry */
  private groups: ToolGroup[] = buildToolGroups()

  /** 扁平化获取总数量用于动画 */
  private flatTools(): ToolEntry[] {
    const arr: ToolEntry[] = []
    for (const g of this.groups) {
      for (const t of g.items) arr.push(t)
    }
    return arr
  }

  /** 拉取远程最新版本并跳转关于页（version.json 发布信息） */
  /** 获取运行时长（只读 uptime，不改变卡片样式） */
  async loadUptime(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const sys: SystemInfo = await this.api.fetchSystemInfo()
      const u: number = sys.uptime
      if (u > 0) {
        const days: number = Math.floor(u / 86400)
        const hrs: number = Math.floor((u % 86400) / 3600)
        const mins: number = Math.floor((u % 3600) / 60)
        if (days > 0) {
          this.upText = `${days}天`
        } else if (hrs > 0) {
          this.upText = `${hrs}时`
        } else {
          this.upText = `${mins}分`
        }
      }
    } catch (e) {}
  }

  /** 全局速率回调：主卡读数 + 迷你折线与首页 / 小管家同源同频 */
  private onLiveRate(rx: number, tx: number): void {
    this.rateDown = rx
    this.rateUp = tx
    const arr: number[] = this.rateSamples.slice()
    arr.push(rx)
    if (arr.length > 24) arr.shift()
    this.rateSamples = arr
    this.drawSpark()
  }

  /** Bento 主卡：IP + 处理器 / 内存 / 连接（速率由全局心跳统一推送） */
  async loadOverview(): Promise<void> {
    hilog.info(0x0001, 'AppsPage', `overview start conn=${this.deviceConnected}`)
    if (!this.deviceConnected) return
    try {
      const lan: WanStatus = await this.api.fetchLanStatus()
      this.wanIp = lan.ipAddress && lan.ipAddress !== '0.0.0.0' ? lan.ipAddress : ''
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `overview rate failed: ${e}`)
    }
    try {
      const sys: SystemInfo = await this.api.fetchSystemInfo()
      this.cpuPct = Math.round(Math.max(0, Math.min(100, sys.cpuUsage)))
      const total: number = sys.memoryTotal
      if (total > 0) {
        const used: number = total - sys.memoryAvailable
        this.memPct = Math.round(Math.max(0, Math.min(100, used / total * 100)))
      }
      this.cpuReady = true
      this.fwVersion = sys.releaseVersion
      this.kernelVersion = sys.kernel
      this.upDays = sys.uptime > 0 ? Math.floor(sys.uptime / 86400) : 0
      hilog.info(0x0001, 'AppsPage', `overview sysinfo ok cpu=${this.cpuPct} mem=${this.memPct}`)
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `overview sysinfo failed: ${e}`)
    }
    try {
      const ct: ConntrackInfo = await this.api.fetchConntrack()
      this.connCount = ct.current
      this.connPercent = ct.percent
      this.connReady = true
      hilog.info(0x0001, 'AppsPage', `overview conntrack ok n=${this.connCount}`)
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `overview conntrack failed: ${e}`)
    }
  }

  /** 读取小管家宠物状态：磁贴上直接展示饱食度 / 能量 / 心情，不必进入页面 */
  private syncPet(): void {
    try {
      const s: PetState = PetStore.getInstance().getState()
      this.petFull = Math.round(Math.max(0, Math.min(100, s.full)))
      this.petEnergy = Math.round(Math.max(0, Math.min(100, s.energy)))
      this.petMood = Math.round(Math.max(0, Math.min(100, s.mood)))
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `syncPet failed: ${e}`)
    }
  }

  /** 宠物存储初始化（幂等，宠物页已初始化时直接复用） */
  private initPet(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) return
      PetStore.getInstance().init(ctx).then(() => {
        this.syncPet()
      })
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `initPet failed: ${e}`)
    }
  }

  /** iStore 已安装插件数：接口本身返回的就是已装列表，低频拉取即可 */
  async loadPluginCount(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const apps: IStoreApp[] = await this.api.fetchIStoreApps()
      this.pluginCount = apps.length
      let up: number = 0
      for (let i = 0; i < apps.length; i++) {
        if (apps[i].hasUpdate) up++
      }
      this.updatableCount = up
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `plugin count failed: ${e}`)
    }
  }

  /** Docker 版本与容器数量（供磁贴直接展示） */
  async loadDockerInfo(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const d: DockerOverview = await this.api.fetchDockerOverview()
      this.dockerVersion = d.dockerVersion
      this.dockerRunning = d.containersRunning
      this.dockerTotal = d.containersTotal
      this.dockerDaemon = d.daemonStatus
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `docker info failed: ${e}`)
    }
  }

  /** Docker 版本胶囊文案 */
  private dockerVerText(): string {
    if (this.dockerTotal < 0) return '同步中'
    if (this.dockerVersion.length === 0) return '未知版本'
    return this.dockerVersion.startsWith('v') ? this.dockerVersion : `v${this.dockerVersion}`
  }

  /** 容器数量胶囊文案：运行中 < 总数时显示 running/total */
  private dockerCountText(): string {
    if (this.dockerTotal < 0) return ''
    if (this.dockerDaemon === 'stopped' && this.dockerTotal === 0) return '未运行'
    if (this.dockerRunning > 0 && this.dockerRunning < this.dockerTotal) {
      return `${this.dockerRunning}/${this.dockerTotal} 个容器`
    }
    return this.dockerTotal === 1 ? '1 个容器' : `${this.dockerTotal} 个容器`
  }

  // ==================== 磁贴指标聚合 ====================

  /** 初始化磁贴指标依赖的本地存储（都可重复调用） */
  private initLocalStores(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) return
      TrafficStatStore.getInstance().init(ctx).then(() => this.syncLocalMetrics())
      DiaryStore.getInstance().init(ctx).then(() => this.syncLocalMetrics())
      FunStore.getInstance().init(ctx).then(() => this.syncLocalMetrics())
      NotifyStore.getInstance().init(ctx).then(() => this.syncLocalMetrics())
      ScheduleStore.getInstance().init(ctx).then(() => this.syncLocalMetrics())
      WidgetDataStore.init(ctx).then(() => {
        this.widgetMetric = WidgetDataStore.loadMetric()
      })
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `initLocalStores failed: ${e}`)
    }
  }

  /** 一分钟一轮：并发拉取各磁贴需要的轻量指标 */
  private loadTileMetrics(): void {
    this.loadDeviceStats()
    this.loadPortStats()
    this.loadWifiStats()
    this.loadSystemStats()
    this.loadOafStats()
    this.loadMediaStats()
    this.syncLocalMetrics()
  }

  private async loadDeviceStats(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const devs: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      let on: number = 0
      for (let i = 0; i < devs.length; i++) {
        if (devs[i].isOnline) on++
      }
      this.totalDevices = devs.length
      this.onlineDevices = on
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `tile devices failed: ${e}`)
    }
    try {
      const ifs: NetworkInterface[] = await this.api.fetchNetworkInterfaces()
      this.ifaceCount = ifs.length
    } catch (e) {}
  }

  /** 物理网口：DSA 固件下 eth0 只是 CPU 侧 conduit，面板口才是 lan/wan */
  private async loadPortStats(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const data: Object = await this.api.fetchEthPortStatuses()
      if (!data || typeof data !== 'object') return
      const rec: Record<string, Object> = data as Record<string, Object>
      const keys: string[] = Object.keys(rec)
      let hasDsa: boolean = false
      for (let i = 0; i < keys.length; i++) {
        const d: Object = rec[keys[i]]
        if (!d || typeof d !== 'object') continue
        if (((d as Record<string, Object>)['devtype'] as string) === 'dsa') hasDsa = true
      }
      let total: number = 0
      let up: number = 0
      for (let i = 0; i < keys.length; i++) {
        const d: Object = rec[keys[i]]
        if (!d || typeof d !== 'object') continue
        const dr: Record<string, Object> = d as Record<string, Object>
        const name: string = ((dr['name'] as string) || keys[i]).toLowerCase()
        const devtype: string = (dr['devtype'] as string) || ''
        if (this.isVirtualIface(name, devtype)) continue
        let physical: boolean = devtype === 'dsa' || this.isLanWanIface(name)
        if (!physical && !hasDsa) physical = name.startsWith('eth') || name.startsWith('en')
        if (!physical) continue
        total++
        let linked: boolean = (dr['up'] as boolean) === true
        const link: Object = dr['link'] as Object
        if (link && typeof link === 'object') {
          const carrier: Object = (link as Record<string, Object>)['carrier']
          if (typeof carrier === 'boolean') linked = linked && (carrier as boolean)
        }
        if (linked) up++
      }
      this.ethTotal = total
      this.ethUp = up
    } catch (e) {
      hilog.warn(0x0001, 'AppsPage', `tile eth ports failed: ${e}`)
    }
  }

  private isVirtualIface(lower: string, devtype: string): boolean {
    if (lower === 'lo') return true
    if (lower.startsWith('br-') || lower.startsWith('bond')) return true
    if (lower.startsWith('veth') || lower.startsWith('docker') || lower.startsWith('virbr')) return true
    if (lower.startsWith('wlan') || lower.startsWith('phy') || lower.startsWith('ra')) return true
    if (lower.startsWith('ppp') || lower.startsWith('tun') || lower.startsWith('tap')) return true
    if (lower.startsWith('wg') || lower.startsWith('sit') || lower.startsWith('gre')) return true
    if (lower.startsWith('vxlan') || lower.startsWith('dummy') || lower.startsWith('ifb')) return true
    return devtype === 'bridge' || devtype === 'vlan' || devtype === 'macvlan' || devtype === 'virt'
  }

  private isLanWanIface(lower: string): boolean {
    if (lower === 'lan' || lower === 'wan') return true
    let rest: string = ''
    if (lower.startsWith('lan')) rest = lower.substring(3)
    else if (lower.startsWith('wan')) rest = lower.substring(3)
    else return false
    if (rest.length === 0) return true
    for (let i: number = 0; i < rest.length; i++) {
      const c: number = rest.charCodeAt(i)
      if (c < 48 || c > 57) return false
    }
    return true
  }

  private async loadWifiStats(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const aps: WifiApInfo[] = await this.api.fetchWifiApList()
      this.ssidCount = aps.length
    } catch (e) {}
    try {
      const cs = await this.api.fetchWirelessClients()
      this.wifiClients = cs.length
    } catch (e) {}
  }

  private async loadSystemStats(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const ps: ProcessInfo[] = await this.api.fetchProcessList()
      this.processCount = ps.length
    } catch (e) {}
    try {
      const items: StartupItem[] = await this.api.fetchStartupItems()
      let en: number = 0
      for (let i = 0; i < items.length; i++) {
        if (items[i].enabled) en++
      }
      this.startupTotal = items.length
      this.startupEnabled = en
    } catch (e) {}
    try {
      const mps: MountPoint[] = await this.api.fetchMountPoints()
      this.mountCount = mps.length
      // 优先看根分区：overlay/tmpfs 这类伪分区经常恒定 100%，会误导
      let rootPct: number = -1
      let bigSize: number = 0
      let bigPct: number = 0
      for (let i = 0; i < mps.length; i++) {
        const m: MountPoint = mps[i]
        if (m.size <= 0) continue
        const p: number = Math.round(m.used / m.size * 100)
        if (m.mountPoint === '/') rootPct = p
        if (m.size > bigSize) {
          bigSize = m.size
          bigPct = p
        }
      }
      this.diskPercent = rootPct >= 0 ? rootPct : bigPct
    } catch (e) {}
  }

  private async loadOafStats(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const st: OafStatus = await this.api.fetchOafStatus()
      this.oafRunning = st.engineStatus === 'running' || st.filterStatus === 'enabled'
    } catch (e) {}
    try {
      const classes: AppClass[] = await this.api.fetchAppFilterClasses()
      this.oafRules = classes.length
    } catch (e) {}
  }

  private async loadMediaStats(): Promise<void> {
    const id: string = AppState.getInstance().getActiveDeviceId()
    if (!id) return
    try {
      const c = await ImmichStore.getInstance().getConfig(id)
      this.albumConfigured = c !== null
    } catch (e) {}
    try {
      const j = await JellyfinStore.getInstance().getConfig(id)
      this.jellyfinConfigured = j !== null
    } catch (e) {}
  }

  /** 本地存储类指标（同步读取，开销很小） */
  private syncLocalMetrics(): void {
    try {
      this.todayTraffic = TrafficStatStore.getInstance().getTodayTotal()
      const days: DayTraffic[] = TrafficStatStore.getInstance().getDays(7)
      let sum: number = 0
      for (let i = 0; i < days.length; i++) {
        sum += days[i].rx + days[i].tx
      }
      this.weekTraffic = sum
    } catch (e) {}
    try {
      this.diaryDays = DiaryStore.getInstance().getAll().length
    } catch (e) {}
    try {
      const fs: FunStore = FunStore.getInstance()
      this.wolCount = fs.getWolDevices().length
      this.usedDays = fs.getLevelUpDays()
    } catch (e) {}
    try {
      const ns: NotifyStore = NotifyStore.getInstance()
      this.notifyOn = ns.isEnabled()
      this.notifyHistory = ns.getHistory().length
    } catch (e) {}
    try {
      const ss: ScheduleStore = ScheduleStore.getInstance()
      const rb: ScheduleTask = ss.getRebootTask()
      const off: ScheduleTask = ss.getWifiOffTask()
      const on: ScheduleTask = ss.getWifiOnTask()
      let n: number = 0
      if (rb.enabled) n++
      if (off.enabled) n++
      if (on.enabled) n++
      this.scheduleCount = n
      let next: string = ''
      if (rb.enabled) next = rb.time
      else if (off.enabled) next = off.time
      else if (on.enabled) next = on.time
      this.nextSchedule = next
    } catch (e) {}
    try {
      this.skinName = AppState.getInstance().getSkin().name
    } catch (e) {}
    try {
      const h: SecurityHistory[] = SecurityHubEngine.getInstance().getHistory()
      if (h.length > 0 && typeof h[0].score === 'number') {
        this.securityScore = h[0].score
        this.securityScans = h.length
      }
    } catch (e) {}
    try {
      const st: PetState = PetStore.getInstance().getState()
      this.petLevel = st.level
      const done: boolean[] = PetStore.getInstance().getDoneTasks()
      let n: number = 0
      for (let i = 0; i < done.length; i++) {
        if (done[i]) n++
      }
      this.petTasksDone = n
    } catch (e) {}
  }

  // ==================== 各应用胶囊 ====================

  private mk(label: string, value: string, color: string): MetricChip {
    return new MetricChip(label, value, color, this.chipBg(color))
  }

  private chipBg(color: string): string {
    if (color === '#22C55E') return 'rgba(34,197,94,0.12)'
    if (color === '#FF8A3D') return 'rgba(255,138,61,0.12)'
    if (color === '#FF5C8A') return 'rgba(255,92,138,0.12)'
    if (color === '#17B8A6') return 'rgba(23,184,166,0.12)'
    if (color === '#7A5CFF') return 'rgba(122,92,255,0.12)'
    if (color === '#8A94A6') return 'rgba(120,140,160,0.12)'
    return 'rgba(46,123,255,0.12)'
  }

  private bytesText(b: number): string {
    if (b < 0) return '--'
    if (b >= 1073741824) return (b / 1073741824).toFixed(1) + 'G'
    if (b >= 1048576) return (b / 1048576).toFixed(0) + 'M'
    if (b >= 1024) return (b / 1024).toFixed(0) + 'K'
    return b.toFixed(0) + 'B'
  }

  private cnt(v: number, unit: string): string {
    return v >= 0 ? `${v}${unit}` : '--'
  }

  /** 固件版本取首段，避免 "25.12-SNAPSHOT (r0-xxxx)" 撑爆胶囊 */
  private fwShort(): string {
    if (this.fwVersion.length === 0) return '--'
    const sp: number = this.fwVersion.indexOf(' ')
    return sp > 0 ? this.fwVersion.substring(0, sp) : this.fwVersion
  }

  /** 小组件主指标的中文名 */
  private widgetMetricText(): string {
    const k: string = this.widgetMetric
    if (k === 'speed') return '网速'
    if (k === 'cpu') return '处理器'
    if (k === 'mem') return '内存'
    if (k === 'devices') return '设备数'
    if (k === 'traffic') return '流量'
    if (k === 'temp') return '温度'
    return k.length > 0 ? k : '默认'
  }

  /** 每个磁贴的 1~3 个胶囊（直接读 @State，由状态变化驱动刷新） */
  private chipsFor(tool: ToolEntry): MetricChip[] {
    const m: string = tool.metric ? tool.metric : ''
    const B: string = '#2E7BFF'
    const G: string = '#22C55E'
    const O: string = '#FF8A3D'
    const P: string = '#7A5CFF'
    const C: string = '#17B8A6'
    const K: string = '#FF5C8A'
    const X: string = '#8A94A6'
    switch (m) {
      case 'pet':
        return [this.mk('饱食', `${this.petFull}`, O), this.mk('能量', `${this.petEnergy}`, G), this.mk('心情', `${this.petMood}`, K)]
      case 'store': {
        const arr: MetricChip[] = [this.mk('已装', this.pluginCount >= 0 ? `${this.pluginCount} 个插件` : '同步中', B)]
        if (this.updatableCount > 0) {
          arr.push(this.mk('可更新', `${this.updatableCount} 个`, O))
        }
        return arr
      }
      case 'docker': {
        const arr: MetricChip[] = [this.mk('版本', this.dockerVerText(), C)]
        if (this.dockerTotal >= 0 && this.dockerCountText().length > 0) {
          arr.push(this.mk('容器', this.dockerCountText(), X))
        }
        return arr
      }
      case 'ip':
        return [this.mk('IP', this.deviceHost.length > 0 ? this.deviceHost : '未连接', P)]
      // ---- 网络 ----
      case 'security':
        return [
          this.mk('评分', this.securityScore >= 0 ? `${this.securityScore}` : '未扫描',
            this.securityScore >= 80 ? G : (this.securityScore >= 0 ? O : X)),
          this.mk('扫描', `${this.securityScans} 次`, B),
          this.mk('在线', this.cnt(this.onlineDevices, ' 台'), X)
        ]
      case 'wifi':
        return [this.mk('SSID', this.cnt(this.ssidCount, ' 个'), B), this.mk('无线', this.cnt(this.wifiClients, ' 台'), G)]
      case 'network':
        return [this.mk('IP', this.wanIp.length > 0 ? this.wanIp : '--', P), this.mk('接口', this.cnt(this.ifaceCount, ' 个'), X)]
      case 'trafficRank':
        return [this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G), this.mk('下行', `${this.rateValue(this.rateDown)} ${this.rateUnit(this.rateDown)}`, B)]
      case 'conntrack':
        return [this.mk('连接', this.connReady ? `${this.connCount}` : '--', B), this.mk('占用', this.connReady ? `${this.connPercent}%` : '--', X)]
      case 'portTraffic':
        return [this.mk('↓', `${this.rateValue(this.rateDown)} ${this.rateUnit(this.rateDown)}`, B), this.mk('↑', `${this.rateValue(this.rateUp)} ${this.rateUnit(this.rateUp)}`, O)]
      case 'ethPort':
        return [this.mk('物理口', this.cnt(this.ethTotal, ' 个'), P), this.mk('已连', this.cnt(this.ethUp, ' 个'), G)]
      case 'trafficReport':
        return [this.mk('今日', this.bytesText(this.todayTraffic), B), this.mk('7 天', this.bytesText(this.weekTraffic), C)]
      case 'netCheck':
        return [this.mk('连通', this.deviceConnected ? '正常' : '异常', this.deviceConnected ? G : O), this.mk('检测', '6 项', X)]
      case 'topology':
        return [this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G), this.mk('无线', this.cnt(this.wifiClients, ' 台'), B)]
      // ---- 多媒体 ----
      case 'album':
        return [this.mk('Immich', this.albumConfigured ? '已配置' : '未配置', this.albumConfigured ? G : X)]
      case 'jellyfin':
        return [this.mk('Jellyfin', this.jellyfinConfigured ? '已配置' : '未配置', this.jellyfinConfigured ? G : X)]
      // ---- 趣味 ----
      case 'smart':
        return [this.mk('陪伴', `${this.usedDays} 天`, O), this.mk('等级', `Lv.${this.petLevel}`, P), this.mk('任务', `${this.petTasksDone}/5`, G)]
      case 'milestone':
        return [this.mk('连续', `${this.upDays} 天`, O), this.mk('内存', `${this.memPct}%`, C)]
      case 'achievement':
        return [this.mk('陪伴', `${this.usedDays} 天`, O), this.mk('等级', `Lv.${this.petLevel}`, P)]
      case 'activity':
        return [this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G), this.mk('设备', this.cnt(this.totalDevices, ' 台'), X)]
      case 'diary':
        return [this.mk('记录', this.cnt(this.diaryDays, ' 天'), B), this.mk('今日', this.todayTraffic >= 0 ? this.bytesText(this.todayTraffic) : '--', C)]
      case 'report':
        return [this.mk('本周', this.bytesText(this.weekTraffic), B), this.mk('今日', this.bytesText(this.todayTraffic), C)]
      case 'fortune':
        return [this.mk('每日一签', '可抽', P), this.mk('陪伴', `${this.usedDays} 天`, O)]
      case 'mood':
        return [this.mk('心情', `${this.petMood}`, K), this.mk('等级', `Lv.${this.petLevel}`, P)]
      case 'wifiCard':
        return [this.mk('SSID', this.cnt(this.ssidCount, ' 个'), B), this.mk('在线', this.cnt(this.wifiClients, ' 台'), G)]
      case 'ecg':
        return [this.mk('下行', `${this.rateValue(this.rateDown)} ${this.rateUnit(this.rateDown)}`, B), this.mk('采样', `${this.rateSamples.length} 次`, X)]
      case 'speedTest':
        return [this.mk('下行', `${this.rateValue(this.rateDown)} ${this.rateUnit(this.rateDown)}`, B), this.mk('上行', `${this.rateValue(this.rateUp)} ${this.rateUnit(this.rateUp)}`, O)]
      case 'alias':
        return [this.mk('设备', this.cnt(this.totalDevices, ' 台'), X), this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G)]
      case 'dns':
        return [this.mk('状态', '待开赛', P), this.mk('延迟', '--', X)]
      case 'wol':
        return [this.mk('可唤醒', this.cnt(this.wolCount, ' 台'), O), this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G)]
      case 'shareCard':
        return [this.mk('在线', this.cnt(this.onlineDevices, ' 台'), G), this.mk('今日', this.bytesText(this.todayTraffic), B)]
      case 'level':
        return [this.mk('等级', `Lv.${this.petLevel}`, P), this.mk('在线天数', `${this.usedDays} 天`, O)]
      case 'bill':
        return [this.mk('今日', this.bytesText(this.todayTraffic), B), this.mk('本周', this.bytesText(this.weekTraffic), C)]
      // ---- 管理 ----
      case 'deviceManage':
        return [this.mk('在网', this.cnt(this.totalDevices, ' 台'), G), this.mk('在线', this.cnt(this.onlineDevices, ' 台'), B), this.mk('已存', this.cnt(this.savedCount, ' 台'), X)]
      case 'aiHelper':
        return [this.mk('AI', this.deviceConnected ? '就绪' : '离线', this.deviceConnected ? G : X), this.mk('设备', this.cnt(this.onlineDevices, ' 台'), B)]
      case 'oaf':
        return [this.mk('引擎', this.oafRunning ? '运行中' : '未运行', this.oafRunning ? G : X), this.mk('类目', this.cnt(this.oafRules, ' 个'), B)]
      case 'process':
        return [this.mk('进程', this.cnt(this.processCount, ' 个'), B), this.mk('CPU', `${this.cpuPct}%`, C)]
      case 'startup':
        return [this.mk('服务', this.cnt(this.startupTotal, ' 项'), B), this.mk('自启', this.cnt(this.startupEnabled, ' 项'), G)]
      case 'notify':
        return [this.mk('通知', this.notifyOn ? '已开启' : '已关闭', this.notifyOn ? G : X), this.mk('记录', this.cnt(this.notifyHistory, ' 条'), B)]
      case 'schedule':
        return [this.mk('任务', this.cnt(this.scheduleCount, ' 个'), B), this.mk('下次', this.nextSchedule.length > 0 ? this.nextSchedule : '未设置', X)]
      case 'skin':
        return [this.mk('当前', this.skinName.length > 0 ? this.skinName : '--', P)]
      case 'ssh':
        return [this.mk('状态', this.deviceConnected ? '已连接' : '未连接', this.deviceConnected ? G : X), this.mk('IP', this.deviceHost.length > 0 ? this.deviceHost : '--', P)]
      case 'files':
        return [this.mk('磁盘', this.cnt(this.diskPercent, '%'), this.diskPercent >= 80 ? O : C), this.mk('挂载', this.cnt(this.mountCount, ' 个'), X)]
      // ---- 系统 ----
      case 'netRestart':
        return [this.mk('连通', this.deviceConnected ? '正常' : '异常', this.deviceConnected ? G : O), this.mk('范围', '仅网络', X)]
      case 'packages':
        return [this.mk('固件', this.fwShort(), B), this.mk('内核', this.kernelVersion.length > 0 ? this.kernelVersion : '--', X)]
      case 'syslog':
        return [this.mk('运行', `${this.upDays} 天`, O), this.mk('内核', this.kernelVersion.length > 0 ? this.kernelVersion : '--', X)]
      case 'backup':
        return [this.mk('固件', this.fwShort(), B), this.mk('配置', '可导出', G)]
      case 'reboot':
        return [this.mk('已运行', `${this.upDays} 天`, O), this.mk('内存', `${this.memPct}%`, C)]
      case 'factory':
        return [this.mk('风险', '不可撤销', O), this.mk('建议', '先备份', X)]
      case 'widget':
        return [this.mk('指标', this.widgetMetricText(), P)]
      case 'about':
        return [this.mk('版本', this.versionText, B), this.mk('内核', this.kernelVersion.length > 0 ? this.kernelVersion : '--', X)]
      default:
        return []
    }
  }

  private chipCount(tool: ToolEntry): number {
    return this.chipsFor(tool).length
  }

  private chipAt(tool: ToolEntry, idx: number): MetricChip {
    const arr: MetricChip[] = this.chipsFor(tool)
    return idx < arr.length ? arr[idx] : new MetricChip('', '', '#2E7BFF', 'rgba(46,123,255,0.12)')
  }

  /** 速率数值 / 单位拆开，方便主卡大号数字排版 */
  private rateValue(v: number): string {
    if (v >= 1048576) return (v / 1048576).toFixed(1)
    if (v >= 1024) return (v / 1024).toFixed(1)
    return v.toFixed(0)
  }

  private rateUnit(v: number): string {
    if (v >= 1048576) return 'MB/s'
    if (v >= 1024) return 'KB/s'
    return 'B/s'
  }

  /** 十六进制颜色 + 透明度 → rgba 字符串（折线渐变面积用） */
  private tint(hex: string, alpha: number): string {
    const h: string = hex.replace('#', '')
    if (h.length !== 6) {
      return hex
    }
    const r: number = parseInt(h.substring(0, 2), 16)
    const g: number = parseInt(h.substring(2, 4), 16)
    const b: number = parseInt(h.substring(4, 6), 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }

  /** 折线主色：跟随皮肤图表色板（缺省回退主色） */
  private sparkColor(): string {
    const colors: string[] = this.theme.chartColors
    return colors.length > 0 ? colors[0] : this.theme.primary
  }

  /** 主卡迷你折线（渐变面积 + 主题色描边） */
  private drawSpark(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.sparkCtx
      const w: number = ctx.width
      const h: number = ctx.height
      if (w <= 0 || h <= 0) return
      const stroke: string = this.sparkColor()
      ctx.clearRect(0, 0, w, h)
      let data: number[] = this.rateSamples
      if (data.length < 2) data = [0, 0]
      let peak: number = 0
      for (let i = 0; i < data.length; i++) {
        if (data[i] > peak) peak = data[i]
      }
      const max: number = Math.max(peak * 1.6, 2048)
      const n: number = data.length
      const step: number = w / (n - 1)
      const top: number = 5
      const span: number = h - top - 5
      const area: CanvasGradient = ctx.createLinearGradient(0, 0, 0, h)
      area.addColorStop(0, this.tint(stroke, 0.26))
      area.addColorStop(1, this.tint(stroke, 0))
      ctx.beginPath()
      ctx.moveTo(0, h)
      for (let i = 0; i < n; i++) {
        ctx.lineTo(i * step, top + span - (data[i] / max) * span)
      }
      ctx.lineTo(w, h)
      ctx.closePath()
      ctx.fillStyle = area
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0, top + span - (data[0] / max) * span)
      for (let i = 1; i < n; i++) {
        ctx.lineTo(i * step, top + span - (data[i] / max) * span)
      }
      ctx.strokeStyle = stroke
      ctx.lineWidth = 1.7
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.stroke()
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `drawSpark failed: ${e}`)
    }
  }

  /** 磁贴渐变色板（未命中语义配色的项按名称散列取色，保证每次渲染颜色稳定） */
  private tilePalette: string[][] = [
    ['#60A5FA', '#2563EB'],
    ['#A78BFA', '#7C3AED'],
    ['#F472B6', '#DB2777'],
    ['#FBBF24', '#F59E0B'],
    ['#34D399', '#059669'],
    ['#22D3EE', '#0891B2'],
    ['#FB923C', '#EA580C'],
    ['#818CF8', '#4F46E5']
  ]

  private tileGradient(tool: ToolEntry): string[] {
    const r: string = tool.route
    if (r.indexOf('PetPage') >= 0) return ['#FF5A6E', '#F03B57']
    if (r.indexOf('StorePage') >= 0) return ['#2E7BFF', '#1B5FE0']
    if (r.indexOf('DockerPage') >= 0) return ['#17B8A6', '#0E9A8C']
    if (r.indexOf('WebViewPage') >= 0) return ['#7A5CFF', '#5B3DE8']
    if (r.indexOf('SecurityHubPage') >= 0) return ['#2E7BFF', '#1B5FE0']
    if (r.indexOf('WifiPage') >= 0) return ['#FF8A2B', '#F26B12']
    if (r.indexOf('NetworkPage') >= 0) return ['#FF7A2B', '#E85F14']
    if (r.indexOf('TrafficRankPage') >= 0) return ['#2E7BFF', '#1B5FE0']
    if (r.indexOf('ConntrackRankPage') >= 0) return ['#14B87A', '#0A9A63']
    if (r.indexOf('PortTrafficPage') >= 0) return ['#14B87A', '#0A9A63']
    if (r.indexOf('EthPortPage') >= 0) return ['#A855F7', '#8B2FE0']
    if (r.indexOf('TrafficReportPage') >= 0) return ['#14B87A', '#0A9A63']
    if (r.indexOf('TopologyPage') >= 0) return ['#6366F1', '#4F46E5']
    let h: number = 7
    for (let i = 0; i < tool.name.length; i++) {
      h = (h * 31 + tool.name.charCodeAt(i)) % 9973
    }
    return this.tilePalette[h % this.tilePalette.length]
  }

  /** Bento 行切分：首行两张主磁贴，其余每行 2 张，落单的一张升为整行横卡 */
  private bentoRows(items: ToolEntry[]): ToolEntry[][] {
    const rows: ToolEntry[][] = []
    let i: number = 0
    if (items.length >= 2) {
      rows.push([items[0], items[1]])
      i = 2
    }
    while (i < items.length) {
      const left: number = items.length - i
      if (left === 1) {
        rows.push([items[i]])
        i += 1
      } else {
        rows.push([items[i], items[i + 1]])
        i += 2
      }
    }
    return rows
  }

  /** 首行 56% + 40%，其余两列 48.5%，落单整行 */
  private tileWidth(rowIdx: number, colIdx: number, len: number): string {
    if (len === 1) return '100%'
    return rowIdx === 0 ? (colIdx === 0 ? '56%' : '40%') : '48.5%'
  }

  /** 横排磁贴高度：带指标胶囊的多留一行 */
  private tileHeight(len: number, hasMetric: boolean): number {
    if (len === 1) return 70
    return hasMetric ? 96 : 84
  }

  handleClick(tool: ToolEntry): void {
    // 关于页：直接进入，版本检查由页面内「检查更新」按钮触发（不再阻塞进入）
    if (tool.route === '__about__') {
      try {
        AppNav.getInstance().open('pages/other/AboutPage')
      } catch (e) {
        hilog.error(0x0001, 'AppsPage', `pushUrl failed: ${e}`)
      }
    } else {
      try {
        AppNav.getInstance().open(tool.route)
      } catch (e) {
        hilog.error(0x0001, 'AppsPage', `pushUrl failed: ${e}`)
      }
    }
  }

  aboutToAppear(): void {
    this.railW = 0
    this.railOpen = false
    this.theme = AppState.getInstance().getTheme()
    // 跟随皮肤切换实时刷新配色（Canvas 折线需手动重绘）
    this.themeListener = () => {
      this.theme = AppState.getInstance().getTheme()
      this.drawSpark()
    }
    AppState.getInstance().onThemeChange(this.themeListener)
    
    // 填充设备信息（仿应用商店「我的」个人卡片）
    const active = AppState.getInstance().getActiveDevice()
    this.deviceConnected = AppState.getInstance().isConnected()
    if (active) {
      this.deviceName = active.label || active.host || '路由器'
      this.deviceHost = active.host ? `${active.host}${active.port && active.port !== '80' ? ':' + active.port : ''}` : ''
    }
    this.savedCount = AppState.getInstance().devices.length
    this.loadUptime()
    // 实时速率：订阅全局心跳（与首页 / 小管家同一份数据、同一节奏）
    this.rateListener = (rx: number, tx: number) => { this.onLiveRate(rx, tx) }
    LiveRateStore.getInstance().subscribe(this.rateListener)
    // Bento 主卡其余指标（IP / CPU / 内存 / 连接）走较慢的节奏即可
    this.loadOverview()
    if (this.overviewTimer >= 0) {
      clearInterval(this.overviewTimer)
    }
    this.overviewTimer = setInterval(() => {
      this.loadOverview()
      this.syncPet()
    }, LIVE_REFRESH_MS * 2)

    // 磁贴指标：宠物状态本地同步读取；iStore 插件数走 HTTP，60 秒一次足够
    this.initPet()
    this.syncPet()
    this.initLocalStores()
    this.loadPluginCount()
    this.loadDockerInfo()
    this.loadTileMetrics()
    if (this.storeTimer >= 0) {
      clearInterval(this.storeTimer)
    }
    this.storeTimer = setInterval(() => {
      this.loadPluginCount()
      this.loadDockerInfo()
      this.loadTileMetrics()
    }, 60000)

    const tools: ToolEntry[] = this.flatTools()
    const slides: number[] = []
    for (let i = 0; i < tools.length; i++) slides.push(300)
    this.itemSlides = slides

    for (let i = 0; i < tools.length; i++) {
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseOut }, () => {
          const arr: number[] = [...this.itemSlides]
          arr[i] = 0
          this.itemSlides = arr
        })
      }, 50 * i)
    }
  }

  aboutToDisappear(): void {
    if (this.rateListener) {
      LiveRateStore.getInstance().unsubscribe(this.rateListener)
      this.rateListener = null
    }
    if (this.overviewTimer >= 0) {
      clearInterval(this.overviewTimer)
      this.overviewTimer = -1
    }
    if (this.storeTimer >= 0) {
      clearInterval(this.storeTimer)
      this.storeTimer = -1
    }
    if (this.themeListener) {
      AppState.getInstance().offThemeChange(this.themeListener)
      this.themeListener = null
    }
  }

  /** 切换设备：回到设备列表（连接状态保留在存储里，可随时切回） */
  switchDevice(): void {
    AppState.getInstance().requestSwitchDevice()
    try {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/entry/LoginPage' })
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `switchDevice nav err: ${String(e)}`)
    }
  }

  /** 获取全局动画索引 */
  getSlideIndex(groupIdx: number, itemIdx: number): number {
    let idx = 0
    for (let g = 0; g < groupIdx; g++) idx += this.groups[g].items.length
    return idx + itemIdx
  }

  /** 分组内双列分组（每行 2 个） */
  groupRows(items: ToolEntry[]): ToolEntry[][] {
    const rows: ToolEntry[][] = []
    for (let i = 0; i < items.length; i += 2) {
      rows.push(items.slice(i, i + 2))
    }
    return rows
  }

  // ================= 分类栏抽屉动画 =================

  /** 0 ~ 1 的展开进度，所有位移 / 透明度都从它推导，避免多份状态不同步 */
  private railProgress(): number {
    return this.railW / this.RAIL_W
  }

  /** Area.position 的类型是 Length（number | string | Resource），统一转成 vp 数值 */
  private toVp(v: Length | undefined): number {
    if (v === undefined) {
      return 0
    }
    if (typeof v === 'number') {
      return v as number
    }
    if (typeof v === 'string') {
      const n: number = parseFloat(v as string)
      return isNaN(n) ? 0 : n
    }
    return 0
  }

  private clampRail(v: number): number {
    if (v < 0) return 0
    if (v > this.RAIL_W) return this.RAIL_W
    return v
  }

  /** 第 idx 个分类项的渐显透明度：按序号错峰，拖到一半时呈现「依次浮现」 */
  private railItemAlpha(idx: number): number {
    const a: number = (this.railProgress() - idx * 0.028) * 2.6
    if (a < 0) return 0
    if (a > 1) return 1
    return a
  }

  /** 松手后的吸附：弹簧曲线，越界回弹更自然 */
  private snapRail(open: boolean): void {
    if (this.railOpen === open && Math.abs(this.railW - (open ? this.RAIL_W : 0)) < 0.5) {
      return
    }
    this.railOpen = open
    this.getUIContext().animateTo({
      duration: 360,
      curve: curves.springMotion(0.34, 0.82)
    }, () => {
      this.railW = open ? this.RAIL_W : 0
    })
  }

  /** 点击分类：滚动到对应分组并收起分类栏 */
  private jumpToGroup(idx: number): void {
    this.activeGroup = idx
    const top: number = this.groupTops[idx] !== undefined ? this.groupTops[idx] : 0
    try {
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: top > 6 ? top - 6 : 0,
        animation: { duration: 320, curve: Curve.EaseInOut }
      })
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `scrollTo group failed: ${e}`)
    }
    this.snapRail(false)
  }

  /** 滚动时同步高亮分类 */
  private syncActiveGroup(): void {
    const off: number = this.scroller.currentOffset().yOffset
    let idx: number = 0
    for (let i = 0; i < this.groupTops.length; i++) {
      const top: number = this.groupTops[i] !== undefined ? this.groupTops[i] : 0
      if (off + 48 >= top) idx = i
    }
    if (idx !== this.activeGroup) this.activeGroup = idx
  }

  /** 左侧分类栏（固定宽度，外层容器按拖动宽度裁切，文字不会被挤压变形） */
  @Builder
  categoryRail() {
    Column({ space: 2 }) {
      ForEach(this.groups, (group: ToolGroup, idx: number) => {
        Text(group.title)
          .fontSize(13)
          .fontWeight(idx === this.activeGroup ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(idx === this.activeGroup ? this.theme.textPrimary : this.theme.textSecondary)
          .maxLines(1)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .borderRadius(100)
          .backgroundColor(idx === this.activeGroup ? this.theme.bgCard : Color.Transparent)
          .border({
            width: idx === this.activeGroup ? 0.5 : 0,
            color: this.theme.borderGlass
          })
          .opacity(this.railItemAlpha(idx))
          .translate({ x: (1 - this.railProgress()) * 16 })
          .onClick(() => this.jumpToGroup(idx))
      }, (group: ToolGroup): string => `rail_${group.title}`)
    }
    .width(this.RAIL_W)
    .height('100%')
    .padding({ top: 12, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 图标多彩底色（按序号循环，同一套形状规范，颜色丰富） */
  private iconPalette: string[][] = [
    ['#60A5FA', '#2563EB'],
    ['#A78BFA', '#7C3AED'],
    ['#F472B6', '#DB2777'],
    ['#FBBF24', '#F59E0B'],
    ['#34D399', '#059669'],
    ['#22D3EE', '#0891B2'],
    ['#FB923C', '#EA580C'],
    ['#818CF8', '#4F46E5']
  ]

  private iconGradient(idx: number): IconGradient {
    const c: string[] = this.iconPalette[Math.abs(idx) % this.iconPalette.length]
    return { angle: 135, colors: [[c[0], 0], [c[1], 1]] }
  }

  /** 双列功能项（图标 + 名称，外层套圆角方框） */
  @Builder
  toolCard(tool: ToolEntry, slideIdx: number) {
    Column() {
      Row() {
        AppIcon({ name: tool.icon, iconSize: 34 })
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)

      Text(tool.name)
        .fontSize(11)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .alignItems(HorizontalAlign.Center)
    .opacity(this.itemSlides.length > slideIdx && this.itemSlides[slideIdx] === 0 ? 1 : 0)
    .translate({ x: this.itemSlides.length > slideIdx ? this.itemSlides[slideIdx] : 300 })
    .onClick(() => this.handleClick(tool))
  }

  // ================= Bento 磁贴 =================

  /** 磁贴图标：彩色渐变圆角块 + 白色线稿；有品牌图时改用白底 + 原图 */
  @Builder
  tileIcon(tool: ToolEntry) {
    if (tool.logo) {
      Row() {
        Image(tool.logo)
          .width(26).height(26).objectFit(ImageFit.Contain)
      }
      .width(34)
      .height(34)
      .borderRadius(11)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')
      .border({ width: 0.5, color: this.theme.borderGlass })
    } else {
      Row() {
        AppIcon({ name: tool.icon, iconSize: 18, colors: ['#FFFFFF'], forcePack: 'line' })
      }
      .width(34)
      .height(34)
      .borderRadius(11)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 148,
        colors: [[this.tileGradient(tool)[0], 0], [this.tileGradient(tool)[1], 1]]
      })
    }
  }

  /** 单枚指标胶囊 */
  @Builder
  chipView(tool: ToolEntry, idx: number) {
    Row() {
      Text(this.chipAt(tool, idx).label)
        .fontSize(8)
        .fontColor(this.theme.textTertiary)
      Text(this.chipAt(tool, idx).value)
        .fontSize(8.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.chipAt(tool, idx).color)
        .margin({ left: 3 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
    .borderRadius(5)
    .backgroundColor(this.chipAt(tool, idx).bg)
    .margin({ right: 4, bottom: 4 })
    .constraintSize({ maxWidth: 112 })
  }

  /** 顶部主卡：设备 + 实时速率 + 迷你折线 + 指标 */
  @Builder
  heroCard() {
    Column() {
      Row() {
        Row()
          .width(5)
          .height(5)
          .borderRadius(3)
          .backgroundColor(this.deviceConnected ? this.theme.success : this.theme.textTertiary)
        Text(`${this.deviceName} · 实时速率`)
          .fontSize(9.5)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(1)
          .margin({ left: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.deviceHost.length > 0 ? this.deviceHost : '未连接')
          .fontSize(9.5)
          .fontColor(this.theme.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.rateValue(this.rateDown))
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
        Text(this.rateUnit(this.rateDown))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 5, bottom: 5 })
        Blank()
        Text(`↑ ${this.rateValue(this.rateUp)} ${this.rateUnit(this.rateUp)}`)
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.accent)
          .backgroundColor(this.tint(this.theme.accent, 0.12))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(8)
          .margin({ bottom: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 2 })

      Canvas(this.sparkCtx)
        .width('100%')
        .height(46)
        .onReady(() => {
          this.drawSpark()
        })

      Flex({ wrap: FlexWrap.Wrap }) {
        Row() {
          Text('处理器').fontSize(9.5).fontColor(this.theme.textTertiary)
          Text(this.cpuReady ? `${this.cpuPct}%` : '--')
            .fontSize(9.5).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(7)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .margin({ right: 6, bottom: 6 })

        Row() {
          Text('内存').fontSize(9.5).fontColor(this.theme.textTertiary)
          Text(this.cpuReady ? `${this.memPct}%` : '--')
            .fontSize(9.5).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(7)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .margin({ right: 6, bottom: 6 })

        Row() {
          Text('连接').fontSize(9.5).fontColor(this.theme.textTertiary)
          Text(this.connReady ? `${this.connCount}` : '--')
            .fontSize(9.5).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(7)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .margin({ right: 6, bottom: 6 })

        Row() {
          Text('运行').fontSize(9.5).fontColor(this.theme.textTertiary)
          Text(this.upText)
            .fontSize(9.5).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(7)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .margin({ right: 6, bottom: 6 })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 12 })
    .borderRadius(24)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .onClick(() => {
      this.switchDevice()
    })
  }

  /** 单张磁贴：统一横排（图标在左，名称 / 描述 / 指标在右） */
  @Builder
  bentoTile(tool: ToolEntry, rowIdx: number, colIdx: number, len: number, slideIdx: number) {
    Row() {
      this.tileIcon(tool)

      Column() {
        Text(tool.name)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(tool.desc)
          .fontSize(9)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 磁贴指标胶囊（1~3 个，超出宽度自动换到第二行）
        if (this.chipCount(tool) > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.chipView(tool, 0)
            if (this.chipCount(tool) > 1) { this.chipView(tool, 1) }
            if (this.chipCount(tool) > 2) { this.chipView(tool, 2) }
          }
          .width('100%')
          .margin({ top: 6 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (len === 1) {
        Text('打开 ›')
          .fontSize(9.5)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width(this.tileWidth(rowIdx, colIdx, len))
    .height(this.tileHeight(len, tool.metric !== undefined))
    .padding({ left: len === 1 ? 14 : 12, right: len === 1 ? 14 : 12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(19)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .opacity(this.itemSlides.length > slideIdx && this.itemSlides[slideIdx] === 0 ? 1 : 0)
    .translate({ x: this.itemSlides.length > slideIdx ? this.itemSlides[slideIdx] : 300 })
    .onClick(() => this.handleClick(tool))
  }

  /** 分组：标题行 + Bento 栅格 */
  @Builder
  groupSection(group: ToolGroup, gIdx: number) {
    Column() {
      Row() {
        Text(group.title)
          .fontSize(13.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textPrimary)
        Text(String(group.items.length))
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 6 })
        Blank()
        Text('全部')
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 20, bottom: 9 })
      .alignItems(VerticalAlign.Center)

      ForEach(this.bentoRows(group.items), (row: ToolEntry[], rowIdx: number) => {
        Row() {
          ForEach(row, (tool: ToolEntry, colIdx: number) => {
            this.bentoTile(tool, rowIdx, colIdx, row.length,
              this.getSlideIndex(gIdx, rowIdx * 2 + colIdx))
          }, (tool: ToolEntry): string => `bt_${tool.name}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 9 })
      }, (row: ToolEntry[], rowIdx: number): string => `br_${rowIdx}`)
    }
    .width('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.groupTops[gIdx] = this.toVp(newArea.position.y)
    })
  }

  // ================= 全局搜索 / 命令面板 =================

  /** 搜索结果（按标题 / 拼音首字母 / 描述 / 路由打分，最多 8 条） */
  private searchHits(): PageEntry[] {
    return searchPages(this.searchText, 8)
  }

  /** 最近使用（AppNav 记录的最近 4 个功能页） */
  private recentHits(): PageEntry[] {
    const out: PageEntry[] = []
    const routes: string[] = AppNav.getInstance().getRecent()
    for (let i = 0; i < routes.length; i++) {
      const p: PageEntry | null = findPage(routes[i])
      if (p !== null) {
        out.push(p)
      }
    }
    return out
  }

  /** 点选结果：跳转并收起搜索 */
  private openPage(route: string): void {
    this.searchText = ''
    this.blurSearch()
    try {
      AppNav.getInstance().open(route)
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `open ${route} failed: ${e}`)
    }
  }

  /** 退出搜索聚焦：收起键盘、恢复完整应用列表 */
  private blurSearch(): void {
    this.searchFocused = false
    try {
      const fc = this.getUIContext().getFocusController()
      if (fc !== undefined) {
        fc.clearFocus()
      }
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `clearFocus failed: ${e}`)
    }
  }

  /** 单条功能（搜索结果 / 最近使用共用） */
  @Builder
  searchRow(p: PageEntry) {
    Row() {
      Row() {
        AppIcon({ name: p.icon, iconSize: 17, colors: [this.theme.primary] })
      }
      .width(32)
      .height(32)
      .borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.theme.bgGlassLight)

      Column() {
        Text(p.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(p.desc)
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      Text(p.group)
        .fontSize(9.5)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(12)
    .onClick(() => this.openPage(p.route))
  }

  /** 搜索结果列表 */
  @Builder
  searchResults(hits: PageEntry[]) {
    Column() {
      Row() {
        Text(hits.length > 0 ? `搜索到 ${hits.length} 个功能` : '没有匹配的功能')
          .fontSize(10)
          .fontColor(this.theme.textTertiary)
        Blank()
      }
      .width('100%')
      .padding({ left: 2, right: 2, bottom: 6 })

      if (hits.length === 0) {
        Column() {
          Text('试试拼音首字母：aqzx → 安全中心')
            .fontSize(11)
            .fontColor(this.theme.textSecondary)
          Text('也可以搜描述或英文名，如 docker / 流量')
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 26, bottom: 26 })
      } else {
        ForEach(hits, (p: PageEntry) => {
          this.searchRow(p)
        }, (p: PageEntry): string => `sr_${p.route}`)
      }
    }
    .width('100%')
    .padding({ top: 8 })
  }

  /** 最近使用（搜索框下方小胶囊，不替换主列表） */
  @Builder
  recentChips(hits: PageEntry[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      Text('最近')
        .fontSize(9.5)
        .fontColor(this.theme.textTertiary)
        .margin({ right: 6, top: 4 })
      ForEach(hits, (p: PageEntry) => {
        Row() {
          AppIcon({ name: p.icon, iconSize: 11 })
          Text(p.title)
            .fontSize(10)
            .fontColor(this.theme.textSecondary)
            .margin({ left: 4 })
            .maxLines(1)
        }
        .padding({ left: 7, right: 8, top: 4, bottom: 4 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgGlassLight)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .margin({ right: 6, top: 4 })
        .onClick(() => this.openPage(p.route))
      }, (p: PageEntry): string => `rc_${p.route}`)
    }
    .width('100%')
    .padding({ top: 2 })
  }

  /** 搜索框（平板分栏下 Ctrl+K 聚焦） */
  @Builder
  searchBar() {
    Row() {
      AppIcon({ name: 'magnifyingglass', iconSize: 15 })
      TextInput({ text: this.searchText, placeholder: '搜索功能，拼音首字母也行' })
        .key('app_search_input')
        .layoutWeight(1)
        .height(38)
        .padding({ left: 8, right: 4 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .placeholderColor(this.theme.textTertiary)
        .placeholderFont({ size: 12.5 })
        .fontColor(this.theme.textPrimary)
        .fontSize(13)
        .caretColor(this.theme.primary)
        .onChange((v: string) => {
          this.searchText = v
        })
        .onFocus(() => {
          this.searchFocused = true
        })
        .onBlur(() => {
          this.searchFocused = false
        })
      if (this.searchText.length > 0) {
        Row() {
          AppIcon({ name: 'xmark', iconSize: 12 })
        }
        .padding(4)
        .onClick(() => {
          this.searchText = ''
        })
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 8 })
    .borderRadius(12)
    .backgroundColor(this.theme.bgCard)
    .border({ width: 0.5, color: this.theme.borderGlass })
  }

  /** 嵌入分栏 + 薄玻璃时透明，让 MainPage 的统一背景透出 */
  private pageGradientColors(): Array<[ResourceColor, number]> {
    if (this.embedded && AppState.getInstance().isGlass()) {
      return [[Color.Transparent, 0], [Color.Transparent, 1]]
    }
    return this.theme.pageGradient
  }

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: this.pageGradientColors()
        })

      Column() {
        // 顶栏（固定不动，只有下方内容区随分类栏让位）
        Row() {
          Row() {
            Text(' 应用中心').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try { AppNav.getInstance().back() }
            catch (e) { hilog.error(0x0001, 'AppsPage', `router.back failed: ${e}`) }
          })

          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset, bottom: 8 })

        // ===== 全局搜索框（标题 / 拼音首字母 / 最近使用）=====
        Column() {
          this.searchBar()
          if (this.searchText.length === 0 && this.searchFocused && this.recentHits().length > 0) {
            this.recentChips(this.recentHits())
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 10 })

        // ===== 抽屉区：左侧分类栏 + 可被挤压的内容区 =====
        Row() {
          // 分类栏外层宽度跟手变化并裁切，内部固定宽度，所以文字不会变形
          Stack({ alignContent: Alignment.TopStart }) {
            this.categoryRail()
          }
          .width(this.railW)
          .height('100%')
          .clip(true)

          // 内容列表（仿鸿蒙应用商店「我的」排版）
          Scroll(this.scroller) {
          Column() {
            if (this.searchText.trim().length > 0) {
              // ===== 搜索结果（标题 / 拼音首字母 / 描述 / 英文名）=====
              this.searchResults(this.searchHits())
            } else {
              // ===== Bento 主卡：设备 + 实时速率 =====
              this.heroCard()

              // ===== 分组：Bento 磁贴栅格 =====
              ForEach(this.groups, (group: ToolGroup, gIdx: number) => {
                this.groupSection(group, gIdx)
              }, (group: ToolGroup): string => `grp_${group.title}`)

              // 底部版本信息
              Column() {
                Text('iStore 路由管家')
                  .fontSize(12).fontColor(this.theme.textTertiary)
                Text(`${this.versionText} · 开源 · HarmonyOS`)
                  .fontSize(10).fontColor(this.theme.textTertiary).opacity(0.7)
                  .margin({ top: 3 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 28, bottom: 40 })
            }
          }
          .width('100%')
          // 内容不足一屏时也从顶部开始（否则 Scroll 会把内容垂直居中）
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 4 })
          .onClick(() => this.blurSearch())
        }
        .layoutWeight(1)
        .height('100%')
        .scrollBar(BarState.Off)
        .padding({ top: 4 })
        .onScroll(() => this.syncActiveGroup())
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%').height('100%')
      // 水平拖动：右滑展开分类栏，左滑收起；与系统边缘返回手势区分（贴左边缘起手时不拦截）
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionStart((event: GestureEvent) => {
            this.dragBase = this.railW
            // 展开前先把高亮同步到当前滚动位置，避免显示上一次的分类
            this.syncActiveGroup()
            let startX: number = 100
            if (event.fingerList.length > 0) {
              startX = event.fingerList[0].localX
            }
            // 收起状态下，从最左 24vp 起手交给系统返回手势
            this.dragFromEdge = this.railW <= 1 && startX < 24
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.dragFromEdge) return
            this.railW = this.clampRail(this.dragBase + event.offsetX)
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.dragFromEdge) {
              this.dragFromEdge = false
              return
            }
            const v: number = event.velocityX
            let open: boolean
            if (v > 420) {
              open = true
            } else if (v < -420) {
              open = false
            } else {
              open = this.railW > this.RAIL_W * 0.38
            }
            this.snapRail(open)
          })
          .onActionCancel(() => {
            this.dragFromEdge = false
            this.snapRail(this.railW > this.RAIL_W * 0.5)
          })
      )
    }
    .width('100%').height('100%')
  }
}
