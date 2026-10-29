/**
 * 设备持久化存储（单例）
 * 使用 Preferences 将路由器设备列表以 JSON 字符串形式持久化
 * 支持增删改查、按最近连接时间排序、版本号驱动 UI 刷新
 */
import { preferences } from '@kit.ArkData'
import { ConnectionConfig } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { encrypt, decrypt } from '../utils/SecureStorage'

const TAG = 'DeviceStore'
const DOMAIN = 0x0001
const STORE_NAME = 'iStore_devices'  // Preferences 存储文件名

/**
 * 已保存的设备信息
 * @field version 版本号，每次保存递增，用于通过 @ObjectLink/@Prop 驱动 UI 刷新
 */
export interface SavedDevice {
  id: string              // 设备唯一标识（host + 随机串）
  label: string           // 用户自定义标签/名称
  host: string            // 路由器地址（IP 或域名）
  port: string            // 端口号（字符串形式以兼容存储）
  token: string           // API 认证令牌
  useHttps: boolean       // 是否使用 HTTPS 连接
  lastConnected: number   // 最近连接时间戳（毫秒）
  /** 版本号，每次保存递增，用于驱动 UI 刷新 */
  version: number
  username: string        // 用户名（用于基本认证）
  password: string        // 密码（用于基本认证）
  /** 收藏（置顶展示），旧数据结构无此字段时按 false 处理 */
  favorite: boolean
  /** 分组名称（空串表示未分组） */
  group: string
  /** 自动探测到的 SSH 端口（Dropbear 配置，空/未定义时按 22 及常见端口依次尝试） */
  sshPort?: string
}

export class DeviceStore {
  // ========== 单例模式 ==========
  private static instance: DeviceStore
  private prefs: preferences.Preferences | null = null  // Preferences 实例

  /**
   * 获取单例实例
   */
  static getInstance(): DeviceStore {
    if (!DeviceStore.instance) {
      DeviceStore.instance = new DeviceStore()
    }
    return DeviceStore.instance
  }

