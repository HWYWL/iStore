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

const TAG = 'ApiService'
const DOMAIN = 0x0001

type AppFilterMode = 'auto' | 'manual'

class EmptyRecord {
}

class ObjectHelper {
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
      const board = await this.client.getSystemBoard()
      const info = await this.client.getSystemInfo()

      const hostname = ObjectHelper.getString(board, 'hostname', 'OpenWrt')
      const model = ObjectHelper.getString(board, 'model', '') || ObjectHelper.getString(board, 'system', '') || 'OpenWrt'
      const kernel = ObjectHelper.getString(board, 'kernel', '')
      const cpuModel = ObjectHelper.getString(board, 'cpu_model', '') || ObjectHelper.getString(board, 'model', '')
      const boardName = ObjectHelper.getString(board, 'board_name', '')
      const distribution = ObjectHelper.getString(board, 'distribution', '')
      const firmwareVersion = ObjectHelper.getString(board, 'firmware_version', '') || ObjectHelper.getString(board, 'version', '')

      const uptime = ObjectHelper.getNumber(info, 'uptime', 0)
      const localtimeVal = ObjectHelper.getString(info, 'localtime', '')
      const localTime = localtimeVal ? new Date(Number(localtimeVal) * 1000).toISOString() : new Date().toISOString()
      const cpuUsage = ObjectHelper.getNumber(info, 'cpu_usage', 0)

      const memoryArr = ObjectHelper.getArray(info, 'memory')
      const memory = memoryArr.length > 0 ? memoryArr[0] : new EmptyRecord()
      const memTotal = ObjectHelper.getNumber(memory, 'total', 0)
      const memUsed = ObjectHelper.getNumber(memory, 'used', 0)
      const memFree = ObjectHelper.getNumber(memory, 'free', 0)
      const memAvailable = ObjectHelper.getNumber(memory, 'available', memFree)
      const memCached = ObjectHelper.getNumber(memory, 'cached', 0) + ObjectHelper.getNumber(memory, 'buffered', 0)

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

  async fetchWanStatus(): Promise<WanStatus> {
    try {
      const interfaces = await this.client.getNetworkInterfaces()
      const interfacesList = ObjectHelper.getArray(interfaces, 'interfaces')

      let wanIf: Object | null = null
      for (let i = 0; i < interfacesList.length; i++) {
        const iface = interfacesList[i]
        const type = ObjectHelper.getString(iface, 'type', '')
        if (type === 'wan') {
          wanIf = iface
          break
        }
      }

      if (!wanIf) {
        return this.emptyWanStatus()
      }

      const ifname = ObjectHelper.getString(wanIf, 'name', 'wan')
      const ipAddress = ObjectHelper.getString(wanIf, 'ip_address', '0.0.0.0')
      const netmask = ObjectHelper.getString(wanIf, 'netmask', '')
      const gateway = ObjectHelper.getString(wanIf, 'gateway', '')
      const dnsArray = ObjectHelper.getArray(wanIf, 'dns')
      const dns: string[] = []
      for (let i = 0; i < dnsArray.length && i < 3; i++) {
        dns.push(String(dnsArray[i]))
      }
      const proto = ObjectHelper.getString(wanIf, 'proto', '')
      const macAddr = ObjectHelper.getString(wanIf, 'mac_address', '')
      const uptime = ObjectHelper.getNumber(wanIf, 'uptime', 0)
      const rxRate = ObjectHelper.getNumber(wanIf, 'rx_rate', 0)
      const txRate = ObjectHelper.getNumber(wanIf, 'tx_rate', 0)

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
      hilog.error(DOMAIN, TAG, `fetchWanStatus err: ${String(e)}`)
    }
    return this.emptyWanStatus()
  }

  async fetchLanStatus(): Promise<WanStatus> {
    return this.fetchWanStatus()
  }

