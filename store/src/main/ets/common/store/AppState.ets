/**
 * 应用全局状态管理器（单例）
 * 负责管理：
 * - 主题切换（深色/浅色模式，持久化到 Preferences）
 * - 设备列表管理（增删改查，通过 DeviceStore 持久化）
 * - 设备连接管理（连接/断开活动设备）
 * - 主题和设备变更的事件通知（观察者模式）
 *
 * 使用方式：
 *   AppState.getInstance().init(context)  // 应用启动时初始化
 *   AppState.getInstance().getTheme()     // 获取当前主题调色板
 *   AppState.getInstance().onThemeChange(() => { ... })  // 监听主题变化
 */
import { preferences } from '@kit.ArkData'
import { ApiClient } from '../../api/ApiClient'
import { ConnectionConfig } from '../../models/Models'
import { DeviceStore, SavedDevice } from './DeviceStore'
import { SshService } from '../ssh/SshService'
import { LIGHT_THEME, ThemePalette, SKINS, SkinDef, getSkinById } from '../theme/ThemeColors'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'AppState'
const DOMAIN = 0x0001
const PREFS_NAME = 'iStore_app_settings'  // Preferences 存储文件名

// 事件监听器类型定义
type ThemeListener = () => void
type DeviceListener = () => void

export class AppState {
  // ========== 单例模式 ==========
  private static instance: AppState

  // ========== 公开状态（会被 UI 组件绑定） ==========
  devices: SavedDevice[] = []          // 设备列表
  activeDeviceId: string = ''          // 当前活动设备 ID
  lastDeviceId: string = ''            // 上次使用的设备 ID（持久化，供自动重连）

  // ========== 内部状态 ==========
  private connected: boolean = false   // 当前是否已连接
  private lastError: string = ''       // 最后一次错误信息

  // ========== 持久化依赖 ==========
  private settingsPrefs: preferences.Preferences | null = null  // 应用设置存储
  private deviceStore: DeviceStore = DeviceStore.getInstance()  // 设备持久化存储
  private initialized: boolean = false                          // 是否已完成初始化

  // ========== 监听器列表 ==========
  private themeListeners: ThemeListener[] = []     // 主题变化监听器
  private deviceListeners: DeviceListener[] = []   // 设备列表变化监听器

  /**
   * 获取单例实例
   */
  static getInstance(): AppState {
    if (!AppState.instance) {
      AppState.instance = new AppState()
    }
    return AppState.instance
  }

