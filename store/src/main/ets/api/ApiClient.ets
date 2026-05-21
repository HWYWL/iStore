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

    const luciOk: boolean = await this.luciFormLogin()
    if (luciOk) {
      this.sessionId = '00000000000000000000000000000000'
      hilog.info(DOMAIN, TAG, 'LuCI form login OK')
    } else {
      hilog.warn(DOMAIN, TAG, 'LuCI form login failed, trying UBUS fallback')
      if (!await this.ubusLogin()) {
        this.lastError = '登录失败，请检查用户名和密码'
        return false
      }
    }

    if (!await this.verifyLogin()) {
      this.lastError = '会话验证失败'
      return false
    }

    this.connected = true
    hilog.info(DOMAIN, TAG, 'Connected successfully')
    return true
  }

  getBaseUrl(): string {
    return this.baseUrl
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

  private async luciFormLogin(): Promise<boolean> {
    const formBody: string =
      `luci_username=${encodeURIComponent(this.username)}&luci_password=${encodeURIComponent(this.password)}`
    const url: string = `${this.baseUrl}/cgi-bin/luci/`
    const req = http.createHttp()
    try {
      const r = await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Accept': '*/*'
        },
        extraData: formBody,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 10000
      })
      let setCookie: string = ''
      const keys = Object.keys(r.header)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        if (key.toLowerCase() === 'set-cookie') {
          const cookieValue = String(r.header[key])
          if (cookieValue.toLowerCase().includes('sysauth')) {
            setCookie = cookieValue
            break
          }
          if (!setCookie) {
            setCookie = cookieValue
          }
        }
      }
      req.destroy()
      if (setCookie) {
        const sysauthMatch: RegExpMatchArray | null = setCookie.match(/sysauth[^;]*/)
        if (sysauthMatch && sysauthMatch[0]) {
          this.authCookie = sysauthMatch[0]
          hilog.info(DOMAIN, TAG, 'LuCI form login OK, cookie: ' + this.authCookie.substring(0, 20) + '...')
          hilog.info(DOMAIN, TAG, 'authCookie set successfully: ' + this.authCookie)
          return true
        }
      }
      hilog.warn(DOMAIN, TAG, 'LuCI form login: no sysauth cookie found')
      hilog.warn(DOMAIN, TAG, 'setCookie header value: ' + setCookie)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'LuCI form login err: ' + String(e))
      req.destroy()
    }
    return false
  }

  private async ubusLogin(): Promise<boolean> {
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
      const resp: Record<string, Object> | null = await this.rpcPost('/ubus', body)
      if (!resp || typeof resp !== 'object') {
        return false
      }
      const resArr = resp['result'] as Object[] | undefined
      if (!resArr || !Array.isArray(resArr) || resArr.length < 2) {
        return false
      }
      const code = Number(resArr[0])
      if (code !== 0) {
        return false
      }
      const data = resArr[1] as Record<string, Object>
      if (!data) {
        return false
      }
      const sid = data['ubus_rpc_session'] as string | undefined
      if (!sid) {
        return false
      }
      this.sessionId = sid
      this.authCookie = `sysauth=${sid}`
      hilog.info(DOMAIN, TAG, `UBUS login OK, session: ${sid.substring(0, 12)}...`)
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'ubusLogin err')
    }
    return false
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
      const resp: Record<string, Object> | null = await this.rpcPost('/cgi-bin/luci/admin/ubus/', body)
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

  getSystemBoard(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'board', {})
  }

  getSystemInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'info', {})
  }

  getLuciNetworkDevices(): Promise<Record<string, Object>> {
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
      '/sys/class/thermal/thermal_zone2/temp',
      '/sys/class/hwmon/hwmon0/temp1_input',
      '/sys/class/hwmon/hwmon1/temp1_input',
      '/sys/class/hwmon/hwmon2/temp1_input',
      '/sys/devices/virtual/thermal/thermal_zone0/temp',
      '/sys/devices/platform/coretemp.0/hwmon/hwmon0/temp1_input',
      '/proc/acpi/thermal_zone/THM0/temperature',
      '/proc/acpi/thermal_zone/THRM/temperature'
    ]
    for (let i = 0; i < paths.length; i++) {
      try {
        const raw: string = await this.readFile(paths[i])
        if (!raw || raw.length === 0) {
          continue
        }
        const trimmed = raw.trim()
        const match = trimmed.match(/(\d+)/)
        if (match && match[1]) {
          const val: number = parseInt(match[1], 10)
          if (!isNaN(val) && val > 0) {
            return val > 200 ? val / 1000 : val
          }
        }
        const floatVal: number = parseFloat(trimmed)
        if (!isNaN(floatVal) && floatVal > 0) {
          return floatVal > 200 ? floatVal / 1000 : floatVal
        }
      } catch (e) {
      }
    }
    return 0
  }

  getCPUUsage(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getCPUUsage', {})
  }

  getOnlineUsers(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getOnlineUsers', {})
  }

  getTempInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getTempInfo', {})
  }

  getMountPoints(): Promise<Record<string, Object>[]> {
    return this.callUbus('luci', 'getMountPoints', {})
  }

  getRealtimeStats(params: Record<string, Object>): Promise<Record<string, Object>[]> {
    return this.callUbus('luci', 'getRealtimeStats', params)
  }

  getProcessList(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getProcessList', {})
  }

  getWirelessDevices(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci-rpc', 'getWirelessDevices', {})
  }

  async execCommand(command: string, params?: string[]): Promise<string> {
    const execObj: Record<string, Object> = {}
    execObj['command'] = command
    execObj['params'] = params || []
    const arr = await this.callUbus('file', 'exec', execObj)
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

  networkInterfaceDump(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.interface', 'dump', {})
  }

  networkDeviceStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.device', 'status', {})
  }

  getLanStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.interface.lan', 'status', {})
  }

  iwinfoAssoclist(ifname: string): Promise<Record<string, Object>> {
    const iwinfoParams: Record<string, Object> = {}
    iwinfoParams['device'] = ifname
    return this.callUbusFirst('iwinfo', 'assoclist', iwinfoParams)
  }

  rcList(): Promise<Record<string, Object>> {
    return this.callUbusFirst('rc', 'list', {})
  }

  async hostapdDelClient(ifname: string, mac: string): Promise<boolean> {
    const delParams: Record<string, Object> = {}
    delParams['addr'] = mac
    const arr: Record<string, Object>[] = await this.callUbus('hostapd.' + ifname, 'del_client', delParams)
    return arr.length > 0
  }

  getOafStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_oaf_status', {})
  }

  getAppFilterBase(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_base', {})
  }

  async setAppFilterBase(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_base', params)
    return arr.length > 0
  }

  getAppFilterClassList(): Promise<Record<string, Object>[]> {
    return this.callUbus('appfilter', 'class_list', {})
  }

  getAppFilter(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter', {})
  }

  async setAppFilter(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter', params)
    return arr.length > 0
  }

  getAppFilterTime(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_time', {})
  }

  async setAppFilterTime(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_time', params)
    return arr.length > 0
  }

  getAppFilterUser(): Promise<Record<string, Object>> {
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

  getAppFilterAdv(): Promise<Record<string, Object>> {
    return this.callUbusFirst('appfilter', 'get_app_filter_adv', {})
  }

  async setAppFilterAdv(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'set_app_filter_adv', params)
    return arr.length > 0
  }

  getAllOafUsers(): Promise<Record<string, Object>[]> {
    const oafParams: Record<string, Object> = {}
    oafParams['flag'] = 3
    return this.callUbus('appfilter', 'get_all_users', oafParams)
  }

  devVisitTime(mac: string): Promise<Record<string, Object>[]> {
    const devVisitTimeParams: Record<string, Object> = {}
    devVisitTimeParams['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_time', devVisitTimeParams)
  }

  devVisitList(mac: string): Promise<Record<string, Object>[]> {
    const devVisitListParams: Record<string, Object> = {}
    devVisitListParams['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_list', devVisitListParams)
  }

  private async httpGet(path: string): Promise<Record<string, Object>> {
    const url: string = `${this.baseUrl}${path}`
    const hdr: Record<string, string> = {}
    if (this.authCookie) {
      hdr['Cookie'] = this.authCookie
    }
    const req = http.createHttp()
    try {
      const r = await req.request(url, {
        method: http.RequestMethod.GET,
        header: hdr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 10000
      })
      req.destroy()
      if (r.result && (r.result as string).length > 5) {
        try {
          return JSON.parse(r.result as string) as Record<string, Object>
        } catch (parseErr) {
          hilog.warn(DOMAIN, TAG, `HTTP GET ${path} parse error: ${parseErr}`)
        }
      }
    } catch (e) {
      req.destroy()
      hilog.warn(DOMAIN, TAG, `HTTP GET ${path} err: ${e}`)
    }
    throw new Error(`HTTP GET ${path} failed`)
  }

  private parseIstoreResult(raw: Record<string, Object>): Record<string, Object> {
    const result: Object | undefined = raw['result']
    if (result !== undefined && result !== null) {
      return result as Record<string, Object>
    }
    const data: Object | undefined = raw['data']
    if (data !== undefined && data !== null) {
      return data as Record<string, Object>
    }
    return raw
  }

  async getIstoreSystemStatus(): Promise<Record<string, Object>> {
    try {
      const raw: Record<string, Object> = await this.httpGet('/cgi-bin/luci/istore/system/status/')
      return this.parseIstoreResult(raw)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getIstoreSystemStatus err, fallback to ubus')
    }
    const result: Record<string, Object> = {}
    const info: Record<string, Object> = await this.callUbusFirst('system', 'info', {})
    if (info) {
      result['uptime'] = Number(info['uptime']) || 0
      result['localtime'] = info['localtime'] || ''
      const loadArr: Object | undefined = info['load']
      if (Array.isArray(loadArr)) {
        result['cpuUsage'] = Math.min(100, Math.max(0, (Number((loadArr as Object[])[0]) / 65536) * 100))
      } else {
        result['cpuUsage'] = 0
      }
      const mem: Object | undefined = info['memory']
      if (mem && typeof mem === 'object') {
        result['memTotal'] = String((mem as Record<string, Object>)['total'] || '')
        result['memAvailable'] = String((mem as Record<string, Object>)['free'] || '')
        result['memAvailablePercentage'] = 0
      }
    }
    result['cpuTemperature'] = -1
    return result
  }

  async getIstoreCPUTemperature(): Promise<number> {
    try {
      const raw: Record<string, Object> = await this.httpGet('/cgi-bin/luci/istore/system/status/')
      const result: Record<string, Object> = this.parseIstoreResult(raw)
      hilog.info(DOMAIN, TAG, `getIstoreCPUTemperature: result keys: ${Object.keys(result).join(', ')}`)
      
      const val: Object = result['cpuTemperature']
      if (val !== undefined && val !== null) {
        const temp: number = Number(val)
        hilog.info(DOMAIN, TAG, `getIstoreCPUTemperature: cpuTemperature=${val}, parsed=${temp}`)
        if (!isNaN(temp) && temp >= 0) {
          return temp
        }
      } else {
        hilog.warn(DOMAIN, TAG, 'getIstoreCPUTemperature: cpuTemperature is undefined or null')
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `getIstoreCPUTemperature err: ${e}, fallback to file read`)
    }
    const fileTemp = await this.getCPUTemp()
    hilog.info(DOMAIN, TAG, `getIstoreCPUTemperature: file temp fallback result=${fileTemp}`)
    return fileTemp
  }

  async getIstoreNetworkStatus(): Promise<Record<string, Object>> {
    try {
      const raw: Record<string, Object> = await this.httpGet('/cgi-bin/luci/istore/u/network/status/')
      return this.parseIstoreResult(raw)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getIstoreNetworkStatus err, fallback to ubus')
    }
    const lanStatus: Record<string, Object> = await this.callUbusFirst('network.interface.lan', 'status', {})
    const result: Record<string, Object> = {}
    result['proto'] = ''
    result['ipv4addr'] = ''
    result['ipv4mask'] = 24
    result['gateway'] = ''
    result['dnsList'] = []
    result['interface'] = ''
    if (lanStatus) {
      result['proto'] = lanStatus['proto'] || ''
      const ipv4Arr: Object | undefined = lanStatus['ipv4_address']
      if (Array.isArray(ipv4Arr) && (ipv4Arr as Object[]).length > 0) {
        const addr: Record<string, Object> = (ipv4Arr as Object[])[0] as Record<string, Object>
        result['ipv4addr'] = addr['address'] || ''
        result['ipv4mask'] = Number(addr['mask']) || 24
      }
      result['gateway'] = lanStatus['ipv4_gateway'] || ''
      const dnsArr: Object | undefined = lanStatus['dns_server']
      if (Array.isArray(dnsArr)) {
        const arr: Object[] = dnsArr as Object[]
        const dns: string[] = []
        if (arr.length > 0) dns.push(String(arr[0]))
        if (arr.length > 1) dns.push(String(arr[1]))
        result['dnsList'] = dns
      }
      result['interface'] = lanStatus['device'] || lanStatus['l3_device'] || ''
    }
    return result
  }

  async getIstoreSystemVersion(): Promise<Record<string, Object>> {
    try {
      const raw: Record<string, Object> = await this.httpGet('/cgi-bin/luci/istore/u/system/version/')
      return this.parseIstoreResult(raw)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getIstoreSystemVersion err, fallback to ubus')
    }
    const board: Record<string, Object> = await this.callUbusFirst('system', 'board', {})
    const result: Record<string, Object> = {}
    result['model'] = ''
    result['arch'] = ''
    result['target'] = ''
    result['version'] = ''
    result['kernel'] = ''
    if (board) {
      result['hostname'] = board['hostname'] || ''
      result['model'] = board['system'] || ''
      result['arch'] = board['model'] || ''
      result['kernel'] = board['kernel'] || ''
      const release: Object | undefined = board['release']
      if (release && typeof release === 'object') {
        const rel: Record<string, Object> = release as Record<string, Object>
        result['arch'] = rel['model'] || board['model'] || ''
        result['target'] = rel['target'] || ''
        result['version'] = rel['description'] || rel['version'] || ''
      }
    }
    return result
  }

  async getIstoreNetworkStatistics(): Promise<Record<string, Object>> {
    try {
      const raw: Record<string, Object> = await this.httpGet('/cgi-bin/luci/istore/u/network/statistics/')
      return this.parseIstoreResult(raw)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getIstoreNetworkStatistics err')
    }
    return {}
  }
}