  async fetchNetworkInterfaces(): Promise<NetworkInterface[]> {
    try {
      const interfaces = await this.client.getNetworkInterfaces()
      const interfacesList = ObjectHelper.getArray(interfaces, 'interfaces')
      const list: NetworkInterface[] = []

      for (let i = 0; i < interfacesList.length; i++) {
        const iface = interfacesList[i]
        const name = ObjectHelper.getString(iface, 'name', '')
        const typeStr = ObjectHelper.getString(iface, 'type', '')
        let type: 'wan' | 'lan' | 'wifi' | 'vpn' = 'lan'
        if (typeStr === 'wan') type = 'wan'
        else if (typeStr === 'wifi') type = 'wifi'
        else if (typeStr === 'vpn') type = 'vpn'
        const ipAddress = ObjectHelper.getString(iface, 'ip_address', '')
        const netmask = ObjectHelper.getString(iface, 'netmask', '')
        const macAddress = ObjectHelper.getString(iface, 'mac_address', '')
        const rxBytes = ObjectHelper.getNumber(iface, 'rx_bytes', 0)
        const txBytes = ObjectHelper.getNumber(iface, 'tx_bytes', 0)
        const rxRate = ObjectHelper.getNumber(iface, 'rx_rate', 0)
        const txRate = ObjectHelper.getNumber(iface, 'tx_rate', 0)
        const uptime = ObjectHelper.getNumber(iface, 'uptime', 0)

        const item: NetworkInterface = {
          name: name,
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
      const leases = await this.client.getLuciDHCPLeases()
      const leasesList = ObjectHelper.getArray(leases, 'leases')
      const list: ConnectedDevice[] = []

      for (let i = 0; i < leasesList.length; i++) {
        const lease = leasesList[i]
        const mac = ObjectHelper.getString(lease, 'mac', '')
        const ip = ObjectHelper.getString(lease, 'ip', '')
        const hostname = ObjectHelper.getString(lease, 'hostname', '')
        const isOnline = ObjectHelper.getNumber(lease, 'online', 0) === 1
        const interfaceName = ObjectHelper.getString(lease, 'interface', '')

        const item: ConnectedDevice = {
          mac: mac,
          ip: ip,
          hostname: hostname,
          vendor: '',
          interface: interfaceName,
          onlineTime: '',
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

  private formatUptime(seconds: number): string {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    if (days > 0) {
      return `${days}天${hours}时${mins}分`
    }
    return `${hours}时${mins}分`
  }

  async fetchMountPoints(): Promise<MountPoint[]> {
    try {
      const mounts = await this.client.getMountPoints()
      const mountsList = ObjectHelper.getArray(mounts, 'mounts')
      const list: MountPoint[] = []

      for (let i = 0; i < mountsList.length; i++) {
        const mount = mountsList[i]
        const size = ObjectHelper.getNumber(mount, 'size', 0)
        const used = ObjectHelper.getNumber(mount, 'used', 0)
        const available = ObjectHelper.getNumber(mount, 'available', 0)
        const usedPercent = size > 0 ? Math.round((used / size) * 100) : 0

        const item: MountPoint = {
          device: ObjectHelper.getString(mount, 'device', ''),
          mountPoint: ObjectHelper.getString(mount, 'mountpoint', ''),
          filesystem: ObjectHelper.getString(mount, 'type', ''),
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
      const info = await this.client.getConntrackInfo()
      const count = ObjectHelper.getNumber(info, 'count', 0)
      const max = ObjectHelper.getNumber(info, 'max', 0)
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
      const wireless = await this.client.getWirelessStatus()
      const interfaces = ObjectHelper.getArray(wireless, 'interfaces')
      const list: WirelessClient[] = []

      for (let i = 0; i < interfaces.length; i++) {
        const iface = interfaces[i]
        const clients = ObjectHelper.getArray(iface, 'clients')
        for (let j = 0; j < clients.length; j++) {
          const client = clients[j]
          const item: WirelessClient = {
            mac: ObjectHelper.getString(client, 'mac', ''),
            hostname: ObjectHelper.getString(client, 'hostname', ''),
            interface: ObjectHelper.getString(client, 'interface', ''),
            signal: ObjectHelper.getNumber(client, 'signal', 0),
            signalNoise: 0,
            rxRate: ObjectHelper.getNumber(client, 'rx_rate', 0),
            txRate: ObjectHelper.getNumber(client, 'tx_rate', 0),
            connectedTime: 0,
            inactiveTime: 0,
            isMesh: false
          }
          list.push(item)
        }
      }
      return list
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchWirelessClients err')
    }
    return []
  }

  async fetchWirelessDevices(): Promise<WirelessDevice[]> {
    try {
      const wireless = await this.client.getWirelessDevices()
      const devices = ObjectHelper.getArray(wireless, 'devices')
      const list: WirelessDevice[] = []

      for (let i = 0; i < devices.length; i++) {
        const device = devices[i]
        const interfaces = ObjectHelper.getArray(device, 'interfaces')

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
      const classes = await this.client.getAppFilterClassList()
      const classList = classes.length > 0 ? ObjectHelper.getArray(classes[0], 'classes') : []
      const list: AppClass[] = []

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
      const time = await this.client.getAppFilterTime()
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
    return false
  }

  async saveAppFilter(_classes: AppClass[]): Promise<boolean> {
    return false
  }

  async saveAppFilterTime(_time: AppFilterTime): Promise<boolean> {
    return false
  }

  async saveAppFilterUser(_user: AppFilterUser): Promise<boolean> {
    return false
  }

  async saveAppFilterAdv(_adv: Object): Promise<boolean> {
    return false
  }

  async rebootDevice(): Promise<boolean> {
    return false
  }
}
