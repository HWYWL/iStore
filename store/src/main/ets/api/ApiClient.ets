import { http } from '@kit.NetworkKit'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'iStoreApi'
const DOMAIN = 0x0001

// ==================== 常量 ====================

/** 初始会话ID，用于 UBUS login 调用 */
const UBUS_INITIAL_SID: string = '00000000000000000000000000000000'

/** UBUS JSON-RPC 端点候选列表（按优先级降序） */
const UBUS_PATHS: string[] = [
  '/ubus',
  '/cgi-bin/luci/admin/ubus/',
  '/cgi-bin/luci/ubus/'
]

/** UBUS 通用错误码 */
const UBUS_STATUS_OK: number = 0
const UBUS_STATUS_INVALID_COMMAND: number = 1
const UBUS_STATUS_INVALID_ARGUMENT: number = 2
const UBUS_STATUS_METHOD_NOT_FOUND: number = 3
const UBUS_STATUS_NOT_FOUND: number = 4
const UBUS_STATUS_NO_DATA: number = 5
/** 会话超时/无效 — 需重新登录 */
const UBUS_STATUS_ACCESS_DENIED: number = 6
const UBUS_STATUS_TIMEOUT: number = 7
const UBUS_STATUS_NOT_SUPPORTED: number = 8
const UBUS_STATUS_UNKNOWN_ERROR: number = 9
const UBUS_STATUS_CONNECTION_FAILED: number = 10

/** 最大自动重登录次数，防止死循环 */
const MAX_RELOGIN_RETRIES: number = 1

// ==================== 类型定义 ====================

/** UBUS JSON-RPC 原始响应 */
interface UbusRpcResponse {
  jsonrpc: string
  id?: number
  result?: Object
  error?: Object
}

/** UBUS call 结果元组 [code, data] */
type UbusCallResult = [number, Object]

// ==================== ApiClient 核心实现 ====================

/**
 * 统一 UBUS API 客户端
 * 所有路由器通信通过 POST JSON-RPC 2.0 协议完成。
 *
 * 关键设计：
 * - 多路径回退登录（/ubus → /cgi-bin/luci/admin/ubus/ → /cgi-bin/luci/ubus/）
 * - 错误码 6（会话超时）自动重登录并重试请求
 * - 重登录期间并发请求排队等待
 */
export class ApiClient {
  baseUrl: string = ''
  username: string = ''
  password: string = ''
  connected: boolean = false
  lastError: string = ''

  private sessionId: string = ''
  private ubusPath: string = ''
  private rpcId: number = 1

  /** 登录阶段捕获的具体错误信息（供 connect() 使用） */
  private loginErrorDetail: string = ''

  /** 已探测可用的 UBUS 命名空间，用于功能降级 */
  capabilities: Record<string, boolean> = {}

  /** 是否正在执行重登录（避免并发重复登录） */
  private reloginInProgress: boolean = false
  /** 重登录等待队列 */
  private reloginWaiters: Array<() => void> = []

  private static instance: ApiClient

  static getInstance(): ApiClient {
    if (!ApiClient.instance) {
      ApiClient.instance = new ApiClient()
    }
    return ApiClient.instance
  }

  // ==================== 连接管理 ====================

