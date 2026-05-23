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

export class ApiService {
  private client: ApiClient
  private historyBuffer: TrafficHistory[] = []

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

      // 通过 realtime stats 获取流量速率
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

  async fetchConnectedDevices(): Promise<ConnectedDevice[]> {
    try {
      const dhcpResult: Record<string, Object> = await this.client.getLuciDHCPLeases()
      if (!dhcpResult || typeof dhcpResult !== 'object') {
        return []
      }

      const leases: Record<string, Object>[] | undefined = dhcpResult['dhcp_leases'] as Record<string, Object>[] | undefined
      if (!leases || !Array.isArray(leases) || leases.length === 0) {
        return []
      }

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
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchConnectedDevices err`)
    }
    return []
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
      const currentStr: string = await this.client.readFile('/proc/sys/net/netfilter/nf_conntrack_count')
      const maxStr: string = await this.client.readFile('/proc/sys/net/netfilter/nf_conntrack_max')
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
          user: (p['USER'] as string) || '',
          command: (p['COMMAND'] as string) || ''
        })
      }
      list.sort((a, b) => b.cpu - a.cpu)
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchProcessList err')
    }
    return []
  }

  async fetchStartupItems(): Promise<StartupItem[]> {
    try {
      const result: Record<string, Object> = await this.client.rcList()
      if (!result || typeof result !== 'object') {
        return []
      }
      const keys: string[] = Object.keys(result)
      const items: StartupItem[] = []
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i]
        const v: Record<string, Object> = result[k] as Record<string, Object>
        if (v && typeof v === 'object') {
          items.push({
            name: k,
            priority: this.n(v, 'start', 50),
            enabled: this.b(v, 'enabled', false),
            running: this.b(v, 'running', false)
          })
        }
      }
      items.sort((a, b) => a.priority - b.priority)
      return items
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchStartupItems err')
    }
    return []
  }

  async fetchRoutes(): Promise<RouteEntry[]> {
    try {
      const output: string = await this.client.execCommand('/sbin/ip', ['-4', 'route', 'show', 'table', 'all'])
      if (!output) {
        return []
      }
      const lines: string[] = output.split('\n')
      const routes: RouteEntry[] = []
      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim()
        if (!line) {
          continue
        }
        const entry: RouteEntry = {
          destination: '', gateway: '', device: '', source: '', scope: '', table: '', flags: ''
        }
        const parts: string[] = line.split(/\s+/)
        if (parts.length > 0 && parts[0] !== 'default') {
          entry.destination = parts[0]
        } else if (parts.length > 0 && parts[0] === 'default') {
          entry.destination = 'default'
        }
        for (let j = 0; j < parts.length; j++) {
          if (parts[j] === 'via' && j + 1 < parts.length) {
            entry.gateway = parts[j + 1]
          }
          if (parts[j] === 'dev' && j + 1 < parts.length) {
            entry.device = parts[j + 1]
          }
          if (parts[j] === 'src' && j + 1 < parts.length) {
            entry.source = parts[j + 1]
          }
          if (parts[j] === 'scope' && j + 1 < parts.length) {
            entry.scope = parts[j + 1]
          }
          if (parts[j] === 'table' && j + 1 < parts.length) {
            entry.table = parts[j + 1]
          }
        }
        routes.push(entry)
      }
      return routes
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchRoutes err')
    }
    return []
  }

  async fetchWirelessClients(ifname: string): Promise<WirelessClient[]> {
    try {
      const result: Record<string, Object> = await this.client.iwinfoAssoclist(ifname)
      if (!result || typeof result !== 'object') {
        return []
      }
      const results: Record<string, Object>[] | undefined = result['results'] as Record<string, Object>[] | undefined
      if (!results || !Array.isArray(results)) {
        return []
      }
      const clients: WirelessClient[] = []
      for (let i = 0; i < results.length; i++) {
        const r: Record<string, Object> = results[i]
        clients.push({
          mac: this.s(r, 'mac', ''),
          hostname: this.s(r, 'hostname', ''),
          interface: ifname,
          signal: this.n(r, 'signal', 0),
          signalNoise: this.n(r, 'signal_noise', 0),
          rxRate: this.n(r, 'rx_rate', 0),
          txRate: this.n(r, 'tx_rate', 0),
          connectedTime: this.n(r, 'connected_time', 0),
          inactiveTime: this.n(r, 'inactive', 0),
          isMesh: this.b(r, 'is_mesh', false)
        })
      }
      return clients
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessClients err')
    }
    return []
  }

  async fetchWirelessDevices(): Promise<WirelessDevice[]> {
    try {
      const result: Record<string, Object> = await this.client.getWirelessDevices()
      if (!result || typeof result !== 'object') {
        return []
      }
      const keys: string[] = Object.keys(result)
      const devices: WirelessDevice[] = []
      for (let i = 0; i < keys.length; i++) {
        const d: Record<string, Object> = result[keys[i]] as Record<string, Object>
        if (!d || typeof d !== 'object') {
          continue
        }
        devices.push({
          name: keys[i],
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
      return devices
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessDevices err')
    }
    return []
  }

  async fetchOafStatus(): Promise<OafStatus> {
    try {
      const result: Record<string, Object> = await this.client.getOafStatus()
      const data = result['data'] as Record<string, Object> | undefined
      const raw = data || result
      const pluginVer: string = this.s(raw, 'version', '')
      const engineVer: string = this.s(raw, 'engine_version', '')
      const kernelVer: string = this.s(raw, 'kernel_version', '')
      let versionTooHigh: boolean = false
      if (pluginVer) {
        const nums: number[] = pluginVer.split('.').map(Number)
        if (nums.length >= 2 && (nums[0] > 3 || (nums[0] === 3 && nums[1] > 2))) {
          versionTooHigh = true
        }
      }
      return {
        pluginVersion: pluginVer,
        engineVersion: engineVer,
        kernelVersion: kernelVer,
        configStatus: this.s(raw, 'config_status', ''),
        filterStatus: this.s(raw, 'filter_status', ''),
        engineStatus: this.s(raw, 'engine_status', ''),
        versionTooHigh: versionTooHigh
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchOafStatus err')
    }
    return {
      pluginVersion: '', engineVersion: '', kernelVersion: '',
      configStatus: '', filterStatus: '', engineStatus: '', versionTooHigh: false
    }
  }

  async fetchAppFilterBase(): Promise<AppFilterBase> {
    try {
      const result: Record<string, Object> = await this.client.getAppFilterBase()
      const data = result['data'] as Record<string, Object> | undefined
      const raw = data || result
      return {
        appFilterEnabled: this.n(raw, 'enable', 0) === 1,
        appLogEnabled: this.n(raw, 'record_enable', 0) === 1,
        workMode: this.n(raw, 'work_mode', 0) === 0 ? 'gateway' : 'bypass'
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterBase err')
    }
    return { appFilterEnabled: false, appLogEnabled: false, workMode: 'gateway' }
  }

  async saveAppFilterBase(base: AppFilterBase): Promise<boolean> {
    const paramsObj: Record<string, Object> = {}
    paramsObj['enable'] = base.appFilterEnabled ? 1 : 0
    paramsObj['record_enable'] = base.appLogEnabled ? 1 : 0
    paramsObj['work_mode'] = base.workMode === 'gateway' ? 0 : 1
    const params: Record<string, Object> = paramsObj
    return this.client.setAppFilterBase(params as never)
  }

  async fetchAppClasses(): Promise<AppClass[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.getAppFilterClassList()
      const results = raw.length > 0 ? raw[0] : null
      if (!results) {
        return []
      }
      const clist = results['class_list'] as Record<string, Object>[] | undefined
      if (!clist || !Array.isArray(clist)) {
        return []
      }
      const classes: AppClass[] = []
      for (let i = 0; i < clist.length; i++) {
        const c = clist[i]
        const appListStr = c['app_list'] as string[] | undefined
        const apps: AppItem[] = []
        if (appListStr && Array.isArray(appListStr)) {
          for (let j = 0; j < appListStr.length; j++) {
            const parts = appListStr[j].split(',')
            apps.push({
              id: parseInt(parts[0], 10) || 0,
              name: parts[1] || '',
              enabled: false
            })
          }
        }
        classes.push({
          id: i + 1,
          name: (c['name'] as string) || '',
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
      const result: Record<string, Object> = await this.client.getAppFilter()
      const appList = result['app_list'] as number[] | undefined
      const classes = await this.fetchAppClasses()
      if (appList && Array.isArray(appList)) {
        for (let ci = 0; ci < classes.length; ci++) {
          for (let ai = 0; ai < classes[ci].apps.length; ai++) {
            classes[ci].apps[ai].enabled = appList.indexOf(classes[ci].apps[ai].id) >= 0
          }
        }
      }
      return classes
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilter err')
    }
    return []
  }

  async saveAppFilter(classes: AppClass[]): Promise<boolean> {
    const rules: Record<string, Object>[] = []
    for (let i = 0; i < classes.length; i++) {
      const c: AppClass = classes[i]
      const apps: Record<string, Object>[] = []
      for (let j = 0; j < c.apps.length; j++) {
        const a: AppItem = c.apps[j]
        const appObj: Record<string, Object> = {}
        appObj['id'] = a.id
        appObj['name'] = a.name
        appObj['enabled'] = a.enabled
        apps.push(appObj)
      }
      const ruleObj: Record<string, Object> = {}
      ruleObj['id'] = c.id
      ruleObj['name'] = c.name
      ruleObj['apps'] = apps
      rules.push(ruleObj)
    }
    const setAppFilterParams: Record<string, Object> = {}
    setAppFilterParams['rules'] = rules
    return this.client.setAppFilter(setAppFilterParams)
  }

  async fetchAppFilterTime(): Promise<AppFilterTime> {
    try {
      const result: Record<string, Object> = await this.client.getAppFilterTime()
      const data = result['data'] as Record<string, Object> | undefined
      const raw = data || result
      const timeList = raw['time_list'] as Record<string, Object>[] | undefined
      const fixedTimes: TimeSlot[] = []
      if (timeList && Array.isArray(timeList)) {
        for (let i = 0; i < timeList.length; i++) {
          const t = timeList[i]
          const startStr = (t['start'] as string) || '00:00'
          const endStr = (t['end'] as string) || '00:00'
          const startParts = startStr.split(':')
          const endParts = endStr.split(':')
          fixedTimes.push({
            startHour: parseInt(startParts[0], 10) || 0,
            startMin: parseInt(startParts[1], 10) || 0,
            endHour: parseInt(endParts[0], 10) || 0,
            endMin: parseInt(endParts[1], 10) || 0
          })
        }
      }
      const weekdayList = raw['weekday_list'] as number[] | undefined
      const weekdays: number[] = weekdayList && Array.isArray(weekdayList) ? [...weekdayList] : []
      return {
        fixedTimes: fixedTimes,
        dynamicMinutes: this.n(raw, 'allow_time', 0),
        dynamicStartHour: 0,
        dynamicStartMin: 0,
        dynamicEndHour: 0,
        dynamicEndMin: 0,
        weekdays: weekdays
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterTime err')
    }
    return { fixedTimes: [], dynamicMinutes: 0, dynamicStartHour: 0, dynamicStartMin: 0, dynamicEndHour: 0, dynamicEndMin: 0, weekdays: [] }
  }

  async saveAppFilterTime(time: AppFilterTime): Promise<boolean> {
    const paramsObj: Record<string, Object> = {}
    const fixedArr: Record<string, Object>[] = []
    for (let fi = 0; fi < time.fixedTimes.length; fi++) {
      const t = time.fixedTimes[fi]
      const slotObj: Record<string, Object> = {}
      slotObj['start_hour'] = t.startHour
      slotObj['start_min'] = t.startMin
      slotObj['end_hour'] = t.endHour
      slotObj['end_min'] = t.endMin
      fixedArr.push(slotObj)
    }
    paramsObj['fixed_time'] = fixedArr
    paramsObj['dynamic_minutes'] = time.dynamicMinutes
    paramsObj['dynamic_start_hour'] = time.dynamicStartHour
    paramsObj['dynamic_start_min'] = time.dynamicStartMin
    paramsObj['dynamic_end_hour'] = time.dynamicEndHour
    paramsObj['dynamic_end_min'] = time.dynamicEndMin
    paramsObj['weekdays'] = time.weekdays
    const params = paramsObj
    return this.client.setAppFilterTime(params)
  }

  async fetchAppFilterUser(): Promise<AppFilterUser> {
    try {
      const result: Record<string, Object> = await this.client.getAppFilterUser()
      const data = result['data'] as Record<string, Object> | undefined
      const raw = data || result
      const mode = this.n(raw, 'mode', 0)
      const userList = raw['list'] as Record<string, Object>[] | undefined
      const users: OafUser[] = []
      if (userList && Array.isArray(userList)) {
        for (let i = 0; i < userList.length; i++) {
          const u = userList[i]
          users.push({
            id: (u['mac'] as string) || '',
            name: (u['nickname'] as string) || (u['hostname'] as string) || '',
            mac: (u['mac'] as string) || '',
            ip: '',
            selected: false
          })
        }
      }
      return {
        mode: mode === 1 ? 'manual' : 'auto',
        users: users
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterUser err')
    }
    return { mode: 'auto', users: [] }
  }

  async saveAppFilterUser(userConfig: AppFilterUser): Promise<boolean> {
    const paramsObj2: Record<string, Object> = {}
    paramsObj2['mode'] = userConfig.mode
    const userArr: Record<string, Object>[] = []
    for (let ui = 0; ui < userConfig.users.length; ui++) {
      const u = userConfig.users[ui]
      const userObj: Record<string, Object> = {}
      userObj['id'] = u.id
      userObj['name'] = u.name
      userObj['mac'] = u.mac
      userObj['ip'] = u.ip
      userObj['selected'] = u.selected
      userArr.push(userObj)
    }
    paramsObj2['users'] = userArr
    const params = paramsObj2
    return this.client.setAppFilterUser(params)
  }

  async addAppFilterUser(user: OafUser): Promise<boolean> {
    const addUserParams: Record<string, Object> = {}
    addUserParams['mac_list'] = [user.mac]
    return this.client.addAppFilterUser(addUserParams)
  }

  async deleteAppFilterUser(user: OafUser): Promise<boolean> {
    const delUserParams: Record<string, Object> = {}
    delUserParams['mac'] = user.mac
    return this.client.delAppFilterUser(delUserParams)
  }

  async fetchAppFilterAdv(): Promise<Record<string, Object>> {
    try {
      const result: Record<string, Object> = await this.client.getAppFilterAdv()
      return (result['data'] as Record<string, Object>) || result
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAppFilterAdv err')
    }
    return {}
  }

  async saveAppFilterAdv(params: Record<string, Object>): Promise<boolean> {
    return this.client.setAppFilterAdv(params)
  }

  async rebootDevice(): Promise<boolean> {
    return this.client.systemReboot()
  }

  async factoryReset(): Promise<string> {
    return this.client.execCommand('/sbin/firstboot', ['-r', '-y'])
  }

  getBaseUrl(): string {
    return this.client.getBaseUrl()
  }

  async fetchAllOafUsers(): Promise<OafUser[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.getAllOafUsers()
      const container = raw.length > 0 ? raw[0] : null
      if (!container) {
        return []
      }
      const data = container['data'] as Record<string, Object> | undefined
      const list = data ? (data['list'] as Record<string, Object>[] | undefined) : undefined
      if (!list || !Array.isArray(list)) {
        return []
      }
      const users: OafUser[] = []
      for (let i = 0; i < list.length; i++) {
        const r = list[i]
        users.push({
          id: (r['mac'] as string) || '',
          name: (r['nickname'] as string) || (r['hostname'] as string) || '',
          mac: (r['mac'] as string) || '',
          ip: (r['ip'] as string) || '',
          selected: false
        })
      }
      return users
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchAllOafUsers err')
    }
    return []
  }

  async fetchUserList(): Promise<UserListItem[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.getAllOafUsers()
      const container = raw.length > 0 ? raw[0] : null
      if (!container) {
        return []
      }
      const data = container['data'] as Record<string, Object> | undefined
      const list = data ? (data['list'] as Record<string, Object>[] | undefined) : undefined
      if (!list || !Array.isArray(list)) {
        return []
      }
      const users: UserListItem[] = []
      for (let i = 0; i < list.length; i++) {
        const r = list[i]
        const appsArr = r['applist'] as Record<string, Object>[] | undefined
        const commonApps: number[] = []
        if (appsArr && Array.isArray(appsArr)) {
          for (let j = 0; j < appsArr.length; j++) {
            commonApps.push(Number(appsArr[j]['id']) || 0)
          }
        }
        users.push({
          hostname: (r['hostname'] as string) || (r['nickname'] as string) || '',
          mac: (r['mac'] as string) || '',
          ip: (r['ip'] as string) || '',
          currentApp: (r['app'] as string) || '',
          currentUrl: (r['url'] as string) || '',
          commonApps: commonApps
        })
      }
      return users
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchUserList err')
    }
    return []
  }

  async fetchDeviceVisitTime(mac: string): Promise<DeviceVisitTime[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.devVisitTime(mac)
      const result = raw.length > 0 ? raw[0] : null
      if (!result) {
        return []
      }
      const list = result['list'] as Record<string, Object>[] | undefined
      if (!list || !Array.isArray(list)) {
        return []
      }
      let total: number = 0
      const items: DeviceVisitTime[] = []
      for (let i = 0; i < list.length; i++) {
        const r = list[i]
        const secs: number = this.n(r, 't', 0)
        items.push({ appId: 0, appName: (r['name'] as string) || '', totalSeconds: secs, percent: 0 })
        total += secs
      }
      for (let i = 0; i < items.length; i++) {
        items[i].percent = total > 0 ? (items[i].totalSeconds / total) * 100 : 0
      }
      items.sort((a, b) => b.totalSeconds - a.totalSeconds)
      return items
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchDeviceVisitTime err')
    }
    return []
  }

  async fetchDeviceVisitList(mac: string): Promise<DeviceVisitRecord[]> {
    try {
      const raw: Record<string, Object>[] = await this.client.devVisitList(mac)
      const result = raw.length > 0 ? raw[0] : null
      if (!result) {
        return []
      }
      const list = result['list'] as Record<string, Object>[] | undefined
      if (!list || !Array.isArray(list)) {
        return []
      }
      const records: DeviceVisitRecord[] = []
      for (let i = 0; i < list.length; i++) {
        const r = list[i]
        records.push({
          appId: this.n(r, 'id', 0),
          appName: (r['name'] as string) || '',
          startTime: new Date(this.n(r, 'ft', 0) * 1000).toISOString(),
          duration: this.n(r, 'tt', 0)
        })
      }
      records.sort((a, b) => b.startTime.localeCompare(a.startTime))
      return records
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchDeviceVisitList err')
    }
    return []
  }

  async kickClient(ifname: string, mac: string): Promise<boolean> {
    return this.client.hostapdDelClient(ifname, mac)
  }
}
