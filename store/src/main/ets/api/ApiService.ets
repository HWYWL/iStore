/**
 * API 业务服务层
 * 封装对 ApiClient 的调用，负责数据解析和类型转换
 * 通过 ObjectHelper 安全读取 JSON 字段，失败时返回空数据兜底
 */
import { ApiClient } from './ApiClient'
import {
  SystemInfo,
  NetworkInterface,
  WanStatus,
  ConnectedDevice,
  TrafficHistory,
  MountPoint,
  ConntrackInfo,
  ProcessInfo,
  StartupItem,
  RouteEntry,
  WirelessClient,
  WirelessDevice,
  WifiApInfo,
  WifiClientDetail,
  IStoreApp,
  DockerOverview,
  DockerContainer,
  DockerStats,
  DockerImage,
  DockerNetwork,
  OafStatus,
  AppFilterBase,
  AppClass,
  AppItem,
  AppFilterTime,
  AppFilterUser,
  UserListItem,
  DeviceVisitTime,
  DeviceVisitRecord,
  TimeSlot
} from '../models/Models'
import { ConnectionConfig, DhcpBindingInfo, GuestWifiInfo, NetworkCheckItem } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ObjectUtil } from '@pura/harmony-utils'
import { FormatUtils } from '../common/utils/FormatUtils'

const TAG = 'ApiService'
const DOMAIN = 0x0001

type AppFilterMode = 'auto' | 'manual'

class EmptyRecord {
}

/** 安全读取工具 — 委托给 @pura/harmony-utils 的 ObjectUtil */
class ObjectHelper {
  static getString(obj: Object, key: string, def: string): string {
    if (!obj || !ObjectUtil.has(obj, key)) return def
    const v: Object = ObjectUtil.getValue(obj, key)
    return (v !== undefined && v !== null) ? String(v) : def
  }
  static getNumber(obj: Object, key: string, def: number): number {
    if (!obj || !ObjectUtil.has(obj, key)) return def
    const v: Object = ObjectUtil.getValue(obj, key)
    if (v === undefined || v === null) return def
    const n: number = Number(v)
    return isNaN(n) ? def : n
  }
  static getArray(obj: Object, key: string): Object[] {
    if (!obj || !ObjectUtil.has(obj, key)) return []
    const v: Object = ObjectUtil.getValue(obj, key)
    return (v !== undefined && v !== null && Array.isArray(v)) ? v as Object[] : []
  }
  static getBool(obj: Object, key: string): boolean {
    if (!obj || !ObjectUtil.has(obj, key)) return false
    const v: Object = ObjectUtil.getValue(obj, key)
    return (v !== undefined && v !== null) ? Boolean(v) : false
  }

  /** 解析 disabled 开关值：'1'/1/true → true；'0'/0/false/无 → false */
  static parseDisabled(v: Object): boolean {
    if (v === undefined || v === null) return false
    if (typeof v === 'boolean') return v as boolean
    if (typeof v === 'number') return (v as number) !== 0
    if (typeof v === 'string') {
      const s: string = (v as string).trim().toLowerCase()
      return s === '1' || s === 'true' || s === 'yes' || s === 'on'
    }
    return false
  }
  static getObject(obj: Object, key: string): Object {
    if (!obj || !ObjectUtil.has(obj, key)) return new EmptyRecord()
    const v: Object = ObjectUtil.getValue(obj, key)
    if (v === undefined || v === null) return new EmptyRecord()
    return (typeof v === 'object') ? v : new EmptyRecord()
  }
  static hasKey(obj: Object, key: string): boolean {
    if (!obj) return false
    return ObjectUtil.has(obj, key)
  }
}

interface WirelessInterfaceInfo {
  name: string
  ssid: string
  channel: number
  mode: string
}

interface TimeSlotInfo {
  startHour: number
  startMin: number
  endHour: number
  endMin: number
}

export class ApiService {
  // ========== 单例 ==========
  private static instance: ApiService | null = null

  /** 获取全局单例（推荐用法，页面间共享缓存） */
  static getInstance(): ApiService {
    if (ApiService.instance === null) {
      ApiService.instance = new ApiService()
    }
    return ApiService.instance
  }

  private client: ApiClient
  private historyBuffer: TrafficHistory[] = []

  // ========== 跨实例共享缓存 ==========
  // 说明：原先这些缓存是实例字段，而调用方普遍 new ApiService()，导致缓存完全失效、
  // 同一时刻多个页面重复请求同一份数据。改为静态并加短 TTL：
  // TTL 内多页共享同一次请求，超出 TTL 必然重新拉取，速率等实时数据不会变"死"。
  private static statsCache: Map<string, number[]> = new Map()
  private static rateMapCache: Record<string, Object> | null = null
  private static interfacesCache: Object | null = null
  private static cacheStamp: number = 0
  private static readonly CACHE_TTL_MS: number = 1200

  constructor() {
    this.client = ApiClient.getInstance()
  }

  /** 清空共享缓存（切换设备 / 重新登录时调用，避免串台） */
  static resetCache(): void {
    ApiService.interfacesCache = null
    ApiService.rateMapCache = null
    ApiService.statsCache = new Map()
    ApiService.cacheStamp = 0
  }

  /**
   * 获取网络接口数据 + 速率映射（TTL 内全局共享，避免多页面重复请求）
   * @param force 强制跳过 TTL 缓存（累计字节数这类有增量语义的读数必须拿最新值）
   */
  private async getNetworkData(force: boolean = false): Promise<void> {
    if (!force && ApiService.interfacesCache && ApiService.rateMapCache &&
      (Date.now() - ApiService.cacheStamp) < ApiService.CACHE_TTL_MS) {
      return
    }
    const result = await this.client.requestDirect('network_interfaces')
    ApiService.interfacesCache = (result && result.data) ? result.data : new EmptyRecord()
    const rateMap: Record<string, Object> = {}
    if (result && result.rates && Array.isArray(result.rates)) {
      const rates = result.rates as Object[]
      for (let i = 0; i < rates.length; i++) {
        const r = rates[i]
        const key = ObjectHelper.getString(r, 'iface', '') ||
          ObjectHelper.getString(r, 'interface', '') ||
          ObjectHelper.getString(r, 'name', '')
        if (key) {
          rateMap[key] = r
        }
      }
    }
    ApiService.rateMapCache = rateMap

    // 同时缓存设备累计字节数（luci-rpc.getNetworkDevices stats 中才有 rx_bytes/tx_bytes）
    const devResult = await this.client.requestDirect('network_devices')
    ApiService.statsCache.clear()
    if (devResult && devResult.data) {
      const devData = devResult.data as Record<string, Object>
      const devNames = Object.keys(devData)
      for (const dn of devNames) {
        const dev = devData[dn] as Record<string, Object>
        if (dev && typeof dev === 'object') {
          const st = dev['stats'] as Record<string, Object>
          if (st && typeof st === 'object') {
            ApiService.statsCache.set(dn, [
              ObjectHelper.getNumber(st, 'rx_bytes', 0),
              ObjectHelper.getNumber(st, 'tx_bytes', 0)
            ])
          }
        }
      }
    }
    ApiService.cacheStamp = Date.now()
  }

  configureConnection(config: ConnectionConfig): void {
    ApiService.resetCache()
    this.client.configure(config)
  }

  async connect(): Promise<boolean> {
    return this.client.connect()
  }

  getLastError(): string {
    return this.client.lastError
  }

  isConnected(): boolean {
    return this.client.getConnected()
  }

