import { preferences } from '@kit.ArkData'
import { ConnectionConfig } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'DeviceStore'
const DOMAIN = 0x0001
const STORE_NAME = 'iStore_devices'

export interface SavedDevice {
  id: string
  label: string
  host: string
  port: string
  token: string
  useHttps: boolean
  lastConnected: number
  /** 版本号，每次保存递增，用于驱动 UI 刷新 */
  version: number
  username: string
  password: string
}

export class DeviceStore {
  private static instance: DeviceStore
  private prefs: preferences.Preferences | null = null

  static getInstance(): DeviceStore {
    if (!DeviceStore.instance) {
      DeviceStore.instance = new DeviceStore()
    }
    return DeviceStore.instance
  }

  async init(context: Context): Promise<void> {
    if (this.prefs) return
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Init failed: ${JSON.stringify(e)}`)
    }
  }

  async loadAll(): Promise<SavedDevice[]> {
    if (!this.prefs) return []
    try {
      const json: string = this.prefs.getSync('device_list', '[]') as string
      const list: SavedDevice[] = JSON.parse(json) as SavedDevice[]
      list.sort((a: SavedDevice, b: SavedDevice) => b.lastConnected - a.lastConnected)
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Load failed: ${JSON.stringify(e)}`)
      return []
    }
  }

  async save(device: SavedDevice): Promise<void> {
    if (!this.prefs) {
      throw new Error('存储未初始化，请重启应用')
    }
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === device.id)
    if (idx >= 0) {
      // 保留原有 version 并在其基础上递增
      const oldVersion: number = (typeof list[idx].version === 'number') ? list[idx].version : 0
      device.version = oldVersion + 1
      list[idx] = device
    } else {
      device.version = 0
      list.unshift(device)
    }
    await this.writeList(list)
  }

  async remove(id: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const filtered: SavedDevice[] = list.filter((d: SavedDevice) => d.id !== id)
    await this.writeList(filtered)
  }

  async recordConnect(id: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === id)
    if (idx >= 0) {
      list[idx].lastConnected = Date.now()
      const oldVersion: number = (typeof list[idx].version === 'number') ? list[idx].version : 0
      list[idx].version = oldVersion + 1
      await this.writeList(list)
    }
  }

  private async writeList(list: SavedDevice[]): Promise<void> {
    if (!this.prefs) return
    try {
      await this.prefs.put('device_list', JSON.stringify(list))
      await this.prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Write failed: ${JSON.stringify(e)}`)
    }
  }

  deviceToConfig(d: SavedDevice): ConnectionConfig {
    return {
      host: d.host,
      port: Number(d.port),
      token: d.token,
      useHttps: d.useHttps
    }
  }

  createDevice(label: string, config: ConnectionConfig): SavedDevice {
    const rand: string = Math.random().toString(36).substring(2, 10)
    return {
      id: `${config.host}_${rand}`,
      label: label || config.host,
      host: config.host.trim(),
      port: String(config.port),
      token: config.token,
      useHttps: config.useHttps,
      lastConnected: Date.now(),
      version: 0,
      username: config.username || '',
      password: config.password || ''
    }
  }
}
