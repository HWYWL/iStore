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
  TimeSlot,
  AppFilterUser,
  OafUser,
  DeviceVisitTime,
  DeviceVisitRecord,
  UserListItem
} from '../models/Models'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'ApiService'
const DOMAIN = 0x0001

/**
 * API 服务层
 * 
 * 负责封装业务逻辑，将 UBUS 原始响应转换为应用所需的数据模型。
 * 
 * 核心职责：
 *  1. 调用 ApiClient 执行 UBUS 请求
 *  2. 解析原始响应数据
 *  3. 转换为类型化的数据模型
 *  4. 实现多级降级策略（不同固件的兼容性处理）
 *  5. 管理流量历史缓存
 * 
 * 数据流转：
 *  UI → ApiService → ApiClient → UBUS → 路由器
 *                              ↓
 *                    ApiClient 返回原始数据
 *                              ↓
 *                    ApiService 解析并转换
 *                              ↓
 *                    返回类型化数据模型给 UI
 */
export class ApiService {
  private client: ApiClient
  /** 流量历史缓存，保留最近30条记录 */
  private historyBuffer: TrafficHistory[] = []
  /** 缓存上一轮网络设备统计值，用于计算流量速率 [rxBytes, txBytes, timestamp] */
  private statsCache: Map<string, number[]> = new Map()

  /**
   * 构造函数
   * 获取 ApiClient 单例实例
   */
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