  /**
   * 初始化 Preferences 存储
   * @param context 应用上下文
   */
  async init(context: Context): Promise<void> {
    if (this.prefs) return  // 已初始化则跳过
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Init failed: ${JSON.stringify(e)}`)
    }
  }

  /**
   * 加载所有设备，按最近连接时间降序排列
   * @returns 设备列表（JSON 解析失败时返回空数组）
   */
  async loadAll(): Promise<SavedDevice[]> {
    if (!this.prefs) return []
    try {
      const json: string = this.prefs.getSync('device_list', '[]') as string
      const list: SavedDevice[] = JSON.parse(json) as SavedDevice[]
      // 解密敏感字段（兼容旧版明文数据：非 enc: 前缀的原样返回）
      for (let i = 0; i < list.length; i++) {
        list[i].password = decrypt(list[i].password)
        list[i].token = decrypt(list[i].token)
        // 兼容旧数据：老版本没有 favorite / group 字段
        list[i].favorite = list[i].favorite === true
        list[i].group = list[i].group ? list[i].group : ''
      }
      // 排序：收藏置顶 → 按最近连接时间降序
      list.sort((a: SavedDevice, b: SavedDevice) => {
        if (a.favorite !== b.favorite) {
          return a.favorite ? -1 : 1
        }
        return b.lastConnected - a.lastConnected
      })
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Load failed: ${JSON.stringify(e)}`)
      return []
    }
  }

  /**
   * 保存/更新设备
   * 如果设备已存在（同 ID），更新该条目并递增 version；
   * 如果设备不存在，新增到列表头部
   * @param device 要保存的设备信息
   */
  async save(device: SavedDevice): Promise<void> {
    if (!this.prefs) {
      throw new Error('存储未初始化，请重启应用')
    }
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === device.id)
    if (idx >= 0) {
      // 保留原有 version 并在其基础上递增，用于触发 UI 刷新
      const oldVersion: number = (typeof list[idx].version === 'number') ? list[idx].version : 0
      device.version = oldVersion + 1
      list[idx] = device
    } else {
      // 新建设备，版本号从 0 开始，插入到列表头部
      device.version = 0
      list.unshift(device)
    }
    await this.writeList(list)
  }

  /**
   * 删除指定设备
   * @param id 设备 ID
   */
  async remove(id: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const filtered: SavedDevice[] = list.filter((d: SavedDevice) => d.id !== id)
    await this.writeList(filtered)
  }

  /**
   * 记录设备最近连接时间（连接成功后调用）
   * @param id 设备 ID
   */
  async recordConnect(id: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === id)
    if (idx >= 0) {
      // 更新最近连接时间并递增版本号
      list[idx].lastConnected = Date.now()
      const oldVersion: number = (typeof list[idx].version === 'number') ? list[idx].version : 0
      list[idx].version = oldVersion + 1
      await this.writeList(list)
    }
  }

  /**
   * 将设备列表序列化并写入 Preferences
   * @param list 设备列表
   */
  private async writeList(list: SavedDevice[]): Promise<void> {
    if (!this.prefs) return
    try {
      // 加密敏感字段后落盘（encrypt 内部已防重复加密）
      const encList: SavedDevice[] = []
      for (let i = 0; i < list.length; i++) {
        const d: SavedDevice = {
          id: list[i].id,
          label: list[i].label,
          host: list[i].host,
          port: list[i].port,
          token: encrypt(list[i].token),
          useHttps: list[i].useHttps,
          lastConnected: list[i].lastConnected,
          version: list[i].version,
          username: list[i].username,
          password: encrypt(list[i].password),
          favorite: list[i].favorite === true,
          group: list[i].group ? list[i].group : '',
          sshPort: list[i].sshPort
        }
        encList.push(d)
      }
      await this.prefs.put('device_list', JSON.stringify(encList))
      await this.prefs.flush()  // 确保数据写入磁盘
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Write failed: ${JSON.stringify(e)}`)
    }
  }

  /**
   * 将 SavedDevice 转换为 ApiClient 可用的 ConnectionConfig
   * @param d 已保存的设备信息
   * @returns 连接配置对象
   */
  deviceToConfig(d: SavedDevice): ConnectionConfig {
    return {
      host: d.host,
      port: Number(d.port),  // port 在 SavedDevice 中是字符串，需转为数字
      token: d.token,
      useHttps: d.useHttps,
      username: d.username || '',
      password: d.password || ''
    }
  }

  /**
   * 创建新设备对象
   * @param label 用户自定义标签
   * @param config 连接配置
   * @returns 新的 SavedDevice 对象
   */
  createDevice(label: string, config: ConnectionConfig): SavedDevice {
    // 生成随机字符串作为 ID 后缀，确保唯一性
    const rand: string = Math.random().toString(36).substring(2, 10)
    return {
      id: `${config.host}_${rand}`,
      label: label || config.host,  // 未指定标签时默认使用 host
      host: config.host.trim(),
      port: String(config.port),
      token: config.token,
      useHttps: config.useHttps,
      lastConnected: Date.now(),
      version: 0,
      username: config.username || '',
      password: config.password || '',
      favorite: false,
      group: ''
    }
  }

  /**
   * 切换收藏状态（收藏的设备在列表内置顶）
   */
  async toggleFavorite(id: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === id)
    if (idx < 0) return
    list[idx].favorite = !list[idx].favorite
    list[idx].version = (list[idx].version || 0) + 1
    await this.writeList(list)
  }

  /**
   * 设置设备分组（传空串表示取消分组）
   */
  async setGroup(id: string, group: string): Promise<void> {
    if (!this.prefs) return
    const list: SavedDevice[] = await this.loadAll()
    const idx: number = list.findIndex((d: SavedDevice) => d.id === id)
    if (idx < 0) return
    list[idx].group = group ? group.trim() : ''
    list[idx].version = (list[idx].version || 0) + 1
    await this.writeList(list)
  }

  /**
   * 记录「上次使用的设备」，用于冷启动自动重连
   */
  async saveActiveId(id: string): Promise<void> {
    if (!this.prefs) return
    try {
      this.prefs.putSync('active_device_id', id)
      await this.prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveActiveId failed: ${JSON.stringify(e)}`)
    }
  }

  /** 读取上次使用的设备 ID（无则返回空串） */
  loadActiveId(): string {
    if (!this.prefs) return ''
    try {
      return this.prefs.getSync('active_device_id', '') as string
    } catch (e) {
      return ''
    }
  }

  /** 清除上次使用的设备（用户主动断开时调用） */
  async clearActiveId(): Promise<void> {
    if (!this.prefs) return
    try {
      this.prefs.putSync('active_device_id', '')
      await this.prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `clearActiveId failed: ${JSON.stringify(e)}`)
    }
  }

  /** 是否允许冷启动自动重连（默认开启） */
  isAutoReconnect(): boolean {
    if (!this.prefs) return true
    try {
      return this.prefs.getSync('auto_reconnect', true) as boolean
    } catch (e) {
      return true
    }
  }

  async setAutoReconnect(enabled: boolean): Promise<void> {
    if (!this.prefs) return
    try {
      this.prefs.putSync('auto_reconnect', enabled)
      await this.prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `setAutoReconnect failed: ${JSON.stringify(e)}`)
    }
  }
}