  configure(config: ConnectionConfig): void {
    let host: string = config.host.trim()
    host = host.replace(/^https?:\/\//, '')
    host = host.replace(/\/$/, '').replace(/\/.*$/, '')
    this.baseUrl = `${config.useHttps ? 'https' : 'http'}://${host}:${config.port}`
    this.username = config.username
    this.password = config.password
    this.lastError = ''
    this.connected = false
    this.sessionId = ''
    this.ubusPath = ''
    this.rpcId = 1
    this.reloginInProgress = false
    this.reloginWaiters = []
    this.capabilities = {}
    hilog.info(DOMAIN, TAG, `Configured: ${this.baseUrl}`)
  }

  getConnected(): boolean {
    return this.connected
  }

  /**
   * 连接设备：依次尝试各 UBUS 路径进行登录，成功则验证会话
   */
  async connect(): Promise<boolean> {
    this.lastError = ''
    this.connected = false
    this.sessionId = ''
    this.ubusPath = ''
    this.reloginInProgress = false
    this.reloginWaiters = []
    this.loginErrorDetail = ''

    // 多路径登录尝试
    let lastErr: string = ''
    let lastDetailErr: string = ''
    for (const path of UBUS_PATHS) {
      if (await this.tryLogin(path)) {
        hilog.info(DOMAIN, TAG, `UBUS login OK via path: ${path}`)
        lastDetailErr = ''
        break
      }
      // 区分：UBUS 业务错误 vs 网络不通
      if (this.loginErrorDetail) {
        lastDetailErr = this.loginErrorDetail
      } else {
        lastErr = `UBUS 路径 ${path} 不可用`
      }
    }

    if (!this.sessionId) {
      // 优先展示具体的业务错误（如密码错误、权限拒绝），其次才是路径不可达
      if (lastDetailErr) {
        this.lastError = lastDetailErr
      } else {
        this.lastError = lastErr || '登录失败，请检查用户名和密码'
      }
      return false
    }

    // 验证会话有效性
    if (!await this.verifySession()) {
      this.lastError = '会话验证失败，请确认设备支持 OpenWrt UBUS'
      return false
    }

    this.connected = true
    // 探测设备支持的 UBUS 命名空间，用于后续功能降级
    await this.probeCapabilities()
    hilog.info(DOMAIN, TAG, `Connected via UBUS (${this.ubusPath})`)
    return true
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  // ==================== 登录 ====================

  /**
   * 在指定端点尝试 UBUS 会话登录
   */
  private async tryLogin(ubusEndpoint: string): Promise<boolean> {
    const loginObj: Record<string, Object> = {}
    loginObj['username'] = this.username
    loginObj['password'] = this.password

    const paramsArr: Object[] = [UBUS_INITIAL_SID, 'session', 'login', loginObj]

    const body: string = JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'call',
      params: paramsArr
    })

    try {
      const resp: Record<string, Object> | null = await this.rawPost(body, ubusEndpoint)
      if (!resp || typeof resp !== 'object') {
        this.loginErrorDetail = `设备 ${this.baseUrl} 无响应，请检查地址和端口`
        return false
      }

      const resArr: Object[] | undefined = resp['result'] as Object[] | undefined
      if (!resArr || !Array.isArray(resArr) || resArr.length < 2) {
        this.loginErrorDetail = `设备响应格式异常，可能不支持 UBUS 协议`
        return false
      }

      const code: number = Number(resArr[0])
      if (code !== 0) {
        const errMsg: string = LoginErrorMessages.get(String(code)) ||
          `UBUS 错误码 ${code}`
        this.loginErrorDetail = errMsg
        hilog.error(DOMAIN, TAG, `Login (${ubusEndpoint}): ${errMsg}`)
        return false
      }

      const data: Record<string, Object> = resArr[1] as Record<string, Object>
      if (!data) {
        this.loginErrorDetail = '登录响应数据为空，请重试'
        return false
      }

      const sid: string | undefined = data['ubus_rpc_session'] as string | undefined
      if (!sid) {
        this.loginErrorDetail = '未能获取会话令牌，请检查用户名和密码'
        return false
      }

      this.sessionId = sid
      this.ubusPath = ubusEndpoint
      this.loginErrorDetail = ''
      hilog.info(DOMAIN, TAG, `UBUS session: ${sid.substring(0, 12)}...`)
      return true
    } catch (e) {
      this.loginErrorDetail = `无法连接 ${this.baseUrl}${ubusEndpoint}，请检查网络和地址`
      return false
    }
  }

