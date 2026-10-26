/**
 * AppNav — 双形态路由分发（手机全屏 / 平板右侧面板）
 *
 * 手机（< 600vp）：open → router.pushUrl 全屏打开，back → router.back
 * 平板（>= 600vp）：open → 推入右侧面板的 NavPathStack，back → 弹出面板
 *   （仅 EMBEDDABLE 白名单内的页面可内嵌，其余仍回落全屏，避免复杂交互页被压缩）
 *
 * 这样业务代码只依赖 AppNav，不用关心当前是大屏还是小屏。
 * 页面内嵌由 MainPage 的 Navigation + common/components/PageHost 完成。
 */
import { UIContext } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppState } from '../store/AppState'

/** 页面标题（右侧面板头部展示） */
const PAGE_TITLES: Record<string, string> = {
  'pages/apps/WifiPage': 'WiFi 管理',
  'pages/apps/TrafficRankPage': '流量排行',
  'pages/apps/NetworkCheckPage': '网络体检',
  'pages/apps/TrafficReportPage': '流量统计',
  'pages/security/SecurityHubPage': '安全中心',
  'pages/apps/FileManagerPage': '文件管理',
  'pages/apps/AppsPage': '应用中心',
  'pages/apps/StorePage': 'iStore 商店',
  'pages/apps/DockerPage': 'Docker',
  'pages/pet/PetPage': '小管家',
  'pages/apps/SmartHubPage': '智能管家',
  'pages/apps/AlbumPage': '相册',
  'pages/apps/JellyfinPage': 'Jellyfin',
  'pages/devices/ClientDetailPage': '设备详情',
  'pages/apps/SshTerminalPage': 'SSH 终端',
  'pages/apps/SpeedTestPage': '测速',
  'pages/apps/TopologyPage': '网络拓扑',
  'pages/apps/WolPage': '网络唤醒',
  'pages/apps/SchedulePage': '定时任务',
  'pages/apps/NotifySettingsPage': '通知设置',
  'pages/apps/WidgetSettingsPage': '小组件设置',
  'pages/apps/SkinManagePage': '皮肤管理',
  'pages/apps/TrafficBillPage': '流量账单',
  'pages/apps/DeviceActivityPage': '设备活跃',
  'pages/apps/DeviceManagePage': '设备管理',
  'pages/system/RebootPage': '重启路由器',
  'pages/system/PackageManagerPage': '软件包',
  'pages/system/SystemLogPage': '系统日志',
  'pages/system/ConfigBackupPage': '配置备份',
  'pages/other/AboutPage': '关于',
  'pages/other/HelpPage': '帮助',
  'pages/apps/DiaryPage': '网络日记',
  'pages/apps/FortunePage': '今日运势',
  'pages/apps/AchievementPage': '网络成就',
  'pages/apps/ConntrackRankPage': '连接排行',
  'pages/apps/DeviceAliasPage': '设备外号',
  'pages/apps/DnsBattlePage': 'DNS 擂台',
  'pages/apps/EthPortPage': '物理网口',
  'pages/apps/MileStonePage': '运行里程碑',
  'pages/apps/NetEcgPage': '网络心电图',
  'pages/apps/NetworkHelperPage': '设备辅助 AI',
  'pages/apps/NetworkPage': '网络管理',
  'pages/apps/NetworkReportPage': 'AI 周报',
  'pages/apps/OafPage': '家长控制',
  'pages/apps/PortTrafficPage': '网口流量',
  'pages/apps/RouterLevelPage': '路由器等级',
  'pages/apps/RouterMoodPage': '路由器心情',
  'pages/apps/ShareCardPage': '分享卡',
  'pages/apps/WifiCardPage': 'WiFi 访客卡',
  'pages/process/ProcessListPage': '系统进程',
  'pages/process/StartupPage': '启动项',
  'pages/system/FactoryResetPage': '恢复出厂',
  'pages/system/NetworkRestartPage': '重启网络'
}

