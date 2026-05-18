import { ApiClient } from './ApiClient'
import {
  SystemInfo,
  NetworkInterface,
  WanStatus,
  ConnectedDevice,
  Plugin,
  TrafficHistory,
  FirewallRule
} from '../models/Models'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'ApiService'
const DOMAIN = 0x0001

export class ApiService {
  private client: ApiClient
  isDemoData: boolean = false
  private demoCpuBase: number = 15 + Math.random() * 25
  private demoRxBase: number = 1024 * 1024 * (2 + Math.random() * 8)
  private demoTxBase: number = 1024 * 1024 * (0.5 + Math.random() * 3)
  private demoStartTime: number = Date.now()
  private demoTemperature: number = 40 + Math.random() * 20
  private demoMemTotal: number = 1024 * 1024 * 1024 * (1 + Math.random() * 3)
  private demoStorageTotal: number = 1024 * 1024 * 1024 * (8 + Math.random() * 56)

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
      const netRaw: ESObject = await this.client.getNetworkStatus()
      const netData: ESObject = this.extractResult(netRaw)

      const sysRaw: ESObject = await this.client.tryGetJSON([
        '/cgi-bin/luci/istore/u/system/status/',
        '/cgi-bin/luci/istore/u/system/info/'
      ])
      const sysData: ESObject = this.extractResult(sysRaw)

      const boardRaw: ESObject = await this.client.tryGetJSON([
        '/cgi-bin/luci/istore/u/system/board/'
      ])
      const boardData: ESObject = this.extractResult(boardRaw)

      const netHasData: boolean = this.countValidKeys(netData) > 0
      if (!netHasData) {
        this.isDemoData = true
        return this.generateDemoSystemInfo()
      }

      const sysHasData: boolean = this.countValidKeys(sysData) > 0
      const boardHasData: boolean = this.countValidKeys(boardData) > 0
      const hasSystemData: boolean = sysHasData || boardHasData

      const hostname: string = this.firstNonEmpty(netData, 'hostname', sysData, 'hostname', boardData, 'hostname', 'iStoreOS')

      const model: string = this.firstNonEmpty(boardData, 'model', sysData, 'model')
      const kernel: string = this.firstNonEmpty(boardData, 'kernel', sysData, 'kernel')

      const fw: string = this.firstNonEmpty(boardData, 'firmwareVersion', boardData, 'release', sysData, 'firmwareVersion', sysData, 'firmware')

      const localTime: string = this.firstNonEmpty(sysData, 'localTime', sysData, 'localtime')

      const uptime: number = this.firstNonZero(netData, 'uptimeStamp', netData, 'uptime', sysData, 'uptimeStamp', sysData, 'uptime')

      const cpu: number = this.firstNonZero(sysData, 'cpuUsage', sysData, 'cpu', sysData, 'cpuload')

      const memTotal: number = this.firstNonZero(sysData, 'memTotal', sysData, 'memoryTotal')
      const memFree: number = this.firstNonZero(sysData, 'memFree', sysData, 'memoryFree', sysData, 'memAvailable')
      let memUsed: number = this.firstNonZero(sysData, 'memUsed', sysData, 'memoryUsed')
      if (memUsed === 0 && memTotal > 0 && memFree >= 0) {
        memUsed = memTotal - memFree
      }
      const memCached: number = this.firstNonZero(sysData, 'memCached', sysData, 'cached')

      const storageTotal: number = this.firstNonZero(sysData, 'storageTotal', sysData, 'diskTotal')
      const storageUsed: number = this.firstNonZero(sysData, 'storageUsed', sysData, 'diskUsed')

      const cpuTemp: number = this.firstNonZero(sysData, 'cpuTemp', sysData, 'cputemp')

      if (hasSystemData) {
        this.isDemoData = false
        return {
          hostname: hostname,
          model: model || 'iStoreOS',
          kernel: kernel,
          firmwareVersion: fw,
          localTime: localTime,
          uptime: uptime,
          cpuUsage: cpu,
          memoryTotal: memTotal,
          memoryUsed: memUsed,
          memoryCached: memCached,
          memoryAvailable: memFree > 0 ? memFree : 0,
          storageTotal: storageTotal,
          storageUsed: storageUsed,
          cpuTemp: cpuTemp
        }
      }

