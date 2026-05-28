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
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { FormatUtils } from '../common/utils/FormatUtils'

const TAG = 'ApiService'
const DOMAIN = 0x0001

type AppFilterMode = 'auto' | 'manual'

class EmptyRecord {
}

class ObjectHelper {
  /** 安全读取字符串字段，缺失时返回默认值 */
  static getString(obj: Object, key: string, def: string): string {
    if (!obj || typeof obj !== 'object') return def
    const keys = Object.keys(obj)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === key) {
        const record = obj as Record<string, Object>
        const v = record[key]
        if (v === undefined || v === null) return def
        return String(v)
      }
    }
    return def
  }

  /** 安全读取数值字段，缺失时返回默认值 */
  static getNumber(obj: Object, key: string, def: number): number {
    if (!obj || typeof obj !== 'object') return def
    const keys = Object.keys(obj)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === key) {
        const record = obj as Record<string, Object>
        const v = record[key]
        if (v === undefined || v === null) return def
        return Number(v)
      }
    }
    return def
  }

  /** 安全读取数组字段，缺失或非数组时返回空数组 */
  static getArray(obj: Object, key: string): Object[] {
    if (!obj || typeof obj !== 'object') return []
    const keys = Object.keys(obj)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === key) {
        const record = obj as Record<string, Object>
        const v = record[key]
        if (!v || !Array.isArray(v)) return []
        return v as Object[]
      }
    }
    return []
  }

  /** 安全读取嵌套对象字段，缺失时返回空对象 */
  static getObject(obj: Object, key: string): Object {
    if (!obj || typeof obj !== 'object') return new EmptyRecord()
    const record = obj as Record<string, Object>
    const v = record[key]
    if (!v || typeof v !== 'object') return new EmptyRecord()
    return v
  }

  /** 检查对象是否包含指定键 */
  static hasKey(obj: Object, key: string): boolean {
    if (!obj || typeof obj !== 'object') return false
    const keys = Object.keys(obj)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === key) return true
    }
    return false
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
  private client: ApiClient
  private historyBuffer: TrafficHistory[] = []
  private statsCache: Map<string, number[]> = new Map()

  constructor() {
    this.client = ApiClient.getInstance()
  }

  configureConnection(config: ConnectionConfig): void {
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
      // 5. 额外获取 CPU 温度
      const cpuTemp = await this.fetchCPUTemp()

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
      // 1. 获取所有网络接口列表
      const interfaces = await this.client.getNetworkInterfaces()
      const interfacesList = ObjectHelper.getArray(interfaces, 'interface')

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
      // rx_rate/tx_rate 为实时速率（字节/秒）
      const rxRate = ObjectHelper.getNumber(lanIf, 'rx_rate', 0)
      const txRate = ObjectHelper.getNumber(lanIf, 'tx_rate', 0)

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
      const interfaces = await this.client.getNetworkInterfaces()
      const interfacesList = ObjectHelper.getArray(interfaces, 'interface')
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
        const rxBytes = ObjectHelper.getNumber(iface, 'rx_bytes', 0)
        const txBytes = ObjectHelper.getNumber(iface, 'tx_bytes', 0)
        const rxRate = ObjectHelper.getNumber(iface, 'rx_rate', 0)
        const txRate = ObjectHelper.getNumber(iface, 'tx_rate', 0)
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

        const item: ConnectedDevice = {
          mac: mac,
          ip: ip,
          hostname: hostname,
          vendor: FormatUtils.getVendorName(mac),
          interface: interfaceName,
          onlineTime: displayOnlineTime,
          signalStrength: 0,
          rxRate: 0,
          txRate: 0,
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

  private emptySystemInfo(): SystemInfo {
    return {
      hostname: '', model: '', kernel: '', firmwareVersion: '',
      localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
      memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0,
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

  async fetchProcessList(): Promise<ProcessInfo[]> {
    try {
      const processes = await this.client.getProcessList()
      const processList = ObjectHelper.getArray(processes, 'processes')
      const list: ProcessInfo[] = []

      for (let i = 0; i < processList.length; i++) {
        const p = processList[i]
        const item: ProcessInfo = {
          pid: ObjectHelper.getNumber(p, 'pid', 0),
          ppid: ObjectHelper.getNumber(p, 'ppid', 0),
          name: ObjectHelper.getString(p, 'name', ''),
          cpu: ObjectHelper.getNumber(p, 'cpu', 0),
          mem: ObjectHelper.getNumber(p, 'mem_bytes', 0),
          memPercent: ObjectHelper.getNumber(p, 'mem_percent', 0),
          status: ObjectHelper.getString(p, 'status', ''),
          user: ObjectHelper.getString(p, 'user', ''),
          command: ObjectHelper.getString(p, 'command', '')
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
    return []
  }

  async fetchRoutes(): Promise<RouteEntry[]> {
    try {
      const routes = await this.client.getRouteTable()
      const routeList = ObjectHelper.getArray(routes, 'routes')
      const list: RouteEntry[] = []

      for (let i = 0; i < routeList.length; i++) {
        const r = routeList[i]
        const item: RouteEntry = {
          destination: ObjectHelper.getString(r, 'destination', ''),
          gateway: ObjectHelper.getString(r, 'gateway', ''),
          device: ObjectHelper.getString(r, 'device', ''),
          source: ObjectHelper.getString(r, 'source', ''),
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
          up: false,
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

  async fetchOafStatus(): Promise<OafStatus> {
    try {
      // 获取 OAF（应用过滤引擎）各组件版本和运行状态
      const status = await this.client.getOafStatus()
      return {
        pluginVersion: ObjectHelper.getString(status, 'plugin_version', ''),
        engineVersion: ObjectHelper.getString(status, 'engine_version', ''),
        kernelVersion: ObjectHelper.getString(status, 'kernel_version', ''),
        configStatus: ObjectHelper.getString(status, 'config_status', ''),
        filterStatus: ObjectHelper.getString(status, 'filter_status', ''),
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
      // 读取应用过滤总开关配置，API 返回 0/1 数值，需转为布尔值
      const base = await this.client.getAppFilterBase()
      return {
        appFilterEnabled: ObjectHelper.getNumber(base, 'enabled', 0) === 1,
        appLogEnabled: ObjectHelper.getNumber(base, 'log_enabled', 0) === 1,
        workMode: 'gateway'
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterBase err')
    }
    return { appFilterEnabled: false, appLogEnabled: false, workMode: 'gateway' }
  }

  async fetchAppFilterClasses(): Promise<AppClass[]> {
    try {
      // API 返回 [{ classes: [{ id, name, apps: [{ id, name }] }] }] 结构
      const classes = await this.client.getAppFilterClassList()
      // 取第一个元素的 'classes' 数组
      const classList = classes.length > 0 ? ObjectHelper.getArray(classes[0], 'classes') : []
      const list: AppClass[] = []

      // 两层嵌套遍历：分类 → 每个分类下的应用
      for (let i = 0; i < classList.length; i++) {
        const cls = classList[i]
        const apps = ObjectHelper.getArray(cls, 'apps')
        const appList: AppItem[] = []

        for (let j = 0; j < apps.length; j++) {
          const app = apps[j]
          const appItem: AppItem = {
            id: ObjectHelper.getNumber(app, 'id', 0),
            name: ObjectHelper.getString(app, 'name', ''),
            enabled: false
          }
          appList.push(appItem)
        }

        const item: AppClass = {
          id: ObjectHelper.getNumber(cls, 'id', 0),
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
      // 解析时间段配置，包含固定时间段和动态时长两种模式
      const time = await this.client.getAppFilterTime()

      // 1. 解析固定时间段数组（每个包含 startHour/startMin/endHour/endMin）
      const fixedTimes = ObjectHelper.getArray(time, 'fixed_times')
      const fixedList: TimeSlot[] = []

      for (let i = 0; i < fixedTimes.length; i++) {
        const t = fixedTimes[i]
        const slot: TimeSlot = {
          startHour: ObjectHelper.getNumber(t, 'start_hour', 0),
          startMin: ObjectHelper.getNumber(t, 'start_min', 0),
          endHour: ObjectHelper.getNumber(t, 'end_hour', 0),
          endMin: ObjectHelper.getNumber(t, 'end_min', 0)
        }
        fixedList.push(slot)
      }

      // 2. 解析生效的星期列表（0=周日, 1=周一 ... 6=周六）
      const weekdaysArr = ObjectHelper.getArray(time, 'weekdays')
      const weekdays: number[] = []
      for (let i = 0; i < weekdaysArr.length; i++) {
        weekdays.push(Number(weekdaysArr[i]))
      }

      return {
        fixedTimes: fixedList,
        dynamicMinutes: ObjectHelper.getNumber(time, 'dynamic_minutes', 0),
        dynamicStartHour: ObjectHelper.getNumber(time, 'dynamic_start_hour', 0),
        dynamicStartMin: ObjectHelper.getNumber(time, 'dynamic_start_min', 0),
        dynamicEndHour: ObjectHelper.getNumber(time, 'dynamic_end_hour', 0),
        dynamicEndMin: ObjectHelper.getNumber(time, 'dynamic_end_min', 0),
        weekdays: weekdays
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterTime err')
    }
    return { fixedTimes: [], dynamicMinutes: 0, dynamicStartHour: 0, dynamicStartMin: 0, dynamicEndHour: 0, dynamicEndMin: 0, weekdays: [] }
  }

  async fetchAppFilterUser(): Promise<AppFilterUser> {
    try {
      const userConfig = await this.client.getAppFilterUser()
      return { mode: ObjectHelper.getString(userConfig, 'mode', 'auto') as AppFilterMode, users: [] }
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

  async factoryReset(): Promise<string> {
    return ''
  }

  async fetchAllOafUsers(): Promise<Object[]> {
    return []
  }

  async fetchUserList(): Promise<UserListItem[]> {
    return []
  }

  async fetchDeviceVisitTime(_mac: string): Promise<DeviceVisitTime[]> {
    return []
  }

  async fetchDeviceVisitList(_mac: string): Promise<DeviceVisitRecord[]> {
    return []
  }

  async saveAppFilterBase(_base: AppFilterBase): Promise<boolean> {
    // TODO: 暂未实现后端保存 API
    return false
  }

  async saveAppFilter(_classes: AppClass[]): Promise<boolean> {
    // TODO: 暂未实现后端保存 API
    return false
  }

  async saveAppFilterTime(_time: AppFilterTime): Promise<boolean> {
    // TODO: 暂未实现后端保存 API
    return false
  }

  async saveAppFilterUser(_user: AppFilterUser): Promise<boolean> {
    // TODO: 暂未实现后端保存 API
    return false
  }

  async saveAppFilterAdv(_adv: Object): Promise<boolean> {
    // TODO: 暂未实现后端保存 API
    return false
  }

  async rebootDevice(): Promise<boolean> {
    // TODO: 暂未实现后端重启 API
    return false
  }
}