  async fetchSystemInfo(): Promise<SystemInfo> {
    try {
      // 1. 并发请求两个 API：主板信息 + 系统运行信息
      const board = await this.client.getSystemBoard()
      const info = await this.client.getSystemInfo()

      // 2. 从主板信息（board）中提取基础硬件信息
      const hostname = ObjectHelper.getString(board, 'hostname', 'OpenWrt')
      // model 字段优先，fallback 到 'system' 字段，最后兜底为 'OpenWrt'
      const model = ObjectHelper.getString(board, 'model', '') || ObjectHelper.getString(board, 'system', '') || 'OpenWrt'
      const kernel = ObjectHelper.getString(board, 'kernel', '')
      // cpu_model 字段优先，fallback 到 'model' 字段
      const cpuModel = ObjectHelper.getString(board, 'system', '') || ObjectHelper.getString(board, 'model', '')
      const boardName = ObjectHelper.getString(board, 'board_name', '')

      // distribution 在 board.release.distribution 中，需先提取 release 对象
      const release = ObjectHelper.getObject(board, 'release')
      const distribution = release ? ObjectHelper.getString(release, 'distribution', '') : ''
      // firmware_version 字段优先，fallback 到 'version' 字段
      const firmwareVersion = release ? ObjectHelper.getString(release, 'description', '') : '' || ObjectHelper.getString(board, 'firmware_version', '') || ObjectHelper.getString(board, 'version', '')

      // 3. 从系统运行信息（info）中提取运行时数据
      const uptime = ObjectHelper.getNumber(info, 'uptime', 0)
      // localtime 字段是 Unix 时间戳（秒），需要乘以 1000 转为毫秒
      const localtimeVal = ObjectHelper.getString(info, 'localtime', '')
      const localTime = localtimeVal ? new Date(Number(localtimeVal) * 1000).toISOString() : new Date().toISOString()
      const cpuUsage = ObjectHelper.getNumber(info, 'cpu_usage', 0)

      // 4. 内存信息在 info.memory 数组中，取第一项
      const memoryArr = ObjectHelper.getArray(info, 'memory')
      const memory = memoryArr.length > 0 ? memoryArr[0] : ObjectHelper.getObject(info, 'memory')
      const memTotal = ObjectHelper.getNumber(memory, 'total', 0)
      const memFree = ObjectHelper.getNumber(memory, 'free', 0)
      // available 字段优先，fallback 到 free（兼容旧固件）
      const memAvailable = ObjectHelper.getNumber(memory, 'available', memFree)
      // cached 和 buffered 合并为缓存总量
      const memCached = ObjectHelper.getNumber(memory, 'cached', 0) + ObjectHelper.getNumber(memory, 'buffered', 0)
      const memUsed = memTotal - memAvailable
      // 5. 额外获取 CPU 温度与当前频率
      const cpuTemp = await this.fetchCPUTemp()
      const cpuFreq = await this.fetchCPUFreq()

      return {
        hostname: hostname,
        model: model,
        kernel: kernel,
        firmwareVersion: firmwareVersion,
        localTime: localTime,
        uptime: uptime,
        cpuUsage: cpuUsage,
        memoryTotal: memTotal,
        memoryUsed: memUsed,
        memoryCached: memCached,
        memoryAvailable: memAvailable,
        storageTotal: 0,
        storageUsed: 0,
        cpuTemp: cpuTemp,
        cpuFreq: cpuFreq,
        boardName: boardName,
        cpuModel: cpuModel,
        distribution: distribution,
        releaseVersion: '',
        releaseRevision: '',
        releaseTarget: ''
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchSystemInfo err: ${String(e)}`)
    }
    return this.emptySystemInfo()
  }

  /**
   * 判断 IPv4 地址是否为私有地址（内网）
   * 支持 10.x.x.x, 172.16-31.x.x, 192.168.x.x
   */
  private isPrivateIPv4(ip: string): boolean {
    if (!ip || ip === '0.0.0.0') return false
    const parts = ip.split('.')
    if (parts.length !== 4) return false
    const first = parseInt(parts[0])
    const second = parseInt(parts[1])
    if (first === 10) return true
    if (first === 172 && second >= 16 && second <= 31) return true
    if (first === 192 && second === 168) return true
    return false
  }

  async fetchLanStatus(): Promise<WanStatus> {
    try {
      await this.getNetworkData()
      const interfacesList = ObjectHelper.getArray(ApiService.interfacesCache!, 'interface')
      const rateMap = ApiService.rateMapCache!

      // 2. 多策略查找 LAN 接口（按优先级尝试）
      let lanIf: Object | null = null

      // 策略 A: 精确匹配 interface === 'lan'
      for (let i = 0; i < interfacesList.length; i++) {
        const iface = interfacesList[i]
        const ifName = ObjectHelper.getString(iface, 'interface', '')
        if (ifName === 'lan') {
          lanIf = iface
          break
        }
      }

      // 策略 B: 匹配 type === 'lan'
      if (!lanIf) {
        for (let i = 0; i < interfacesList.length; i++) {
          const iface = interfacesList[i]
          const typeStr = ObjectHelper.getString(iface, 'type', '')
          if (typeStr === 'lan') {
            lanIf = iface
            break
          }
        }
      }

      // 策略 C: 匹配常见 LAN 桥接设备名（br-lan）
      if (!lanIf) {
        for (let i = 0; i < interfacesList.length; i++) {
          const iface = interfacesList[i]
          const device = ObjectHelper.getString(iface, 'device', '')
          if (device === 'br-lan' || device.startsWith('br-lan')) {
            lanIf = iface
            break
          }
        }
      }

      // 策略 D: 查找第一个持有私有 IPv4 地址的接口
      if (!lanIf) {
        for (let i = 0; i < interfacesList.length; i++) {
          const iface = interfacesList[i]
          const ip = ObjectHelper.getString(ObjectHelper.getArray(iface, 'ipv4-address')?.[0], 'address', '')
          if (this.isPrivateIPv4(ip)) {
            lanIf = iface
            break
          }
        }
      }

      // 3. 未找到 LAN 接口则返回空状态
      if (!lanIf) {
        return this.emptyWanStatus()
      }

      // 4. 从 LAN 接口对象中提取网络配置
      const ifname = ObjectHelper.getString(lanIf, 'device', '')
      const ipAddress = ObjectHelper.getString(ObjectHelper.getArray(lanIf, 'ipv4-address')?.[0], 'address', '0.0.0.0');
      const netmask = ObjectHelper.getString(ObjectHelper.getArray(lanIf, 'ipv4-address')?.[0], 'mask', '0');
      const gateway = ObjectHelper.getString(ObjectHelper.getArray(lanIf, 'route')?.[0], 'nexthop', '0.0.0.0');

      // DNS 服务器可能有多条，最多取前 3 条
      const dnsArray = ObjectHelper.getArray(lanIf, 'dns-server')
      const dns: string[] = []
      for (let i = 0; i < dnsArray.length && i < 3; i++) {
        dns.push(String(dnsArray[i]))
      }
      const proto = ObjectHelper.getString(lanIf, 'proto', '')
      const macAddr = ObjectHelper.getString(lanIf, 'mac_address', '')
      const uptime = ObjectHelper.getNumber(lanIf, 'uptime', 0)
      // rx_rate/tx_rate 优先从 rateMap 查找（真实计算值）
      const lanName = ObjectHelper.getString(lanIf, 'interface', '') ||
        ObjectHelper.getString(lanIf, 'device', '')
      const lanRate = rateMap[lanName] || rateMap[ifname]
      let rxRate = ObjectHelper.getNumber(lanRate, 'rx_rate', 0)
      let txRate = ObjectHelper.getNumber(lanRate, 'tx_rate', 0)
      if (rxRate === 0 && txRate === 0) {
        rxRate = ObjectHelper.getNumber(lanIf, 'rx_rate', 0)
        txRate = ObjectHelper.getNumber(lanIf, 'tx_rate', 0)
      }

      // 5. 将 uptime 秒数转为可读字符串
      const onlineTime = this.formatUptime(uptime)

      return {
        interface: ifname,
        uptime: uptime,
        ipAddress: ipAddress,
        netmask: netmask,
        gateway: gateway,
        dns: dns,
        rxRate: rxRate,
        txRate: txRate,
        onlineTime: onlineTime,
        proto: proto,
        macAddr: macAddr
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchLanStatus err: ${String(e)}`)
    }
    return this.emptyWanStatus()
  }