/** 可在右侧面板内真正渲染的页面（其余显示"建议全屏"兜底卡） */
const EMBEDDABLE: string[] = [
  'pages/apps/AchievementPage',
  'pages/apps/AlbumPage',
  'pages/apps/ConntrackRankPage',
  'pages/apps/DeviceActivityPage',
  'pages/apps/DeviceAliasPage',
  'pages/apps/DeviceManagePage',
  'pages/apps/DiaryPage',
  'pages/apps/DnsBattlePage',
  'pages/apps/DockerPage',
  'pages/apps/EthPortPage',
  'pages/apps/FileManagerPage',
  'pages/apps/FortunePage',
  'pages/apps/JellyfinPage',
  'pages/apps/MileStonePage',
  'pages/apps/NetEcgPage',
  'pages/apps/NetworkCheckPage',
  'pages/apps/NetworkHelperPage',
  'pages/apps/NetworkPage',
  'pages/apps/NetworkReportPage',
  'pages/apps/NotifySettingsPage',
  'pages/apps/WidgetSettingsPage',
  'pages/apps/OafPage',
  'pages/apps/PortTrafficPage',
  'pages/apps/RouterLevelPage',
  'pages/apps/RouterMoodPage',
  'pages/apps/SchedulePage',
  'pages/apps/ShareCardPage',
  'pages/apps/SkinManagePage',
  'pages/apps/SmartHubPage',
  'pages/apps/SpeedTestPage',
  'pages/apps/SshTerminalPage',
  'pages/apps/StorePage',
  'pages/apps/TopologyPage',
  'pages/apps/TrafficBillPage',
  'pages/apps/TrafficRankPage',
  'pages/apps/TrafficReportPage',
  'pages/apps/WifiCardPage',
  'pages/apps/WifiPage',
  'pages/apps/WolPage',
  'pages/pet/PetPage',
  'pages/process/ProcessListPage',
  'pages/process/StartupPage',
  'pages/security/SecurityHubPage',
  'pages/system/ConfigBackupPage',
  'pages/system/FactoryResetPage',
  'pages/system/NetworkRestartPage',
  'pages/system/PackageManagerPage',
  'pages/system/RebootPage',
  'pages/system/SystemLogPage',
  'pages/other/AboutPage'
]

/** 无参数占位（ArkTS 不允许无类型对象字面量） */
class EmptyNavParam {
  readonly empty: boolean = true
}

const EMPTY_PARAM: EmptyNavParam = new EmptyNavParam()

export class AppNav {
  private static instance: AppNav | null = null
  private uiCtx: UIContext | null = null
  private stack: NavPathStack | null = null
  private recentList: string[] = []
  private recentListeners: (() => void)[] = []
  private panelListeners: (() => void)[] = []
  private lastUrl: string = ''

  static getInstance(): AppNav {
    if (!AppNav.instance) {
      AppNav.instance = new AppNav()
    }
    return AppNav.instance
  }

  setUIContext(ctx: UIContext): void {
    this.uiCtx = ctx
  }

  /** 右侧面板的导航栈（MainPage 创建后注册） */
  attachStack(stack: NavPathStack): void {
    this.stack = stack
  }

  detachStack(): void {
    this.stack = null
  }

  isWide(): boolean {
    return AppState.getInstance().isWideScreen()
  }

  /** 该页面能否在右侧面板内渲染 */
  canEmbed(url: string): boolean {
    return EMBEDDABLE.indexOf(url) >= 0
  }

  titleOf(url: string): string {
    const t: string = PAGE_TITLES[url]
    return t ? t : '功能'
  }

  /** 最近访问（右侧空态展示） */
  getRecent(): string[] {
    return this.recentList
  }

  onRecentChange(listener: () => void): void {
    if (this.recentListeners.indexOf(listener) < 0) {
      this.recentListeners.push(listener)
    }
  }

