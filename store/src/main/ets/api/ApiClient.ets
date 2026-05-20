import { http } from '@kit.NetworkKit'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'iStoreApi'
const DOMAIN = 0x0001

export class ApiClient {
  baseUrl: string = ''
  username: string = ''
  password: string = ''
  connected: boolean = false
  lastError: string = ''
  private authCookie: string = ''
  private sessionId: string = ''
  private rpcId: number = 1

  private static instance: ApiClient

  static getInstance(): ApiClient {
    if (!ApiClient.instance) {
      ApiClient.instance = new ApiClient()
    }
    return ApiClient.instance
  }

  configure(config: ConnectionConfig): void {
    let host: string = config.host.trim()
    host = host.replace(/^https?:\/\//, '')
    host = host.replace(/\/$/, '').replace(/\/.*$/, '')
    this.baseUrl = `${config.useHttps ? 'https' : 'http'}://${host}:${config.port}`
    this.username = config.username
    this.password = config.password
    this.lastError = ''
    this.connected = false
    this.authCookie = ''
    this.sessionId = ''
    this.rpcId = 1
    hilog.info(DOMAIN, TAG, `Configured: ${this.baseUrl}`)
  }

  getConnected(): boolean {
    return this.connected
  }

  async connect(): Promise<boolean> {
    this.lastError = ''
    this.connected = false
    this.sessionId = ''

    if (!await this.probe()) {
      this.lastError = '无法连接到设备'
      return false
    }

    const loginResult: Record<string, Object> | null = await this.ubusLogin()
    if (!loginResult) {
      this.lastError = '登录失败，请检查用户名和密码'
      return false
    }

    if (!await this.verifyLogin()) {
      this.lastError = '会话验证失败'
      return false
    }

    this.connected = true
    return true
  }

  private async probe(): Promise<boolean> {
    const req = http.createHttp()
    try {
      const r = await req.request(`${this.baseUrl}/`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 3000,
        readTimeout: 3000
      })
      req.destroy()
      return r.responseCode >= 200 && r.responseCode < 500
    } catch (e) {
      req.destroy()
      return false
    }
  }

