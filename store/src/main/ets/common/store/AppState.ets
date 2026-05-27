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
import { DARK_THEME, LIGHT_THEME, ThemePalette } from '../theme/ThemeColors'
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
  isDarkMode: boolean = true           // 是否为深色模式（默认深色）

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
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Settings pref init failed: ${JSON.stringify(e)}`)
    }

    // 从持久化存储加载主题和设备列表
    await this.loadTheme()
    await this.loadDevices()

    this.initialized = true
    hilog.info(DOMAIN, TAG, `Initialized: ${this.devices.length} devices, ${this.isDarkMode ? 'dark' : 'light'}`)
  }

  // ========== 主题管理 ==========

  /**
   * 获取当前主题调色板
   */
  getTheme(): ThemePalette {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME
  }

  /**
   * 切换深色/浅色主题，持久化并通知所有监听器
   */
  toggleTheme(): void {
    this.isDarkMode = !this.isDarkMode
    this.saveTheme()
    this.notifyThemeListeners()
  }

  /**
   * 从 Preferences 加载主题偏好
   */
  private async loadTheme(): Promise<void> {
    if (!this.settingsPrefs) return
    try {
      const val: preferences.ValueType = this.settingsPrefs.getSync('isDarkMode', true)
      if (typeof val === 'boolean') this.isDarkMode = val
    } catch (e) {
      this.isDarkMode = true  // 加载失败时默认深色模式
    }
  }

  /**
   * 保存主题偏好到 Preferences
   */
  private async saveTheme(): Promise<void> {
    if (!this.settingsPrefs) return
    try {
      await this.settingsPrefs.put('isDarkMode', this.isDarkMode)
      await this.settingsPrefs.flush()  // 确保写入磁盘
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Save theme failed: ${JSON.stringify(e)}`)
    }
  }

  // ========== 主题变更监听（观察者模式） ==========

  /**
   * 注册主题变化监听器
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

  /**
   * 通知所有主题监听器（各组件收到通知后更新 @State theme）
   */
  private notifyThemeListeners(): void {
    for (const l of this.themeListeners) {
      try { l() } catch (e) {}
    }
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
      this.lastError = ''
      // 记录最近连接时间
      this.deviceStore.recordConnect(deviceId)
      this.notifyDeviceListeners()
      return true
    } else {
      this.lastError = client.lastError || '连接失败'
      return false
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