  /**
   * 初始化：加载持久化的主题和设备数据
   * @param context 应用上下文（用于创建 Preferences）
   */
  async init(context: Context): Promise<void> {
    if (this.initialized) return  // 防止重复初始化

    // 初始化设备存储
    await this.deviceStore.init(context)

    // 初始化应用设置存储
    try {
      this.settingsPrefs = await preferences.getPreferences(context, PREFS_NAME)
      // 恢复上次皮肤
      const savedSkin: string = this.settingsPrefs.getSync('skinId', 'white') as string
      if (savedSkin && getSkinById(savedSkin).id === savedSkin) {
        this.currentSkinId = savedSkin
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Settings pref init failed: ${JSON.stringify(e)}`)
    }

    // 从持久化存储加载设备列表
    await this.loadDevices()
    // 恢复「上次使用的设备」，供冷启动自动重连
    this.lastDeviceId = this.deviceStore.loadActiveId()

    this.initialized = true
    hilog.info(DOMAIN, TAG, `Initialized: ${this.devices.length} devices, last=${this.lastDeviceId}`)
  }

  private navHidden: boolean = false
  private navListeners: (() => void)[] = []

  // ========== 当前主 Tab 索引（用于前台感知轮询）==========
  private currentTab: number = 0
  private tabListeners: ((tab: number) => void)[] = []

  /** 设置当前主 Tab 索引（MainPage 切换时调用） */
  setCurrentTab(tab: number): void {
    if (this.currentTab !== tab) {
      this.currentTab = tab
      for (const l of this.tabListeners) {
        try { l(tab) } catch (_e) {}
      }
    }
  }

  /** 获取当前主 Tab 索引 */
  getCurrentTab(): number {
    return this.currentTab
  }

  /** 订阅主 Tab 切换 */
  onTabChange(listener: (tab: number) => void): void {
    if (!this.tabListeners.includes(listener)) {
      this.tabListeners.push(listener)
    }
  }

  /** 取消订阅主 Tab 切换 */
  offTabChange(listener: (tab: number) => void): void {
    const idx: number = this.tabListeners.indexOf(listener)
    if (idx >= 0) {
      this.tabListeners.splice(idx, 1)
    }
  }

  hideNav(): void {
    if (!this.navHidden) {
      this.navHidden = true
      for (const l of this.navListeners) {
        try { l() } catch (_e) {}
      }
    }
  }

  showNav(): void {
    if (this.navHidden) {
      this.navHidden = false
      for (const l of this.navListeners) {
        try { l() } catch (_e) {}
      }
    }
  }

  isNavHidden(): boolean {
    return this.navHidden
  }

  onNavChange(listener: () => void): void {
    if (!this.navListeners.includes(listener)) {
      this.navListeners.push(listener)
    }
  }

  offNavChange(listener: () => void): void {
    const idx = this.navListeners.indexOf(listener)
    if (idx >= 0) this.navListeners.splice(idx, 1)
  }

  // ========== 底部导航安全区（悬浮主导航条占用高度，随机型/导航模式变化）==========
  // 组成：系统导航条高度（手势 24vp / 三键 48vp）+ 悬浮间距 4 + HdsTabs 导航条高度 + 内容间隙
  private bottomNavInset: number = 134  // 默认：24(手势导航条) + 110
  private navInsetListeners: ((inset: number) => void)[] = []

  /** 设置主页悬浮导航条占用的底部空间（MainPage 根据机型安全区计算后广播） */
  setBottomNavInset(inset: number): void {
    if (inset > 0 && inset !== this.bottomNavInset) {
      this.bottomNavInset = inset
      for (const l of this.navInsetListeners) {
        try { l(inset) } catch (_e) {}
      }
    }
  }

  /** 获取主页悬浮导航条占用的底部空间（供子页做相对布局避免遮挡） */
  getBottomNavInset(): number {
    return this.bottomNavInset
  }

  /** 订阅底部导航 inset 变化（机型安全区确认后触发） */
  onBottomNavInsetChange(listener: (inset: number) => void): void {
    if (!this.navInsetListeners.includes(listener)) {
      this.navInsetListeners.push(listener)
    }
  }

  /** 取消订阅底部导航 inset 变化 */
  offBottomNavInsetChange(listener: (inset: number) => void): void {
    const idx = this.navInsetListeners.indexOf(listener)
    if (idx >= 0) this.navInsetListeners.splice(idx, 1)
  }

  // ========== 大屏（平板/折叠展开）断点状态 ==========
  // 宽度 >= 600vp 视为大屏：主界面缩到左侧，功能页展开到右侧面板
  private wideScreen: boolean = false
  private wideListeners: ((wide: boolean) => void)[] = []

  /** 设置是否为大屏（MainPage 监听窗口尺寸后广播） */
  setWideScreen(wide: boolean): void {
    if (this.wideScreen !== wide) {
      this.wideScreen = wide
      for (const l of this.wideListeners) {
        try { l(wide) } catch (_e) {}
      }
    }
  }

  /** 当前是否大屏双栏模式 */
  isWideScreen(): boolean {
    return this.wideScreen
  }

  onWideScreenChange(listener: (wide: boolean) => void): void {
    if (!this.wideListeners.includes(listener)) {
      this.wideListeners.push(listener)
    }
  }

  offWideScreenChange(listener: (wide: boolean) => void): void {
    const idx: number = this.wideListeners.indexOf(listener)
    if (idx >= 0) this.wideListeners.splice(idx, 1)
  }

  // ========== 相册子视图状态（供 MainPage 拦截返回手势） ==========

  private albumSubViewActive: boolean = false
  private albumBackListeners: (() => void)[] = []

  /** 设置相册是否处于子视图（相册详情/全部照片） */
  setAlbumSubView(active: boolean): void {
    this.albumSubViewActive = active
  }

  /** 相册是否处于子视图 */
  isAlbumSubView(): boolean {
    return this.albumSubViewActive
  }

  /** 注册相册返回回调（返回 true 表示已处理，阻止默认返回） */
  onAlbumBack(listener: () => void): void {
    if (!this.albumBackListeners.includes(listener)) {
      this.albumBackListeners.push(listener)
    }
  }

  offAlbumBack(listener: () => void): void {
    const idx: number = this.albumBackListeners.indexOf(listener)
    if (idx >= 0) this.albumBackListeners.splice(idx, 1)
  }

  /** 通知相册退出子视图（由 MainPage 的 onBackPress 触发） */
  notifyAlbumBack(): void {
    for (const l of this.albumBackListeners) {
      try { l() } catch (_e) {}
    }
  }

  // ========== 主题管理 ==========

  /** 当前皮肤 id（持久化，默认 white 纯净白） */
  private currentSkinId: string = 'white'

  /**
   * 获取当前皮肤定义
   */
  getSkin(): SkinDef {
    return getSkinById(this.currentSkinId)
  }

  /**
   * 获取当前主题调色板（跟随当前皮肤）
   */
  getTheme(): ThemePalette {
    return this.getSkin().theme
  }

  /**
   * 切换皮肤并持久化，通知全应用刷新
   */
  setSkin(id: string): void {
    const skin: SkinDef = getSkinById(id)
    if (skin.id === this.currentSkinId) return
    this.currentSkinId = skin.id
    try {
      if (this.settingsPrefs) {
        this.settingsPrefs.putSync('skinId', skin.id)
        this.settingsPrefs.flush()
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `save skinId err: ${JSON.stringify(e)}`)
    }
    for (const l of this.themeListeners) {
      try { l() } catch (_e) {}
    }
  }

  // ========== 主题变更监听 ==========

  /**
   * 注册主题变化监听器（切换皮肤时触发）
   */
  onThemeChange(listener: ThemeListener): void {
    if (!this.themeListeners.includes(listener)) {
      this.themeListeners.push(listener)
    }
  }

  /**
   * 移除主题变化监听器
   */
  offThemeChange(listener: ThemeListener): void {
    const idx: number = this.themeListeners.indexOf(listener)
    if (idx >= 0) this.themeListeners.splice(idx, 1)
  }


  // ========== 设备变更监听（观察者模式） ==========

  /**
   * 注册设备列表变化监听器
   */
  onDeviceChange(listener: DeviceListener): void {
    if (!this.deviceListeners.includes(listener)) {
      this.deviceListeners.push(listener)
    }
  }

  /**
   * 移除设备列表变化监听器
   */
  offDeviceChange(listener: DeviceListener): void {
    const idx: number = this.deviceListeners.indexOf(listener)
    if (idx >= 0) this.deviceListeners.splice(idx, 1)
  }

  /**
   * 通知所有设备监听器（设备增删后触发 UI 刷新）
   */
  private notifyDeviceListeners(): void {
    for (const l of this.deviceListeners) {
      try { l() } catch (e) {}
    }
  }

  // ========== 设备管理 ==========

  /**
   * 从 DeviceStore 加载所有已保存的设备
   */
  async loadDevices(): Promise<void> {
    this.devices = await this.deviceStore.loadAll()
    this.notifyDeviceListeners()
  }

  /**
   * 保存/更新设备信息并刷新列表
   */
  async saveDevice(device: SavedDevice): Promise<void> {
    await this.deviceStore.save(device)
    await this.loadDevices()
  }

  /**
   * 删除设备：如果删除的是当前活动设备，先断开连接
   * @param id 设备 ID
   */
  async removeDevice(id: string): Promise<void> {
    // 如果删除的是活动设备，先断开连接
    if (this.activeDeviceId === id) {
      this.disconnect()
    }
    await this.deviceStore.remove(id)
    // 清除活动设备 ID
    if (this.activeDeviceId === id) {
      this.activeDeviceId = ''
    }
    await this.loadDevices()
  }

  /**
   * 按 ID 查找设备
   */
  getDeviceById(id: string): SavedDevice | undefined {
    return this.devices.find(d => d.id === id)
  }

  // ========== 连接管理 ==========

  /**
   * 连接到指定设备
   * @param deviceId 设备 ID
   * @returns 连接是否成功
   */
  async connectToDevice(deviceId: string): Promise<boolean> {
    const device: SavedDevice | undefined = this.getDeviceById(deviceId)
    if (!device) return false

    // 将 SavedDevice 转换为 ApiClient 需要的连接配置
    const config: ConnectionConfig = this.deviceStore.deviceToConfig(device)
    const client: ApiClient = ApiClient.getInstance()

    // 配置并连接
    client.configure(config)
    const connected: boolean = await client.connect()

    if (connected) {
      this.connected = true
      this.activeDeviceId = deviceId
      this.lastDeviceId = deviceId
      this.lastError = ''
      // 记录最近连接时间 + 记住「上次使用的设备」
      this.deviceStore.recordConnect(deviceId)
      this.deviceStore.saveActiveId(deviceId)
      this.notifyDeviceListeners()
      // 后台探测路由器 SSH 端口（Dropbear 配置），供 SSH 终端/文件管理/体检等功能复用
      this.detectSshPortAsync(device)
      return true
    } else {
      this.lastError = client.lastError || '连接失败'
      return false
    }
  }

  /**
   * 后台探测 SSH 端口并回写到设备记录（失败不影响主流程）
   * 已记录过端口的设备直接复用，不再重复探测
   */
  private async detectSshPortAsync(device: SavedDevice): Promise<void> {
    try {
      const cached: string = device.sshPort ? device.sshPort : ''
      if (cached.length > 0) {
        SshService.getInstance().preferredPort = cached
        return
      }
      const port: string = await ApiClient.getInstance().detectSshPort()
      if (port.length > 0) {
        SshService.getInstance().preferredPort = port
        device.sshPort = port
        device.version = (device.version ? device.version : 0) + 1
        await this.saveDevice(device)
        this.notifyDeviceListeners()
      }
    } catch (e) {
      hilog.warn(0x0001, 'AppState', `detectSshPort failed: ${String(e)}`)
    }
  }

  /**
   * 检查当前是否已连接到设备
   */
  isConnected(): boolean {
    return this.connected && ApiClient.getInstance().getConnected()
  }

  /**
   * 获取最近一次错误信息
   */
  getLastError(): string {
    return this.lastError || ApiClient.getInstance().lastError
  }

  /**
   * 断开当前连接
   */
  disconnect(): void {
    this.connected = false
    this.activeDeviceId = ''
    this.lastError = ''
    // 主动断开（如删除设备）后不再自动重连
    this.lastDeviceId = ''
    this.deviceStore.clearActiveId()
  }

  // ========== 主动切换设备 ==========

  private switchingDevice: boolean = false

  /**
   * 请求切换到设备列表：断开当前连接但不忘记上次设备，
   * 登录页据此跳过自动重连，避免"点切换又被弹回主页面"
   */
  requestSwitchDevice(): void {
    this.switchingDevice = true
    this.connected = false
    this.activeDeviceId = ''
    this.lastError = ''
  }

  /** 登录页消费一次切换请求（消费后自动复位） */
  consumeSwitchRequest(): boolean {
    const v: boolean = this.switchingDevice
    this.switchingDevice = false
    return v
  }

  // ========== 冷启动自动重连 ==========

  /** 上次使用的设备 ID（无则空串） */
  getLastDeviceId(): string {
    return this.lastDeviceId
  }

  /** 是否开启「启动自动重连」 */
  isAutoReconnectEnabled(): boolean {
    return this.deviceStore.isAutoReconnect()
  }

  async setAutoReconnect(enabled: boolean): Promise<void> {
    await this.deviceStore.setAutoReconnect(enabled)
  }

  /**
   * 自动重连上次设备（登录页冷启动时调用）
   * @returns 连接成功返回 true；未开启开关 / 无记录 / 连接失败返回 false
   */
  async connectLastDevice(): Promise<boolean> {
    if (this.connected && this.activeDeviceId) {
      return true
    }
    if (!this.isAutoReconnectEnabled()) {
      return false
    }
    const id: string = this.lastDeviceId || this.deviceStore.loadActiveId()
    if (!id) {
      return false
    }
    if (!this.getDeviceById(id)) {
      // 设备已被删除，清掉记录避免反复尝试
      this.lastDeviceId = ''
      await this.deviceStore.clearActiveId()
      return false
    }
    return this.connectToDevice(id)
  }

  // ========== 设备收藏 / 分组 ==========

  /** 切换收藏（收藏置顶） */
  async toggleFavorite(id: string): Promise<void> {
    await this.deviceStore.toggleFavorite(id)
    await this.loadDevices()
  }

  /** 设置分组（传空串取消分组） */
  async setDeviceGroup(id: string, group: string): Promise<void> {
    await this.deviceStore.setGroup(id, group)
    await this.loadDevices()
  }

  /**
   * 获取当前活动设备
   */
  getActiveDevice(): SavedDevice | undefined {
    return this.getDeviceById(this.activeDeviceId)
  }

  /**
   * 获取当前活动设备 ID
   */
  getActiveDeviceId(): string {
    return this.activeDeviceId
  }
}