      const demo: SystemInfo = this.generateDemoSystemInfo()
      this.isDemoData = true
      return {
        hostname: hostname || demo.hostname,
        model: model || demo.model,
        kernel: kernel || demo.kernel,
        firmwareVersion: fw || demo.firmwareVersion,
        localTime: localTime || demo.localTime,
        uptime: uptime || demo.uptime,
        cpuUsage: cpu || demo.cpuUsage,
        memoryTotal: memTotal || demo.memoryTotal,
        memoryUsed: memUsed || demo.memoryUsed,
        memoryCached: memCached || demo.memoryCached,
        memoryAvailable: memFree > 0 ? memFree : demo.memoryAvailable,
        storageTotal: storageTotal || demo.storageTotal,
        storageUsed: storageUsed || demo.storageUsed,
        cpuTemp: cpuTemp || demo.cpuTemp
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchSystemInfo err: ${JSON.stringify(e)}`)
    }
    this.isDemoData = true
    return this.generateDemoSystemInfo()
  }

  async fetchWanStatus(): Promise<WanStatus> {
    try {
      const raw: ESObject = await this.client.getNetworkStatus()
      const data: ESObject = this.extractResult(raw)

      if (this.countValidKeys(data) === 0) {
        this.isDemoData = true
        return this.generateDemoWanStatus()
      }

      const dnsArr: string[] = this.parseStringArray(data, 'dnsList')
      const ip: string = this.firstNonEmpty(data, 'ipv4addr', data, 'ipaddr')

      const rxRate: number = this.firstNonZero(data, 'rxRate', data, 'rx_rate', data, 'download', data, 'rxrate')
      const txRate: number = this.firstNonZero(data, 'txRate', data, 'tx_rate', data, 'upload', data, 'txrate')
      const uptime: number = this.firstNonZero(data, 'uptimeStamp', data, 'uptime')

      this.isDemoData = false
      return {
        interface: this.firstNonEmpty(data, 'defaultInterface', data, 'ifname') || 'wan',
        uptime: uptime,
        ipAddress: ip || '0.0.0.0',
        gateway: this.firstNonEmpty(data, 'gateway', data, 'gw'),
        dns: dnsArr,
        rxRate: rxRate,
        txRate: txRate,
        onlineTime: this.firstNonEmpty(data, 'uptime', data, 'onlineTime')
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchWanStatus err: ${JSON.stringify(e)}`)
    }
    this.isDemoData = true
    return this.generateDemoWanStatus()
  }

  async fetchNetworkInterfaces(): Promise<NetworkInterface[]> {
    try {
      const raw: ESObject = await this.client.getNetworkInterfaces()
      const data: ESObject = this.extractResult(raw)

      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const keys: string[] = Object.keys(data)
        const list: NetworkInterface[] = []
        for (let i = 0; i < keys.length; i++) {
          const ifName: string = keys[i]
          const ifData: ESObject = data[ifName] as ESObject
          if (ifData && typeof ifData === 'object') {
            list.push(this.parseInterface(ifName, ifData))
          }
        }
        if (list.length > 0) {
          this.isDemoData = false
          return list
        }
      }

      if (Array.isArray(data) && data.length > 0) {
        const arr: ESObject[] = data as ESObject[]
        const list: NetworkInterface[] = []
        for (let i = 0; i < arr.length; i++) {
          const ifData: ESObject = arr[i]
          const ifName: string = this.s(ifData, 'name', this.s(ifData, 'ifname', ''))
          list.push(this.parseInterface(ifName, ifData))
        }
        if (list.length > 0) {
          this.isDemoData = false
          return list
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchNetworkInterfaces err: ${JSON.stringify(e)}`)
    }

    const wanRaw: ESObject = await this.client.getNetworkStatus()
    const wanData: ESObject = this.extractResult(wanRaw)
    if (this.countValidKeys(wanData) > 0) {
      this.isDemoData = false
      return [{
        name: this.s(wanData, 'defaultInterface', 'lan'),
        type: this.inferType(this.s(wanData, 'defaultInterface', 'lan')),
        ipAddress: this.s(wanData, 'ipv4addr', ''),
        netmask: this.s(wanData, 'ipv4mask', '').toString(),
        gateway: this.s(wanData, 'gateway', ''),
        macAddress: '',
        mtu: 1500,
        status: this.s(wanData, 'networkInfo', '') === 'netSuccess' ? 'up' : 'down',
        rxBytes: 0,
        txBytes: 0,
        rxRate: this.firstNonZero(wanData, 'rxRate', wanData, 'rx_rate'),
        txRate: this.firstNonZero(wanData, 'txRate', wanData, 'tx_rate')
      }]
    }
    this.isDemoData = true
    return this.generateDemoNetworkInterfaces()
  }

  async fetchConnectedDevices(): Promise<ConnectedDevice[]> {
    try {
      const raw: ESObject = await this.client.getDhcpLeases()
      const data: ESObject = this.extractResult(raw)

      if (Array.isArray(data) && data.length > 0) {
        this.isDemoData = false
        const arr: ESObject[] = data as ESObject[]
        const devs: ConnectedDevice[] = []
        for (let i = 0; i < arr.length; i++) {
          devs.push(this.parseDevice(arr[i]))
        }
        return devs
      }

      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const keys: string[] = Object.keys(data)
        if (keys.length > 0) {
          this.isDemoData = false
          const devs: ConnectedDevice[] = []
          for (let i = 0; i < keys.length; i++) {
            const l: ESObject = data[keys[i]] as ESObject
            if (l && typeof l === 'object') {
              const dev: ConnectedDevice = this.parseDevice(l)
              if (!dev.mac) dev.mac = keys[i]
              devs.push(dev)
            }
          }
          return devs
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchConnectedDevices err: ${JSON.stringify(e)}`)
    }
    return []
  }

  async fetchPlugins(): Promise<Plugin[]> {
    try {
      const raw: ESObject = await this.client.getInstalledPackages()
      const data: ESObject = this.extractResult(raw)

      if (Array.isArray(data) && data.length > 0) {
        this.isDemoData = false
        const arr: ESObject[] = data as ESObject[]
        const plugins: Plugin[] = []
        for (let i = 0; i < arr.length; i++) {
          plugins.push(this.parsePlugin(arr[i], ''))
        }
        return plugins
      }

      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const keys: string[] = Object.keys(data)
        if (keys.length > 0) {
          this.isDemoData = false
          const plugins: Plugin[] = []
          for (let i = 0; i < keys.length; i++) {
            const p: ESObject = data[keys[i]] as ESObject
            if (p && typeof p === 'object') {
              plugins.push(this.parsePlugin(p, keys[i]))
            }
          }
          return plugins
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchPlugins err: ${JSON.stringify(e)}`)
    }
    return []
  }

  async fetchFirewallRules(): Promise<FirewallRule[]> {
    try {
      const raw: ESObject = await this.client.getFirewallRules()
      const data: ESObject = this.extractResult(raw)

      if (Array.isArray(data)) {
        const arr: ESObject[] = data as ESObject[]
        const rules: FirewallRule[] = []
        for (let i = 0; i < arr.length; i++) {
          const r: ESObject = arr[i]
          rules.push({
            name: this.s(r, 'name', this.s(r, 'comment', '')),
            src: this.s(r, 'src', ''),
            dest: this.s(r, 'dest', ''),
            proto: this.s(r, 'proto', this.s(r, 'protocol', '')),
            port: this.s(r, 'port', ''),
            target: this.parseTarget(this.s(r, 'target', 'ACCEPT')),
            enabled: this.b(r, 'enabled', true)
          })
        }
        return rules
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchFirewallRules err: ${JSON.stringify(e)}`)
    }
    return []
  }

  async fetchTrafficHistory(): Promise<TrafficHistory[]> {
    try {
      const raw: ESObject = await this.client.getNetworkStatus()
      const data: ESObject = this.extractResult(raw)
      const trafficArr: ESObject[] | undefined = data['trafficHistory'] as ESObject[] | undefined
      if (trafficArr && Array.isArray(trafficArr) && trafficArr.length > 0) {
        const history: TrafficHistory[] = []
        for (let i = 0; i < trafficArr.length; i++) {
          const t: ESObject = trafficArr[i]
          history.push({
            timestamp: this.s(t, 'timestamp', ''),
            rx: this.n(t, 'rx', 0),
            tx: this.n(t, 'tx', 0)
          })
        }
        return history
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `fetchTrafficHistory err: ${JSON.stringify(e)}`)
    }
    return this.generateMockTrafficHistory()
  }

  generateMockTrafficHistory(): Promise<TrafficHistory[]> {
    const history: TrafficHistory[] = []
    const now: number = Date.now()
    for (let i = 19; i >= 0; i--) {
      history.push({
        timestamp: new Date(now - i * 3000).toISOString(),
        rx: (this.demoRxBase * (0.4 + Math.random() * 1.2)),
        tx: (this.demoTxBase * (0.4 + Math.random() * 1.2))
      })
    }
    return Promise.resolve(history)
  }

  private generateDemoSystemInfo(): SystemInfo {
    const elapsed: number = (Date.now() - this.demoStartTime) / 1000
    const cpuUsage: number = this.demoCpuBase + Math.sin(elapsed / 30) * 15 + (Math.random() - 0.5) * 10
    const memRatio: number = 0.3 + Math.sin(elapsed / 120) * 0.15 + (Math.random() - 0.5) * 0.05
    const storageRatio: number = 0.25 + Math.random() * 0.02
    const tempVariation: number = Math.sin(elapsed / 60) * 3 + (Math.random() - 0.5) * 2

    return {
      hostname: 'iStoreOS',
      model: 'Generic x86/64',
      kernel: 'Linux 5.15.162',
      firmwareVersion: 'iStoreOS 24.10.0',
      localTime: new Date().toISOString(),
      uptime: Math.floor(elapsed + 43200),
      cpuUsage: Math.max(0, Math.min(100, cpuUsage)),
      memoryTotal: this.demoMemTotal,
      memoryUsed: Math.floor(this.demoMemTotal * memRatio),
      memoryCached: Math.floor(this.demoMemTotal * 0.12),
      memoryAvailable: Math.floor(this.demoMemTotal * (1 - memRatio)),
      storageTotal: this.demoStorageTotal,
      storageUsed: Math.floor(this.demoStorageTotal * storageRatio),
      cpuTemp: this.demoTemperature + tempVariation
    }
  }

  private generateDemoWanStatus(): WanStatus {
    const elapsed: number = (Date.now() - this.demoStartTime) / 1000
    const rxRate: number = this.demoRxBase * (0.5 + 0.5 * Math.sin(elapsed / 15) + (Math.random() - 0.5) * 0.4)
    const txRate: number = this.demoTxBase * (0.5 + 0.5 * Math.cos(elapsed / 20) + (Math.random() - 0.5) * 0.3)

    return {
      interface: 'eth0',
      uptime: Math.floor(elapsed + 43200),
      ipAddress: '123.45.67.89',
      gateway: '123.45.67.1',
      dns: ['114.114.114.114', '223.5.5.5'],
      rxRate: Math.max(0, Math.floor(rxRate)),
      txRate: Math.max(0, Math.floor(txRate)),
      onlineTime: this.formatDemoUptime(Math.floor(elapsed + 43200))
    }
  }

  private generateDemoNetworkInterfaces(): NetworkInterface[] {
    const elapsed: number = (Date.now() - this.demoStartTime) / 1000
    return [
      {
        name: 'eth0', type: 'wan',
        ipAddress: '123.45.67.89', netmask: '255.255.255.0',
        gateway: '123.45.67.1', macAddress: '00:11:22:33:44:55',
        mtu: 1500, status: 'up',
        rxBytes: Math.floor(this.demoRxBase * (elapsed + 3600)),
        txBytes: Math.floor(this.demoTxBase * (elapsed + 3600)),
        rxRate: Math.floor(this.demoRxBase * (0.5 + Math.random())),
        txRate: Math.floor(this.demoTxBase * (0.5 + Math.random()))
      },
      {
        name: 'br-lan', type: 'lan',
        ipAddress: '192.168.1.1', netmask: '255.255.255.0',
        gateway: '', macAddress: '00:11:22:33:44:56',
        mtu: 1500, status: 'up',
        rxBytes: Math.floor(this.demoRxBase * 3 * (elapsed + 3600)),
        txBytes: Math.floor(this.demoTxBase * 3 * (elapsed + 3600)),
        rxRate: Math.floor(this.demoRxBase * 2 * (0.5 + Math.random())),
        txRate: Math.floor(this.demoTxBase * 2 * (0.5 + Math.random()))
      },
      {
        name: 'wlan0', type: 'wifi',
        ipAddress: '192.168.2.1', netmask: '255.255.255.0',
        gateway: '', macAddress: '00:11:22:33:44:57',
        mtu: 1500, status: 'up',
        rxBytes: Math.floor(this.demoRxBase * 1.5 * (elapsed + 3600)),
        txBytes: Math.floor(this.demoTxBase * 1.5 * (elapsed + 3600)),
        rxRate: Math.floor(this.demoRxBase * 0.8 * (0.5 + Math.random())),
        txRate: Math.floor(this.demoTxBase * 0.4 * (0.5 + Math.random()))
      }
    ]
  }

  private parseInterface(ifName: string, ifData: ESObject): NetworkInterface {
    return {
      name: ifName,
      type: this.inferType(ifName),
      ipAddress: this.s(ifData, 'ipv4addr', this.s(ifData, 'ipaddr', '')),
      netmask: this.s(ifData, 'netmask', this.s(ifData, 'mask', '')),
      gateway: this.s(ifData, 'gateway', ''),
      macAddress: this.s(ifData, 'macaddr', this.s(ifData, 'mac', '')),
      mtu: this.n(ifData, 'mtu', 1500),
      status: this.s(ifData, 'status', '') === 'down' ? 'down' : 'up',
      rxBytes: this.n(ifData, 'rxBytes', this.n(ifData, 'rx_bytes', 0)),
      txBytes: this.n(ifData, 'txBytes', this.n(ifData, 'tx_bytes', 0)),
      rxRate: this.n(ifData, 'rxRate', this.n(ifData, 'rx_rate', 0)),
      txRate: this.n(ifData, 'txRate', this.n(ifData, 'tx_rate', 0))
    }
  }

  private parseDevice(l: ESObject): ConnectedDevice {
    return {
      mac: this.s(l, 'macaddr', this.s(l, 'mac', '')),
      ip: this.s(l, 'ipaddr', this.s(l, 'ip', '')),
      hostname: this.s(l, 'hostname', this.s(l, 'name', 'Unknown')),
      vendor: this.s(l, 'vendor', ''),
      interface: this.s(l, 'interface', 'lan'),
      onlineTime: this.s(l, 'onlineTime', this.s(l, 'uptime', '')),
      signalStrength: this.n(l, 'signalStrength', this.n(l, 'signal', -1)),
      rxRate: this.n(l, 'rxRate', this.n(l, 'rx_rate', 0)),
      txRate: this.n(l, 'txRate', this.n(l, 'tx_rate', 0)),
      isOnline: this.b(l, 'isOnline', this.b(l, 'online', true))
    }
  }

  private parsePlugin(p: ESObject, fallbackId: string): Plugin {
    const pkg: string = this.s(p, 'package', this.s(p, 'id', fallbackId))
    return {
      id: pkg,
      name: pkg,
      displayName: this.s(p, 'title', this.s(p, 'displayName', pkg)),
      description: this.s(p, 'description', ''),
      version: this.s(p, 'version', ''),
      author: this.s(p, 'author', ''),
      category: this.s(p, 'category', 'utility'),
      installed: this.b(p, 'installed', true),
      enabled: this.b(p, 'enabled', false),
      running: this.b(p, 'running', false),
      iconUrl: this.s(p, 'icon', this.s(p, 'iconUrl', '')),
      size: this.s(p, 'size', '')
    }
  }

  private firstNonEmpty(source1: ESObject, key1: string, source2: ESObject, key2: string, source3?: ESObject, key3?: string, source4?: ESObject, key4?: string): string {
    let v: string = this.s(source1, key1, '')
    if (v) return v
    v = this.s(source2, key2, '')
    if (v) return v
    if (source3 && key3) {
      v = this.s(source3, key3, '')
      if (v) return v
    }
    if (source4 && key4) {
      v = this.s(source4, key4, '')
      if (v) return v
    }
    return ''
  }

  private firstNonZero(source1: ESObject, key1: string, source2: ESObject, key2: string, source3?: ESObject, key3?: string, source4?: ESObject, key4?: string): number {
    let v: number = this.n(source1, key1, 0)
    if (v !== 0) return v
    v = this.n(source2, key2, 0)
    if (v !== 0) return v
    if (source3 && key3) {
      v = this.n(source3, key3, 0)
      if (v !== 0) return v
    }
    if (source4 && key4) {
      v = this.n(source4, key4, 0)
      if (v !== 0) return v
    }
    return 0
  }

  private countValidKeys(obj: ESObject): number {
    if (!obj || typeof obj !== 'object') return 0
    const keys: string[] = Object.keys(obj)
    let count: number = 0
    for (let i = 0; i < keys.length; i++) {
      const v: ESObject = obj[keys[i]]
      if (v !== undefined && v !== null && v !== '') count++
    }
    return count
  }

  private formatDemoUptime(seconds: number): string {
    if (seconds < 60) return `${seconds}s`
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`
    const days: number = Math.floor(seconds / 86400)
    const hours: number = Math.floor((seconds % 86400) / 3600)
    return `${days}d ${hours}h`
  }

  private extractResult(response: ESObject): ESObject {
    if (!response) return {}
    const result: ESObject | undefined = response['result'] as ESObject | undefined
    if (result !== undefined && result !== null) return result as ESObject
    const data: ESObject | undefined = response['data'] as ESObject | undefined
    if (data !== undefined && data !== null) return data as ESObject
    return response
  }

  private parseStringArray(obj: ESObject, key: string): string[] {
    if (!obj || typeof obj !== 'object') return []
    const v: ESObject = obj[key] as ESObject
    if (Array.isArray(v)) return v as string[]
    if (typeof v === 'string') return v.split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0)
    return []
  }

  private parseTarget(target: string): 'ACCEPT' | 'REJECT' | 'DROP' {
    const t: string = target.toLowerCase()
    if (t === 'reject') return 'REJECT'
    if (t === 'drop') return 'DROP'
    return 'ACCEPT'
  }

  private s(obj: ESObject, key: string, def: string): string {
    if (!obj || typeof obj !== 'object') return def
    const v: string = obj[key] as string
    return (v !== undefined && v !== null) ? v : def
  }

  private n(obj: ESObject, key: string, def: number): number {
    if (!obj || typeof obj !== 'object') return def
    const v: number = Number(obj[key])
    return (v !== undefined && v !== null && !isNaN(v)) ? v : def
  }

  private b(obj: ESObject, key: string, def: boolean): boolean {
    if (!obj || typeof obj !== 'object') return def
    const v: boolean = obj[key] as boolean
    return (v !== undefined && v !== null) ? v : def
  }

  private inferType(name: string): 'wan' | 'lan' | 'wifi' | 'vpn' {
    const n: string = name.toLowerCase()
    if (n.includes('wan') || n.includes('pppoe') || n.startsWith('eth')) return 'wan'
    if (n.includes('wlan') || n.includes('ra') || n.includes('radio')) return 'wifi'
    if (n.includes('tun') || n.includes('wg') || n.includes('pptp') || n.includes('vpn')) return 'vpn'
    return 'lan'
  }
}
