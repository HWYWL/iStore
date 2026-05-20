import { preferences } from '@kit.ArkData'
import { ApiClient } from '../../api/ApiClient'
import { ConnectionConfig } from '../../models/Models'
import { DeviceStore, SavedDevice } from './DeviceStore'
import { DARK_THEME, LIGHT_THEME, ThemePalette } from '../theme/ThemeColors'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'AppState'
const DOMAIN = 0x0001
const PREFS_NAME = 'iStore_app_settings'

type ThemeListener = () => void
type DeviceListener = () => void

/**
 * 全局应用状态 - 单例模式
 * 管理设备列表、活跃设备连接、主题切换
 * 当前设计：同一时间只连接一台设备（适合移动端）
 */
export class AppState {
  private static instance: AppState

  // 设备管理
  devices: SavedDevice[] = []
  activeDeviceId: string = ''

  // 主题
  isDarkMode: boolean = true

  // 连接 (使用 ApiClient 单例，切换设备时重新配置)
  private connected: boolean = false
  private lastError: string = ''

  // 持久化
  private settingsPrefs: preferences.Preferences | null = null
  private deviceStore: DeviceStore = DeviceStore.getInstance()
  private initialized: boolean = false

  // 监听器
  private themeListeners: ThemeListener[] = []
  private deviceListeners: DeviceListener[] = []

  static getInstance(): AppState {
    if (!AppState.instance) {
      AppState.instance = new AppState()
    }
    return AppState.instance
  }

  async init(context: Context): Promise<void> {
    if (this.initialized) return

    await this.deviceStore.init(context)

    try {
      this.settingsPrefs = await preferences.getPreferences(context, PREFS_NAME)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Settings pref init failed: ${JSON.stringify(e)}`)
    }

    await this.loadTheme()
    await this.loadDevices()

    this.initialized = true
    hilog.info(DOMAIN, TAG, `Initialized: ${this.devices.length} devices, ${this.isDarkMode ? 'dark' : 'light'}`)
  }

  // ==================== 主题管理 ====================

  getTheme(): ThemePalette {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME
  }

  toggleTheme(): void {
    this.isDarkMode = !this.isDarkMode
    this.saveTheme()
    this.notifyThemeListeners()
  }

  private async loadTheme(): Promise<void> {
    if (!this.settingsPrefs) return
    try {
      const val: preferences.ValueType = this.settingsPrefs.getSync('isDarkMode', true)
      if (typeof val === 'boolean') this.isDarkMode = val
    } catch (e) {
      this.isDarkMode = true
    }
  }

  private async saveTheme(): Promise<void> {
    if (!this.settingsPrefs) return
    try {
      await this.settingsPrefs.put('isDarkMode', this.isDarkMode)
      await this.settingsPrefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Save theme failed: ${JSON.stringify(e)}`)
    }
  }

  onThemeChange(listener: ThemeListener): void {
    if (!this.themeListeners.includes(listener)) {
      this.themeListeners.push(listener)
    }
  }

  offThemeChange(listener: ThemeListener): void {
    const idx: number = this.themeListeners.indexOf(listener)
    if (idx >= 0) this.themeListeners.splice(idx, 1)
  }

  private notifyThemeListeners(): void {
    for (const l of this.themeListeners) {
      try { l() } catch (e) {}
    }
  }

  onDeviceChange(listener: DeviceListener): void {
    if (!this.deviceListeners.includes(listener)) {
      this.deviceListeners.push(listener)
    }
  }

  offDeviceChange(listener: DeviceListener): void {
    const idx: number = this.deviceListeners.indexOf(listener)
    if (idx >= 0) this.deviceListeners.splice(idx, 1)
  }

  private notifyDeviceListeners(): void {
    for (const l of this.deviceListeners) {
      try { l() } catch (e) {}
    }
  }

  // ==================== 设备管理 ====================

  async loadDevices(): Promise<void> {
    this.devices = await this.deviceStore.loadAll()
    this.notifyDeviceListeners()
  }

  async saveDevice(device: SavedDevice): Promise<void> {
    await this.deviceStore.save(device)
    await this.loadDevices()
  }

  async removeDevice(id: string): Promise<void> {
    if (this.activeDeviceId === id) {
      this.disconnect()
    }
    await this.deviceStore.remove(id)
    if (this.activeDeviceId === id) {
      this.activeDeviceId = ''
    }
    await this.loadDevices()
  }

  getDeviceById(id: string): SavedDevice | undefined {
    return this.devices.find(d => d.id === id)
  }

  // ==================== 连接管理 (单设备模式) ====================

  async connectToDevice(deviceId: string): Promise<boolean> {
    const device: SavedDevice | undefined = this.getDeviceById(deviceId)
    if (!device) return false

    const config: ConnectionConfig = this.deviceStore.deviceToConfig(device)
    const client: ApiClient = ApiClient.getInstance()

    client.configure(config)
    const connected: boolean = await client.connect()

    if (connected) {
      this.connected = true
      this.activeDeviceId = deviceId
      this.lastError = ''
      this.deviceStore.recordConnect(deviceId)
      this.notifyDeviceListeners()
      return true
    } else {
      this.lastError = client.lastError || '连接失败'
      return false
    }
  }

  isConnected(): boolean {
    return this.connected && ApiClient.getInstance().getConnected()
  }

  getLastError(): string {
    return this.lastError || ApiClient.getInstance().lastError
  }

  disconnect(): void {
    this.connected = false
    this.activeDeviceId = ''
    this.lastError = ''
  }

  getActiveDevice(): SavedDevice | undefined {
    return this.getDeviceById(this.activeDeviceId)
  }

  getActiveDeviceId(): string {
    return this.activeDeviceId
  }
}