  /** 订阅右侧面板显隐变化（MainPage 用于刷新面板 UI） */
  onPanelChange(listener: () => void): void {
    if (this.panelListeners.indexOf(listener) < 0) {
      this.panelListeners.push(listener)
    }
  }

  offPanelChange(listener: () => void): void {
    const idx: number = this.panelListeners.indexOf(listener)
    if (idx >= 0) this.panelListeners.splice(idx, 1)
  }

  private notifyPanel(): void {
    for (const l of this.panelListeners) {
      try { l() } catch (e) {}
    }
  }

  /** 面板栈顶页面路径（空栈返回空串） */
  currentUrl(): string {
    if (!this.stack) return ''
    try {
      const names: string[] = this.stack.getAllPathName()
      return names.length > 0 ? names[names.length - 1] : ''
    } catch (e) {
      return this.lastUrl
    }
  }

  /** 面板栈深度（用于面板头部展示"返回上一级"） */
  depth(): number {
    if (!this.stack) return 0
    try {
      return this.stack.size()
    } catch (e) {
      return 0
    }
  }

  private pushRecent(url: string): void {
    const next: string[] = [url]
    for (let i = 0; i < this.recentList.length && next.length < 4; i++) {
      if (this.recentList[i] !== url) {
        next.push(this.recentList[i])
      }
    }
    this.recentList = next
    for (const l of this.recentListeners) {
      try { l() } catch (e) {}
    }
  }

  /**
   * 打开功能页
   * @param url 页面路径（与 main_pages.json 一致）
   * @param params 路由参数
   */
  open(url: string, params?: object): void {
    const stack: NavPathStack | null = this.stack
    // 大屏 + 面板栈可用 + 该页支持内嵌：直接推入右侧面板
    if (this.isWide() && stack !== null && this.canEmbed(url)) {
      this.lastUrl = url
      this.pushRecent(url)
      try {
        if (params) {
          stack.pushPathByName(url, params)
        } else {
          stack.pushPathByName(url, EMPTY_PARAM)
        }
      } catch (e) {
        hilog.error(0x0001, 'AppNav', `pushPathByName failed: ${JSON.stringify(e)}`)
      }
      this.notifyPanel()
      return
    }
    this.openFullscreen(url, params)
  }

  /** 强制全屏打开（兜底卡上的"全屏打开"按钮，或重交互页） */
  openFullscreen(url: string, params?: object): void {
    try {
      if (params) {
        this.uiCtx?.getRouter().pushUrl({ url: url, params: params })
      } else {
        this.uiCtx?.getRouter().pushUrl({ url: url })
      }
    } catch (e) {}
  }

  /** 返回：宽屏弹右侧栈，窄屏走路由返回 */
  back(): void {
    if (this.isWide() && this.stack) {
      // 分栏模式：只出栈；栈空时不做任何事（避免把主界面 pop 掉）
      if (this.stack.size() > 0) {
        try {
          this.stack.pop()
        } catch (e) {}
        this.notifyPanel()
      }
      return
    }
    try {
      this.uiCtx?.getRouter().back()
    } catch (e) {}
  }

  /**
   * 打开应用中心
   * - 分栏模式：应用中心常驻中栏，这里收起右侧应用、回到应用中心
   * - 手机单栏：全屏路由打开应用中心页面
   */
  showApps(): void {
    if (this.isWide() && this.stack) {
      this.clearPanel()
      return
    }
    this.openFullscreen('pages/apps/AppsPage')
  }

  /** 清空右侧面板（离开大屏或点关闭时） */
  clearPanel(): void {
    if (!this.stack) return
    try {
      if (this.stack.size() > 0) {
        this.stack.clear()
      }
    } catch (e) {}
    this.notifyPanel()
  }

  /** 当前面板是否为空 */
  isPanelEmpty(): boolean {
    if (!this.stack) return true
    try {
      return this.stack.size() <= 0
    } catch (e) {
      return true
    }
  }
}