  private async ubusLogin(): Promise<Record<string, Object> | null> {
    const loginObj: Record<string, Object> = {}
    loginObj['username'] = this.username
    loginObj['password'] = this.password
    const body = JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'call',
      params: ['00000000000000000000000000000000', 'session', 'login', loginObj]
    })
    try {
      const result = await this.rpcPost('/ubus', body)
      if (!result || typeof result !== 'object') {
        return null
      }
      const resArr = result['result'] as Object[] | undefined
      if (!resArr || !Array.isArray(resArr) || resArr.length < 2) {
        return null
      }
      const code = Number(resArr[0])
      if (code !== 0) {
        return null
      }
      const data = resArr[1] as Record<string, Object>
      if (!data) {
        return null
      }
      const sid = data['ubus_rpc_session'] as string | undefined
      if (!sid) {
        return null
      }
      this.sessionId = sid
      const timeoutVal = data['timeout'] as number | undefined
      const timeout = timeoutVal || 300
      this.authCookie = `sysauth=${sid}`
      hilog.info(DOMAIN, TAG, `ubus login OK, session: ${sid.substring(0, 12)}...`)
      return data
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'ubusLogin err')
      return null
    }
  }

  private async verifyLogin(): Promise<boolean> {
    const board = await this.getSystemBoard()
    if (board && typeof board === 'object') {
      const hostname = board['hostname']
      if (hostname) {
        return true
      }
    }
    return false
  }

  private async rpcPost(path: string, body: string): Promise<Record<string, Object> | null> {
    const url: string = `${this.baseUrl}${path}`

    const hdr: Record<string, string> = { 'Content-Type': 'application/json' }
    if (this.authCookie) {
      hdr['Cookie'] = this.authCookie
    }

    const req = http.createHttp()
    try {
      const r = await req.request(url, {
        method: http.RequestMethod.POST,
        header: hdr,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      req.destroy()

      const respBody: string = r.result as string || ''
      if (r.responseCode >= 200 && r.responseCode < 400 && respBody.length > 5) {
        return JSON.parse(respBody) as Record<string, Object>
      }
    } catch (e) {
      req.destroy()
    }
    return null
  }

  async callUbus(namespace: string, procedure: string, params: Record<string, Object>): Promise<Record<string, Object>[]> {
    const body: string = JSON.stringify({
      jsonrpc: '2.0',
      id: this.rpcId++,
      method: 'call',
      params: [this.sessionId, namespace, procedure, params || {}]
    })

    try {
      const resp: Record<string, Object> | null = await this.rpcPost('/ubus/', body)
      if (!resp || typeof resp !== 'object') {
        return []
      }

      const result: Object | undefined = resp['result']
      if (result === undefined || result === null) {
        return []
      }

      if (Array.isArray(result)) {
        if (result.length >= 2 && typeof result[0] === 'number' && result[0] === 0) {
          const payload: Record<string, Object> = result[1] as Record<string, Object>
          if (payload && typeof payload === 'object') {
            return [payload]
          }
          return []
        }
        if (result.length >= 2 && typeof result[0] === 'number' && result[0] !== 0) {
          hilog.warn(DOMAIN, TAG, `ubus ${namespace}.${procedure} err: ${result[1]}`)
          return []
        }
      }

      return []
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ubus ${namespace}.${procedure} err`)
    }
    return []
  }

  async callUbusFirst(namespace: string, procedure: string, params: Record<string, Object>): Promise<Record<string, Object>> {
    const arr: Record<string, Object>[] = await this.callUbus(namespace, procedure, params)
    if (arr.length > 0 && typeof arr[0] === 'object' && arr[0] !== null) {
      return arr[0] as Record<string, Object>
    }
    return {}
  }

  async getSystemBoard(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'board', {})
  }

  async getSystemInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'info', {})
  }

  async getLuciNetworkDevices(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci-rpc', 'getNetworkDevices', {})
  }

  async getLuciDHCPLeases(): Promise<Record<string, Object>> {
    const arr: Record<string, Object>[] = await this.callUbus('luci-rpc', 'getDHCPLeases', {})
    if (arr.length > 0) {
      const container: Record<string, Object> = arr[0] as Record<string, Object>
      if (container) {
        return container
      }
    }
    return {}
  }

  async readFile(filepath: string): Promise<string> {
    const readParams: Record<string, Object> = {}
    readParams['path'] = filepath
    const arr: Record<string, Object>[] = await this.callUbus('file', 'read', readParams)
    if (arr.length > 0) {
      const container: Record<string, Object> = arr[0] as Record<string, Object>
      if (container) {
        const data: string | undefined = container['data'] as string | undefined
        if (data) {
          return data
        }
      }
    }
    return ''
  }

  async getCPUTemp(): Promise<number> {
    const paths: string[] = [
      '/sys/class/thermal/thermal_zone0/temp',
      '/sys/class/thermal/thermal_zone1/temp',
      '/sys/class/hwmon/hwmon0/temp1_input',
      '/sys/class/hwmon/hwmon1/temp1_input'
    ]
    for (let i = 0; i < paths.length; i++) {
      try {
        const raw: string = await this.readFile(paths[i])
        const val: number = parseInt(raw.trim(), 10)
        if (!isNaN(val) && val > 0) {
          return val > 200 ? val / 1000 : val
        }
      } catch (e) {
      }
    }
    return 0
  }

  async getCPUUsage(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getCPUUsage', {})
  }

  async getOnlineUsers(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getOnlineUsers', {})
  }

  async getTempInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getTempInfo', {})
  }

  async getMountPoints(): Promise<Record<string, Object>[]> {
    return this.callUbus('luci', 'getMountPoints', {})
  }

  async getRealtimeStats(params: Record<string, Object>): Promise<Record<string, Object>[]> {
    return this.callUbus('luci', 'getRealtimeStats', params)
  }

  async getProcessList(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getProcessList', {})
  }

  async getWirelessDevices(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci-rpc', 'getWirelessDevices', {})
  }

  async execCommand(command: string, params?: string[]): Promise<string> {
    const execObj: Record<string, Object> = {}
    execObj['command'] = command
    execObj['params'] = params || []
    const execParams: Record<string, Object> = execObj
    const arr = await this.callUbus('file', 'exec', execParams)
    if (arr.length > 0) {
      const container = arr[0] as Record<string, Object>
      if (container) {
        const codeVal = container['code']
        const code: number = codeVal !== undefined ? Number(codeVal) : -1
        if (code === 0) {
          const stdout = container['stdout'] as string | undefined
          if (stdout) {
            return stdout
          }
        }
      }
    }
    return ''
  }

  async systemReboot(): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('system', 'reboot', {})
    return arr.length > 0
  }

  async networkInterfaceDump(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.interface', 'dump', {})
  }

  async networkDeviceStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.device', 'status', {})
  }

  async iwinfoAssoclist(ifname: string): Promise<Record<string, Object>> {
    const iwinfoParams: Record<string, Object> = {}
    iwinfoParams['device'] = ifname
    return this.callUbusFirst('iwinfo', 'assoclist', iwinfoParams)
  }

  async rcList(): Promise<Record<string, Object>> {
    return this.callUbusFirst('rc', 'list', {})
  }

  async hostapdDelClient(ifname: string, mac: string): Promise<boolean> {
    const delParams: Record<string, Object> = {}
    delParams['addr'] = mac
    const arr: Record<string, Object>[] = await this.callUbus('hostapd.' + ifname, 'del_client', delParams)
    return arr.length > 0
  }

  async getOafStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_oaf_status', {})
  }

  async getAppFilterBase(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_base', {})
  }

  async setAppFilterBase(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_base', params)
    return arr.length > 0
  }

  async getAppFilterClassList(): Promise<Record<string, Object>[]> {
    return this.callUbus('appfilter', 'class_list', {})
  }

  async getAppFilter(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter', {})
  }

  async setAppFilter(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter', params)
    return arr.length > 0
  }

  async getAppFilterTime(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_time', {})
  }

  async setAppFilterTime(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_time', params)
    return arr.length > 0
  }

  async getAppFilterUser(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_user', {})
  }

  async setAppFilterUser(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_user', params)
    return arr.length > 0
  }

  async addAppFilterUser(user: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'add_app_filter_user', user)
    return arr.length > 0
  }

  async delAppFilterUser(user: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'del_app_filter_user', user)
    return arr.length > 0
  }

  async getAppFilterAdv(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_adv', {})
  }

  async setAppFilterAdv(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_adv', params)
    return arr.length > 0
  }

  async getAllOafUsers(): Promise<Record<string, Object>[]> {
    const oafParams: Record<string, Object> = {}
    oafParams['flag'] = 3
    return this.callUbus('appfilter', 'get_all_users', oafParams)
  }

  async devVisitTime(mac: string): Promise<Record<string, Object>[]> {
    const devVisitTimeParams: Record<string, Object> = {}
    devVisitTimeParams['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_time', devVisitTimeParams)
  }

  async devVisitList(mac: string): Promise<Record<string, Object>[]> {
    const devVisitListParams: Record<string, Object> = {}
    devVisitListParams['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_list', devVisitListParams)
  }

  getBaseUrl(): string {
    return this.baseUrl
  }
}
