import { ApiClient } from './ApiClient'
import {
  SystemInfo,
  NetworkInterface,
  WanStatus,
  ConnectedDevice,
  Plugin,
  TrafficHistory
} from '../models/Models'
import { ConnectionConfig } from '../models/Models'

export class ApiService {
  private client: ApiClient

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
    const networkRaw: ESObject = await this.client.getNetworkStatus()
    const networkData: ESObject = this.extractResult(networkRaw)
    const uptimeVal: number = this.n(networkData, 'uptimeStamp', 0)

    return {
      hostname: 'iStoreOS',
      model: '',
      kernel: '',
      firmwareVersion: this.s(networkData, 'proto', ''),
      localTime: '',
      uptime: uptimeVal,
      cpuUsage: 0,
      memoryTotal: 0,
      memoryUsed: 0,
      memoryCached: 0,
      memoryAvailable: 0,
      storageTotal: 0,
      storageUsed: 0,
      cpuTemp: 0
    }
  }

  async fetchWanStatus(): Promise<WanStatus> {
    const raw: ESObject = await this.client.getNetworkStatus()
    const data: ESObject = this.extractResult(raw)

    const dnsArr: string[] = (data['dnsList'] as string[]) || []

    return {
      interface: this.s(data, 'defaultInterface', 'wan'),
      uptime: this.n(data, 'uptimeStamp', 0),
      ipAddress: this.s(data, 'ipv4addr', '0.0.0.0'),
      gateway: this.s(data, 'gateway', ''),
      dns: dnsArr,
      rxRate: this.n(data, 'rxRate', 0),
      txRate: this.n(data, 'txRate', 0),
      onlineTime: this.s(data, 'uptime', '')
    }
  }

  async fetchNetworkInterfaces(): Promise<NetworkInterface[]> {
    const raw: ESObject = await this.client.getNetworkStatus()
    const data: ESObject = this.extractResult(raw)

    return [{
      name: this.s(data, 'defaultInterface', 'lan'),
      type: this.inferType(this.s(data, 'defaultInterface', 'lan')),
      ipAddress: this.s(data, 'ipv4addr', ''),
      netmask: this.s(data, 'ipv4mask', '').toString(),
      gateway: this.s(data, 'gateway', ''),
      macAddress: '',
      mtu: 1500,
      status: this.s(data, 'networkInfo', '') === 'netSuccess' ? 'up' : 'down',
      rxBytes: 0,
      txBytes: 0,
      rxRate: this.n(data, 'rxRate', 0),
      txRate: this.n(data, 'txRate', 0)
    }]
  }

  async fetchConnectedDevices(): Promise<ConnectedDevice[]> {
    try {
      const raw: ESObject = await this.client.getDhcpLeases()
      const data: ESObject = this.extractResult(raw)
      if (Array.isArray(data)) {
        const arr: ESObject[] = data as ESObject[]
        const devs: ConnectedDevice[] = []
        for (let i = 0; i < arr.length; i++) {
          const l: ESObject = arr[i]
          devs.push({
            mac: this.s(l, 'macaddr', ''),
            ip: this.s(l, 'ipaddr', ''),
            hostname: this.s(l, 'hostname', 'Unknown'),
            vendor: '', interface: 'lan', onlineTime: '',
            signalStrength: -1, rxRate: 0, txRate: 0, isOnline: true
          })
        }
        return devs
      }
    } catch (e) {}
    return []
  }

  async fetchPlugins(): Promise<Plugin[]> {
    try {
      const raw: ESObject = await this.client.getInstalledPackages()
      const data: ESObject = this.extractResult(raw)
      if (Array.isArray(data)) {
        const arr: ESObject[] = data as ESObject[]
        const plugins: Plugin[] = []
        for (let i = 0; i < arr.length; i++) {
          const p: ESObject = arr[i]
          plugins.push({
            id: this.s(p, 'package', ''), name: this.s(p, 'package', ''),
            displayName: this.s(p, 'title', this.s(p, 'package', '')),
            description: this.s(p, 'description', ''), version: this.s(p, 'version', ''),
            author: this.s(p, 'author', ''), category: this.s(p, 'category', 'utility'),
            installed: this.b(p, 'installed', false), enabled: this.b(p, 'enabled', false),
            running: this.b(p, 'running', false), iconUrl: this.s(p, 'icon', ''),
            size: String(this.n(p, 'size', 0))
          })
        }
        return plugins
      }
    } catch (e) {}
    return []
  }

  async generateMockTrafficHistory(): Promise<TrafficHistory[]> {
    const history: TrafficHistory[] = []
    const now: number = Date.now()
    for (let i = 19; i >= 0; i--) {
      history.push({
        timestamp: new Date(now - i * 3000).toISOString(),
        rx: Math.random() * 1024 * 1024 * 100,
        tx: Math.random() * 1024 * 1024 * 50
      })
    }
    return history
  }

  async fetchFirewallRules(): Promise<ESObject> { return {} as ESObject }

  private extractResult(response: ESObject): ESObject {
    if (!response) return {}
    const result: ESObject | undefined = response['result'] as ESObject | undefined
    if (result && typeof result === 'object') return result as ESObject
    return response
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
    if (n.includes('wan') || n.includes('pppoe') || n.includes('eth0')) return 'wan'
    if (n.includes('wlan') || n.includes('ra') || n.includes('radio')) return 'wifi'
    if (n.includes('tun') || n.includes('wg') || n.includes('pptp') || n.includes('vpn')) return 'vpn'
    return 'lan'
  }

  private o(obj: ESObject, key: string, def: ESObject): ESObject {
    if (!obj || typeof obj !== 'object') return def
    const v: ESObject = obj[key] as ESObject
    return (v !== undefined && v !== null) ? v : def
  }
}