  /**
   * 重登录：仅用于会话过期后的自动恢复
   * 使用已确认为可用的 ubusPath，跳过路径探测
   */
  private async relogin(): Promise<boolean> {
    const path: string = this.ubusPath
    if (!path || !this.username || !this.password) {
      hilog.error(DOMAIN, TAG, 'relogin: no path or credentials')
      return false
    }

    this.sessionId = ''
    const ok: boolean = await this.tryLogin(path)
    if (ok) {
      hilog.info(DOMAIN, TAG, 'Auto re-login OK')
    } else {
      this.connected = false
      this.lastError = '会话过期，重新登录失败'
      hilog.error(DOMAIN, TAG, 'Auto re-login failed')
    }
    return ok
  }

  /**
   * 等待重登录完成（供并发请求使用）
   */
  private async waitForRelogin(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.reloginWaiters.push(() => {
        resolve(this.sessionId.length > 0)
      })
    })
  }

  /**
   * 通知所有等待者重登录已完成
   */
  private notifyReloginWaiters(): void {
    const waiters: Array<() => void> = this.reloginWaiters
    this.reloginWaiters = []
    for (const resolve of waiters) {
      try { resolve() } catch (e) {}
    }
  }

  /**
   * 验证会话 — 调用 system.board（标准 OpenWrt），失败则回退到 rc.list
   * QWRT / ImmortalWrt 等衍生版本可能不授权 system 命名空间，但通常开放 rc.list
   */
  private async verifySession(): Promise<boolean> {
    try {
      const board: Record<string, Object> = await this.getSystemBoard()
      if (board && typeof board === 'object' && board['hostname']) {
        hilog.info(DOMAIN, TAG, 'Session verified via system.board')
        return true
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `verifySession via system.board: ${String(e)}`)
    }

    // Fallback: rc.list（QWRT / ImmortalWrt 等衍生版本通常开放此权限）
    try {
      const rcList: Record<string, Object> = await this.rcList()
      if (rcList && typeof rcList === 'object' && Object.keys(rcList).length > 0) {
        hilog.info(DOMAIN, TAG, 'Session verified via rc.list')
        return true
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `verifySession via rc.list: ${String(e)}`)
    }

    return false
  }

  /**
   * 探测设备支持的 UBUS 命名空间，用于后续功能降级
   * 根据探测结果决定使用哪些 API 路径获取数据
   */
  private async probeCapabilities(): Promise<void> {
    this.capabilities = {}

    // 探测 luci-rpc（用于 DHCP 租约、无线设备等）
    try {
      const result: [number, Object | null] =
        await this.execUbusCall('luci-rpc', 'getDHCPLeases', {})
      this.capabilities['luci-rpc'] = (result[0] === UBUS_STATUS_OK)
    } catch (e) {
      this.capabilities['luci-rpc'] = false
    }

    // 探测 luci（用于挂载点、进程列表、实时流量等）
    try {
      const result: [number, Object | null] =
        await this.execUbusCall('luci', 'getMountPoints', {})
      this.capabilities['luci'] = (result[0] === UBUS_STATUS_OK)
    } catch (e) {
      this.capabilities['luci'] = false
    }

    // 探测 file（用于文件读取和命令执行）
    try {
      const fileParams: Record<string, Object> = {}
      fileParams['path'] = '/etc/openwrt_release'
      const result: [number, Object | null] =
        await this.execUbusCall('file', 'read', fileParams)
      this.capabilities['file'] = (result[0] === UBUS_STATUS_OK)
    } catch (e) {
      this.capabilities['file'] = false
    }

    // 探测 appfilter（iStoreOS 特有，用于应用过滤/家长控制）
    try {
      const result: [number, Object | null] =
        await this.execUbusCall('appfilter', 'get_oaf_status', {})
      this.capabilities['appfilter'] = (result[0] === UBUS_STATUS_OK)
    } catch (e) {
      this.capabilities['appfilter'] = false
    }

    hilog.info(DOMAIN, TAG,
      `Capabilities: luci-rpc=${this.capabilities['luci-rpc']}, ` +
      `luci=${this.capabilities['luci']}, file=${this.capabilities['file']}, ` +
      `appfilter=${this.capabilities['appfilter']}`)
  }

  /**
   * 检查指定命名空间是否可用
   */
  hasCapability(namespace: string): boolean {
    return this.capabilities[namespace] === true
  }

  // ==================== 底层通信 ====================

  /**
   * 发送 HTTP POST 到指定 UBUS 端点，返回解析后的 JSON 对象
   */
  private async rawPost(body: string, pathOverride?: string): Promise<Record<string, Object> | null> {
    const path: string = pathOverride || this.ubusPath
    const url: string = `${this.baseUrl}${path}`
    const req: http.HttpRequest = http.createHttp()

    try {
      const r: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 10000
      })
      req.destroy()

      const respBody: string = (r.result as string) || ''
      if (r.responseCode >= 200 && r.responseCode < 500 && respBody.length > 5) {
        return JSON.parse(respBody) as Record<string, Object>
      }
      hilog.warn(DOMAIN, TAG, `rawPost: HTTP ${r.responseCode}, body len=${respBody.length}`)
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `rawPost exception: ${String(e)}`)
    }
    return null
  }

  /**
   * 执行一次 UBUS调用，返回 [code, data] 元组
   * 不做重登录处理，由上层 callUbus / callUbusFirst 统一处理
   */
  private async execUbusCall(
    namespace: string,
    procedure: string,
    params: Record<string, Object>
  ): Promise<[number, Object | null]> {
    const body: string = JSON.stringify({
      jsonrpc: '2.0',
      id: this.rpcId++,
      method: 'call',
      params: [this.sessionId, namespace, procedure, params || {}]
    })

    try {
      const resp: Record<string, Object> | null = await this.rawPost(body)
      if (!resp || typeof resp !== 'object') {
        return [-1, null]
      }

      const result: Object | undefined = resp['result']
      if (result === undefined || result === null) {
        return [-1, null]
      }

      if (Array.isArray(result) && result.length >= 2) {
        const code: number = typeof result[0] === 'number' ? result[0] as number : Number(result[0])
        return [code, result[1]]
      }

      return [-1, null]
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ubus ${namespace}.${procedure} exception: ${String(e)}`)
      return [-1, null]
    }
  }

  /**
   * 带自动重登录的 UBUS 调用
   * 发生错误码 6（会话超时）时自动重登录并重试一次
   */
  private async ubusCallInternal(
    namespace: string,
    procedure: string,
    params: Record<string, Object>
  ): Promise<[number, Object | null]> {
    // 首次尝试
    let result: [number, Object | null] = await this.execUbusCall(namespace, procedure, params)
    let code: number = result[0]
    let data: Object | null = result[1]

    if (code !== UBUS_STATUS_ACCESS_DENIED) {
      return [code, data]
    }

    // === 会话超时，需要重登录 ===

    // 如果已有其他请求正在重登录，等待其完成
    if (this.reloginInProgress) {
      hilog.info(DOMAIN, TAG, `Waiting for in-progress relogin...`)
      const ok: boolean = await this.waitForRelogin()
      if (!ok) {
        return [UBUS_STATUS_ACCESS_DENIED, null]
      }
      // 重试
      result = await this.execUbusCall(namespace, procedure, params)
      return [result[0], result[1]]
    }

    // 亲自执行重登录
    this.reloginInProgress = true
    try {
      const ok: boolean = await this.relogin()
      this.reloginInProgress = false
      this.notifyReloginWaiters()

      if (!ok) {
        return [UBUS_STATUS_ACCESS_DENIED, null]
      }
      // 重试
      result = await this.execUbusCall(namespace, procedure, params)
      return [result[0], result[1]]
    } catch (e) {
      this.reloginInProgress = false
      this.notifyReloginWaiters()
      return [UBUS_STATUS_ACCESS_DENIED, null]
    }
  }

  // ==================== 公开 UBUS 调用接口 ====================

  /**
   * 调用 UBUS 方法，返回结果数组
   * 自动处理错误码 6（会话超时 → 重登录 → 重试）
   */
  async callUbus(
    namespace: string,
    procedure: string,
    params: Record<string, Object>
  ): Promise<Record<string, Object>[]> {
    const result: [number, Object | null] = await this.ubusCallInternal(namespace, procedure, params)
    const code: number = result[0]
    const data: Object | null = result[1]

    if (code === UBUS_STATUS_OK) {
      if (data && typeof data === 'object') {
        return [data as Record<string, Object>]
      }
      return []
    }

    if (code === UBUS_STATUS_ACCESS_DENIED) {
      this.lastError = `会话过期，请重新连接`
      hilog.error(DOMAIN, TAG, `ubus ${namespace}.${procedure}: session expired after relogin`)
      return []
    }

    // 其他错误码：同时记录 lastError 供 UI 展示
    const errMsg: string = UbusErrorMessages.get(String(code)) ||
      `错误码 ${code}`
    this.lastError = `调用 ${namespace}.${procedure} 失败：${errMsg}`
    hilog.warn(DOMAIN, TAG, `ubus ${namespace}.${procedure}: ${errMsg}`)
    return []
  }

  /**
   * callUbus 的便捷封装，直接返回第一个结果对象
   */
  async callUbusFirst(
    namespace: string,
    procedure: string,
    params: Record<string, Object>
  ): Promise<Record<string, Object>> {
    const arr: Record<string, Object>[] = await this.callUbus(namespace, procedure, params)
    if (arr.length > 0 && typeof arr[0] === 'object' && arr[0] !== null) {
      return arr[0] as Record<string, Object>
    }
    return {}
  }

  // ==================== system ====================

  getSystemBoard(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'board', {})
  }

  getSystemInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('system', 'info', {})
  }

  async systemReboot(): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('system', 'reboot', {})
    return arr.length > 0
  }

  // ==================== luci / luci-rpc ====================

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

  getWirelessDevices(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci-rpc', 'getWirelessDevices', {})
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

  getTempInfo(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getTempInfo', {})
  }

  getCPUUsage(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getCPUUsage', {})
  }

  getOnlineUsers(): Promise<Record<string, Object>> {
    return this.callUbusFirst('luci', 'getOnlineUsers', {})
  }

  // ==================== network ====================

  networkInterfaceDump(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.interface', 'dump', {})
  }

  networkDeviceStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.device', 'status', {})
  }

  getLanStatus(): Promise<Record<string, Object>> {
    return this.callUbusFirst('network.interface.lan', 'status', {})
  }

  // ==================== file ====================

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

  async execCommand(command: string, params?: string[]): Promise<string> {
    const execObj: Record<string, Object> = {}
    execObj['command'] = command
    execObj['params'] = params || []
    const arr: Record<string, Object>[] = await this.callUbus('file', 'exec', execObj)
    if (arr.length > 0) {
      const container: Record<string, Object> = arr[0] as Record<string, Object>
      if (container) {
        const codeVal: Object | undefined = container['code']
        const code: number = codeVal !== undefined ? Number(codeVal) : -1
        if (code === 0) {
          const stdout: string | undefined = container['stdout'] as string | undefined
          if (stdout) {
            return stdout
          }
        }
      }
    }
    return ''
  }

  // ==================== 温度 ====================

  async getCPUTemp(): Promise<number> {
    // 先尝试 UBUS luci.getTempInfo
    try {
      const tempInfo: Record<string, Object> = await this.getTempInfo()
      const raw: string = this.extractStr(tempInfo, 'tempinfo', '')
      if (raw) {
        const match: RegExpMatchArray | null = raw.match(/CPU:\s*([\d.]+)/i)
        if (match && match[1]) {
          const parsed: number = parseFloat(match[1])
          if (parsed > 0 && parsed < 150) {
            return parsed
          }
        }
        const numMatch: RegExpMatchArray | null = raw.match(/([\d.]+)/)
        if (numMatch && numMatch[1]) {
          const parsed: number = parseFloat(numMatch[1])
          if (parsed > 0 && parsed < 150) {
            return parsed
          }
        }
      }
    } catch (e) {
      // 继续尝试文件读取
    }

    // 降级到文件读取
    const thermalPaths: string[] = [
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

    for (let i = 0; i < thermalPaths.length; i++) {
      try {
        const raw: string = await this.readFile(thermalPaths[i])
        if (!raw || raw.length === 0) {
          continue
        }
        const trimmed: string = raw.trim()
        const match: RegExpMatchArray | null = trimmed.match(/(\d+)/)
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
        // 继续下一个路径
      }
    }
    return 0
  }

  // ==================== wireless ====================

  iwinfoAssoclist(ifname: string): Promise<Record<string, Object>> {
    const iwinfoParams: Record<string, Object> = {}
    iwinfoParams['device'] = ifname
    return this.callUbusFirst('iwinfo', 'assoclist', iwinfoParams)
  }

  async hostapdDelClient(ifname: string, mac: string): Promise<boolean> {
    const delParams: Record<string, Object> = {}
    delParams['addr'] = mac
    const arr: Record<string, Object>[] = await this.callUbus('hostapd.' + ifname, 'del_client', delParams)
    return arr.length > 0
  }

  // ==================== rc ====================

  rcList(): Promise<Record<string, Object>> {
    return this.callUbusFirst('rc', 'list', {})
  }

  // ==================== appfilter ====================

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

  async delAppFilterUser(params: Record<string, Object>): Promise<boolean> {
    const arr: Record<string, Object>[] = await this.callUbus('appfilter', 'del_app_filter_user', params)
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
    return this.callUbus('appfilter', 'get_all_oaf_users', {})
  }

  devVisitTime(mac: string): Promise<Record<string, Object>[]> {
    const params: Record<string, Object> = {}
    params['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_time', params)
  }

  devVisitList(mac: string): Promise<Record<string, Object>[]> {
    const params: Record<string, Object> = {}
    params['mac'] = mac
    return this.callUbus('appfilter', 'dev_visit_list', params)
  }

  // ==================== 工具方法 ====================

  private extractStr(obj: Record<string, Object>, key: string, def: string): string {
    if (!obj || typeof obj !== 'object') {
      return def
    }
    const v: Object = obj[key]
    if (v === undefined || v === null) {
      return def
    }
    return String(v)
  }
}

/** UBUS 通用错误码描述映射（供日志和 UI 使用） */
const UbusErrorMessages: Map<string, string> = new Map([
  ['0', '成功'],
  ['1', '无效的命令'],
  ['2', '无效的参数'],
  ['3', '方法未找到'],
  ['4', '对象未找到'],
  ['5', '无数据'],
  ['6', '权限被拒绝（会话过期或密码错误）'],
  ['7', '请求超时'],
  ['8', '不支持的操作'],
  ['9', '未知错误'],
  ['10', '连接失败']
])

/** 登录阶段的错误码描述映射 — 针对用户更友好的提示 */
const LoginErrorMessages: Map<string, string> = new Map([
  ['0', '登录成功'],
  ['1', '无效的登录命令，设备可能不支持 UBUS 协议'],
  ['2', '登录参数无效，请检查用户名格式'],
  ['3', '登录方法未找到，请确认设备为 OpenWrt 系统'],
  ['4', '会话对象未找到，设备可能已重启'],
  ['5', '登录响应无数据，请重试'],
  ['6', '用户名或密码错误，请重新输入'],
  ['7', '登录请求超时，请检查网络连接'],
  ['8', '设备不支持该登录方式'],
  ['9', '登录时发生未知错误，请重试'],
  ['10', '无法连接到设备，请检查 IP 地址和端口']
])
