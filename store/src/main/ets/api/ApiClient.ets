import { http } from '@kit.NetworkKit'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'iStoreApi'
const DOMAIN = 0x0001

class RouterApiResponse {
  code: number = 0
  message: string = ''
  data: Object = new EmptyRecord()
}

class EmptyRecord {
}

export class ApiClient {
  baseUrl: string = ''
  token: string = ''
  connected: boolean = false
  lastError: string = ''
  private static instance: ApiClient

  static getInstance(): ApiClient {
    if (!ApiClient.instance) {
      ApiClient.instance = new ApiClient()
    }
    return ApiClient.instance
  }

  configure(config: ConnectionConfig): void {
    const protocol: string = config.useHttps ? 'https' : 'http'
    this.baseUrl = `${protocol}://${config.host}:${config.port}/cgi-bin/router-api`
    this.token = config.token
    this.connected = false
    this.lastError = ''
  }

  async connect(): Promise<boolean> {
    try {
      const result = await this.request('ping')
      if (result && result.code === 0) {
        this.connected = true
        this.lastError = ''
        return true
      } else {
        const msg: string = result && typeof result.message === 'string' ? result.message : 'Connection failed'
        this.lastError = msg
        return false
      }
    } catch (e) {
      this.lastError = `Connection failed: ${String(e)}`
      hilog.error(DOMAIN, TAG, `Connect failed: ${e}`)
      return false
    }
  }

  async request(action: string, device?: string): Promise<RouterApiResponse | null> {
    let url = `${this.baseUrl}?action=${action}&token=${encodeURIComponent(this.token)}`
    if (device) {
      url += `&device=${encodeURIComponent(device)}`
    }
    hilog.info(DOMAIN, TAG, `Requesting: ${url}`)

    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json',
          'X-Auth-Token': this.token
        },
        connectTimeout: 5000,
        readTimeout: 10000
      })

      const code = r.responseCode
      if (code === 200) {
        const resultData = r.result as Object
        let respBody = ''
        if (typeof resultData === 'string') {
          respBody = resultData
        } else {
          respBody = String(resultData)
        }
        req.destroy()
        const parsed: RouterApiResponse = JSON.parse(respBody) as RouterApiResponse
        return parsed
      } else {
        req.destroy()
        this.lastError = `HTTP Error: ${code}`
        return null
      }
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `Request error: ${e}`)
      this.lastError = `Request failed: ${String(e)}`
      return null
    }
  }

  async getSystemBoard(): Promise<Object> {
    const result = await this.request('system_board')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getSystemInfo(): Promise<Object> {
    const result = await this.request('system_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getLuciDHCPLeases(): Promise<Object> {
    const result = await this.request('dhcp_leases')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getMemoryInfo(): Promise<Object> {
    const result = await this.request('memory_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getNetworkInterfaces(): Promise<Object> {
    const result = await this.request('network_interfaces')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getNetworkDeviceStats(device: string): Promise<Object> {
    const result = await this.request('network_devices', device)
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getCPUTemp(): Promise<number> {
    const result = await this.request('cpu_info')
    if (result && result.data) {
      const data = result.data as Record<string, Object>
      return Number(data['temp'] || data['temperature'] || 0)
    }
    return 0
  }

  async getMountPoints(): Promise<Object> {
    const result = await this.request('storage_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getProcessList(): Promise<Object> {
    const result = await this.request('processes')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getRouteTable(): Promise<Object> {
    const result = await this.request('route_table')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getWirelessStatus(): Promise<Object> {
    const result = await this.request('network_wifi')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getConntrackInfo(): Promise<Object> {
    const result = await this.request('conntrack')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async networkInterfaceDump(): Promise<Object> {
    const result = await this.request('network_interfaces')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async networkDeviceStatus(): Promise<Object> {
    const result = await this.request('network_devices')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getRealtimeStats(device: string): Promise<Object[]> {
    const result = await this.request('bandwidth', device)
    if (result && result.data) {
      return [result.data]
    }
    return []
  }

  async getWirelessDevices(): Promise<Object> {
    const result = await this.request('network_wifi')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getOafStatus(): Promise<Object> {
    const result = await this.request('oaf_status')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getAppFilterBase(): Promise<Object> {
    const result = await this.request('appfilter_base')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getAppFilterClassList(): Promise<Object[]> {
    const result = await this.request('appfilter_classes')
    if (result && result.data) {
      return [result.data]
    }
    return []
  }

  async getAppFilterTime(): Promise<Object> {
    const result = await this.request('appfilter_time')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getAppFilterUser(): Promise<Object> {
    const result = await this.request('appfilter_user')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getAppFilterAdv(): Promise<Object> {
    const result = await this.request('appfilter_adv')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  disconnect(): void {
    this.connected = false
    this.token = ''
    this.baseUrl = ''
    this.lastError = ''
  }

  getConnected(): boolean {
    return this.connected
  }

  getLastError(): string {
    return this.lastError
  }

  hasCapability(_cap: string): boolean {
    return true
  }

  async execCommand(_command: string, _params?: string[]): Promise<string> {
    return ''
  }

  async readFile(_filepath: string): Promise<string> {
    return ''
  }

  callUbus(_namespace: string, _procedure: string, _params: Record<string, Object>): Promise<[number, Object | null]> {
    return Promise.resolve([0, null])
  }

  callUbusFirst(_namespace: string, _procedure: string, _params: Record<string, Object>): Promise<Object> {
    return Promise.resolve(new EmptyRecord())
  }
}