  async fetchNetworkInterfaces(): Promise<NetworkInterface[]> {
    try {
      await this.getNetworkData()
      const interfacesList = ObjectHelper.getArray(ApiService.interfacesCache!, 'interface')
      const rateMap = ApiService.rateMapCache!

      const list: NetworkInterface[] = []

      for (let i = 0; i < interfacesList.length; i++) {
        const iface = interfacesList[i]
        const name = ObjectHelper.getString(iface, 'name', '')
        // 优先用 interface 字段作为名称，name 字段作为备选
        const ifName = ObjectHelper.getString(iface, 'interface', '')
        const displayName = name || ifName || ''

        // 类型推断：优先使用 type 字段，其次根据接口名推断
        const typeStr = ObjectHelper.getString(iface, 'type', '')
        let type: 'wan' | 'lan' | 'wifi' | 'vpn' = 'lan'
        if (typeStr === 'wan') type = 'wan'
        else if (typeStr === 'wifi') type = 'wifi'
        else if (typeStr === 'vpn') type = 'vpn'
        // 从接口名称推断类型（当 type 字段为空或不存在时）
        else if (typeStr === '') {
          const lower = ifName.toLowerCase()
          if (lower.startsWith('wan') || lower.startsWith('wwan')) type = 'wan'
          else if (lower.startsWith('wlan') || lower.startsWith('phy') || lower.startsWith('radio')) type = 'wifi'
          else if (lower.startsWith('vpn') || lower.startsWith('tun') || lower.startsWith('tap')) type = 'vpn'
          // 其他（包括 'lan', 'br-lan', 等）保持默认 'lan'
        }
        // 提取接口的 IP、速率、流量统计等字段
        const ipAddress = ObjectHelper.getString(ObjectHelper.getArray(iface, 'ipv4-address')?.[0], 'address', '0.0.0.0');
        const netmask = ObjectHelper.getString(ObjectHelper.getArray(iface, 'ipv4-address')?.[0], 'mask', '0');

        const macAddress = ObjectHelper.getString(iface, 'mac_address', '')
        // 累计字节从 luci-rpc.getNetworkDevices 的 stats 子对象获取
        // （network.interface dump 在 iStoreOS 上不含 rx_bytes/tx_bytes）
        const lookupDev: string = ObjectHelper.getString(iface, 'device', '') || ''
        const byteStats: number[] | undefined = ApiService.statsCache.get(displayName) ||
          ApiService.statsCache.get(ifName) || ApiService.statsCache.get(name) || ApiService.statsCache.get(lookupDev)
        let rxBytes: number = byteStats ? byteStats[0] : 0
        let txBytes: number = byteStats ? byteStats[1] : 0
        // 兜底：部分固件的 network.interface dump 自带 statistics 字段
        if (rxBytes === 0 && txBytes === 0) {
          const stObj: Object | undefined = (iface as Record<string, Object>)['statistics']
          if (stObj && typeof stObj === 'object') {
            const st: Record<string, Object> = stObj as Record<string, Object>
            rxBytes = ObjectHelper.getNumber(st, 'rx_bytes', 0)
            txBytes = ObjectHelper.getNumber(st, 'tx_bytes', 0)
          }
        }

        // 速率优先从 rateMap 查找（真实计算值），fallback 到 ubus 返回的字段
        const devName = ObjectHelper.getString(iface, 'device', '') || ''
        const rate = rateMap[displayName] || rateMap[ifName] || rateMap[name] || rateMap[devName]
        let rxRate = ObjectHelper.getNumber(rate, 'rx_rate', 0)
        let txRate = ObjectHelper.getNumber(rate, 'tx_rate', 0)
        if (rxRate === 0 && txRate === 0) {
          rxRate = ObjectHelper.getNumber(iface, 'rx_rate', 0)
          txRate = ObjectHelper.getNumber(iface, 'tx_rate', 0)
        }
        const uptime = ObjectHelper.getNumber(iface, 'uptime', 0)

        const item: NetworkInterface = {
          name: displayName,
          type: type,
          ipAddress: ipAddress,
          netmask: netmask,
          gateway: '',
          macAddress: macAddress,
          mtu: 0,
          status: 'up',
          rxBytes: rxBytes,
          txBytes: txBytes,
          rxRate: rxRate,
          txRate: txRate,
          uptime: uptime
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchNetworkInterfaces err: ${String(e)}`)
    }
    return []
  }

  async fetchConnectedDevices(): Promise<ConnectedDevice[]> {
    try {
      // 从 DHCP 租约列表获取已连接设备信息
      const leases = await this.client.getLuciDHCPLeases()

      // API 返回的 data 直接就是数组 [{mac, ip, name, expires}, ...]，也可能包在 leases 中
      let leaseArray: Object[] = []
      if (Array.isArray(leases)) {
        leaseArray = leases as Object[]
      } else {
        leaseArray = ObjectHelper.getArray(leases, 'leases')
      }

      // 构建 WiFi 客户端查找表（MAC → 信号/速率），合并到 DHCP 设备中
      const wifiMap: Map<string, WirelessClient> = new Map()
      try {
        const wClients: WirelessClient[] = await this.fetchWirelessClients()
        for (const wc of wClients) {
          const wmac: string = (wc.mac || '').toUpperCase()
          if (wmac) wifiMap.set(wmac, wc)
        }
      } catch (_e) { /* WiFi 数据获取失败不阻塞主流程 */ }

      const now = Math.floor(Date.now() / 1000)
      const list: ConnectedDevice[] = []

      for (let i = 0; i < leaseArray.length; i++) {
        const lease = leaseArray[i]
        const mac = ObjectHelper.getString(lease, 'mac', '') ||
          ObjectHelper.getString(lease, 'macaddr', '') ||
          ObjectHelper.getString(lease, 'hwaddr', '')
        const ip = ObjectHelper.getString(lease, 'ip', '') ||
          ObjectHelper.getString(lease, 'ipaddr', '') ||
          ObjectHelper.getString(lease, 'ipaddress', '')
        // 优先 hostname，其次 name（API 实际返回的字段）
        const hostname = ObjectHelper.getString(lease, 'hostname', '') ||
          ObjectHelper.getString(lease, 'name', '')
        // expires 为 Unix 时间戳，大于当前时间表示租约未过期 = 在线
        const expiresNum = ObjectHelper.getNumber(lease, 'expires', 0)
        const isOnline = ObjectHelper.getNumber(lease, 'online', 0) === 1 ||
          ObjectHelper.getString(lease, 'online', '') === 'true' ||
          ObjectHelper.getString(lease, 'active', '') === 'true' ||
          (expiresNum > 0 && expiresNum > now)
        const interfaceName = ObjectHelper.getString(lease, 'interface', '') ||
          ObjectHelper.getString(lease, 'dev', '') ||
          ObjectHelper.getString(lease, 'device', '')
        const onlineTimeStr = ObjectHelper.getString(lease, 'online_time', '') ||
          ObjectHelper.getString(lease, 'lease_time', '')
        // 如果只有 expires 时间戳，转换为可读时间
        const expiresTime = expiresNum > 0 ? this.formatTimestamp(expiresNum) : ''
        const displayOnlineTime = onlineTimeStr || expiresTime

        // 从 WiFi 客户端数据中合并信号强度和速率
        const wc: WirelessClient | undefined = wifiMap.get(mac.toUpperCase())
        const signalStrength: number = wc ? (wc.signal || 0) : 0
        const rxRate: number = wc ? (wc.rxRate || 0) : 0
        const txRate: number = wc ? (wc.txRate || 0) : 0

        // 厂商识别不到时置空，避免页面出现无意义的 "Unknown" 占位
        const vendorName: string = FormatUtils.getVendorName(mac)
        const item: ConnectedDevice = {
          mac: mac,
          ip: ip,
          hostname: hostname,
          vendor: vendorName === 'Unknown' ? '' : vendorName,
          interface: interfaceName,
          onlineTime: displayOnlineTime,
          signalStrength: signalStrength,
          rxRate: rxRate,
          txRate: txRate,
          isOnline: isOnline
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchConnectedDevices err: ${String(e)}`)
    }
    return []
  }

  async fetchTrafficHistory(): Promise<TrafficHistory[]> {
    return this.historyBuffer.length > 0 ? this.historyBuffer.slice(-20) : []
  }

  private async fetchCPUTemp(): Promise<number> {
    return this.client.getCPUTemp()
  }

  private async fetchCPUFreq(): Promise<number> {
    return this.client.getCPUFreq()
  }

  private emptySystemInfo(): SystemInfo {
    return {
      hostname: '', model: '', kernel: '', firmwareVersion: '',
      localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
      memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0, cpuFreq: 0,
      boardName: '', cpuModel: '', distribution: '', releaseVersion: '', releaseRevision: '', releaseTarget: ''
    }
  }

  private emptyWanStatus(): WanStatus {
    return {
      interface: '', uptime: 0, ipAddress: '0.0.0.0', netmask: '',
      gateway: '', dns: [], rxRate: 0, txRate: 0, onlineTime: '',
      proto: '', macAddr: ''
    }
  }

  /** 将秒数格式化为可读的 "X天X时X分" 格式 */
  private formatUptime(seconds: number): string {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    if (days > 0) {
      return `${days}天${hours}时${mins}分`
    }
    return `${hours}时${mins}分`
  }

  /** 将 Unix 时间戳转换为可读的日期时间字符串 */
  async fetchEthPortStatuses(): Promise<Object> {
    return this.client.networkDeviceStatus()
  }

  private formatTimestamp(ts: number): string {
    const d: Date = new Date(ts * 1000)
    const pad = (n: number): string => n.toString().padStart(2, '0')
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  }

  async fetchMountPoints(): Promise<MountPoint[]> {
    try {
      const mounts = await this.client.getMountPoints()

      // API 返回的 data 直接就是数组 [{device, mount, fs, total_kb, ...}, ...]，也可能包在 mounts 中
      let mountArray: Object[] = []
      if (Array.isArray(mounts)) {
        mountArray = mounts as Object[]
      } else {
        mountArray = ObjectHelper.getArray(mounts, 'mounts')
      }

      const list: MountPoint[] = []

      for (let i = 0; i < mountArray.length; i++) {
        const mount = mountArray[i]
        // API 返回 total_kb/used_kb/free_kb（KB），需 ×1024 转字节
        const sizeKb = ObjectHelper.getNumber(mount, 'total_kb', 0) ||
          ObjectHelper.getNumber(mount, 'total', 0)
        const usedKb = ObjectHelper.getNumber(mount, 'used_kb', 0) ||
          ObjectHelper.getNumber(mount, 'used', 0)
        const freeKb = ObjectHelper.getNumber(mount, 'free_kb', 0) ||
          ObjectHelper.getNumber(mount, 'available', 0) ||
          ObjectHelper.getNumber(mount, 'free', 0)
        const size = sizeKb * 1024
        const used = usedKb * 1024
        const available = freeKb * 1024
        // 计算磁盘使用率百分比（避免除零）
        const usedPercent = size > 0 ? Math.round((used / size) * 100) : 0

        const item: MountPoint = {
          device: ObjectHelper.getString(mount, 'device', ''),
          mountPoint: ObjectHelper.getString(mount, 'mount', '') ||
            ObjectHelper.getString(mount, 'mountpoint', '') ||
            ObjectHelper.getString(mount, 'mount_point', ''),
          filesystem: ObjectHelper.getString(mount, 'fs', '') ||
            ObjectHelper.getString(mount, 'type', '') ||
            ObjectHelper.getString(mount, 'filesystem', ''),
          size: size,
          used: used,
          available: available,
          usedPercent: usedPercent
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchMountPoints err')
    }
    return []
  }

  async fetchConntrackInfo(): Promise<ConntrackInfo> {
    try {
      // 获取 NAT 连接跟踪统计
      const info = await this.client.getConntrackInfo()
      const count = ObjectHelper.getNumber(info, 'count', 0)
      const max = ObjectHelper.getNumber(info, 'max', 0)
      // 当前连接数 / 最大连接数 的百分比
      const percent = max > 0 ? Math.round((count / max) * 100) : 0

      return {
        current: count,
        max: max,
        percent: percent
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchConntrackInfo err')
    }
    return { current: 0, max: 0, percent: 0 }
  }

  async fetchConntrack(): Promise<ConntrackInfo> {
    return this.fetchConntrackInfo()
  }
  async fetchConntrackList(): Promise<Object[]> {
    try {
      return await this.client.getConntrackList()
    } catch (e) {
      return []
    }
  }



  async fetchProcessList(): Promise<ProcessInfo[]> {
    try {
      const processes = await this.client.getProcessList()
      let processList: Object[] = []
      if (Array.isArray(processes)) {
        processList = processes as Object[]
      } else {
        processList = ObjectHelper.getArray(processes, 'processes')
      }
      const list: ProcessInfo[] = []

      for (let i = 0; i < processList.length; i++) {
        const p = processList[i]
        const rssKb = ObjectHelper.getNumber(p, 'rss_kb', 0)
        const rssRaw = ObjectHelper.getNumber(p, 'rss', 0)
        const item: ProcessInfo = {
          pid: ObjectHelper.getNumber(p, 'pid', 0),
          ppid: ObjectHelper.getNumber(p, 'ppid', 0),
          name: ObjectHelper.getString(p, 'comm', '') ||
            ObjectHelper.getString(p, 'name', ''),
          cpu: ObjectHelper.getNumber(p, 'cpu_percent', 0) ||
            ObjectHelper.getNumber(p, 'cpu', 0) ||
            ObjectHelper.getNumber(p, 'pcpu', 0),
          mem: ObjectHelper.getNumber(p, 'mem_bytes', 0) ||
            ObjectHelper.getNumber(p, 'mem', 0) ||
            (rssKb > 0 ? rssKb * 1024 : 0) ||
            (rssRaw > 0 ? rssRaw * 1024 : 0),
          memPercent: ObjectHelper.getNumber(p, 'mem_percent', 0) ||
            ObjectHelper.getNumber(p, 'pmem', 0),
          status: ObjectHelper.getString(p, 'status', '') ||
            ObjectHelper.getString(p, 'stat', ''),
          user: ObjectHelper.getString(p, 'user', ''),
          command: ObjectHelper.getString(p, 'command', '') ||
            ObjectHelper.getString(p, 'args', '') ||
            ObjectHelper.getString(p, 'comm', '') ||
            ObjectHelper.getString(p, 'name', '')
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchProcessList err')
    }
    return []
  }

  async fetchStartupItems(): Promise<StartupItem[]> {
    try {
      const items = await this.client.getStartupItems()
      const list: StartupItem[] = []

      // ubus rc list 返回对象格式: { "name": { "start": 30, "enabled": true, "running": true } }
      if (Array.isArray(items)) {
        // 兼容旧数组格式
        const arr = items as Object[]
        for (let i = 0; i < arr.length; i++) {
          const it = arr[i]
          const name = ObjectHelper.getString(it, 'name', '') ||
            ObjectHelper.getString(it, 'comm', '')
          list.push(this.parseStartupItem(it, name))
        }
      } else if (items && typeof items === 'object') {
        // 对象格式：遍历 key
        const keys = Object.keys(items)
        for (let i = 0; i < keys.length; i++) {
          const name = keys[i]
          const svc = (items as Record<string, Object>)[name]
          list.push(this.parseStartupItem(svc, name))
        }
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchStartupItems err')
    }
    return []
  }

  private parseStartupItem(svc: Object, name: string): StartupItem {
    return {
      name: typeof name === 'string' ? name : ObjectHelper.getString(svc, 'name', ''),
      priority: ObjectHelper.getNumber(svc, 'start', 0),
      enabled: ObjectHelper.getNumber(svc, 'enabled', 0) === 1 ||
        ObjectHelper.getString(svc, 'enabled', '') === 'true',
      running: ObjectHelper.getNumber(svc, 'running', 0) === 1 ||
        ObjectHelper.getString(svc, 'running', '') === 'true'
    }
  }

  async fetchRoutes(): Promise<RouteEntry[]> {
    try {
      const routes = await this.client.getRouteTable()
      let routeList: Object[] = []
      if (Array.isArray(routes)) {
        routeList = routes as Object[]
      } else {
        routeList = ObjectHelper.getArray(routes, 'routes')
      }
      const list: RouteEntry[] = []

      for (let i = 0; i < routeList.length; i++) {
        const r = routeList[i]
        const item: RouteEntry = {
          destination: ObjectHelper.getString(r, 'destination', ''),
          gateway: ObjectHelper.getString(r, 'gateway', ''),
          device: ObjectHelper.getString(r, 'device', '') ||
            ObjectHelper.getString(r, 'iface', ''),
          source: ObjectHelper.getString(r, 'source', '') ||
            ObjectHelper.getString(r, 'src', ''),
          scope: ObjectHelper.getString(r, 'scope', ''),
          table: ObjectHelper.getString(r, 'table', ''),
          flags: ObjectHelper.getString(r, 'flags', '')
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchRoutes err')
    }
    return []
  }

  async fetchWirelessClients(_device?: string): Promise<WirelessClient[]> {
    try {
      // 获取无线状态，包含所有接口及其连接的客户端列表
      const wireless = await this.client.getWirelessStatus()
      const list: WirelessClient[] = []

      // 先尝试顶层直接返回的 clients 数组（扁平结构）
      const topClients = ObjectHelper.getArray(wireless, 'clients')
      if (topClients.length > 0) {
        for (let j = 0; j < topClients.length; j++) {
          const client = topClients[j]
          list.push(this.parseWirelessClient(client, client))
        }
        return list
      }

      // 遍历每个无线接口下的客户端（两层嵌套：interfaces → 每个 interface 下的 clients）
      const interfaces = ObjectHelper.getArray(wireless, 'interfaces')
      for (let i = 0; i < interfaces.length; i++) {
        const iface = interfaces[i]
        const clients = ObjectHelper.getArray(iface, 'clients')
        for (let j = 0; j < clients.length; j++) {
          const client = clients[j]
          list.push(this.parseWirelessClient(client, iface))
        }
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessClients err')
    }
    return []
  }

  private parseWirelessClient(client: Object, iface: Object): WirelessClient {
    return {
      mac: ObjectHelper.getString(client, 'mac', '') ||
        ObjectHelper.getString(client, 'macaddr', ''),
      hostname: ObjectHelper.getString(client, 'hostname', '') ||
        ObjectHelper.getString(client, 'name', ''),
      interface: ObjectHelper.getString(client, 'interface', '') ||
        ObjectHelper.getString(iface, 'interface', '') ||
        ObjectHelper.getString(iface, 'ifname', '') ||
        ObjectHelper.getString(iface, 'name', ''),
      signal: ObjectHelper.getNumber(client, 'signal', 0) ||
        ObjectHelper.getNumber(client, 'rssi', 0),
      signalNoise: ObjectHelper.getNumber(client, 'noise', 0) ||
        ObjectHelper.getNumber(client, 'signal_noise', 0),
      rxRate: ObjectHelper.getNumber(client, 'rx_rate', 0) ||
        ObjectHelper.getNumber(client, 'rx_bitrate', 0) ||
        ObjectHelper.getNumber(client, 'rx', 0),
      txRate: ObjectHelper.getNumber(client, 'tx_rate', 0) ||
        ObjectHelper.getNumber(client, 'tx_bitrate', 0) ||
        ObjectHelper.getNumber(client, 'tx', 0),
      connectedTime: ObjectHelper.getNumber(client, 'connected_time', 0) ||
        ObjectHelper.getNumber(client, 'assoc_time', 0) ||
        ObjectHelper.getNumber(client, 'uptime', 0),
      inactiveTime: ObjectHelper.getNumber(client, 'inactive_time', 0) ||
        ObjectHelper.getNumber(client, 'idle_time', 0),
      isMesh: ObjectHelper.getNumber(client, 'mesh', 0) === 1 ||
        ObjectHelper.getString(client, 'mesh', '') === 'true'
    }
  }

  async fetchWirelessDevices(): Promise<WirelessDevice[]> {
    try {
      // 获取无线设备列表（如无线网卡），每个设备可能包含多个接口（如 2.4G + 5G）
      const wireless = await this.client.getWirelessDevices()
      const devices = ObjectHelper.getArray(wireless, 'devices')
      const list: WirelessDevice[] = []

      for (let i = 0; i < devices.length; i++) {
        const device = devices[i]
        const interfaces = ObjectHelper.getArray(device, 'interfaces')

        // 从设备的所有子接口中提取 SSID、信道等信息
        let ssid = ''
        let channel = 0
        let frequency = 0
        let bandwidth = ''
        let encryption = ''
        let signal = 0
        let quality = 0
        let mode = ''

        for (let j = 0; j < interfaces.length; j++) {
          const iface = interfaces[j]
          ssid = ObjectHelper.getString(iface, 'ssid', ssid)
          channel = ObjectHelper.getNumber(iface, 'channel', channel)
          mode = ObjectHelper.getString(iface, 'mode', mode)
        }

        const item: WirelessDevice = {
          name: ObjectHelper.getString(device, 'name', ''),
          bssid: '',
          ssid: ssid,
          channel: channel,
          frequency: frequency,
          bandwidth: bandwidth,
          encryption: encryption,
          signal: signal,
          quality: quality,
          mode: mode,
          up: !ObjectHelper.parseDisabled(ObjectUtil.getValue(device, 'disabled')),
          hwmode: '',
          protocol: ''
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessDevices err')
    }
    return []
  }

  // ========== WiFi 管理 ==========

  /**
   * 获取所有 WiFi 接入点信息（含客户端数，用于管理页展示）
   */
  async fetchWifiApList(): Promise<WifiApInfo[]> {
    try {
      const devices = await this.fetchWirelessDevices()
      // 读取 wireless 配置，获取每个无线接口的 disabled 状态（接口名为 key）
      const disabledMap: Map<string, boolean> = new Map()
      try {
        const wlConfig: Object = await this.client.getWirelessConfig()
        const configRec = wlConfig as Record<string, Object>
        const ifaceNames: string[] = Object.keys(configRec)
        for (let i = 0; i < ifaceNames.length; i++) {
          const ifaceRec = configRec[ifaceNames[i]] as Record<string, Object>
          if (!ifaceRec) continue
          const disabledVal = ifaceRec['disabled']
          disabledMap.set(ifaceNames[i], ObjectHelper.parseDisabled(disabledVal))
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'fetchWifiApList config err')
      }
      const list: WifiApInfo[] = []
      for (let i = 0; i < devices.length; i++) {
        const dev = devices[i]
        // 优先用 wireless 配置的 disabled（key 匹配），缺失时回退 dev.up
        let disabled: boolean = disabledMap.get(dev.name) ?? false
        if (!disabledMap.has(dev.name)) {
          disabled = !dev.up
        }
        list.push({
          device: dev.name,
          ssid: dev.ssid,
          channel: dev.channel,
          frequency: dev.frequency,
          txpower: 0,
          encryption: dev.encryption,
          quality: dev.quality,
          hwmode: dev.hwmode,
          mode: dev.mode,
          up: !disabled,
          clientCount: 0,
          bandwidth: dev.bandwidth,
          disabled: disabled
        })
      }
      // 补充客户端数
      const clients = await this.fetchWifiClients()
      for (let i = 0; i < list.length; i++) {
        let cnt: number = 0
        for (let j = 0; j < clients.length; j++) {
          if (clients[j].device === list[i].device) {
            cnt++
          }
        }
        list[i].clientCount = cnt
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWifiApList err')
    }
    return []
  }

  /**
   * 获取所有 WiFi 客户端详情（含信号/速率/时长）
   */
  async fetchWifiClients(): Promise<WifiClientDetail[]> {
    try {
      const raw = await this.client.getWirelessStatus()
      const list: WifiClientDetail[] = []
      const topClients = ObjectHelper.getArray(raw, 'clients')
      if (topClients.length > 0) {
        for (let i = 0; i < topClients.length; i++) {
          list.push(this.parseWifiClientDetail(topClients[i], topClients[i]))
        }
        return list
      }
      const interfaces = ObjectHelper.getArray(raw, 'interfaces')
      for (let i = 0; i < interfaces.length; i++) {
        const iface = interfaces[i]
        const clients = ObjectHelper.getArray(iface, 'clients')
        for (let j = 0; j < clients.length; j++) {
          list.push(this.parseWifiClientDetail(clients[j], iface))
        }
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWifiClients err')
    }
    return []
  }

  private parseWifiClientDetail(client: Object, iface: Object): WifiClientDetail {
    return {
      mac: ObjectHelper.getString(client, 'mac', '') || ObjectHelper.getString(client, 'macaddr', ''),
      hostname: ObjectHelper.getString(client, 'hostname', '') || ObjectHelper.getString(client, 'name', ''),
      device: ObjectHelper.getString(client, 'interface', '') ||
        ObjectHelper.getString(iface, 'interface', '') ||
        ObjectHelper.getString(iface, 'ifname', '') ||
        ObjectHelper.getString(iface, 'name', ''),
      signal: ObjectHelper.getNumber(client, 'signal', 0),
      noise: ObjectHelper.getNumber(client, 'noise', 0) || ObjectHelper.getNumber(client, 'signal_noise', 0),
      rxRate: ObjectHelper.getNumber(client, 'rx_rate', 0) ||
        ObjectHelper.getNumber(client, 'rx', 0),
      txRate: ObjectHelper.getNumber(client, 'tx_rate', 0) ||
        ObjectHelper.getNumber(client, 'tx', 0),
      connectedTime: ObjectHelper.getNumber(client, 'connected_time', 0) ||
        ObjectHelper.getNumber(client, 'assoc_time', 0),
      inactiveTime: ObjectHelper.getNumber(client, 'inactive_time', 0)
    }
  }

  /**
   * 修改 WiFi 配置（SSID/密码/信道/频宽/开关等）
   * @param device 无线设备段（radio0 等）
   * @param option 配置项（ssid/key/disabled/channel/htmode 等）
   * @param value 新值
   */
  async updateWifiConfig(device: string, option: string, value: string): Promise<boolean> {
    try {
      const ok: boolean = await this.client.setWifiConfig(device, option, value)
      if (!ok) {
        return false
      }
      return await this.client.applyWifiConfig()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'updateWifiConfig err')
    }
    return false
  }

  /** 执行远程命令（受路由器 ACL 白名单限制） */
  async execCommand(command: string, params?: string[]): Promise<string> {
    try {
      return await this.client.execCommand(command, params)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'execCommand err')
    }
    return ''
  }

  /** 智能网络体检：逐项执行 ping 检测并解析结果 */
  async networkDiagnose(): Promise<NetworkCheckItem[]> {
    const items: NetworkCheckItem[] = []
    // 1. 先识别网关地址（路由表默认路由）
    let gateway: string = ''
    try {
      const gwOut: string = await this.execCommand('/sbin/ip', ['route', 'show', 'default'])
      const gwMatch: RegExpMatchArray | null = gwOut.match(/default via ([\d.]+)/)
      if (gwMatch && gwMatch[1]) {
        gateway = gwMatch[1]
      }
    } catch (e) {}
    // 2. 逐项检测（串行，避免并发命令在路由器上冲突）
    items.push(await this.pingCheck('gateway', '网关连通性', gateway ? gateway : '192.168.1.1',
      '内网网关延迟', gateway ? '' : '未识别网关，使用默认 192.168.1.1'))
    items.push(await this.pingCheck('wan_ali', '外网连通性', '223.5.5.5', '阿里公共 DNS'))
    items.push(await this.pingCheck('wan_tx', '公网延迟', '119.29.29.29', '腾讯公共 DNS'))
    items.push(await this.pingCheck('dns', 'DNS 解析', 'baidu.com', '域名解析能力'))
    return items
  }

  /** 单项 ping 检测：执行 ping -c 3 -W 1 并解析丢包率/平均延迟 */
  private async pingCheck(key: string, name: string, target: string, desc: string,
    detailNote: string = ''): Promise<NetworkCheckItem> {
    let status: string = 'fail'
    let latency: number = 0
    let loss: number = 100
    let detail: string = detailNote
    try {
      const out: string = await this.execCommand('/bin/ping', ['-c', '3', '-W', '1', target])
      if (out) {
        const lossMatch: RegExpMatchArray | null = out.match(/(\d+)% packet loss/i)
        if (lossMatch) {
          loss = parseInt(lossMatch[1])
        } else {
          const recvMatch: RegExpMatchArray | null = out.match(/(\d+) packets received/i)
          if (recvMatch) {
            loss = 3 - parseInt(recvMatch[1])
          }
        }
        const avgMatch: RegExpMatchArray | null = out.match(/round-trip min\/avg\/max = [\d.]+\/([\d.]+)\//) ||
          out.match(/min\/avg\/max\s*=\s*[\d.]+\/([\d.]+)\//)
        if (avgMatch && avgMatch[1]) {
          latency = parseFloat(avgMatch[1])
        }
        if (loss >= 100) {
          status = 'fail'
          detail = detail || '目标不可达'
        } else if (loss > 0) {
          status = 'warn'
          detail = detail || `${loss}% 丢包`
        } else if (latency > 0 && latency < 50) {
          status = 'ok'
          detail = detail || '网络优秀'
        } else if (latency >= 50 && latency < 150) {
          status = 'ok'
          detail = detail || '网络正常'
        } else if (latency >= 150) {
          status = 'warn'
          detail = detail || '延迟偏高'
        } else {
          status = 'ok'
          detail = detail || '连通正常'
        }
      } else {
        detail = detail || '命令无输出（可能无 ping 权限）'
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `pingCheck ${key} err: ${String(e)}`)
      detail = detail || '检测异常'
    }
    return { key: key, name: name, target: target, desc: desc, status: status,
      latencyMs: Math.round(latency), lossPercent: loss, detail: detail }
  }

  /** 读取路由器文件内容 */
  async readFile(path: string): Promise<string> {
    try {
      return await this.client.readFile(path)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readFile err')
    }
    return ''
  }

  /** 轻量在线检测：执行 ACL 白名单内的 /bin/df，成功即在线 */
  async isRouterOnline(): Promise<boolean> {
    try {
      const out: string = await this.client.execCommand('/bin/df', ['-k'])
      return out.length > 0
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'isRouterOnline err')
    }
    return false
  }

  /** 获取无线接口名列表（radio0 / radio1 等，用于定时开关 WiFi） */
  async getWirelessRadios(): Promise<string[]> {
    try {
      const list: WifiApInfo[] = await this.fetchWifiApList()
      const radios: string[] = []
      for (let i = 0; i < list.length; i++) {
        const dev: string = list[i].device
        if (dev && radios.indexOf(dev) < 0) {
          radios.push(dev)
        }
      }
      return radios
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getWirelessRadios err')
    }
    return []
  }

  /** 开关所有无线接口（定时任务用）：disabled=1 关 / 0 开 */
  async setAllWifiEnabled(enabled: boolean): Promise<boolean> {
    try {
      const radios: string[] = await this.getWirelessRadios()
      if (radios.length === 0) {
        return false
      }
      const disabledVal: string = enabled ? '0' : '1'
      let ok: boolean = true
      for (let i = 0; i < radios.length; i++) {
        const r: boolean = await this.updateWifiConfig(radios[i], 'disabled', disabledVal)
        if (!r) {
          ok = false
        }
      }
      return ok
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setAllWifiEnabled err')
    }
    return false
  }

  /**
   * 踢下线 WiFi 客户端
   * @param device 无线设备名（radio0）
   * @param mac 客户端 MAC
   */
  async kickWifiClient(device: string, mac: string): Promise<boolean> {
    try {
      return await this.client.kickWifiClient(device, mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'kickWifiClient err')
    }
    return false
  }

  /** 禁用设备联网（添加防火墙 DROP 规则） */
  async denyDeviceNet(mac: string): Promise<boolean> {
    try {
      return await this.client.denyDeviceNet(mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'denyDeviceNet err')
    }
    return false
  }

  /** 恢复设备联网（删除防火墙规则） */
  async allowDeviceNet(mac: string): Promise<boolean> {
    try {
      return await this.client.allowDeviceNet(mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'allowDeviceNet err')
    }
    return false
  }

  /** 查询设备是否被禁用联网 */
  async isDeviceDenied(mac: string): Promise<boolean> {
    try {
      return await this.client.isDeviceDenied(mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'isDeviceDenied err')
    }
    return false
  }

  /** 获取 DHCP 静态绑定列表 */
  async listDhcpBindings(): Promise<DhcpBindingInfo[]> {
    try {
      return await this.client.listDhcpBindings()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'listDhcpBindings err')
    }
    return []
  }

  /** 添加 DHCP 静态绑定 */
  async addDhcpBinding(mac: string, ip: string, name: string): Promise<boolean> {
    try {
      return await this.client.addDhcpBinding(mac, ip, name)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'addDhcpBinding err')
    }
    return false
  }

  /** 移除 DHCP 静态绑定 */
  async removeDhcpBinding(mac: string): Promise<boolean> {
    try {
      return await this.client.removeDhcpBinding(mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'removeDhcpBinding err')
    }
    return false
  }

  /** 查询指定 MAC 是否已有静态绑定 */
  async isDhcpBound(mac: string): Promise<boolean> {
    try {
      return await this.client.isDhcpBound(mac)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'isDhcpBound err')
    }
    return false
  }

  /** 获取访客网络状态 */
  async getGuestWifiStatus(): Promise<GuestWifiInfo | null> {
    try {
      return await this.client.getGuestWifiStatus()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getGuestWifiStatus err')
    }
    return null
  }

  /** 开启访客网络 */
  async enableGuestWifi(ssid: string, password: string, device: string): Promise<boolean> {
    try {
      return await this.client.enableGuestWifi(ssid, password, device)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'enableGuestWifi err')
    }
    return false
  }

  /** 关闭访客网络 */
  async disableGuestWifi(): Promise<boolean> {
    try {
      return await this.client.disableGuestWifi()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'disableGuestWifi err')
    }
    return false
  }

  /**
   * 获取 WAN 接口累计收发字节数（流量统计用，返回 [rx, tx]）
   * 数据源按可靠性依次降级：
   *   1. network.interface dump 的 statistics（netifd 提供，ACL 最宽松，与网口流量页同一次请求）
   *   2. luci-rpc getNetworkDevices 的 stats 缓存
   *   3. ubus luci-rpc / /proc/net/dev
   * 之前只用了第 3 条，在 luci-rpc 被 ACL 拒绝的固件上恒为 [0,0]，导致所有流量统计页永远为空
   */
  async fetchWanTrafficBytes(): Promise<number[]> {
    try {
      // 累计字节数有增量语义，必须拿最新值，不能吃 TTL 缓存
      await this.getNetworkData(true)
      const list: Object[] = ObjectHelper.getArray(ApiService.interfacesCache!, 'interface')
      // 1. 优先 network.interface dump 自带的 statistics
      const fromDump: number[] = this.pickWanBytes(list, true)
      if (fromDump[0] > 0 || fromDump[1] > 0) {
        return fromDump
      }
      // 2. 次选 luci-rpc 的设备统计缓存
      const fromCache: number[] = this.pickWanBytes(list, false)
      if (fromCache[0] > 0 || fromCache[1] > 0) {
        return fromCache
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchWanTrafficBytes err: ${String(e)}`)
    }
    // 3. 最终回退：ubus 通道（部分固件只有这条可用）
    try {
      return await this.client.getWanTrafficBytes()
    } catch (e) {
      return [0, 0]
    }
  }

  /**
   * 从接口列表中挑出 WAN 的累计收发字节
   * @param useDump true=读接口对象的 statistics 字段；false=读 luci-rpc stats 缓存
   */
  private pickWanBytes(list: Object[], useDump: boolean): number[] {
    // 1. WAN 逻辑接口
    for (let i = 0; i < list.length; i++) {
      const it: Object = list[i]
      const type: string = ObjectHelper.getString(it, 'type', '')
      const name: string = ObjectHelper.getString(it, 'interface', '') ||
        ObjectHelper.getString(it, 'name', '')
      const dev: string = ObjectHelper.getString(it, 'l3_device', '') ||
        ObjectHelper.getString(it, 'device', '')
      const isWan: boolean = type === 'wan' || name === 'wan' || name.startsWith('wan') ||
        name.startsWith('pppoe')
      if (!isWan) {
        continue
      }
      const v: number[] = this.bytesOf(it, dev, name, useDump)
      if (v[0] > 0 || v[1] > 0) {
        return v
      }
    }
    // 2. 回退：累计字节最大的非虚拟接口（排除 lo / 网桥 / 容器虚拟网卡）
    let best: number[] = [0, 0]
    let bestSum: number = 0
    for (let i = 0; i < list.length; i++) {
      const it: Object = list[i]
      const name: string = ObjectHelper.getString(it, 'interface', '') ||
        ObjectHelper.getString(it, 'name', '')
      const dev: string = ObjectHelper.getString(it, 'l3_device', '') ||
        ObjectHelper.getString(it, 'device', '')
      const target: string = dev ? dev : name
      if (!target || this.isVirtualIface(target)) {
        continue
      }
      const v: number[] = this.bytesOf(it, dev, name, useDump)
      const sum: number = v[0] + v[1]
      if (sum > bestSum) {
        bestSum = sum
        best = v
      }
    }
    return best
  }

  /** 读取单个接口的累计字节（[rx, tx]） */
  private bytesOf(it: Object, dev: string, logicalName: string, useDump: boolean): number[] {
    if (useDump) {
      const stObj: Object | undefined = (it as Record<string, Object>)['statistics']
      if (stObj && typeof stObj === 'object') {
        const st: Record<string, Object> = stObj as Record<string, Object>
        return [
          ObjectHelper.getNumber(st, 'rx_bytes', 0),
          ObjectHelper.getNumber(st, 'tx_bytes', 0)
        ]
      }
      return [0, 0]
    }
    const byDev: number[] | undefined = dev ? ApiService.statsCache.get(dev) : undefined
    return byDev || ApiService.statsCache.get(logicalName) || ApiService.statsCache.get(dev) || [0, 0]
  }

  /** 是否虚拟接口（不计入 WAN 流量回退） */
  private isVirtualIface(name: string): boolean {
    return name === 'lo' || name.startsWith('br-') || name.startsWith('docker') ||
      name.startsWith('veth') || name.startsWith('virbr') || name.startsWith('tun') ||
      name.startsWith('tap') || name.startsWith('wg')
  }

  /**
   * 读取 WiFi 配置项（uci get wireless.<device>.<option>）
   */
  async getWifiOption(device: string, option: string): Promise<string> {
    try {
      return await this.client.getUciOption('wireless', device, option)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getWifiOption err')
    }
    return ''
  }

  async fetchOafStatus(): Promise<OafStatus> {
    try {
      // 获取 OAF（应用过滤引擎）各组件版本和运行状态
      // ubus appfilter.get_oaf_status 返回 {enable, version, engine_status, engine_version, kernel_version, config_enable}
      const status = await this.client.getOafStatus()
      return {
        pluginVersion: ObjectHelper.getString(status, 'version', ''),
        engineVersion: ObjectHelper.getString(status, 'engine_version', ''),
        kernelVersion: ObjectHelper.getString(status, 'kernel_version', ''),
        configStatus: ObjectHelper.getString(status, 'config_enable', ''),
        filterStatus: ObjectHelper.getString(status, 'enable', ''),
        engineStatus: ObjectHelper.getString(status, 'engine_status', ''),
        versionTooHigh: false
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchOafStatus err')
    }
    return {
      pluginVersion: '',
      engineVersion: '',
      kernelVersion: '',
      configStatus: '',
      filterStatus: '',
      engineStatus: '',
      versionTooHigh: false
    }
  }

  async fetchAppFilterBase(): Promise<AppFilterBase> {
    try {
      // 读取应用过滤总开关配置
      // ubus appfilter.get_app_filter_base 返回 {enable, work_mode, record_enable}
      const base = await this.client.getAppFilterBase()
      return {
        appFilterEnabled: ObjectHelper.getNumber(base, 'enable', 0) === 1,
        appLogEnabled: ObjectHelper.getNumber(base, 'record_enable', 0) === 1,
        workMode: ObjectHelper.getNumber(base, 'work_mode', 0) === 1 ? 'bypass' : 'gateway'
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterBase err')
    }
    return { appFilterEnabled: false, appLogEnabled: false, workMode: 'gateway' }
  }

  async fetchAppFilterClasses(): Promise<AppClass[]> {
    try {
      // ubus appfilter.class_list 返回 {class_list: [{name, app_list: ["id,名称,启用", ...]}]}
      const classes = await this.client.getAppFilterClassList()
      const classList = classes.length > 0 ? ObjectHelper.getArray(classes[0], 'class_list') : []
      const list: AppClass[] = []

      for (let i = 0; i < classList.length; i++) {
        const cls = classList[i]
        const apps = ObjectHelper.getArray(cls, 'app_list')
        const appList: AppItem[] = []

        for (let j = 0; j < apps.length; j++) {
          // 应用条目为 "id,名称,启用标志" 的 CSV 字符串
          const parts: string[] = String(apps[j]).split(',')
          if (parts.length < 2) continue
          const appItem: AppItem = {
            id: parseInt(parts[0]) || 0,
            name: parts[1] || '',
            enabled: parts.length > 2 && parts[2] === '1'
          }
          appList.push(appItem)
        }

        const item: AppClass = {
          id: i + 1,
          name: ObjectHelper.getString(cls, 'name', ''),
          apps: appList
        }
        list.push(item)
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterClasses err')
    }
    return []
  }

  async fetchAppFilter(): Promise<AppClass[]> {
    return this.fetchAppFilterClasses()
  }

  async fetchAppFilterTime(): Promise<AppFilterTime> {
    try {
      // ubus appfilter.get_app_filter_time 返回
      // {mode, weekday_list, start_time, end_time, deny_time, allow_time, time_list: [{start, end}]}
      const time = await this.client.getAppFilterTime()

      // 1. 解析固定时间段数组（start/end 为 "HH:MM" 字符串）
      const fixedTimes = ObjectHelper.getArray(time, 'time_list')
      const fixedList: TimeSlot[] = []

      for (let i = 0; i < fixedTimes.length; i++) {
        const t = fixedTimes[i]
        const startParts: string[] = ObjectHelper.getString(t, 'start', '00:00').split(':')
        const endParts: string[] = ObjectHelper.getString(t, 'end', '00:00').split(':')
        const slot: TimeSlot = {
          startHour: parseInt(startParts[0]) || 0,
          startMin: startParts.length > 1 ? (parseInt(startParts[1]) || 0) : 0,
          endHour: parseInt(endParts[0]) || 0,
          endMin: endParts.length > 1 ? (parseInt(endParts[1]) || 0) : 0
        }
        fixedList.push(slot)
      }

      // 2. 解析动态时长起止时间（顶层 start_time/end_time）
      const dynStart: string[] = ObjectHelper.getString(time, 'start_time', '00:00').split(':')
      const dynEnd: string[] = ObjectHelper.getString(time, 'end_time', '00:00').split(':')
      // 动态时长：allow_time 为允许使用分钟数（-1 表示未启用）
      const allowTime: number = ObjectHelper.getNumber(time, 'allow_time', -1)

      // 3. 解析生效的星期列表（0=周日, 1=周一 ... 6=周六）
      const weekdaysArr = ObjectHelper.getArray(time, 'weekday_list')
      const weekdays: number[] = []
      for (let i = 0; i < weekdaysArr.length; i++) {
        weekdays.push(Number(weekdaysArr[i]))
      }

      return {
        fixedTimes: fixedList,
        dynamicMinutes: allowTime > 0 ? allowTime : 0,
        dynamicStartHour: parseInt(dynStart[0]) || 0,
        dynamicStartMin: dynStart.length > 1 ? (parseInt(dynStart[1]) || 0) : 0,
        dynamicEndHour: parseInt(dynEnd[0]) || 0,
        dynamicEndMin: dynEnd.length > 1 ? (parseInt(dynEnd[1]) || 0) : 0,
        weekdays: weekdays
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterTime err')
    }
    return { fixedTimes: [], dynamicMinutes: 0, dynamicStartHour: 0, dynamicStartMin: 0, dynamicEndHour: 0, dynamicEndMin: 0, weekdays: [] }
  }

  async fetchAppFilterUser(): Promise<AppFilterUser> {
    try {
      // ubus appfilter.get_app_filter_user 返回 {mode: 0|1, list: [...]}
      const userConfig = await this.client.getAppFilterUser()
      const mode: AppFilterMode = ObjectHelper.getNumber(userConfig, 'mode', 0) === 1 ? 'manual' : 'auto'
      return { mode: mode, users: [] }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterUser err')
    }
    return { mode: 'auto', users: [] }
  }

  async fetchAppFilterAdv(): Promise<Object> {
    try {
      return await this.client.getAppFilterAdv()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterAdv err')
    }
    return new EmptyRecord()
  }

  async fetchIStoreApps(): Promise<IStoreApp[]> {
    try {
      const result = await this.client.getIStoreApps()
      const apps = result.length > 0 ? result[0] as Object[] : []
      const list: IStoreApp[] = []
      for (let i = 0; i < apps.length; i++) {
        const a = apps[i]
        list.push({
          name: ObjectHelper.getString(a, 'name', ''),
          title: ObjectHelper.getString(a, 'title', ''),
          version: ObjectHelper.getString(a, 'version', ''),
          icon: ObjectHelper.getString(a, 'icon', ''),
          link: ObjectHelper.getString(a, 'link', ''),
          iconBase64: '',
          category: ObjectHelper.getString(a, 'category', '')
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchIStoreApps err: ${String(e)}`)
    }
    return []
  }

  /** 当前设备 API 基础 URL（协议://主机:端口），用于拼 LuCI 静态资源地址 */
  getBaseUrl(): string {
    return this.client.baseUrl
  }

  async fetchDockerOverview(): Promise<DockerOverview> {
    try {
      const data = await this.client.getDockerOverview()
      return {
        dockerVersion: ObjectHelper.getString(data, 'docker_version', ''),
        daemonStatus: ObjectHelper.getString(data, 'daemon_status', 'stopped'),
        containersTotal: ObjectHelper.getNumber(data, 'containers_total', 0),
        containersRunning: ObjectHelper.getNumber(data, 'containers_running', 0),
        imagesTotal: ObjectHelper.getNumber(data, 'images_total', 0),
        diskUsed: ObjectHelper.getString(data, 'disk_used', '0'),
        memUsedMb: ObjectHelper.getString(data, 'mem_used_mb', '0')
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDockerOverview err: ${String(e)}`)
    }
    return { dockerVersion: '', daemonStatus: 'stopped', containersTotal: 0, containersRunning: 0, imagesTotal: 0, diskUsed: '0', memUsedMb: '0' }
  }

  async dockerServiceAction(action: string): Promise<boolean> {
    try {
      await this.client.dockerService(action)
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, `dockerServiceAction err: ${String(e)}`)
    }
    return false
  }

  /** Docker Remote API（2375）是否可用 */
  hasDockerApi(): boolean {
    return this.client.hasDockerApi()
  }

  /** 开启 Docker Remote API（会导致容器短暂重启） */
  async enableDockerApi(): Promise<boolean> {
    try {
      return await this.client.enableDockerApi()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `enableDockerApi err: ${String(e)}`)
    }
    return false
  }

  async fetchDockerContainers(): Promise<DockerContainer[]> {
    try {
      const result = await this.client.getDockerContainers()
      const arr = result.length > 0 ? result[0] as Object[] : []
      const list: DockerContainer[] = []
      for (let i = 0; i < arr.length; i++) {
        const c = arr[i]
        list.push({
          id: ObjectHelper.getString(c, 'id', ''),
          name: ObjectHelper.getString(c, 'name', ''),
          status: ObjectHelper.getString(c, 'status', ''),
          image: ObjectHelper.getString(c, 'image', ''),
          running: ObjectHelper.getBool(c, 'running')
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDockerContainers err: ${String(e)}`)
    }
    return []
  }

  async dockerContainerAction(container: string, action: string): Promise<boolean> {
    try {
      await this.client.dockerContainerAction(container, action)
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, `dockerContainerAction err: ${String(e)}`)
    }
    return false
  }

  /** 获取 Docker 镜像列表（仅 Docker API 可用时返回数据） */
  async fetchDockerImages(): Promise<DockerImage[]> {
    try {
      const result = await this.client.getDockerImages()
      const arr = result.length > 0 ? result[0] as Object[] : []
      const list: DockerImage[] = []
      for (let i = 0; i < arr.length; i++) {
        const c = arr[i]
        list.push({
          id: ObjectHelper.getString(c, 'id', ''),
          repoTag: ObjectHelper.getString(c, 'repoTag', '<none>:<none>'),
          size: ObjectHelper.getNumber(c, 'size', 0),
          created: ObjectHelper.getNumber(c, 'created', 0)
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDockerImages err: ${String(e)}`)
    }
    return []
  }

  /** 获取 Docker 网络列表（仅 Docker API 可用时返回数据） */
  async fetchDockerNetworks(): Promise<DockerNetwork[]> {
    try {
      const result = await this.client.getDockerNetworks()
      const arr = result.length > 0 ? result[0] as Object[] : []
      const list: DockerNetwork[] = []
      for (let i = 0; i < arr.length; i++) {
        const c = arr[i]
        list.push({
          id: ObjectHelper.getString(c, 'id', ''),
          name: ObjectHelper.getString(c, 'name', ''),
          driver: ObjectHelper.getString(c, 'driver', ''),
          scope: ObjectHelper.getString(c, 'scope', '')
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDockerNetworks err: ${String(e)}`)
    }
    return []
  }

  async fetchDockerStats(): Promise<DockerStats[]> {
    try {
      const result = await this.client.getDockerStats()
      const arr = result.length > 0 ? result[0] as Object[] : []
      const list: DockerStats[] = []
      for (let i = 0; i < arr.length; i++) {
        const s = arr[i]
        list.push({
          id: ObjectHelper.getString(s, 'id', ''),
          name: ObjectHelper.getString(s, 'name', ''),
          cpuPercent: ObjectHelper.getNumber(s, 'cpu_percent', 0),
          memUsage: ObjectHelper.getString(s, 'mem_usage', '0'),
          memPercent: ObjectHelper.getNumber(s, 'mem_percent', 0)
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDockerStats err: ${String(e)}`)
    }
    return []
  }

  async factoryReset(): Promise<string> {
    try {
      const ok = await this.client.factoryReset()
      return ok ? 'reset_initiated' : ''
    } catch (e) {
      hilog.error(DOMAIN, TAG, `factoryReset err: ${String(e)}`)
      return ''
    }
  }

  async fetchAllOafUsers(): Promise<Object[]> {
    try {
      const data: Object = await this.client.getAllUsers(3)
      const list = ObjectHelper.getArray(data, 'list')
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchAllOafUsers err: ${String(e)}`)
    }
    return []
  }

  async fetchUserList(): Promise<UserListItem[]> {
    try {
      const data: Object = await this.client.getAllUsers(3)
      const list = ObjectHelper.getArray(data, 'list')
      const result: UserListItem[] = []
      for (let i = 0; i < list.length; i++) {
        const u = list[i]
        const appList = ObjectHelper.getArray(u, 'applist')
        const commonApps: number[] = []
        for (let j = 0; j < appList.length; j++) {
          const id = ObjectHelper.getNumber(appList[j], 'id', 0)
          if (id > 0) commonApps.push(id)
        }
        result.push({
          hostname: ObjectHelper.getString(u, 'hostname', '') || ObjectHelper.getString(u, 'nickname', ''),
          mac: ObjectHelper.getString(u, 'mac', ''),
          ip: ObjectHelper.getString(u, 'ip', ''),
          currentApp: ObjectHelper.getString(u, 'app', ''),
          currentUrl: ObjectHelper.getString(u, 'url', ''),
          commonApps: commonApps
        })
      }
      return result
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchUserList err: ${String(e)}`)
    }
    return []
  }

  async fetchDeviceVisitTime(mac: string): Promise<DeviceVisitTime[]> {
    try {
      const data: Object = await this.client.getDeviceVisitTime(mac)
      const list = ObjectHelper.getArray(data, 'list')
      const result: DeviceVisitTime[] = []
      for (let i = 0; i < list.length; i++) {
        const v = list[i]
        const totalSec: number = ObjectHelper.getNumber(v, 't', 0)
        result.push({
          appId: ObjectHelper.getNumber(v, 'id', 0),
          appName: ObjectHelper.getString(v, 'name', ''),
          totalSeconds: totalSec,
          percent: 0
        })
      }
      // 计算占比
      let sum: number = 0
      for (let i = 0; i < result.length; i++) {
        sum += result[i].totalSeconds
      }
      if (sum > 0) {
        for (let i = 0; i < result.length; i++) {
          result[i].percent = Math.round(result[i].totalSeconds * 100 / sum)
        }
      }
      return result
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDeviceVisitTime err: ${String(e)}`)
    }
    return []
  }

  async fetchDeviceVisitList(mac: string): Promise<DeviceVisitRecord[]> {
    try {
      const data: Object = await this.client.getDeviceVisitList(mac)
      const list = ObjectHelper.getArray(data, 'list')
      const result: DeviceVisitRecord[] = []
      for (let i = 0; i < list.length; i++) {
        const v = list[i]
        result.push({
          appId: ObjectHelper.getNumber(v, 'id', 0),
          appName: ObjectHelper.getString(v, 'name', ''),
          startTime: this.formatTimestamp(ObjectHelper.getNumber(v, 'ft', 0)),
          duration: ObjectHelper.getNumber(v, 'tt', 0)
        })
      }
      return result
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchDeviceVisitList err: ${String(e)}`)
    }
    return []
  }

  async saveAppFilterBase(base: AppFilterBase): Promise<boolean> {
    try {
      const workModeBypass: boolean = base.workMode === 'bypass'
      return await this.client.setAppFilterBase(base.appFilterEnabled, workModeBypass, base.appLogEnabled)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveAppFilterBase err: ${String(e)}`)
    }
    return false
  }

  async saveAppFilter(classes: AppClass[]): Promise<boolean> {
    try {
      // 收集所有启用的应用 ID
      const appIds: number[] = []
      for (let i = 0; i < classes.length; i++) {
        const cls = classes[i]
        for (let j = 0; j < cls.apps.length; j++) {
          if (cls.apps[j].enabled) {
            appIds.push(cls.apps[j].id)
          }
        }
      }
      return await this.client.setAppFilter(appIds)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveAppFilter err: ${String(e)}`)
    }
    return false
  }

  async saveAppFilterTime(time: AppFilterTime): Promise<boolean> {
    try {
      // mode: 0=固定时段（有固定时段时），1=动态时长（有动态时长时）
      let mode: number = 0
      if (time.dynamicMinutes > 0) {
        mode = 1
      }
      const fixedTimes: Object[] = []
      for (let i = 0; i < time.fixedTimes.length; i++) {
        const slot = time.fixedTimes[i]
        const item: Record<string, Object> = {}
        item['start'] = `${String(slot.startHour).padStart(2, '0')}:${String(slot.startMin).padStart(2, '0')}`
        item['end'] = `${String(slot.endHour).padStart(2, '0')}:${String(slot.endMin).padStart(2, '0')}`
        fixedTimes.push(item as Object)
      }
      const dynStart: string = `${String(time.dynamicStartHour).padStart(2, '0')}:${String(time.dynamicStartMin).padStart(2, '0')}`
      const dynEnd: string = `${String(time.dynamicEndHour).padStart(2, '0')}:${String(time.dynamicEndMin).padStart(2, '0')}`
      return await this.client.setAppFilterTime(mode, time.weekdays, fixedTimes,
        time.dynamicMinutes, dynStart, dynEnd)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveAppFilterTime err: ${String(e)}`)
    }
    return false
  }

  async saveAppFilterUser(user: AppFilterUser): Promise<boolean> {
    try {
      const mode: number = user.mode === 'manual' ? 1 : 0
      return await this.client.setAppFilterUser(mode)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveAppFilterUser err: ${String(e)}`)
    }
    return false
  }

  async saveAppFilterAdv(adv: Object): Promise<boolean> {
    try {
      const rec = adv as Record<string, Object>
      const tcpRst: number = Number(rec['tcp_rst']) || 0
      const lanIfname: string = String(rec['lan_ifname'] || '')
      const disableHnat: number = Number(rec['disable_hnat']) || 0
      const autoLoadEngine: number = Number(rec['auto_load_engine']) || 0
      return await this.client.setAppFilterAdv(tcpRst, lanIfname, disableHnat, autoLoadEngine)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveAppFilterAdv err: ${String(e)}`)
    }
    return false
  }

  async rebootDevice(): Promise<boolean> {
    try {
      return await this.client.reboot()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `rebootDevice err: ${String(e)}`)
      return false
    }
  }
}