  /**
   * 获取系统信息
   * 
   * 数据来源（优先级从高到低）：
   *  1. UBUS system.board - 设备基础信息（主机名、型号、内核版本等）
   *  2. UBUS system.info - 运行状态（运行时间、CPU负载、内存使用等）
   *  3. UBUS luci.getTempInfo / 文件读取 - CPU温度
   * 
   * system.board 返回格式：
   * {
   *   "hostname": "OpenWrt",
   *   "system": "Acer Revo One RL85",
   *   "kernel": "6.1.xx",
   *   "board_name": "acer-revo-one-rl85",
   *   "release": {
   *     "distribution": "iStoreOS",
   *     "version": "24.10.5",
   *     "revision": "2025123110",
   *     "target": "x86/64",
   *     "description": "iStoreOS 24.10.5"
   *   }
   * }
   * 
   * system.info 返回格式：
   * {
   *   "uptime": 3600,        // 运行时间（秒）
   *   "localtime": 1704067200, // 本地时间戳
   *   "load": [32768, 65536, 98304], // CPU负载（65536 = 100%）
   *   "memory": {
   *     "total": 8388608,
   *     "free": 4194304,
   *     "buffered": 524288,
   *     "shared": 1048576,
   *     "available": 4608000
   *   }
   * }
   * 
   * @returns SystemInfo 对象，包含所有系统信息
   */
  async fetchSystemInfo(): Promise<SystemInfo> {
    try {
      // 通过 UBUS system.board 获取设备基础信息
      const board: Record<string, Object> = await this.client.getSystemBoard()
      const hostname: string = this.s(board, 'hostname', 'OpenWrt')
      const systemDesc: string = this.s(board, 'system', '')
      const kernel: string = this.s(board, 'kernel', '')
      const cpuModel: string = this.s(board, 'system', '') || this.s(board, 'model', '')
      const boardName: string = this.s(board, 'board_name', '')

      const release: Record<string, Object> | undefined = board['release'] as Record<string, Object> | undefined
      const distribution: string = release ? this.s(release, 'distribution', '') : ''
      const rversion: string = release ? this.s(release, 'version', '') : ''
      const rrevision: string = release ? this.s(release, 'revision', '') : ''
      const rtarget: string = release ? this.s(release, 'target', '') : ''
      const fw: string = release
        ? (this.s(release, 'description', '') || rversion)
        : ''

      // 通过 UBUS system.info 获取运行状态
      let uptime: number = 0
      let localTime: string = ''
      let cpuUsage: number = 0
      let memTotal: number = 0
      let memFree: number = 0
      let memBuffered: number = 0
      let memShared: number = 0
      let memAvailable: number = 0

      try {
        const info: Record<string, Object> = await this.client.getSystemInfo()
        if (info && typeof info === 'object') {
          uptime = this.n(info, 'uptime', 0)
          const lt: number = this.n(info, 'localtime', 0)
          if (lt > 0) {
            localTime = new Date(lt * 1000).toISOString()
          }

          // 从 load 数组计算 CPU 使用率
          // OpenWrt 的 load 值范围是 0-65536，对应 0%-100%
          const loadRaw: Object | undefined = info['load']
          if (Array.isArray(loadRaw)) {
            const loadArr: Object[] = loadRaw as Object[]
            if (loadArr.length > 0) {
              const firstVal: number = Number(loadArr[0])
              if (!isNaN(firstVal)) {
                cpuUsage = Math.min(100, Math.max(0, (firstVal / 65536) * 100))
              }
            }
          }

          // 内存信息
          const memory: Record<string, Object> | undefined = info['memory'] as Record<string, Object> | undefined
          if (memory) {
            memTotal = this.n(memory, 'total', 0)
            memFree = this.n(memory, 'free', 0)
            memBuffered = this.n(memory, 'buffered', 0)
            memShared = this.n(memory, 'shared', 0)
            memAvailable = this.n(memory, 'available', 0)
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'getSystemInfo failed')
      }

      // CPU 温度（UBUS + 文件读取降级）
      const cpuTemp: number = await this.fetchCPUTemp()

      if (!localTime) {
        localTime = new Date().toISOString()
      }

      // 计算实际使用内存
      // 优先使用 available（更准确），否则用 total - free - buffered - shared*0.5
      const memRealUsed: number = memAvailable > 0
        ? memTotal - memAvailable
        : (memTotal > 0 ? Math.max(0, memTotal - memFree - memBuffered - (memShared > 0 ? memShared * 0.5 : 0)) : 0)

      return {
        hostname: hostname,
        model: systemDesc || 'OpenWrt',
        kernel: kernel,
        firmwareVersion: fw,
        localTime: localTime,
        uptime: uptime,
        cpuUsage: cpuUsage,
        memoryTotal: memTotal,
        memoryUsed: memRealUsed,
        memoryCached: memBuffered + memShared,
        memoryAvailable: memAvailable > 0 ? memAvailable : (memFree + memBuffered),
        storageTotal: 0,
        storageUsed: 0,
        cpuTemp: cpuTemp,
        boardName: boardName,
        cpuModel: cpuModel,
        distribution: distribution,
        releaseVersion: rversion,
        releaseRevision: rrevision,
        releaseTarget: rtarget
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchSystemInfo err`)
    }
    return this.emptySystemInfo()
  }

  async fetchWanStatus(): Promise<WanStatus> {
    try {
      // 通过 network.interface.dump 获取所有接口状态（文档指定接口）
      const ifDump: Record<string, Object> = await this.client.networkInterfaceDump()
      const ifList: Record<string, Object>[] = ifDump['interface'] as Record<string, Object>[] || []

      let wanIf: Record<string, Object> | null = null
      let lanIf: Record<string, Object> | null = null

      // 遍历找到 WAN 和 LAN 接口
      for (let i = 0; i < ifList.length; i++) {
        const iface: Record<string, Object> = ifList[i]
        const ifName: string = this.s(iface, 'interface', '')
        const proto: string = this.s(iface, 'proto', '')
        const device: string = this.s(iface, 'device', '')

        // WAN 判断：接口名为 wan / wan6 / wwan，或协议为 pppoe/dhcp/static（不是 lan）
        if (ifName === 'wan' || ifName === 'wan6' || ifName === 'wwan' ||
            proto === 'pppoe' || (proto === 'dhcp' && ifName !== 'lan') ||
            (proto === 'static' && ifName !== 'lan' && !device.includes('br-lan'))) {
          wanIf = iface
        }

        // LAN 判断
        if (ifName === 'lan' || device === 'br-lan' || (device.includes('br-') && !wanIf)) {
          lanIf = iface
        }
      }

      // WAN 数据解析
      let ipAddress: string = '0.0.0.0'
      let netmask: string = ''
      let gateway: string = ''
      const dnsList: string[] = []
      let proto: string = ''
      let macAddr: string = ''
      let ifUptime: number = 0
      let ifname: string = 'wan'

      if (wanIf) {
        ifname = this.s(wanIf, 'interface', 'wan')
        proto = this.s(wanIf, 'proto', '')

        const ipv4Arr: Object | undefined = wanIf['ipv4-address']
        if (Array.isArray(ipv4Arr)) {
          const arr: Object[] = ipv4Arr as Object[]
          if (arr.length > 0) {
            const addr: Record<string, Object> = arr[0] as Record<string, Object>
            ipAddress = this.s(addr, 'address', '0.0.0.0')
            const mask: number = this.n(addr, 'mask', 24)
            netmask = `${mask}`
          }
        }

        const routeArr: Object | undefined = wanIf['route']
        if (Array.isArray(routeArr)) {
          const arr: Object[] = routeArr as Object[]
          for (let i = 0; i < arr.length; i++) {
            const r: Record<string, Object> = arr[i] as Record<string, Object>
            if (this.s(r, 'target', '') === '0.0.0.0' && this.s(r, 'mask', '') === '0') {
              gateway = this.s(r, 'nexthop', '')
              break
            }
          }
        }

        const dnsRaw: Object | undefined = wanIf['dns-server']
        if (Array.isArray(dnsRaw)) {
          for (const d of dnsRaw as Object[]) {
            dnsList.push(String(d))
          }
        }

        ifUptime = this.n(wanIf, 'uptime', 0)
      }

      // 备选：LAN 作为 fallback（如果没找到 WAN）
      if (!wanIf && lanIf) {
        ifname = this.s(lanIf, 'interface', 'lan')
        proto = this.s(lanIf, 'proto', '')
        const ipv4Arr: Object | undefined = lanIf['ipv4-address']
        if (Array.isArray(ipv4Arr)) {
          const arr: Object[] = ipv4Arr as Object[]
          if (arr.length > 0) {
            const addr: Record<string, Object> = arr[0] as Record<string, Object>
            ipAddress = this.s(addr, 'address', '0.0.0.0')
          }
        }
        ifUptime = this.n(lanIf, 'uptime', 0)
      }

      // 通过 realtime stats 获取流量速率（优先使用 luci.getRealtimeStats）
      let rxRate: number = 0
      let txRate: number = 0
      try {
        const rtStatsParams: Record<string, Object> = {}
        rtStatsParams['mode'] = 'interface'
        rtStatsParams['device'] = 'br-lan'
        const raw: Record<string, Object>[] = await this.client.getRealtimeStats(rtStatsParams)
        const results: Record<string, Object> | null = raw.length > 0 ? raw[0] : null
        const arr: (number[])[] | undefined = results
          ? (results['result'] as (number[])[] | undefined)
          : undefined
        if (arr && Array.isArray(arr) && arr.length >= 2) {
          const last: number[] = arr[arr.length - 1]
          const prev: number[] = arr[arr.length - 2]
          if (last && last.length >= 5 && prev && prev.length >= 5) {
            const dt: number = last[0] - prev[0]
            if (dt > 0) {
              rxRate = Math.max(0, Math.floor((last[1] - prev[1]) / dt))
              txRate = Math.max(0, Math.floor((last[3] - prev[3]) / dt))
            }
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'getRealtimeStats failed for wan status')
      }

      // 降级：如果 luci.getRealtimeStats 不可用，通过 network.device.status 统计计算速率
      if (rxRate === 0 && txRate === 0 && wanIf) {
        try {
          const wanDevice: string = this.s(wanIf, 'device', '')
          if (wanDevice) {
            const devStatus: Record<string, Object> = await this.client.networkDeviceStatus()
            const devData: Record<string, Object> | undefined =
              devStatus[wanDevice] as Record<string, Object> | undefined
            if (devData && typeof devData === 'object') {
              const stats: Record<string, Object> | undefined =
                devData['statistics'] as Record<string, Object> | undefined
              if (stats) {
                const rxBytes: number = Number(stats['rx_bytes']) || 0
                const txBytes: number = Number(stats['tx_bytes']) || 0
                const now: number = Date.now()
                // 使用缓存的上一轮统计值计算速率
                const prevKey: string = `stats_${wanDevice}`
                const prevEntry: number[] | undefined = this.statsCache.get(prevKey)
                if (prevEntry && prevEntry.length === 3) {
                  const prevRx: number = prevEntry[0]
                  const prevTx: number = prevEntry[1]
                  const prevTime: number = prevEntry[2]
                  const dtSec: number = (now - prevTime) / 1000
                  if (dtSec > 0 && rxBytes >= prevRx && txBytes >= prevTx) {
                    rxRate = Math.max(0, Math.floor((rxBytes - prevRx) / dtSec))
                    txRate = Math.max(0, Math.floor((txBytes - prevTx) / dtSec))
                  }
                }
                this.statsCache.set(prevKey, [rxBytes, txBytes, now])
              }
            }
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'fallback traffic calc failed')
        }
      }

      // 通过 network.device.status 获取 MAC 地址
      if (wanIf) {
        const wanDevice: string = this.s(wanIf, 'device', '')
        if (wanDevice) {
          try {
            const devStatus: Record<string, Object> = await this.client.networkDeviceStatus()
            const devData: Record<string, Object> | undefined =
              devStatus[wanDevice] as Record<string, Object> | undefined
            if (devData && typeof devData === 'object') {
              macAddr = this.s(devData, 'macaddr', '')
            }
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'get mac addr failed')
          }
        }
      }

      this.historyBuffer.push({
        timestamp: new Date().toISOString(),
        rx: rxRate,
        tx: txRate
      })
      if (this.historyBuffer.length > 30) {
        this.historyBuffer = this.historyBuffer.slice(-30)
      }

      return {
        interface: ifname,
        uptime: ifUptime,
        ipAddress: ipAddress,
        netmask: netmask,
        gateway: gateway,
        dns: dnsList,
        rxRate: rxRate,
        txRate: txRate,
        onlineTime: '',
        proto: proto,
        macAddr: macAddr
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchWanStatus err: ${String(e)}`)
    }
    return this.emptyWanStatus()
  }

  /**
   * 获取 LAN 网络状态（文档指定接口：network.interface.dump + network.device.status）
   * 遍历接口列表找到 LAN 接口，提取 IP地址、网关、DNS、MAC等字段
   */
  async fetchLanStatus(): Promise<WanStatus> {
    try {
      const dumpResults: [Record<string, Object>, Record<string, Object>] =
        await Promise.all([
          this.client.networkInterfaceDump(),
          this.client.networkDeviceStatus()
        ])
      const ifDump: Record<string, Object> = dumpResults[0]
      const devStatus: Record<string, Object> = dumpResults[1]

      const ifList: Record<string, Object>[] = ifDump['interface'] as Record<string, Object>[] || []

      // 找到 LAN 接口：ifName === 'lan' 或 device 包含 'br-lan' 或类型默认
      let lanIf: Record<string, Object> | null = null
      for (let i = 0; i < ifList.length; i++) {
        const iface: Record<string, Object> = ifList[i]
        const ifName: string = this.s(iface, 'interface', '')
        const device: string = this.s(iface, 'device', '')
        const proto: string = this.s(iface, 'proto', '')
        const iptype: 'wan' | 'lan' | 'wifi' | 'vpn' = this.inferNetType(ifName, proto, device)
        if (iptype === 'lan') {
          lanIf = iface
          break
        }
      }

      if (!lanIf) {
        return this.emptyWanStatus()
      }

      const ifname: string = this.s(lanIf, 'interface', 'lan')
      const proto: string = this.s(lanIf, 'proto', '')
      const up: boolean = this.b(lanIf, 'up', false)
      const uptime: number = this.n(lanIf, 'uptime', 0)

      // 提取 IP 地址
      let ipAddress: string = ''
      let netmask: string = ''
      const ipv4Arr: Object | undefined = lanIf['ipv4-address']
      if (Array.isArray(ipv4Arr) && (ipv4Arr as Object[]).length > 0) {
        const addr: Record<string, Object> = (ipv4Arr as Object[])[0] as Record<string, Object>
        ipAddress = this.s(addr, 'address', '')
        const mask: number = this.n(addr, 'mask', 24)
        netmask = `${mask}`
      }

      // 提取网关
      let gateway: string = ''
      const routeArr: Object | undefined = lanIf['route']
      if (Array.isArray(routeArr)) {
        for (const r of routeArr as Object[]) {
          const route: Record<string, Object> = r as Record<string, Object>
          if (this.s(route, 'target', '') === '0.0.0.0') {
            gateway = this.s(route, 'nexthop', '')
            break
          }
        }
      }

      // 提取 DNS
      const dnsList: string[] = []
      const dnsRaw: Object | undefined = lanIf['dns-server']
      if (Array.isArray(dnsRaw)) {
        for (const d of dnsRaw as Object[]) {
          dnsList.push(String(d))
        }
      }

      // 提取 MAC 地址
      let macAddr: string = ''
      const device: string = this.s(lanIf, 'device', '')
      if (device) {
        const devData: Record<string, Object> | undefined =
          devStatus[device] as Record<string, Object> | undefined
        if (devData && typeof devData === 'object') {
          macAddr = this.s(devData, 'macaddr', '')
        }
      }

      return {
        interface: ifname,
        uptime: uptime,
        ipAddress: ipAddress,
        netmask: netmask,
        gateway: gateway,
        dns: dnsList,
        rxRate: 0,
        txRate: 0,
        onlineTime: '',
        proto: proto,
        macAddr: macAddr
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchLanStatus err: ${String(e)}`)
    }
    return this.emptyWanStatus()
  }

  /**
   * 获取网络接口状态（文档指定接口：network.interface.dump + network.device.status）
   */
  async fetchNetworkInterfaces(): Promise<NetworkInterface[]> {
    try {
      // 并行获取接口信息和设备状态
      const dumpResults: [Record<string, Object>, Record<string, Object>] =
        await Promise.all([
          this.client.networkInterfaceDump(),
          this.client.networkDeviceStatus()
        ])
      const ifDump: Record<string, Object> = dumpResults[0]
      const devStatus: Record<string, Object> = dumpResults[1]

      const ifList: Record<string, Object>[] = ifDump['interface'] as Record<string, Object>[] || []
      const list: NetworkInterface[] = []

      for (let i = 0; i < ifList.length; i++) {
        const iface: Record<string, Object> = ifList[i]
        const ifName: string = this.s(iface, 'interface', '')
        if (!ifName) {
          continue
        }

        const proto: string = this.s(iface, 'proto', '')
        const device: string = this.s(iface, 'device', '')
        const up: boolean = this.b(iface, 'up', false)

        // 从 ipv4-address 提取 IP
        const ipv4Arr: Object | undefined = iface['ipv4-address']
        let ip: string = ''
        let netmask: string = ''
        if (Array.isArray(ipv4Arr) && (ipv4Arr as Object[]).length > 0) {
          const addr: Record<string, Object> = (ipv4Arr as Object[])[0] as Record<string, Object>
          ip = this.s(addr, 'address', '')
          const mask: number = this.n(addr, 'mask', 0)
          netmask = mask > 0 ? `${mask}` : ''
        }

        // 从 route 提取网关
        let gateway: string = ''
        const routeArr: Object | undefined = iface['route']
        if (Array.isArray(routeArr)) {
          for (const r of routeArr as Object[]) {
            const route: Record<string, Object> = r as Record<string, Object>
            if (this.s(route, 'target', '') === '0.0.0.0') {
              gateway = this.s(route, 'nexthop', '')
              break
            }
          }
        }

        // 从 network.device.status 获取设备级别信息
        const devData: Record<string, Object> | undefined =
          devStatus[device] as Record<string, Object> | undefined
        let mac: string = ''
        let mtu: number = 1500
        let rxBytes: number = 0
        let txBytes: number = 0
        if (devData && typeof devData === 'object') {
          mac = this.s(devData, 'macaddr', '')
          mtu = this.n(devData, 'mtu', 1500)
          const stats: Record<string, Object> | undefined =
            devData['statistics'] as Record<string, Object> | undefined
          if (stats) {
            rxBytes = this.n(stats, 'rx_bytes', 0)
            txBytes = this.n(stats, 'tx_bytes', 0)
          }
        }

        // 接口类型推断
        const type: 'wan' | 'lan' | 'wifi' | 'vpn' = this.inferNetType(ifName, proto, device)

        list.push({
          name: ifName,
          type: type,
          ipAddress: ip,
          netmask: netmask,
          gateway: gateway,
          macAddress: mac,
          mtu: mtu,
          status: up ? 'up' : 'down',
          rxBytes: rxBytes,
          txBytes: txBytes,
          rxRate: 0,
          txRate: 0
        })
      }

      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchNetworkInterfaces err: ${String(e)}`)
    }
    return []
  }

  /**
   * 获取已连接设备列表（DHCP 租约）
   * 
   * 降级策略（按优先级）：
   * 
   * ┌─────────────────────────────────────────────────────────────┐
   * │  优先级 1: luci-rpc.getDHCPLeases                          │
   * │  └─ 适用：iStoreOS、安装了 luci-rpc 包的设备                 │
   * ├─────────────────────────────────────────────────────────────┤
   * │  优先级 2: file.read /tmp/dhcp.leases                       │
   * │  └─ 适用：标准 OpenWrt，file 命名空间可用                     │
   * ├─────────────────────────────────────────────────────────────┤
   * │  优先级 3: file.exec cat /tmp/dhcp.leases                   │
   * │  └─ 适用：标准 OpenWrt，file.exec 可用但 file.read 不可用      │
   * ├─────────────────────────────────────────────────────────────┤
   * │  最终降级: 返回空数组                                       │
   * │  └─ 适用：以上都不可用的设备                                  │
   * └─────────────────────────────────────────────────────────────┘
   * 
   * luci-rpc.getDHCPLeases 返回格式：
   * {
   *   "dhcp_leases": [
   *     { "macaddr": "00:11:22:33:44:55", "ipaddr": "192.168.1.100", "hostname": "myphone" },
   *     ...
   *   ]
   * }
   * 
   * /tmp/dhcp.leases 文件格式：
   * timestamp mac ip hostname clientid
   * 示例：1680000000 00:11:22:33:44:55 192.168.1.100 myphone *
   * 
   * @returns ConnectedDevice[] 已连接设备列表
   */
  async fetchConnectedDevices(): Promise<ConnectedDevice[]> {
    try {
      const client: ApiClient = ApiClient.getInstance()

      // 优先使用 luci-rpc.getDHCPLeases（iStoreOS / 安装了 luci-rpc 的设备）
      if (client.hasCapability('luci-rpc')) {
        const dhcpResult: Record<string, Object> = await client.getLuciDHCPLeases()
        if (dhcpResult && typeof dhcpResult === 'object') {
          const leases: Record<string, Object>[] | undefined =
            dhcpResult['dhcp_leases'] as Record<string, Object>[] | undefined
          if (leases && Array.isArray(leases) && leases.length > 0) {
            return this.parseDhcpLeases(leases)
          }
        }
      }

      // 降级：尝试通过 file.read 读取 /tmp/dhcp.leases（标准 OpenWrt）
      if (client.hasCapability('file')) {
        const leaseRaw: string = await client.readFile('/tmp/dhcp.leases')
        if (leaseRaw && leaseRaw.trim().length > 0) {
          return this.parseDhcpLeasesFile(leaseRaw)
        }
      }

      // 进一步降级：尝试通过 file.exec 调用 cat
      if (client.hasCapability('file')) {
        const leaseRaw: string = await client.execCommand('cat', ['/tmp/dhcp.leases'])
        if (leaseRaw && leaseRaw.trim().length > 0) {
          return this.parseDhcpLeasesFile(leaseRaw)
        }
      }

      // 最终降级：无可用数据源，返回空
      hilog.info(DOMAIN, TAG, 'fetchConnectedDevices: no available data source')
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchConnectedDevices err`)
    }
    return []
  }

  /**
   * 解析 luci-rpc 返回的 DHCP 租约数据
   */
  private parseDhcpLeases(leases: Record<string, Object>[]): ConnectedDevice[] {
    const devs: ConnectedDevice[] = []
    for (let i = 0; i < leases.length; i++) {
      const l: Record<string, Object> = leases[i]
      devs.push({
        mac: this.s(l, 'macaddr', ''),
        ip: this.s(l, 'ipaddr', ''),
        hostname: this.s(l, 'hostname', 'Unknown'),
        vendor: '',
        interface: 'lan',
        onlineTime: '',
        signalStrength: -1,
        rxRate: 0,
        txRate: 0,
        isOnline: true
      })
    }
    return devs
  }

  /**
   * 解析 /tmp/dhcp.leases 文件内容
   * 格式：timestamp mac ip hostname clientid
   * 示例：1680000000 00:11:22:33:44:55 192.168.1.100 myphone *
   */
  private parseDhcpLeasesFile(raw: string): ConnectedDevice[] {
    const devs: ConnectedDevice[] = []
    const lines: string[] = raw.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim()
      if (!line || line.startsWith('#')) {
        continue
      }
      const parts: string[] = line.split(/\s+/)
      if (parts.length >= 4) {
        // parts[0]=timestamp, parts[1]=mac, parts[2]=ip, parts[3]=hostname
        devs.push({
          mac: parts[1] || '',
          ip: parts[2] || '',
          hostname: parts[3] !== '*' ? parts[3] : 'Unknown',
          vendor: '',
          interface: 'lan',
          onlineTime: '',
          signalStrength: -1,
          rxRate: 0,
          txRate: 0,
          isOnline: true
        })
      }
    }
    return devs
  }

  async fetchTrafficHistory(): Promise<TrafficHistory[]> {
    if (this.historyBuffer.length > 0) {
      return this.historyBuffer.slice(-20)
    }
    return []
  }

  /** 获取 CPU 温度：UBUS luci.getTempInfo → 文件读取降级 */
  private async fetchCPUTemp(): Promise<number> {
    return await this.client.getCPUTemp()
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

  /**
   * 根据接口名称、协议和设备名推断网络接口类型
   * 
   * 判断优先级：
   *  1. WAN 接口 → 2. WiFi 接口 → 3. VPN/隧道 → 4. 默认 LAN
   * 
   * WAN 接口判断条件：
   * - 接口名以 'wan' 或 'wwan' 开头
   * - 协议为 'pppoe'
   * - 接口名以 'eth' 开头且设备名不包含 'br-'（通常表示物理端口）
   * 
   * WiFi 接口判断条件：
   * - 接口名包含 'wlan', 'ra', 'radio'
   * - 设备名包含 'wlan', 'ra'
   * 
   * VPN/隧道判断条件：
   * - 接口名包含 'tun', 'wg' (WireGuard), 'pptp', 'vpn', 'ipsec', 'tailscale'
   * 
   * 默认返回 LAN（局域网接口）
   * 
   * @param ifName 接口名称（如 eth0, br-lan, wlan0）
   * @param proto 协议类型（如 dhcp, static, pppoe）
   * @param device 设备名称（如 br-lan, eth0）
   * @returns 接口类型：'wan' | 'lan' | 'wifi' | 'vpn'
   */
  private inferNetType(ifName: string, proto: string, device: string): 'wan' | 'lan' | 'wifi' | 'vpn' {
    const n: string = ifName.toLowerCase()
    // WAN 接口
    if (n.startsWith('wan') || n.startsWith('wwan') || proto === 'pppoe' ||
        (n.startsWith('eth') && !device.includes('br-'))) {
      return 'wan'
    }
    // WiFi 接口
    if (n.includes('wlan') || n.includes('ra') || n.includes('radio') ||
        device.includes('wlan') || device.includes('ra')) {
      return 'wifi'
    }
    // VPN/隧道
    if (n.includes('tun') || n.includes('wg') || n.includes('pptp') ||
        n.includes('vpn') || n.includes('ipsec') || n.includes('tailscale')) {
      return 'vpn'
    }
    return 'lan'
  }

  private s(obj: Record<string, Object>, key: string, def: string): string {
    if (!obj || typeof obj !== 'object') {
      return def
    }
    const v: Object = obj[key]
    if (v === undefined || v === null) {
      return def
    }
    return String(v)
  }

  private n(obj: Record<string, Object>, key: string, def: number): number {
    if (!obj || typeof obj !== 'object') {
      return def
    }
    const v: Object = obj[key]
    if (v === undefined || v === null) {
      return def
    }
    const num: number = Number(v)
    return isNaN(num) ? def : num
  }

  private b(obj: Record<string, Object>, key: string, def: boolean): boolean {
    if (!obj || typeof obj !== 'object') {
      return def
    }
    const v: Object = obj[key]
    if (v === undefined || v === null) {
      return def
    }
    return Boolean(v)
  }

  async fetchMountPoints(): Promise<MountPoint[]> {
    try {
      const results: Record<string, Object>[] = await this.client.getMountPoints()
      if (!results || !Array.isArray(results) || results.length === 0) {
        return []
      }
      const container = results.length > 0 ? results[0] : null
      const innerResult = container ? (container['result'] as Record<string, Object>[] | undefined) : undefined
      const items = innerResult || results
      const mounts: MountPoint[] = []
      for (let i = 0; i < items.length; i++) {
        const mp: Record<string, Object> = items[i]
        if (!mp || typeof mp !== 'object') {
          continue
        }
        const mountPoint: string = this.s(mp, 'mount', '')
        if (mountPoint === '/' || mountPoint.startsWith('/dev')) {
          continue
        }
        const size: number = this.n(mp, 'size', 0)
        const usedVal: number = this.n(mp, 'used', 0)
        const usedPct: number = size > 0 ? (usedVal / size) * 100 : 0
        mounts.push({
          device: this.s(mp, 'device', ''),
          mountPoint: mountPoint,
          filesystem: this.s(mp, 'fs', ''),
          size: size,
          used: usedVal,
          available: this.n(mp, 'free', 0),
          usedPercent: usedPct
        })
      }
      return mounts
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchMountPoints err')
    }
    return []
  }

  async fetchConntrack(): Promise<ConntrackInfo> {
    try {
      const client: ApiClient = ApiClient.getInstance()
      // 只有 file 命名空间可用时才读取 conntrack 信息
      if (!client.hasCapability('file')) {
        return { current: 0, max: 0, percent: 0 }
      }
      const currentStr: string = await client.readFile('/proc/sys/net/netfilter/nf_conntrack_count')
      const maxStr: string = await client.readFile('/proc/sys/net/netfilter/nf_conntrack_max')
      const current: number = parseInt(currentStr.trim(), 10)
      const max: number = parseInt(maxStr.trim(), 10)
      if (!isNaN(current) && !isNaN(max) && max > 0) {
        return {
          current: current,
          max: max,
          percent: Math.min(100, (current / max) * 100)
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchConntrack err')
    }
    return { current: 0, max: 0, percent: 0 }
  }

  async fetchProcessList(): Promise<ProcessInfo[]> {
    try {
      const raw: Record<string, Object> = await this.client.getProcessList()
      if (!raw || typeof raw !== 'object') {
        return []
      }
      const resultArr = raw['result'] as Record<string, Object>[] | undefined
      if (!resultArr || !Array.isArray(resultArr)) {
        return []
      }
      const list: ProcessInfo[] = []
      for (let i = 0; i < resultArr.length; i++) {
        const p = resultArr[i]
        if (!p) {
          continue
        }
        const pidVal = p['PID']; const pid: number = pidVal !== undefined ? parseInt(String(pidVal), 10) : 0
        const ppidVal = p['PPID']; const ppid: number = ppidVal !== undefined ? parseInt(String(ppidVal), 10) : 0
        const cpuVal = p['%CPU']; const cpu: number = cpuVal !== undefined ? parseFloat(String(cpuVal)) : 0
        const memVal = p['%MEM']; const mem: number = memVal !== undefined ? parseFloat(String(memVal)) : 0
        const vszStr = p['VSZ'] as string | undefined
        let memBytes = 0
        if (vszStr) {
          const vsz = parseFloat(vszStr)
          if (vszStr.endsWith('m')) {
            memBytes = vsz * 1024
          } else {
            memBytes = vsz
          }
        }
        list.push({
          pid: pid,
          ppid: ppid,
          name: (p['COMMAND'] as string) || '',
          cpu: cpu,
          mem: memBytes,
          memPercent: mem,
          status: (p['STAT'] as string) || '',
          user: '',
          command: (p['COMMAND'] as string) || ''
        })
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
      const output: string = await this.client.execCommand('/sbin/ip', ['-4', 'route', 'show', 'table', 'all'])
      const lines: string[] = output.split('\n')
      const routes: RouteEntry[] = []

      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim()
        if (!line) {
          continue
        }

        const parts: string[] = line.split(/\s+/)
        if (parts.length === 0) {
          continue
        }

        const entry: RouteEntry = {
          destination: (parts[0] === 'default') ? 'default' : parts[0],
          gateway: '', device: '', source: '', scope: '', table: '', flags: ''
        }

        const flagParts: string[] = []
        for (let j = 0; j < parts.length; j++) {
          if (parts[j] === 'via' && j + 1 < parts.length) {
            entry.gateway = parts[j + 1]
            j++
          } else if (parts[j] === 'dev' && j + 1 < parts.length) {
            entry.device = parts[j + 1]
            j++
          } else if (parts[j] === 'src' && j + 1 < parts.length) {
            entry.source = parts[j + 1]
            j++
          } else if (parts[j] === 'scope' && j + 1 < parts.length) {
            entry.scope = parts[j + 1]
            j++
          } else if (parts[j] === 'table' && j + 1 < parts.length) {
            entry.table = parts[j + 1]
            j++
          } else if (j > 0) {
            if (parts[j] === 'proto' && j + 1 < parts.length) {
              flagParts.push(`proto:${parts[j + 1]}`)
              j++
            } else if (parts[j] !== 'default') {
              flagParts.push(parts[j])
            }
          }
        }
        entry.flags = flagParts.join(' ')

        routes.push(entry)
      }

      return routes
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchRoutes err')
    }
    return []
  }

  async fetchWirelessClients(ifname: string): Promise<WirelessClient[]> {
    return []
  }

  async fetchWirelessDevices(): Promise<WirelessDevice[]> {
    try {
      const raw: Record<string, Object> = await this.client.getWirelessDevices()
      if (!raw || typeof raw !== 'object') {
        return []
      }
      const devices = raw['result'] as Record<string, Object>[] | undefined
      if (!devices || !Array.isArray(devices)) {
        return []
      }
      const list: WirelessDevice[] = []
      for (let i = 0; i < devices.length; i++) {
        const d: Record<string, Object> = devices[i]
        list.push({
          name: this.s(d, 'name', ''),
          bssid: this.s(d, 'bssid', ''),
          ssid: this.s(d, 'ssid', ''),
          channel: this.n(d, 'channel', 0),
          frequency: this.n(d, 'frequency', 0),
          bandwidth: this.s(d, 'bandwidth', ''),
          encryption: this.s(d, 'encryption', ''),
          signal: this.n(d, 'signal', 0),
          quality: this.n(d, 'quality', 0),
          mode: this.s(d, 'mode', ''),
          up: this.b(d, 'up', false),
          hwmode: this.s(d, 'hwmode', ''),
          protocol: this.s(d, 'protocol', '')
        })
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessDevices err')
    }
    return []
  }

  async fetchOafStatus(): Promise<OafStatus> {
    try {
      const raw: Record<string, Object> = await this.client.getOafStatus()
      if (!raw || typeof raw !== 'object') {
        return this.emptyOaf()
      }
      const pluginVer: string = this.s(raw, 'version', '')
      const engineVer: string = this.s(raw, 'engine_version', '')
      const kernelVer: string = this.s(raw, 'kernel_version', '')
      const nums: number[] = pluginVer.split('.').map(Number)
      let verTooHigh = false
      if (nums.length >= 2 && (nums[0] > 3 || (nums[0] === 3 && nums[1] > 2))) {
        verTooHigh = true
      }
      return {
        pluginVersion: pluginVer,
        engineVersion: engineVer,
        kernelVersion: kernelVer,
        configStatus: this.s(raw, 'config_status', ''),
        filterStatus: this.s(raw, 'filter_status', ''),
        engineStatus: this.s(raw, 'engine_status', ''),
        versionTooHigh: verTooHigh
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchOafStatus err')
    }
    return this.emptyOaf()
  }

  private emptyOaf(): OafStatus {
    return {
      pluginVersion: '', engineVersion: '', kernelVersion: '',
      configStatus: '', filterStatus: '', engineStatus: '', versionTooHigh: false
    }
  }

  async fetchAppFilterBase(): Promise<AppFilterBase> {
    try {
      const raw: Record<string, Object> = await this.client.getAppFilterBase()
      return {
        appFilterEnabled: this.b(raw, 'app_filter_enabled', false),
        appLogEnabled: this.b(raw, 'app_log_enabled', false),
        workMode: (this.s(raw, 'work_mode', 'gateway') as 'gateway' | 'bypass')
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterBase err')
    }
    return { appFilterEnabled: false, appLogEnabled: false, workMode: 'gateway' }
  }

  async fetchAppClasses(): Promise<AppClass[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.getAppFilterClassList()
      if (!raw || !Array.isArray(raw) || raw.length === 0) {
        return []
      }
      const container = raw[0] as Record<string, Object>
      const clist = container['result'] as Record<string, Object>[] | undefined
      if (!clist || !Array.isArray(clist)) {
        return []
      }
      const classes: AppClass[] = []
      for (let i = 0; i < clist.length; i++) {
        const c: Record<string, Object> = clist[i]
        const appListStr: string = this.s(c, 'appids', '')
        const rawList = appListStr ? appListStr.split(',') : []
        const apps: AppItem[] = []
        for (let j = 0; j < rawList.length; j++) {
          const parts = rawList[j].split(',')
          if (parts.length > 0) {
            apps.push({
              id: parseInt(parts[0], 10) || 0,
              name: parts.length > 1 ? parts[1] : '',
              enabled: true
            })
          }
        }
        classes.push({
          id: this.n(c, 'id', 0),
          name: this.s(c, 'name', ''),
          apps: apps
        })
      }
      return classes
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppClasses err')
    }
    return []
  }

  async fetchAppFilter(): Promise<AppClass[]> {
    try {
      return this.fetchAppClasses()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilter err')
    }
    return []
  }

  async fetchAppFilterTime(): Promise<AppFilterTime> {
    try {
      const raw: Record<string, Object> = await this.client.getAppFilterTime()
      return {
        fixedTimes: [],
        dynamicMinutes: 0,
        dynamicStartHour: 0,
        dynamicStartMin: 0,
        dynamicEndHour: 0,
        dynamicEndMin: 0,
        weekdays: []
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterTime err')
    }
    return { fixedTimes: [], dynamicMinutes: 0, dynamicStartHour: 0, dynamicStartMin: 0, dynamicEndHour: 0, dynamicEndMin: 0, weekdays: [] }
  }

  async fetchAppFilterUser(): Promise<AppFilterUser> {
    try {
      const raw: Record<string, Object> = await this.client.getAppFilterUser()
      return { mode: 'auto', users: [] }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterUser err')
    }
    return { mode: 'auto', users: [] }
  }

  async fetchAppFilterAdv(): Promise<Record<string, Object>> {
    try {
      const raw: Record<string, Object> = await this.client.getAppFilterAdv()
      return raw
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterAdv err')
    }
    return {}
  }

  async factoryReset(): Promise<string> {
    return this.client.execCommand('/sbin/firstboot', ['-r', '-y'])
  }

  async fetchAllOafUsers(): Promise<Record<string, Object>[]> {
    return []
  }

  async fetchUserList(): Promise<UserListItem[]> {
    return []
  }

  async fetchDeviceVisitTime(mac: string): Promise<DeviceVisitTime[]> {
    return []
  }

  async fetchDeviceVisitList(mac: string): Promise<DeviceVisitRecord[]> {
    return []
  }

  async saveAppFilterBase(base: AppFilterBase): Promise<boolean> {
    return false
  }

  async saveAppFilter(classes: AppClass[]): Promise<boolean> {
    return false
  }

  async saveAppFilterTime(config: AppFilterTime): Promise<boolean> {
    return false
  }

  async saveAppFilterUser(config: AppFilterUser): Promise<boolean> {
    return false
  }

  async saveAppFilterAdv(params: Record<string, Object>): Promise<boolean> {
    return false
  }

  async rebootDevice(): Promise<string> {
    return 'ok'
  }
}
