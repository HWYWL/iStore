/**
 * API 客户端（单例）
 * 负责与路由器的底层 HTTP 通信，提供各类数据的底层请求方法
 *
 * 架构说明：
 * - ApiClient：底层 HTTP 通信层（本文件）
 * - ApiService：业务逻辑层，调用 ApiClient 并解析数据为 Models 类型
 *
 * 连接模式（connect 时自动选择）：
 * 1. ubus 模式（推荐）：使用 LuCI 自带的 /ubus JSON-RPC 接口，
 *    通过账号密码登录获取会话，无需在路由器上安装任何脚本。
 *    所有 OpenWrt 衍生版（iStoreOS / ImmortalWrt / QWRT / LEDE 等）
 *    只要带有 LuCI 网页管理界面即原生支持。
 * 2. legacy 模式（兼容）：使用旧版 router-api CGI 脚本 + Token，
 *    仅用于兼容已保存的旧设备，新设备不再使用。
 */
import { http } from '@kit.NetworkKit'
import { ConnectionConfig, DhcpBindingInfo, GuestWifiInfo } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SshService } from '../common/ssh/SshService'
import { SavedDevice } from '../common/store/DeviceStore'
import { AppState } from '../common/store/AppState'
import { ApiUtils } from './ApiUtils'


const TAG = 'iStoreApi'
const DOMAIN = 0x0001

// ========== 统一请求超时（毫秒） ==========
/** 建连超时：局域网内 5s 足够，避免弱网下长时间卡住 */
const CONNECT_TIMEOUT_MS = 5000
/** 普通读请求超时 */
const READ_TIMEOUT_MS = 10000
/** 重请求超时（LuCI 页面渲染、Docker 统计等） */
const READ_TIMEOUT_LONG_MS = 15000
/** 只读请求传输失败后的重试退避 */
const RETRY_BACKOFF_MS = 250

/** ubus 未登录时使用的空会话 ID */
const NULL_SESSION = '00000000000000000000000000000000'

/**
 * 路由器 API 标准响应格式
 */
class RouterApiResponse {
  code: number = 0       // 0 表示成功
  message: string = ''   // 响应消息
  msg: string = ''       // 兼容 msg 字段
  data: Object = new EmptyRecord()  // 响应数据
  rates: Object = new EmptyRecord() // 网速速率（network_interfaces 返回）
}

/**
 * 空对象占位符，用于无数据时的默认返回值
 */
class EmptyRecord {
}

// ========== ubus JSON-RPC 请求参数类型（ArkTS 要求显式声明） ==========

class RpcRequest {
  jsonrpc: string = '2.0'
  id: number = 1
  method: string = 'call'
  params: Object[] = []
}

class LoginParams {
  username: string = ''
  password: string = ''
}

class DeviceParam {
  device: string = ''
}

class FileReadParam {
  path: string = ''
}

class FileExecParam {
  command: string = ''
  params: string[] = []
}

class UciGetParam {
  config: string = ''
  section: string = ''
  option: string = ''
}

class RcInitParam {
  name: string = ''
  action: string = ''
}

class ServiceListParam {
  name: string = ''
}

class VerboseParam {
  verbose: boolean = true
}

// ========== OAF 应用过滤写操作参数（appfilter set_* 接口） ==========

/** uci add/delete 参数 */
class UciSectionParam {
  config: string = ''
  section: string = ''
}

/** network.wireless reload 参数 */
class WirelessReloadParam {
  rollback: boolean = false
}

/** hostapd 踢客户端参数 */
class DelClientParam {
  mac: string = ''
}

/** AppFilterBaseSetParam 前补：uci 通用单值 set 参数 */

/** set_app_filter_base 参数 */
class AppFilterBaseSetParam {
  enable: number = 0
  work_mode: number = 0
  record_enable: number = 0
  disable_quic: number = 0
  app_filter_mode: number = 0
}

/** set_app_filter 参数（管控应用 ID 列表） */
class AppFilterSetParam {
  app_list: number[] = []
}

/** 时间段条目 {start, end}（HH:MM 字符串） */
class AppFilterTimeItemParam {
  start: string = ''
  end: string = ''
}

/** set_app_filter_time 参数 */
class AppFilterTimeSetParam {
  mode: number = 0              // 0=固定时段 1=动态时长
  weekday_list: number[] = []
  time_list: AppFilterTimeItemParam[] = []
  deny_time: number = 0
  allow_time: number = 0
  start_time: string = ''
  end_time: string = ''
}

/** set_app_filter_user 参数（user_mode） */
class AppFilterUserSetParam {
  mode: number = 0
}

/** set_app_filter_adv 参数 */
class AppFilterAdvSetParam {
  tcp_rst: number = 0
  lan_ifname: string = ''
  disable_hnat: number = 0
  auto_load_engine: number = 0
}

/** get_all_users / dev_visit_list 分页参数 */
class UsersPageParam {
  flag: number = 3
  page: number = 1
  page_size: number = 50
}

/** MAC 查询参数 */
class MacParam {
  mac: string = ''
}

class UciSetParam {
  config: string = ''
  section: string = ''
  values: Object = new Object()
}

/** uci add <config> <type>：添加匿名 section */
class UciAddParam {
  config: string = ''
  type: string = ''
}

/** uci delete <config>.<section>：删除 section */
class UciDeleteParam {
  config: string = ''
  section: string = ''
}

/** uci rename <config>.<section> <value>：给匿名 section 命名 */
class UciRenameParam {
  config: string = ''
  section: string = ''
  value: string = ''
}

class UciApplyParam {
  rollback: boolean = false
}

class DockerHostsValues {
  hosts: string[] = []
}

/**
 * LuCI 网页通道 HTTP 结果
 */
class LuciHttpResult {
  status: number = 0   // HTTP 状态码（0 = 网络错误）
  body: string = ''    // 响应体（HTML 或 JSON 文本）
}

/** dockerman 容器行解析结果 */
class DockerRow {
  fullId: string = ''
  shortId: string = ''
  name: string = ''
  image: string = ''
  status: string = ''
  command: string = ''
  running: boolean = false
}

/**
 * JSON-RPC 底层响应
 */
class RpcResponse {
  transportOk: boolean = false  // HTTP 200 且 JSON 解析成功
  httpCode: number = 0
  hasError: boolean = false     // 存在 JSON-RPC error 对象
  errorCode: number = 0
  errorMessage: string = ''
  result: Object = new EmptyRecord() // result 原始内容（数组或对象）
}

/** 连接模式 */
type ConnMode = 'none' | 'ubus' | 'legacy'

export class ApiClient {
  baseUrl: string = ''       // API 基础 URL（协议://主机:端口）
  token: string = ''         // 认证令牌（legacy 模式）
  connected: boolean = false // 连接状态
  lastError: string = ''     // 最近一次错误信息

  // ========== 连接配置 ==========
  private username: string = ''
  private password: string = ''
  private ubusUrl: string = ''    // /ubus JSON-RPC 地址
  private legacyUrl: string = ''  // /cgi-bin/router-api 地址（旧脚本）

  // ========== ubus 会话状态 ==========
  private mode: ConnMode = 'none'
  private sessionId: string = ''
  private sessionExpireAt: number = 0
  private loginInFlight: Promise<boolean> | null = null  // 登录互斥锁，防止并发重复登录
  private ubusMissing: boolean = false                   // /ubus 接口不存在（非 LuCI 设备）

  // ========== LuCI 网页通道状态（补充 ubus ACL 之外的能力：iStore 应用、Docker 容器） ==========
  private luciCookie: string = ''                        // sysauth_http 会话 Cookie
  private luciLoginInFlight: Promise<boolean> | null = null
  private dockerIdMap: Map<string, string> = new Map()   // 容器名/短ID -> 完整ID（用于操作）
  private dockerApiBase: string = ''                     // Docker Remote API 根地址（探测成功才设置）
  private iStoreStatusCache: Object | null = null        // quickstart 系统状态缓存（温度/CPU 真实值）
  private iStoreStatusTime: number = 0

  // ========== 网速统计快照（用于差值计算实时速率） ==========
  private prevDevStats: Map<string, number[]> = new Map()
  private prevStatsTime: number = 0
  private ratesInFlight: Promise<Object[]> | null = null // 速率采样互斥锁
  private boardCache: Object | null = null               // system board 缓存
  private rpcId: number = 1

  // ========== 单例模式 ==========
  private static instance: ApiClient

  static getInstance(): ApiClient {
    if (!ApiClient.instance) {
      ApiClient.instance = new ApiClient()
    }
    return ApiClient.instance
  }

  /**
   * 配置连接参数
   * @param config 连接配置（host, port, token, username, password, useHttps）
   */
  configure(config: ConnectionConfig): void {
    const protocol: string = config.useHttps ? 'https' : 'http'
    this.baseUrl = `${protocol}://${config.host}:${config.port}`
    this.ubusUrl = `${this.baseUrl}/ubus`
    this.legacyUrl = `${this.baseUrl}/cgi-bin/router-api`
    this.token = config.token
    this.username = config.username ? config.username : ''
    this.password = config.password ? config.password : ''
    this.mode = 'none'
    this.connected = false
    this.lastError = ''
    this.sessionId = ''
    this.sessionExpireAt = 0
    this.ubusMissing = false
    this.prevDevStats.clear()
    this.prevStatsTime = 0
    this.boardCache = null
    this.luciCookie = ''
    this.dockerIdMap.clear()
    this.dockerApiBase = ''
    this.iStoreStatusCache = null
    this.iStoreStatusTime = 0
  }

  /**
   * 建立连接：
   * 1. 有用户名时优先尝试 ubus 账号密码登录（无需脚本）
   * 2. ubus 不可用且有 Token 时，回退到旧版 router-api 脚本模式
   * @returns 连接是否成功
   */
  async connect(): Promise<boolean> {
    // 1. 优先 ubus 模式（账号密码登录）
    if (this.username) {
      const loginOk: boolean = await this.ensureSession(true)
      if (loginOk) {
        // 验证会话权限：调用 system board
        const board: Object | null = await this.ubusCall('system', 'board', new EmptyRecord())
        if (board) {
          this.mode = 'ubus'
          this.connected = true
          this.lastError = ''
          this.boardCache = board
          // 后台异步建立 LuCI 通道 + 探测 Docker API，不阻塞登录流程
          this.ensureLuciCookie(true)
          this.probeDockerApi()
          return true
        }
        // system board 被拒 → 尝试 QWRT 自动授权（crontab 注入 ACL 文件）
        if (this.luciCookie || await this.ensureLuciCookie(true)) {
          if (await this.qwrtAutoFix()) {
            // 授权成功，重新 ubus 登录并验证
            const reloginOk: boolean = await this.ensureSession(true)
            if (reloginOk) {
              const board2: Object | null = await this.ubusCall('system', 'board', new EmptyRecord())
              if (board2) {
                this.mode = 'ubus'
                this.connected = true
                this.lastError = ''
                this.boardCache = board2
                this.probeDockerApi()
                return true
              }
            }
          }
        }
        this.lastError = '登录成功，但设备 API 权限受限：路由器的 rpcd 未授权 LuCI 基础接口（QWRT 等定制固件需在 /usr/share/rpcd/acl.d/ 添加授权文件）'
        return false
      }
      // ubus 接口存在但登录失败（密码错误等）→ 直接失败，不回退
      if (!this.ubusMissing) {
        return false
      }
      // /ubus 不存在（非 LuCI 设备）→ 尝试 legacy 模式
    }

    // 2. legacy 模式（旧 Token + router-api 脚本）
    if (this.token) {
      const legacyOk: boolean = await this.legacyConnect()
      if (legacyOk) {
        this.mode = 'legacy'
        this.connected = true
        this.lastError = ''
        return true
      }
      return false
    }

    if (this.ubusMissing) {
      this.lastError = '该设备未安装 LuCI 管理界面，无法使用账号密码登录'
    } else if (!this.username) {
      this.lastError = '请输入用户名和密码'
    }
    return false
  }

  // ============================================================
  //  ubus JSON-RPC 通信
  // ============================================================

  /**
   * 发送 JSON-RPC 请求（POST）
   */
  private async jsonRpc(url: string, method: string, params: Object[]): Promise<RpcResponse> {
    const resp: RpcResponse = new RpcResponse()
    const body: RpcRequest = new RpcRequest()
    body.id = this.rpcId++
    body.method = method
    body.params = params
    const bodyStr: string = JSON.stringify(body)

    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: bodyStr,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      })
      resp.httpCode = r.responseCode
      if (r.responseCode === 200) {
        const resultData = r.result
        const text: string = (typeof resultData === 'string') ? resultData : JSON.stringify(resultData)
        const parsed = JSON.parse(text) as Record<string, Object>
        const errObj = parsed['error']
        if (errObj && typeof errObj === 'object') {
          resp.hasError = true
          resp.errorCode = ApiUtils.numOf(errObj, 'code', 0)
          resp.errorMessage = ApiUtils.strOf(errObj, 'message')
        }
        const resultVal = parsed['result']
        if (resultVal !== undefined && resultVal !== null) {
          resp.result = resultVal as Object
        }
        resp.transportOk = true
      }
      req.destroy()
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `jsonRpc error: ${e}`)
    }
    return resp
  }

  /**
   * 执行 ubus 登录，获取会话 ID
   */
  private async doUbusLogin(): Promise<boolean> {
    const params: LoginParams = new LoginParams()
    params.username = this.username
    params.password = this.password
    const res: RpcResponse = await this.jsonRpc(this.ubusUrl, 'call',
      [NULL_SESSION, 'session', 'login', params])

    if (!res.transportOk) {
      if (res.httpCode === 404) {
        // /ubus 路径不存在 = 非 LuCI 设备
        this.ubusMissing = true
        this.lastError = '该设备未安装 LuCI 管理界面，无法使用账号密码登录'
      } else {
        // httpCode 0 = 网络错误（设备离线/地址错误/超时）
        this.lastError = '无法连接到设备，请检查网络和地址'
      }
      return false
    }
    this.ubusMissing = false

    if (res.hasError) {
      this.lastError = '登录请求被拒绝，请确认设备支持 LuCI 网页管理'
      return false
    }

    // result 格式：[ubus状态码, 数据]
    const arr = res.result
    if (!Array.isArray(arr) || arr.length < 1) {
      this.lastError = '登录响应格式异常'
      return false
    }
    const code: number = Number(arr[0])
    if (code === 0 && arr.length >= 2) {
      const data = arr[1] as Record<string, Object>
      const sid = data['ubus_rpc_session']
      this.sessionId = (typeof sid === 'string') ? sid : ''
      const timeoutSec: number = ApiUtils.numOf(data, 'timeout', 300)
      // 预留 30 秒余量，会话为滑动过期（每次调用自动续期）
      this.sessionExpireAt = Date.now() + Math.max(timeoutSec - 30, 30) * 1000
      if (!this.sessionId) {
        this.lastError = '登录响应缺少会话标识'
        return false
      }
      return true
    }

    // ubus 错误码：5=用户不存在 6=密码错误/权限拒绝
    if (code === 6) {
      this.lastError = '用户名或密码错误'
    } else if (code === 5 || code === 4) {
      this.lastError = '用户不存在或登录参数错误'
    } else {
      this.lastError = `登录失败（错误码 ${code}）`
    }
    return false
  }

  /**
   * 确保 ubus 会话有效（带互斥锁，避免并发重复登录）
   * @param force 是否强制重新登录
   */
  private async ensureSession(force: boolean = false): Promise<boolean> {
    if (!force && this.sessionId && Date.now() < this.sessionExpireAt) {
      return true
    }
    if (this.loginInFlight) {
      return this.loginInFlight
    }
    this.loginInFlight = this.doUbusLogin()
    const ok: boolean = await this.loginInFlight
    this.loginInFlight = null
    return ok
  }

  /**
   * 调用 ubus 对象方法
   * @returns 成功时返回数据对象，失败返回 null（失败原因写入 lastError）
   *
   * 统一失败处理：
   * - 传输失败（超时/断网）：只对只读请求做一次短退避重试，避免写操作重复执行
   * - 会话失效（-32002/-32004）：重登后重试一次
   * - 其它 RPC 错误 / 非零 ubus 状态码：翻译成用户可读文案写入 lastError
   */
  private async ubusCall(obj: string, method: string, params: Object, allowRetry: boolean = true): Promise<Object | null> {
    const loggedIn: boolean = await this.ensureSession()
    if (!loggedIn) {
      return null
    }
    let res: RpcResponse = await this.jsonRpc(this.ubusUrl, 'call', [this.sessionId, obj, method, params])

    if (!res.transportOk && allowRetry && ApiClient.isReadonlyCall(method)) {
      await ApiClient.sleep(RETRY_BACKOFF_MS)
      res = await this.jsonRpc(this.ubusUrl, 'call', [this.sessionId, obj, method, params])
    }

    if (!res.transportOk) {
      this.lastError = ApiClient.describeTransport(res.httpCode)
      hilog.warn(DOMAIN, TAG, `ubus ${obj}.${method} transport fail http=${res.httpCode} -> ${this.lastError}`)
      return null
    }
    if (res.hasError) {
      // -32002/-32004：会话无效或访问被拒（会话过期）→ 重新登录后重试一次
      if (allowRetry && (res.errorCode === -32002 || res.errorCode === -32004)) {
        this.sessionId = ''
        this.sessionExpireAt = 0
        const reloginOk: boolean = await this.ensureSession(true)
        if (reloginOk) {
          return this.ubusCall(obj, method, params, false)
        }
      }
      this.lastError = ApiClient.describeRpcError(res.errorCode)
      hilog.warn(DOMAIN, TAG, `ubus ${obj}.${method} rpc error ${res.errorCode}: ${res.errorMessage}`)
      return null
    }

    const arr = res.result
    if (Array.isArray(arr) && arr.length >= 1) {
      const code: number = Number(arr[0])
      if (code === 0) {
        if (arr.length >= 2 && arr[1] !== null && typeof arr[1] === 'object') {
          return arr[1] as Object
        }
        // 无数据但调用成功（如 reboot / rc init）
        return new EmptyRecord()
      }
      this.lastError = `设备拒绝该操作（状态码 ${code}），可能是权限不足或接口不支持`
      hilog.warn(DOMAIN, TAG, `ubus ${obj}.${method} status ${code}`)
    } else {
      this.lastError = '设备返回数据格式异常'
      hilog.warn(DOMAIN, TAG, `ubus ${obj}.${method} empty result`)
    }
    return null
  }

  /** 只读方法判定：仅这类请求允许在传输失败后自动重试，防止写操作被执行两次 */
  private static isReadonlyCall(method: string): boolean {
    const m: string = method.toLowerCase()
    return m.startsWith('get') || m.startsWith('info') || m.startsWith('dump') ||
      m.startsWith('list') || m.startsWith('status') || m.startsWith('board') ||
      m.startsWith('read') || m.startsWith('assoclist') || m === 'login'
  }

  /** 传输层失败 → 用户可读文案 */
  private static describeTransport(httpCode: number): string {
    if (httpCode === 401) {
      return '认证失败：账号或密码不正确'
    }
    if (httpCode === 403) {
      return '权限被拒绝：路由器 rpcd 未授权该接口'
    }
    if (httpCode === 404) {
      return '接口不存在：该设备可能未启用 LuCI 管理界面'
    }
    if (httpCode >= 500) {
      return `路由器内部错误（HTTP ${httpCode}）`
    }
    if (httpCode > 0) {
      return `请求失败（HTTP ${httpCode}）`
    }
    return '设备无响应：请检查设备是否在线、管理地址是否正确'
  }

  /** ubus RPC 错误码 → 用户可读文案 */
  private static describeRpcError(code: number): string {
    if (code === -32002 || code === -32004) {
      return '登录会话已失效，请重新连接设备'
    }
    if (code === -32601) {
      return '该设备不支持此接口（方法不存在）'
    }
    if (code === -32602) {
      return '请求参数不被设备接受'
    }
    return `设备返回错误（RPC ${code}）`
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  /**
   * 列出 ubus 对象（用于 WiFi 设备发现等），返回对象名列表
   */
  private async ubusList(pattern: string): Promise<string[]> {
    const names: string[] = []
    const loggedIn: boolean = await this.ensureSession()
    if (!loggedIn) {
      return names
    }
    const res: RpcResponse = await this.jsonRpc(this.ubusUrl, 'list', [this.sessionId, pattern])
    if (!res.transportOk || res.hasError) {
      return names
    }
    const result = res.result as Record<string, Object>
    const keys = Object.keys(result)
    for (let i = 0; i < keys.length; i++) {
      names.push(keys[i])
    }
    return names
  }

  /** 读取路由器文件内容（受 LuCI 文件 ACL 限制） */
  private async ubusReadFile(path: string): Promise<string> {
    const p: FileReadParam = new FileReadParam()
    p.path = path
    const data: Object | null = await this.ubusCall('file', 'read', p)
    if (data) {
      return ApiUtils.strOf(data, 'data')
    }
    return ''
  }

  /** 在路由器上执行命令（受 LuCI 命令 ACL 限制） */
  private async ubusExec(command: string, args: string[]): Promise<string> {
    const p: FileExecParam = new FileExecParam()
    p.command = command
    p.params = args
    const data: Object | null = await this.ubusCall('file', 'exec', p)
    if (data) {
      return ApiUtils.strOf(data, 'stdout')
    }
    return ''
  }

  // ============================================================
  //  LuCI 网页通道（表单登录 + Cookie）
  //  用于获取 ubus ACL 之外的数据：iStore 应用列表、Docker 容器等
  // ============================================================

  /**
   * LuCI 表单登录，获取 sysauth_http Cookie
   */
  private async doLuciFormLogin(): Promise<boolean> {
    this.luciCookie = ''
    const body: string =
      `luci_username=${encodeURIComponent(this.username)}&luci_password=${encodeURIComponent(this.password)}`
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}/cgi-bin/luci/`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      })
      // 登录成功：302 跳转（或直接 200），从 Set-Cookie 中提取 sysauth* 值
      const cookie: string = ApiClient.extractSysauthCookie(r.header)
      req.destroy()
      if (cookie) {
        this.luciCookie = cookie
        return true
      }
      return false
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `luciFormLogin error: ${e}`)
      return false
    }
  }

  /**
   * 从响应头中提取 sysauth Cookie（兼容 sysauth / sysauth_http，大小写不敏感）
   */
  private static extractSysauthCookie(header: Object): string {
    if (!header || typeof header !== 'object') {
      return ''
    }
    const rec = header as Record<string, Object>
    const keys = Object.keys(rec)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== 'set-cookie') {
        continue
      }
      const raw = rec[keys[i]]
      const parts: string[] = []
      if (Array.isArray(raw)) {
        for (let j = 0; j < raw.length; j++) {
          parts.push(String(raw[j]))
        }
      } else if (raw !== undefined && raw !== null) {
        parts.push(String(raw))
      }
      for (let j = 0; j < parts.length; j++) {
        const m = parts[j].match(/(sysauth[_a-z]*)=([0-9a-fA-F]+)/)
        if (m && m[2]) {
          return `${m[1]}=${m[2]}`
        }
      }
    }
    return ''
  }

  /**
   * 确保 LuCI Cookie 有效（带互斥锁）
   */
  private async ensureLuciCookie(force: boolean = false): Promise<boolean> {
    if (!force && this.luciCookie) {
      return true
    }
    if (this.luciLoginInFlight) {
      return this.luciLoginInFlight
    }
    this.luciLoginInFlight = this.doLuciFormLogin()
    const ok: boolean = await this.luciLoginInFlight
    this.luciLoginInFlight = null
    return ok
  }

  /**
   * LuCI 网页 GET 请求（自动带 Cookie，403 时自动重新登录重试一次）
   */
  private async luciGet(path: string, allowRetry: boolean = true): Promise<LuciHttpResult> {
    const ok: boolean = await this.ensureLuciCookie()
    if (!ok) {
      return new LuciHttpResult()
    }
    const res: LuciHttpResult = await this.luciHttp('GET', path, '')
    if ((res.status === 401 || res.status === 403) && allowRetry) {
      const reOk: boolean = await this.ensureLuciCookie(true)
      if (reOk) {
        return this.luciGet(path, false)
      }
      return new LuciHttpResult()
    }
    return res
  }

  /**
   * LuCI 网页表单 POST（自动带 Cookie，403 时自动重新登录重试一次）
   */
  private async luciPostForm(path: string, encodedBody: string, allowRetry: boolean = true): Promise<LuciHttpResult> {
    const ok: boolean = await this.ensureLuciCookie()
    if (!ok) {
      return new LuciHttpResult()
    }
    const res: LuciHttpResult = await this.luciHttp('POST', path, encodedBody)
    if ((res.status === 401 || res.status === 403) && allowRetry) {
      const reOk: boolean = await this.ensureLuciCookie(true)
      if (reOk) {
        return this.luciPostForm(path, encodedBody, false)
      }
      return new LuciHttpResult()
    }
    return res
  }

  /**
   * LuCI 网页底层请求
   */
  private async luciHttp(method: string, path: string, encodedBody: string): Promise<LuciHttpResult> {
    const result: LuciHttpResult = new LuciHttpResult()
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}/cgi-bin/luci/${path}`, {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: {
          'Cookie': this.luciCookie,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        extraData: method === 'POST' ? encodedBody : undefined,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_LONG_MS
      })
      result.status = r.responseCode
      const data = r.result
      if (typeof data === 'string') {
        result.body = data
      } else if (data !== undefined && data !== null) {
        result.body = JSON.stringify(data)
      }
      req.destroy()
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `luciHttp ${method} ${path} error: ${e}`)
    }
    return result
  }

  // ============================================================
  //  Docker Remote API 通道（tcp 2375，官方接口：容器/统计/操作）
  // ============================================================

  /** Docker API 根地址（http(s)://host:2375） */
  private dockerApiRoot(): string {
    const protoSplit: string[] = this.baseUrl.split('://')
    const proto: string = protoSplit.length > 0 ? protoSplit[0] : 'http'
    const hostPort: string = protoSplit.length > 1 ? protoSplit[1] : ''
    const host: string = hostPort.split(':')[0]
    return `${proto}://${host}:2375`
  }

  /** 探测 Docker Remote API 是否可用 */
  private async probeDockerApi(): Promise<void> {
    this.dockerApiBase = ''
    const root: string = this.dockerApiRoot()
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${root}/info`, {
        method: http.RequestMethod.GET,
        connectTimeout: 2500,
        readTimeout: 4000
      })
      req.destroy()
      if (r.responseCode === 200) {
        this.dockerApiBase = root
      }
    } catch (e) {
      req.destroy()
    }
  }

  /** Docker API 是否可用 */
  hasDockerApi(): boolean {
    return this.dockerApiBase !== ''
  }

  /**
   * 开启 Docker Remote API（uci 配置 hosts + 应用 + 重启 dockerd）
   * 注意：会导致运行中的容器短暂停止重启
   */
  async enableDockerApi(): Promise<boolean> {
    if (this.mode !== 'ubus') {
      return false
    }
    const hosts: DockerHostsValues = new DockerHostsValues()
    hosts.hosts = ['unix:///var/run/docker.sock', 'tcp://0.0.0.0:2375']
    const setP: UciSetParam = new UciSetParam()
    setP.config = 'dockerd'
    setP.section = 'globals'
    setP.values = hosts as Object
    const setOk: Object | null = await this.ubusCall('uci', 'set', setP)
    if (setOk === null) {
      return false
    }
    const applyP: UciApplyParam = new UciApplyParam()
    applyP.rollback = false
    const applyOk: Object | null = await this.ubusCall('uci', 'apply', applyP)
    if (applyOk === null) {
      return false
    }
    const rcP: RcInitParam = new RcInitParam()
    rcP.name = 'dockerd'
    rcP.action = 'restart'
    const rcOk: Object | null = await this.ubusCall('rc', 'init', rcP)
    if (rcOk === null) {
      return false
    }
    // 等待 dockerd 完成重启后再探测
    await ApiUtils.sleep(10000)
    await this.probeDockerApi()
    return this.dockerApiBase !== ''
  }

  /** Docker API GET，返回解析后的 JSON（失败 null） */
  private async dockerApiGet(path: string, timeout: number = 8000): Promise<Object | null> {
    if (!this.dockerApiBase) {
      return null
    }
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.dockerApiBase}${path}`, {
        method: http.RequestMethod.GET,
        connectTimeout: 4000,
        readTimeout: timeout
      })
      if (r.responseCode === 200) {
        const data = r.result
        const text: string = (typeof data === 'string') ? data : JSON.stringify(data)
        req.destroy()
        return JSON.parse(text) as Object
      }
      req.destroy()
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `dockerApiGet ${path} error: ${e}`)
    }
    return null
  }

  /** Docker API POST（无 body），返回是否成功（204/304/200 视为成功） */
  private async dockerApiPost(path: string): Promise<boolean> {
    if (!this.dockerApiBase) {
      return false
    }
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.dockerApiBase}${path}`, {
        method: http.RequestMethod.POST,
        connectTimeout: 4000,
        readTimeout: 15000
      })
      const code: number = r.responseCode
      req.destroy()
      return code === 204 || code === 304 || code === 200
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `dockerApiPost ${path} error: ${e}`)
    }
    return false
  }

  /** 经 Docker API 构建容器列表 */
  private async buildDockerContainersApi(): Promise<Object> {
    const list: Object[] = []
    const data: Object | null = await this.dockerApiGet('/containers/json?all=1')
    if (data && Array.isArray(data)) {
      const arr = data as Object[]
      for (let i = 0; i < arr.length; i++) {
        const c = arr[i] as Record<string, Object>
        if (!c || typeof c !== 'object') {
          continue
        }
        const id: string = ApiUtils.strOf(c, 'Id')
        let name: string = ''
        const names = c['Names']
        if (Array.isArray(names) && names.length > 0) {
          name = String(names[0]).replace(/^\//, '')
        }
        const item: Record<string, Object> = {}
        item['id'] = id.length > 12 ? id.substring(0, 12) : id
        item['name'] = name
        item['image'] = ApiUtils.strOf(c, 'Image')
        item['status'] = ApiUtils.strOf(c, 'Status')
        item['running'] = ApiUtils.strOf(c, 'State') === 'running'
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 经 Docker API 构建镜像列表 */
  private async buildDockerImagesApi(): Promise<Object> {
    const list: Object[] = []
    const data: Object | null = await this.dockerApiGet('/images/json')
    if (data && Array.isArray(data)) {
      const arr = data as Object[]
      for (let i = 0; i < arr.length; i++) {
        const im = arr[i] as Record<string, Object>
        if (!im || typeof im !== 'object') {
          continue
        }
        const id: string = ApiUtils.strOf(im, 'Id')
        let repoTag: string = '<none>:<none>'
        const tags = im['RepoTags']
        if (Array.isArray(tags) && tags.length > 0) {
          repoTag = String(tags[0])
        }
        const item: Record<string, Object> = {}
        item['id'] = id.length > 12 ? id.substring(7, 19) : id
        item['repoTag'] = repoTag
        item['size'] = ApiUtils.numOf(im, 'Size', 0)
        item['created'] = ApiUtils.numOf(im, 'Created', 0)
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 经 Docker API 构建网络列表 */
  private async buildDockerNetworksApi(): Promise<Object> {
    const list: Object[] = []
    const data: Object | null = await this.dockerApiGet('/networks')
    if (data && Array.isArray(data)) {
      const arr = data as Object[]
      for (let i = 0; i < arr.length; i++) {
        const nw = arr[i] as Record<string, Object>
        if (!nw || typeof nw !== 'object') {
          continue
        }
        const id: string = ApiUtils.strOf(nw, 'Id')
        const item: Record<string, Object> = {}
        item['id'] = id.length > 12 ? id.substring(0, 12) : id
        item['name'] = ApiUtils.strOf(nw, 'Name')
        item['driver'] = ApiUtils.strOf(nw, 'Driver')
        item['scope'] = ApiUtils.strOf(nw, 'Scope')
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 经 Docker API 构建容器实时统计（CPU%/内存，官方采样差值公式） */
  private async buildDockerStatsApi(): Promise<Object> {
    const list: Object[] = []
    const data: Object | null = await this.dockerApiGet('/containers/json')
    if (!data || !Array.isArray(data)) {
      return list as Object
    }
    const arr = data as Object[]
    const jobs: Promise<Object | null>[] = []
    for (let i = 0; i < arr.length; i++) {
      const c = arr[i] as Record<string, Object>
      const id: string = ApiUtils.strOf(c, 'Id')
      if (id) {
        jobs.push(this.fetchOneContainerStat(id))
      }
    }
    const results: (Object | null)[] = await Promise.all(jobs)
    for (let i = 0; i < results.length; i++) {
      if (results[i] !== null) {
        list.push(results[i] as Object)
      }
    }
    return list as Object
  }

  /** 获取单个容器统计并计算 CPU%/内存占比 */
  private async fetchOneContainerStat(id: string): Promise<Object | null> {
    const data: Object | null = await this.dockerApiGet(`/containers/${id}/stats?stream=false`, 10000)
    if (!data) {
      return null
    }
    const j = data as Record<string, Object>
    const cpuStats = j['cpu_stats'] as Record<string, Object>
    const preStats = j['precpu_stats'] as Record<string, Object>
    const memStats = j['memory_stats'] as Record<string, Object>
    if (!cpuStats || !preStats || !memStats) {
      return null
    }
    const curUsage = (cpuStats['cpu_usage'] as Record<string, Object>)
    const preUsage = (preStats['cpu_usage'] as Record<string, Object>)
    const cpuDelta: number = ApiUtils.numOf(curUsage, 'total_usage', 0) - ApiUtils.numOf(preUsage, 'total_usage', 0)
    const sysDelta: number = ApiUtils.numOf(cpuStats, 'system_cpu_usage', 0) - ApiUtils.numOf(preStats, 'system_cpu_usage', 0)
    const onlineCpus: number = ApiUtils.numOf(cpuStats, 'online_cpus', 0)
    let cpuPercent: number = 0
    if (sysDelta > 0 && cpuDelta >= 0 && onlineCpus > 0) {
      cpuPercent = (cpuDelta / sysDelta) * onlineCpus * 100
    }
    const memUsage: number = ApiUtils.numOf(memStats, 'usage', 0)
    const memLimit: number = ApiUtils.numOf(memStats, 'limit', 0)
    const memPercent: number = memLimit > 0 ? (memUsage / memLimit) * 100 : 0

    const item: Record<string, Object> = {}
    item['id'] = id.length > 12 ? id.substring(0, 12) : id
    item['name'] = ApiUtils.strOf(j, 'name').replace(/^\//, '')
    item['cpu_percent'] = Math.round(cpuPercent * 100) / 100
    item['mem_usage'] = `${ApiClient.fmtBytes(memUsage)} / ${ApiClient.fmtBytes(memLimit)}`
    item['mem_percent'] = Math.round(memPercent * 100) / 100
    return item as Object
  }

  /** 字节格式化（与 FormatUtils 一致的简版，避免通信层依赖 UI 工具） */
  private static fmtBytes(bytes: number): string {
    if (bytes <= 0 || isNaN(bytes)) {
      return '0 B'
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
    const base: number = 1024
    const i: number = Math.min(Math.floor(Math.log(bytes) / Math.log(base)), units.length - 1)
    return `${(bytes / Math.pow(base, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`
  }

  // ============================================================
  //  QWRT 自动授权（Rust SSH 写入 ACL 文件）
  // ============================================================

  /**
   * QWRT 自动授权：通过 Rust SSH（@ohos-rs/ssh）直接写入 ACL 文件并重启 rpcd
   * 纯异步，无回调，约 2~3 秒完成
   */
  private async qwrtAutoFix(): Promise<boolean> {
    this.lastError = 'QWRT 自动授权中…'
    // 复用 SshService（libssh2 会话）
    const sshSvc: SshService = SshService.getInstance()
    try {
      // 用当前登录设备的连接参数（不能用 activeDevice——登录失败时 activeDeviceId
      // 尚未更新到当前设备，会连错到旧设备！）
      const host: string = this.getConfigHost()
      if (!host || !this.username || !this.password) {
        this.lastError = '未配置设备 SSH 账号'
        return false
      }
      const device: SavedDevice = {
        id: '', label: host, host: host, port: '22', token: '',
        useHttps: false, lastConnected: 0, version: 0,
        username: this.username, password: this.password,
        favorite: false, group: ''
      }
      const connOk: boolean = await sshSvc.connect(device)
      if (!connOk) {
        this.lastError = 'SSH 密码认证失败'
        return false
      }

      const aclJson: string = ApiClient.getQwrtAclJson()
      const escaped: string = ApiClient.shellEscape(aclJson)
      // 写入 ACL + 回读验证 + 重启 rpcd（mkdir -p 保证目录存在）
      const cmd: string = `mkdir -p /usr/share/rpcd/acl.d && ` +
        `printf '%s' '${escaped}' > /usr/share/rpcd/acl.d/istore-app.json && ` +
        `cat /usr/share/rpcd/acl.d/istore-app.json > /dev/null && ` +
        `/etc/init.d/rpcd restart && echo FIX_OK`

      const result: string = await sshSvc.exec(cmd)
      sshSvc.disconnect()

      if (result.indexOf('FIX_OK') < 0) {
        this.lastError = `SSH 命令执行失败：${result.substring(0, 80)}`
        return false
      }

      // Verify ubus permissions
      await ApiUtils.sleep(2000)
      const reOk: boolean = await this.ensureSession(true)
      if (reOk) {
        const board: Object | null = await this.ubusCall('system', 'board', new EmptyRecord())
        if (board) {
          this.lastError = ''
          return true
        }
      }
      this.lastError = '授权文件已写入但会话验证失败'
      return false
    } catch (e) {
      hilog.error(DOMAIN, TAG, `qwrtAutoFix error: ${e}`)
      this.lastError = 'SSH 连接失败，请确认路由器已开启 SSH（端口 22）'
      return false
    }
  }

  /** 从 baseUrl 中提取主机名/IP */
  private getConfigHost(): string {
    const protoSplit: string[] = this.baseUrl.split('://')
    const hostPort: string = protoSplit.length > 1 ? protoSplit[1] : protoSplit[0]
    return hostPort.split(':')[0]
  }

  private static shellEscape(s: string): string {
    return (s.indexOf("'") >= 0) ? s.replace(/'/g, "'\\''") : s
  }

  /**
   * \u8fd4\u56de QWRT ACL \u6388\u6743 JSON \u7684\u7d27\u51d1\u5355\u884c\u5f62\u5f0f
   */
  private static getQwrtAclJson(): string {
    return '{"istore-app":{"description":"iStore App / LuCI base access","read":{"ubus":' +
      '{"system":["board","info"],"network.interface":["dump"],"network.device":["status"],' +
      '"network.wireless":["status"],"luci":["*"],"luci-rpc":["*"],"iwinfo":["*"],' +
      '"rc":["list"],"service":["list"],"session":["access","login"],' +
      '"file":["read","list","stat","md5"],"uci":["get","state","configs","changes"],' +
      '"dhcp":["ipv4leases","ipv6leases"],"hostapd.*":["del_client","wps_status"]},' +
      '"file":{"/proc/sys/net/netfilter/nf_conntrack_count":["read"],' +
      '"/proc/sys/net/netfilter/nf_conntrack_max":["read"],"/proc/mounts":["read"],' +
      '"/proc/net/dev":["read"],"/proc/meminfo":["read"],"/proc/cpuinfo":["read"],' +
      '"/proc/loadavg":["read"],"/proc/stat":["read"],"/tmp/dhcp.leases":["read"],' +
      '"/sys/class/thermal/*":["read"],"/etc/board.json":["read"]}},' +
      '"write":{"ubus":{"system":["reboot"],"rc":["list","init"],' +
      '"service":["list","state","signal","event"],' +
      '"uci":["get","state","configs","set","add","delete","rename","order","changes","apply","confirm","rollback","revert"],' +
      '"file":["read","write","list","stat","remove","exec"],"appfilter":["*"],' +
      '"luci":["setInitAction","setLocaltime","setPassword","setBlockDetect"]},' +
      '"uci":{"*":["read","write"]},"file":{"/etc/config/*":["read","write"],' +
      '"/sbin/reboot":["exec"],"/sbin/firstboot -r -y":["exec"],' +
      '"/sbin/ip -[46] route show table all":["exec"],' +
      '"/sbin/ip -[46] neigh show":["exec"],"/bin/df":["exec"],' +
      '"/bin/ps":["exec"],"/usr/bin/ps":["exec"]}}}}'
  }
// ============================================================
  //  统一 action 请求入口
  // ============================================================

  /**
   * 底层请求方法（保持原有 action 接口不变）
   * @param action API 操作名称（可附带 &key=value 参数）
   * @param device 可选设备参数（如网络接口名）
   * @returns 解析后的 API 响应，失败时返回 null
   */
  async request(action: string, device?: string): Promise<RouterApiResponse | null> {
    if (this.mode === 'legacy') {
      return this.legacyRequest(action, device)
    }
    if (this.mode === 'ubus') {
      return this.ubusRequest(action, device)
    }
    return null
  }

  /** 直接请求任意 action 并返回完整响应（含 rates 等扩展字段） */
  async requestDirect(action: string, device?: string): Promise<RouterApiResponse | null> {
    return this.request(action, device)
  }

  /**
   * ubus 模式：将旧 action 映射为 ubus 调用，返回与旧脚本一致的数据结构
   */
  private async ubusRequest(action: string, device?: string): Promise<RouterApiResponse | null> {
    // 解析 action 中附带的参数（如 docker_service&service_action=start）
    const parts: string[] = action.split('&')
    const base: string = parts[0]
    const kv: Map<string, string> = new Map()
    for (let i = 1; i < parts.length; i++) {
      const eq: number = parts[i].indexOf('=')
      if (eq > 0) {
        kv.set(parts[i].substring(0, eq), decodeURIComponent(parts[i].substring(eq + 1)))
      }
    }

    const resp: RouterApiResponse = new RouterApiResponse()

    switch (base) {
      case 'ping': {
        resp.code = 0
        return resp
      }

      case 'system_board': {
        const data: Object | null = await this.getBoard()
        if (data) {
          resp.code = 0
          resp.data = data
          return resp
        }
        return null
      }

      case 'system_info': {
        const info: Object | null = await this.ubusCall('system', 'info', new EmptyRecord())
        if (!info) {
          return null
        }
        resp.code = 0
        resp.data = this.buildSystemInfo(info, await this.getCpuUsage())
        return resp
      }

      case 'cpu_info': {
        const st: Object | null = await this.fetchIStoreSystemStatus()
        const board: Object | null = await this.getBoard()
        const data: Record<string, Object> = {}
        data['usage_percent'] = await this.getCpuUsage()
        data['model'] = board ? ApiUtils.strOf(board, 'system') : ''
        data['cores'] = 0
        // CPU 温度：quickstart 接口（iStoreOS）或 /sys/class/thermal（ACL 授权的系统）
        data['cpu_temp'] = st ? ApiUtils.numOf(st, 'cpuTemperature', 0) : await this.getThermalTemp()
        data['cpu_freq'] = await this.getCpuFreqMhz()
        resp.code = 0
        resp.data = data as Object
        return resp
      }

      case 'memory_info': {
        const info: Object | null = await this.ubusCall('system', 'info', new EmptyRecord())
        if (!info) {
          return null
        }
        const mem = (info as Record<string, Object>)['memory'] as Record<string, Object>
        const data: Record<string, Object> = {}
        if (mem) {
          data['total_kb'] = Math.floor(ApiUtils.numOf(mem, 'total', 0) / 1024)
          data['free_kb'] = Math.floor(ApiUtils.numOf(mem, 'free', 0) / 1024)
          data['available_kb'] = Math.floor(ApiUtils.numOf(mem, 'available', 0) / 1024)
          data['used_kb'] = Math.floor((ApiUtils.numOf(mem, 'total', 0) - ApiUtils.numOf(mem, 'available', 0)) / 1024)
          data['buffers_kb'] = Math.floor(ApiUtils.numOf(mem, 'buffered', 0) / 1024)
          data['cached_kb'] = Math.floor(ApiUtils.numOf(mem, 'cached', 0) / 1024)
        }
        resp.code = 0
        resp.data = data as Object
        return resp
      }

      case 'network_interfaces': {
        const dump: Object | null = await this.ubusCall('network.interface', 'dump', new EmptyRecord())
        const rates: Object[] = await this.sampleRates(dump)
        resp.code = 0
        resp.data = dump ? dump : new EmptyRecord()
        resp.rates = rates as Object
        return resp
      }

      case 'network_rates': {
        const rates: Object[] = await this.sampleRates(null)
        resp.code = 0
        resp.data = rates as Object
        return resp
      }

      case 'bandwidth': {
        const rates: Object[] = await this.sampleRates(null)
        const dev: string = device ? device : (kv.get('device') ? kv.get('device')! : '')
        let found: Object = new EmptyRecord()
        for (let i = 0; i < rates.length; i++) {
          if (ApiUtils.strOf(rates[i], 'iface') === dev) {
            found = rates[i]
            break
          }
        }
        resp.code = 0
        resp.data = found
        return resp
      }

      case 'network_devices': {
        const data: Object | null = await this.ubusCall('luci-rpc', 'getNetworkDevices', new EmptyRecord())
        if (data) {
          resp.code = 0
          resp.data = data
          return resp
        }
        return null
      }

      case 'network_wifi': {
        resp.code = 0
        resp.data = await this.buildWirelessData()
        return resp
      }

      case 'dhcp_leases': {
        const data: Object | null = await this.ubusCall('luci-rpc', 'getDHCPLeases', new EmptyRecord())
        resp.code = 0
        resp.data = data ? this.buildDhcpLeases(data) : await this.buildDhcpLeasesFromFile()
        return resp
      }

      case 'storage_info': {
        resp.code = 0
        resp.data = await this.buildStorageInfo()
        return resp
      }

      case 'processes': {
        resp.code = 0
        resp.data = await this.buildProcessList()
        return resp
      }

      case 'route_table': {
        resp.code = 0
        resp.data = await this.buildRouteTable()
        return resp
      }

      case 'startup_items': {
        const data: Object | null = await this.ubusCall('rc', 'list', new VerboseParam())
        resp.code = 0
        resp.data = data ? data : new EmptyRecord()
        return resp
      }

      case 'conntrack': {
        resp.code = 0
        resp.data = await this.buildConntrack()
        return resp
      }

      case 'uci_get': {
        const p: UciGetParam = new UciGetParam()
        p.config = kv.get('config') ? kv.get('config')! : ''
        p.section = kv.get('section') ? kv.get('section')! : ''
        p.option = kv.get('option') ? kv.get('option')! : ''
        const data: Object | null = await this.ubusCall('uci', 'get', p)
        resp.code = 0
        resp.data = data ? data : new EmptyRecord()
        return resp
      }

      case 'uci_get_all': {
        const p: UciGetParam = new UciGetParam()
        p.config = kv.get('config') ? kv.get('config')! : ''
        const data: Object | null = await this.ubusCall('uci', 'get', p)
        resp.code = 0
        resp.data = data ? data : new EmptyRecord()
        return resp
      }

      case 'reboot': {
        const ok: Object | null = await this.ubusCall('system', 'reboot', new EmptyRecord())
        resp.code = ok !== null ? 0 : 1
        resp.message = ok !== null ? 'reboot signal sent' : 'reboot failed'
        return resp
      }

      case 'factory_reset': {
        const out: string = await this.ubusExec('/sbin/firstboot', ['-r', '-y'])
        resp.code = 0
        resp.message = `factory reset initiated ${out}`
        return resp
      }

      // ========== 家长控制（OAF 应用过滤） ==========
      case 'oaf_status': {
        resp.code = 0
        resp.data = await this.unwrapOafData(await this.ubusCall('appfilter', 'get_oaf_status', new EmptyRecord()))
        return resp
      }
      case 'appfilter_base': {
        resp.code = 0
        resp.data = await this.unwrapOafData(await this.ubusCall('appfilter', 'get_app_filter_base', new EmptyRecord()))
        return resp
      }
      case 'appfilter_classes': {
        const data: Object | null = await this.ubusCall('appfilter', 'class_list', new EmptyRecord())
        resp.code = 0
        resp.data = data ? data : new EmptyRecord()
        return resp
      }
      case 'appfilter_time': {
        resp.code = 0
        resp.data = await this.unwrapOafData(await this.ubusCall('appfilter', 'get_app_filter_time', new EmptyRecord()))
        return resp
      }
      case 'appfilter_user': {
        resp.code = 0
        resp.data = await this.unwrapOafData(await this.ubusCall('appfilter', 'get_app_filter_user', new EmptyRecord()))
        return resp
      }
      case 'appfilter_adv': {
        resp.code = 0
        resp.data = await this.unwrapOafData(await this.ubusCall('appfilter', 'get_app_filter_adv', new EmptyRecord()))
        return resp
      }

      // ========== iStore 应用列表（经 LuCI 网页通道调 iStore 商店接口） ==========
      case 'istore_apps': {
        resp.code = 0
        resp.data = await this.buildIStoreApps()
        return resp
      }

      // ========== Docker（优先 Docker Remote API，降级 dockerman 页面/ubus） ==========
      case 'docker_overview': {
        resp.code = 0
        resp.data = await this.buildDockerOverview()
        return resp
      }
      case 'docker_service': {
        const p: RcInitParam = new RcInitParam()
        p.name = 'dockerd'
        p.action = kv.get('service_action') ? kv.get('service_action')! : 'restart'
        const ok: Object | null = await this.ubusCall('rc', 'init', p)
        resp.code = ok !== null ? 0 : 1
        resp.message = ok !== null ? 'Docker service signal sent' : 'operation not permitted'
        return resp
      }
      case 'docker_containers': {
        resp.code = 0
        resp.data = this.dockerApiBase ? await this.buildDockerContainersApi() : await this.buildDockerContainers()
        return resp
      }
      case 'docker_stats': {
        resp.code = 0
        // 统计仅 Docker API 可用（dockerman 统计在 cgroup v2 系统上已损坏）
        resp.data = this.dockerApiBase ? await this.buildDockerStatsApi() : [] as Object
        return resp
      }
      case 'docker_images': {
        resp.code = 0
        // 镜像列表仅 Docker API 可用
        resp.data = this.dockerApiBase ? await this.buildDockerImagesApi() : [] as Object
        return resp
      }
      case 'docker_networks': {
        resp.code = 0
        // 网络列表仅 Docker API 可用
        resp.data = this.dockerApiBase ? await this.buildDockerNetworksApi() : [] as Object
        return resp
      }
      case 'docker_container': {
        const cname: string = kv.get('container') ? kv.get('container')! : ''
        const caction: string = kv.get('container_action') ? kv.get('container_action')! : ''
        let ok: boolean = false
        if (this.dockerApiBase && (caction === 'start' || caction === 'stop' || caction === 'restart' || caction === 'kill')) {
          ok = await this.dockerApiPost(`/containers/${encodeURIComponent(cname)}/${caction}`)
        } else {
          ok = await this.dockerContainerActionViaLuci(cname, caction)
        }
        resp.code = ok ? 0 : 501
        resp.message = ok ? 'action sent' : '容器操作失败（设备无 dockerman 或不支持）'
        return resp
      }

      default: {
        resp.code = 404
        resp.message = `unknown action: ${base}`
        return resp
      }
    }
  }

  // ============================================================
  //  ubus 数据构建辅助
  // ============================================================

  /** 获取 system board（带缓存） */
  private async getBoard(): Promise<Object | null> {
    if (this.boardCache) {
      return this.boardCache
    }
    const data: Object | null = await this.ubusCall('system', 'board', new EmptyRecord())
    if (data) {
      this.boardCache = data
    }
    return data
  }

  /**
   * 构建与旧脚本一致的 system_info 数据结构
   * ubus system info 内存单位为字节（与 UI formatBytes 期望一致）
   */
  private buildSystemInfo(info: Object, cpuUsage: number): Object {
    const rec = info as Record<string, Object>
    const mem = rec['memory'] as Record<string, Object>
    const loadArr = rec['load']
    const data: Record<string, Object> = {}
    data['uptime'] = ApiUtils.numOf(rec, 'uptime', 0)
    data['localtime'] = ApiUtils.numOf(rec, 'localtime', 0)
    data['cpu_usage'] = cpuUsage

    // ubus load 为 65536 倍定点数，转换为常规负载值
    const loadOut: number[] = []
    if (Array.isArray(loadArr)) {
      for (let i = 0; i < loadArr.length; i++) {
        loadOut.push(Math.round(Number(loadArr[i]) / 65536 * 100) / 100)
      }
    }
    data['load'] = loadOut as Object

    const memOut: Record<string, Object> = {}
    if (mem) {
      memOut['total'] = ApiUtils.numOf(mem, 'total', 0)
      memOut['free'] = ApiUtils.numOf(mem, 'free', 0)
      memOut['available'] = ApiUtils.numOf(mem, 'available', 0)
      memOut['buffered'] = ApiUtils.numOf(mem, 'buffered', 0)
      memOut['buffers'] = ApiUtils.numOf(mem, 'buffered', 0)
      memOut['cached'] = ApiUtils.numOf(mem, 'cached', 0)
    }
    data['memory'] = memOut as Object

    if (rec['root']) {
      data['root'] = rec['root'] as Object
    }
    if (rec['tmp']) {
      data['tmp'] = rec['tmp'] as Object
    }
    return data as Object
  }

  /** 获取 CPU 使用率（三级降级：quickstart → 进程求和 → /proc/stat 差值） */
  private async getCpuUsage(): Promise<number> {
    const st: Object | null = await this.fetchIStoreSystemStatus()
    if (st) {
      return ApiUtils.numOf(st, 'cpuUsage', 0)
    }
    const fromProcs: number = await this.getCpuUsageFromProcs()
    if (fromProcs >= 0) {
      return fromProcs
    }
    return this.getCpuUsageFromProcStat()
  }

  /** 通过进程列表 %CPU 求和估算（luci getProcessList 不可用时返回 -1） */
  private async getCpuUsageFromProcs(): Promise<number> {
    const data: Object | null = await this.ubusCall('luci', 'getProcessList', new EmptyRecord())
    if (!data) {
      return -1
    }
    const procs = (data as Record<string, Object>)['result']
    if (!Array.isArray(procs)) {
      return -1
    }
    let total: number = 0
    for (let i = 0; i < procs.length; i++) {
      total += ApiUtils.percentOf(procs[i] as Record<string, Object>, '%CPU')
    }
    return Math.min(100, Math.round(total))
  }

  /** 通过 /proc/stat 两次采样差值计算 CPU 使用率（间隔 1 秒） */
  private async getCpuUsageFromProcStat(): Promise<number> {
    const s1: string = await this.ubusReadFile('/proc/stat')
    if (!s1) {
      return 0
    }
    await ApiUtils.sleep(1000)
    const s2: string = await this.ubusReadFile('/proc/stat')
    const a: number[] = ApiUtils.parseProcStatCpu(s1)
    const b: number[] = ApiUtils.parseProcStatCpu(s2)
    if (a.length === 0 || b.length === 0) {
      return 0
    }
    const deltaTotal: number = b[0] - a[0]
    const deltaIdle: number = b[1] - a[1]
    if (deltaTotal <= 0) {
      return 0
    }
    return Math.min(100, Math.round((deltaTotal - deltaIdle) * 100 / deltaTotal))
  }

  /** 读取 CPU 温度（/sys/class/thermal，受 ACL 授权限制） */
  private async getThermalTemp(): Promise<number> {
    const zones: string[] = ['thermal_zone0', 'thermal_zone1', 'thermal_zone2']
    for (let i = 0; i < zones.length; i++) {
      const raw: string = await this.ubusReadFile(`/sys/class/thermal/${zones[i]}/temp`)
      const milli: number = parseInt(raw.trim()) || 0
      if (milli > 0) {
        return Math.round(milli / 100) / 10
      }
    }
    return 0
  }

  /** CPU 当前频率（MHz）：cat scaling_cur_freq（kHz → MHz） */
  private cachedCpuFreq: number = 0
  private sshFreqTried: boolean = false
  private sshFreqFails: number = 0

  /** CPU 频率（MHz）：后台异步获取并缓存，首次调用立即返回 0（不阻塞首页加载） */
  private async getCpuFreqMhz(): Promise<number> {
    if (this.cachedCpuFreq > 0) {
      return this.cachedCpuFreq
    }
    if (!this.sshFreqTried && this.sshFreqFails < 3) {
      this.sshFreqTried = true
      this.fetchCpuFreqBackground()
    }
    return 0
  }

  private async fetchCpuFreqBackground(): Promise<void> {
    try {
      const ssh: SshService = SshService.getInstance()
      let out: string = ''
      if (ssh.isConnected()) {
        out = await ssh.exec('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')
      } else {
        const device: SavedDevice | undefined = AppState.getInstance().getActiveDevice()
        if (device && device.username && device.password) {
          const ok: boolean = await ssh.connect(device)
          if (ok) {
            out = await ssh.exec('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')
          }
        }
      }
      const khz: number = parseInt(SshService.cleanShellOut(out)) || 0
      if (khz > 0) {
        this.cachedCpuFreq = Math.round(khz / 1000)
        this.sshFreqFails = 0
        hilog.error(DOMAIN, TAG, `cpu_freq bg ok=${this.cachedCpuFreq} MHz`)
        return
      }
      hilog.error(DOMAIN, TAG, `cpu_freq bg out=[${out}]`)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `cpu_freq bg err: ${String(e)}`)
    }
    // 失败：下次轮询重试（最多 3 次）
    this.sshFreqTried = false
    this.sshFreqFails++
  }

  /**
   * 采样网络设备统计并计算实时速率（字节/秒）
   * 首次调用间隔 1 秒采样两次，之后与上次快照做差值
   * @param dump 可选的 network.interface dump，用于补充逻辑接口名别名
   */
  private async sampleRates(dump: Object | null): Promise<Object[]> {
    if (this.ratesInFlight) {
      return this.ratesInFlight
    }
    this.ratesInFlight = this.doSampleRates(dump)
    const result: Object[] = await this.ratesInFlight
    this.ratesInFlight = null
    return result
  }

  private async doSampleRates(dump: Object | null): Promise<Object[]> {
    const first: Map<string, number[]> = await this.fetchDevStats()
    if (this.prevDevStats.size === 0 || this.prevStatsTime === 0) {
      // 首次采样：等待 1 秒后再采一次
      this.prevDevStats = first
      this.prevStatsTime = Date.now()
      await ApiUtils.sleep(1000)
    }
    const second: Map<string, number[]> = await this.fetchDevStats()
    const now: number = Date.now()
    const elapsed: number = Math.max(now - this.prevStatsTime, 1)

    const rates: Object[] = []
    const prev = this.prevDevStats
    second.forEach((cur: number[], name: string) => {
      const old = prev.get(name)
      const rxRate: number = old ? Math.max(0, Math.floor((cur[0] - old[0]) * 1000 / elapsed)) : 0
      const txRate: number = old ? Math.max(0, Math.floor((cur[1] - old[1]) * 1000 / elapsed)) : 0
      const item: Record<string, Object> = {}
      item['iface'] = name
      item['rx_bytes'] = cur[0]
      item['tx_bytes'] = cur[1]
      item['rx_rate'] = rxRate
      item['tx_rate'] = txRate
      rates.push(item as Object)
    })

    // 为逻辑接口名（lan/wan）补充别名，方便上层按接口名合并速率
    if (dump) {
      const ifaces = (dump as Record<string, Object>)['interface']
      if (Array.isArray(ifaces)) {
        for (let i = 0; i < ifaces.length; i++) {
          const ifRec = ifaces[i] as Record<string, Object>
          const logical: string = ApiUtils.strOf(ifRec, 'interface')
          const devName: string = ApiUtils.strOf(ifRec, 'l3_device') || ApiUtils.strOf(ifRec, 'device')
          if (logical && devName && logical !== devName) {
            for (let j = 0; j < rates.length; j++) {
              if (ApiUtils.strOf(rates[j], 'iface') === devName) {
                const alias: Record<string, Object> = {}
                alias['iface'] = logical
                alias['rx_bytes'] = ApiUtils.numOf(rates[j], 'rx_bytes', 0)
                alias['tx_bytes'] = ApiUtils.numOf(rates[j], 'tx_bytes', 0)
                alias['rx_rate'] = ApiUtils.numOf(rates[j], 'rx_rate', 0)
                alias['tx_rate'] = ApiUtils.numOf(rates[j], 'tx_rate', 0)
                rates.push(alias as Object)
                break
              }
            }
          }
        }
      }
    }

    this.prevDevStats = second
    this.prevStatsTime = now
    return rates
  }

  /** 获取各网络设备的累计收发字节数（luci-rpc 优先，降级 /proc/net/dev） */
  private async fetchDevStats(): Promise<Map<string, number[]>> {
    const stats: Map<string, number[]> = new Map()
    const data: Object | null = await this.ubusCall('luci-rpc', 'getNetworkDevices', new EmptyRecord())
    if (data) {
      const rec = data as Record<string, Object>
      const names = Object.keys(rec)
      for (let i = 0; i < names.length; i++) {
        const dev = rec[names[i]] as Record<string, Object>
        if (!dev || typeof dev !== 'object') {
          continue
        }
        const st = dev['stats'] as Record<string, Object>
        if (!st || typeof st !== 'object') {
          continue
        }
        stats.set(names[i], [ApiUtils.numOf(st, 'rx_bytes', 0), ApiUtils.numOf(st, 'tx_bytes', 0)])
      }
    }
    if (stats.size > 0) {
      return stats
    }

    // 降级：解析 /proc/net/dev
    const text: string = await this.ubusReadFile('/proc/net/dev')
    if (text) {
      const lines: string[] = text.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const idx: number = lines[i].indexOf(':')
        if (idx < 0) {
          continue
        }
        const name: string = lines[i].substring(0, idx).trim()
        const nums: string[] = lines[i].substring(idx + 1).trim().split(/\s+/)
        if (name && nums.length >= 9) {
          const rx: number = parseInt(nums[0]) || 0
          const tx: number = parseInt(nums[8]) || 0
          stats.set(name, [rx, tx])
        }
      }
    }
    return stats
  }

  /** 获取 WAN 接口累计收发字节数（流量统计用，返回 [rx, tx]） */
  async getWanTrafficBytes(): Promise<number[]> {
    try {
      const stats: Map<string, number[]> = await this.fetchDevStats()
      if (stats.size === 0) return [0, 0]
      const names: string[] = Array.from(stats.keys())
      // 1. 优先 wan 类接口（wan / wan6 / pppoe-wan / wwan）；
      //    注意：逻辑接口 wan 的计数可能恒为 0，必须跳过，否则会一直返回 0 导致统计永远为空
      for (let i = 0; i < names.length; i++) {
        const n: string = names[i]
        const lower: string = n.toLowerCase()
        if (lower === 'wan' || lower.startsWith('wan') || lower.startsWith('pppoe') ||
          lower.startsWith('wwan')) {
          const v: number[] | undefined = stats.get(n)
          if (v && (v[0] > 0 || v[1] > 0)) {
            return [v[0], v[1]]
          }
        }
      }
      // 2. 回退：累计字节最大的非虚拟接口（排除 lo / 网桥 / 容器网卡）
      let best: number[] = [0, 0]
      let bestSum: number = 0
      for (let i = 0; i < names.length; i++) {
        const n: string = names[i]
        const lower: string = n.toLowerCase()
        if (n === 'lo' || lower.startsWith('br') || lower.startsWith('docker') ||
          lower.startsWith('veth') || lower.startsWith('tun') || lower.startsWith('tap')) {
          continue
        }
        const v: number[] | undefined = stats.get(n)
        if (!v) {
          continue
        }
        const sum: number = v[0] + v[1]
        if (sum > bestSum) {
          bestSum = sum
          best = v
        }
      }
      if (bestSum > 0) {
        return [best[0], best[1]]
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `getWanTrafficBytes err: ${JSON.stringify(e)}`)
    }
    return [0, 0]
  }

  /**
   * 构建无线网络数据（WiFi 接口及已连接客户端）
   * 无 WiFi 设备返回空结构
   */
  private async buildWirelessData(): Promise<Object> {
    const interfaces: Object[] = []
    const devices: Object[] = []

    // 0. 读取 wireless 配置，获取各无线接口的 disabled 状态（key 为 radio0 等接口名）
    const disabledMap: Map<string, boolean> = new Map()
    try {
      const wlCfgRaw: Object | null = await this.ubusCall('network.wireless', 'status', new EmptyRecord())
      if (wlCfgRaw) {
        let cfgRec = wlCfgRaw as Record<string, Object>
        // ubus 响应含 data 包装层
        const inner = cfgRec['data']
        if (inner && typeof inner === 'object') {
          cfgRec = inner as Record<string, Object>
        }
        const cfgKeys: string[] = Object.keys(cfgRec)
        for (let i = 0; i < cfgKeys.length; i++) {
          const ifaceRec = cfgRec[cfgKeys[i]] as Record<string, Object>
          if (!ifaceRec) continue
          const disabledVal = ifaceRec['disabled']
          const disabled: boolean = disabledVal === 1 || disabledVal === '1' ||
            disabledVal === true || disabledVal === 'true'
          disabledMap.set(cfgKeys[i], disabled)
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'buildWirelessData config err')
    }

    // 1. 收集候选无线设备名：hostapd.* ubus 对象
    const candidates: string[] = []
    const hostapd: string[] = await this.ubusList('hostapd.*')
    for (let i = 0; i < hostapd.length; i++) {
      const dev: string = hostapd[i].replace('hostapd.', '')
      if (dev && candidates.indexOf(dev) < 0) {
        candidates.push(dev)
      }
    }

    // 2. 补充候选：luci-rpc getWirelessDevices
    const wlDevs: Object | null = await this.ubusCall('luci-rpc', 'getWirelessDevices', new EmptyRecord())
    if (wlDevs) {
      const rec = wlDevs as Record<string, Object>
      const keys = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        if (candidates.indexOf(keys[i]) < 0) {
          candidates.push(keys[i])
        }
      }
    }

    // 3. 逐个设备获取信息与客户端列表
    for (let i = 0; i < candidates.length; i++) {
      const dev: string = candidates[i]
      const dp: DeviceParam = new DeviceParam()
      dp.device = dev

      let ssid: string = ''
      let channel: number = 0
      let wifiMode: string = ''
      let frequency: number = 0
      let txpower: number = 0
      let encryption: string = ''
      let quality: number = 0
      let hwmode: string = ''
      const info: Object | null = await this.ubusCall('iwinfo', 'info', dp)
      if (info) {
        const infoRec = info as Record<string, Object>
        ssid = ApiUtils.strOf(infoRec, 'ssid') || ApiUtils.strOf(infoRec, 'essid')
        channel = ApiUtils.numOf(infoRec, 'channel', 0)
        wifiMode = ApiUtils.strOf(infoRec, 'mode')
        frequency = ApiUtils.numOf(infoRec, 'frequency', 0)
        txpower = ApiUtils.numOf(infoRec, 'txpower', 0)
        encryption = ApiUtils.strOf(infoRec, 'encryption')
        quality = ApiUtils.numOf(infoRec, 'quality', 0)
        hwmode = ApiUtils.strOf(infoRec, 'hwmode')
      }

      const clients: Object[] = []
      const assoc: Object | null = await this.ubusCall('iwinfo', 'assoclist', dp)
      if (assoc) {
        const results = (assoc as Record<string, Object>)['results']
        if (Array.isArray(results)) {
          for (let j = 0; j < results.length; j++) {
            clients.push(this.buildWifiClient(results[j] as Record<string, Object>, dev))
          }
        }
      }

      const ifItem: Record<string, Object> = {}
      ifItem['interface'] = dev
      ifItem['ifname'] = dev
      ifItem['ssid'] = ssid
      ifItem['channel'] = channel
      ifItem['mode'] = wifiMode
      ifItem['frequency'] = frequency
      ifItem['txpower'] = txpower
      ifItem['encryption'] = encryption
      ifItem['quality'] = quality
      ifItem['hwmode'] = hwmode
      ifItem['clients'] = clients as Object
      interfaces.push(ifItem as Object)

      const devIf: Record<string, Object> = {}
      devIf['ssid'] = ssid
      devIf['channel'] = channel
      devIf['mode'] = wifiMode
      devIf['frequency'] = frequency
      devIf['txpower'] = txpower
      devIf['encryption'] = encryption
      devIf['quality'] = quality
      devIf['hwmode'] = hwmode
      const devItem: Record<string, Object> = {}
      devItem['name'] = dev
      devItem['disabled'] = (disabledMap.get(dev) ?? false) as Object
      devItem['interfaces'] = [devIf] as Object
      devices.push(devItem as Object)
    }

    const data: Record<string, Object> = {}
    data['interfaces'] = interfaces as Object
    data['devices'] = devices as Object
    return data as Object
  }

  /** 构建单个 WiFi 客户端条目 */
  private buildWifiClient(c: Record<string, Object>, dev: string): Object {
    const rx = c['rx'] as Record<string, Object>
    const tx = c['tx'] as Record<string, Object>
    const item: Record<string, Object> = {}
    item['mac'] = ApiUtils.strOf(c, 'mac')
    item['hostname'] = ''
    item['interface'] = dev
    item['signal'] = ApiUtils.numOf(c, 'signal', 0)
    item['noise'] = ApiUtils.numOf(c, 'noise', 0)
    item['rx_rate'] = rx ? ApiUtils.numOf(rx, 'rate', 0) : 0
    item['tx_rate'] = tx ? ApiUtils.numOf(tx, 'rate', 0) : 0
    item['connected_time'] = ApiUtils.numOf(c, 'connected_time', 0)
    item['inactive_time'] = ApiUtils.numOf(c, 'inactive_time', 0)
    return item as Object
  }

  /** 构建 DHCP 租约列表（与旧脚本结构一致：mac/ip/name/expires 绝对时间戳） */
  private buildDhcpLeases(data: Object | null): Object {
    const list: Object[] = []
    if (data) {
      const leases = (data as Record<string, Object>)['dhcp_leases']
      if (Array.isArray(leases)) {
        const now: number = Math.floor(Date.now() / 1000)
        for (let i = 0; i < leases.length; i++) {
          const l = leases[i] as Record<string, Object>
          const item: Record<string, Object> = {}
          item['mac'] = ApiUtils.strOf(l, 'macaddr')
          item['ip'] = ApiUtils.strOf(l, 'ipaddr')
          item['name'] = ApiUtils.strOf(l, 'hostname')
          // luci-rpc 返回的 expires 为剩余秒数，转换为绝对时间戳
          item['expires'] = now + ApiUtils.numOf(l, 'expires', 0)
          list.push(item as Object)
        }
      }
    }
    return list as Object
  }

  /** 降级：解析 /tmp/dhcp.leases 文件（expires 本身即绝对时间戳） */
  private async buildDhcpLeasesFromFile(): Promise<Object> {
    const list: Object[] = []
    const text: string = await this.ubusReadFile('/tmp/dhcp.leases')
    if (text) {
      const lines: string[] = text.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const toks: string[] = lines[i].trim().split(/\s+/)
        if (toks.length < 4) {
          continue
        }
        const item: Record<string, Object> = {}
        item['expires'] = parseInt(toks[0]) || 0
        item['mac'] = toks[1]
        item['ip'] = toks[2]
        item['name'] = toks[3] === '*' ? '' : toks[3]
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 构建存储挂载点信息（KB 单位，与旧脚本一致） */
  private async buildStorageInfo(): Promise<Object> {
    const list: Object[] = []

    // 文件系统类型映射：dev -> type
    const fsMap: Map<string, string> = new Map()
    const blockDevs: Object | null = await this.ubusCall('luci', 'getBlockDevices', new EmptyRecord())
    if (blockDevs) {
      const rec = blockDevs as Record<string, Object>
      const keys = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        const bd = rec[keys[i]] as Record<string, Object>
        if (bd && typeof bd === 'object') {
          const devPath: string = ApiUtils.strOf(bd, 'dev')
          const fsType: string = ApiUtils.strOf(bd, 'type')
          if (devPath && fsType) {
            fsMap.set(devPath, fsType)
          }
        }
      }
    }

    const mounts: Object | null = await this.ubusCall('luci', 'getMountPoints', new EmptyRecord())
    if (mounts) {
      const arr = (mounts as Record<string, Object>)['result']
      if (Array.isArray(arr)) {
        for (let i = 0; i < arr.length; i++) {
          const m = arr[i] as Record<string, Object>
          const devPath: string = ApiUtils.strOf(m, 'device')
          // 与旧脚本一致：仅统计 /dev/* 设备，过滤 tmpfs 和 docker overlay
          if (!devPath.startsWith('/dev/')) {
            continue
          }
          const size: number = ApiUtils.numOf(m, 'size', 0)
          const free: number = ApiUtils.numOf(m, 'free', 0)
          const avail: number = ApiUtils.numOf(m, 'avail', 0)
          const item: Record<string, Object> = {}
          item['device'] = devPath
          item['mount'] = ApiUtils.strOf(m, 'mount')
          item['fs'] = fsMap.get(devPath) ? fsMap.get(devPath)! : ''
          item['total_kb'] = Math.floor(size / 1024)
          item['used_kb'] = Math.floor((size - free) / 1024)
          item['free_kb'] = Math.floor(avail / 1024)
          list.push(item as Object)
        }
      }
    }
    if (list.length > 0) {
      return list as Object
    }

    // 降级：luci getMountPoints 不可用（无 luci-rpc 的系统），用 df -k + /proc/mounts
    return this.buildStorageFromDf()
  }

  /** 降级：通过 df -k 与 /proc/mounts 构建存储挂载点信息 */
  private async buildStorageFromDf(): Promise<Object> {
    const list: Object[] = []

    // mount -> 文件系统类型
    const fsByMount: Map<string, string> = new Map()
    const mountsText: string = await this.ubusReadFile('/proc/mounts')
    if (mountsText) {
      const mlines: string[] = mountsText.split('\n')
      for (let i = 0; i < mlines.length; i++) {
        const toks: string[] = mlines[i].trim().split(/\s+/)
        if (toks.length >= 3) {
          fsByMount.set(toks[1], toks[2])
        }
      }
    }

    const out: string = await this.ubusExec('/bin/df', ['-k'])
    if (out) {
      const rawLines: string[] = out.split('\n')
      // 预处理：df 输出中长文件系统名单独占一行的，与下一行合并
      const lines: string[] = []
      for (let i = 0; i < rawLines.length; i++) {
        const cur: string = rawLines[i].trim()
        if (!cur) {
          continue
        }
        const toks: string[] = cur.split(/\s+/)
        if (toks.length === 1 && i + 1 < rawLines.length && rawLines[i + 1].trim()) {
          lines.push(`${cur} ${rawLines[i + 1].trim()}`)
          i++
          continue
        }
        lines.push(cur)
      }

      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i]
        if (line.startsWith('Filesystem')) {
          continue
        }
        const toks: string[] = line.split(/\s+/)
        // 格式：文件系统 1K-blocks Used Available Use% 挂载点（共 6 列）
        if (toks.length < 6) {
          continue
        }
        const devPath: string = toks[0]
        if (!devPath.startsWith('/dev/')) {
          continue
        }
        const mountPoint: string = toks[toks.length - 1]
        const item: Record<string, Object> = {}
        item['device'] = devPath
        item['mount'] = mountPoint
        item['fs'] = fsByMount.get(mountPoint) ? fsByMount.get(mountPoint)! : ''
        item['total_kb'] = parseInt(toks[1]) || 0
        item['used_kb'] = parseInt(toks[2]) || 0
        item['free_kb'] = parseInt(toks[3]) || 0
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 构建进程列表（优先 LuCI getProcessList，降级 /bin/ps） */
  private async buildProcessList(): Promise<Object> {
    const list: Object[] = []
    const data: Object | null = await this.ubusCall('luci', 'getProcessList', new EmptyRecord())
    if (data) {
      const procs = (data as Record<string, Object>)['result']
      if (Array.isArray(procs)) {
        for (let i = 0; i < procs.length; i++) {
          const p = procs[i] as Record<string, Object>
          const cmd: string = ApiUtils.strOf(p, 'COMMAND')
          const item: Record<string, Object> = {}
          item['pid'] = ApiUtils.numOf(p, 'PID', 0)
          item['ppid'] = ApiUtils.numOf(p, 'PPID', 0)
          item['user'] = ApiUtils.strOf(p, 'USER').trim()
          item['status'] = ApiUtils.strOf(p, 'STAT').trim()
          item['rss_kb'] = ApiUtils.parseSizeToKb(ApiUtils.strOf(p, 'VSZ'))
          item['cpu_percent'] = ApiUtils.percentOf(p, '%CPU')
          item['mem_percent'] = ApiUtils.percentOf(p, '%MEM')
          item['command'] = cmd
          // comm 取命令首字段的文件名部分
          const firstTok: string = cmd.split(' ')[0]
          const slashIdx: number = firstTok.lastIndexOf('/')
          item['comm'] = slashIdx >= 0 ? firstTok.substring(slashIdx + 1) : firstTok
          list.push(item as Object)
        }
      }
    }
    if (list.length > 0) {
      return list as Object
    }

    // 降级：解析 /bin/ps 输出（PID USER VSZ STAT COMMAND）
    const out: string = await this.ubusExec('/bin/ps', [])
    if (out) {
      const lines: string[] = out.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim()
        if (!line || line.startsWith('PID')) {
          continue
        }
        const toks: string[] = line.split(/\s+/)
        if (toks.length < 5) {
          continue
        }
        const cmd: string = toks.slice(4).join(' ')
        const firstTok: string = toks[4]
        const slashIdx: number = firstTok.lastIndexOf('/')
        const item: Record<string, Object> = {}
        item['pid'] = parseInt(toks[0]) || 0
        item['ppid'] = 0
        item['user'] = toks[1]
        item['status'] = toks[3]
        item['rss_kb'] = parseInt(toks[2]) || 0
        item['cpu_percent'] = 0
        item['mem_percent'] = 0
        item['command'] = cmd
        item['comm'] = slashIdx >= 0 ? firstTok.substring(slashIdx + 1) : firstTok
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 构建路由表（通过 ACL 放行的 ip route 命令） */
  private async buildRouteTable(): Promise<Object> {
    const list: Object[] = []
    const out: string = await this.ubusExec('/sbin/ip', ['-4', 'route', 'show', 'table', 'all'])
    if (out) {
      const lines: string[] = out.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim()
        if (!line) {
          continue
        }
        const toks: string[] = line.split(/\s+/)
        const first: string = toks[0]
        // 仅保留主路由条目（目标网段或 default），过滤 broadcast/local 等噪音
        if (first !== 'default' && first.indexOf('.') < 0 && first.indexOf(':') < 0) {
          continue
        }
        const item: Record<string, Object> = {}
        item['destination'] = first
        item['gateway'] = ApiUtils.tokenAfter(toks, 'via')
        item['device'] = ApiUtils.tokenAfter(toks, 'dev')
        item['source'] = ApiUtils.tokenAfter(toks, 'src')
        item['table'] = ApiUtils.tokenAfter(toks, 'table')
        item['scope'] = ApiUtils.tokenAfter(toks, 'scope')
        item['flags'] = ''
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /** 构建 NAT 连接跟踪统计 */
  private async buildConntrack(): Promise<Object> {
    const countStr: string = await this.ubusReadFile('/proc/sys/net/netfilter/nf_conntrack_count')
    const maxStr: string = await this.ubusReadFile('/proc/sys/net/netfilter/nf_conntrack_max')
    const data: Record<string, Object> = {}
    data['count'] = parseInt(countStr.trim()) || 0
    data['max'] = parseInt(maxStr.trim()) || 0
    return data as Object
  }

  /** OAF 接口返回 {data:{...}} 嵌套结构，解包为内层数据 */
  private async unwrapOafData(data: Object | null): Promise<Object> {
    if (!data) {
      return new EmptyRecord()
    }
    const inner = (data as Record<string, Object>)['data']
    if (inner && typeof inner === 'object') {
      return inner as Object
    }
    return data
  }

  /** 构建 Docker 概览（优先 Docker API /info，降级 ubus 服务状态 + dockerman 概览页） */
  private async buildDockerOverview(): Promise<Object> {
    const overview: Record<string, Object> = {}
    overview['docker_version'] = ''
    overview['daemon_status'] = 'stopped'
    overview['containers_total'] = 0
    overview['containers_running'] = 0
    overview['images_total'] = 0
    overview['disk_used'] = '0'
    overview['mem_used_mb'] = '0'

    // 1. Docker Remote API（最准确）
    if (this.dockerApiBase) {
      const info: Object | null = await this.dockerApiGet('/info')
      if (info) {
        const rec = info as Record<string, Object>
        overview['docker_version'] = ApiUtils.strOf(rec, 'ServerVersion')
        overview['daemon_status'] = 'running'
        overview['containers_total'] = ApiUtils.numOf(rec, 'Containers', 0)
        overview['containers_running'] = ApiUtils.numOf(rec, 'ContainersRunning', 0)
        overview['images_total'] = ApiUtils.numOf(rec, 'Images', 0)
        return overview as Object
      }
    }

    // 2. ubus procd 服务状态判断守护进程
    const p: ServiceListParam = new ServiceListParam()
    p.name = 'dockerd'
    const data: Object | null = await this.ubusCall('service', 'list', p)
    if (data) {
      const svc = (data as Record<string, Object>)['dockerd'] as Record<string, Object>
      if (svc && typeof svc === 'object') {
        const inst = svc['instances'] as Record<string, Object>
        if (inst && typeof inst === 'object') {
          const instKeys = Object.keys(inst)
          for (let i = 0; i < instKeys.length; i++) {
            const one = inst[instKeys[i]] as Record<string, Object>
            if (one && typeof one === 'object' && one['running'] === true) {
              overview['daemon_status'] = 'running'
              break
            }
          }
        }
      }
    }

    // 3. dockerman 概览页补充：容器计数、镜像数、Docker 版本
    const res: LuciHttpResult = await this.luciGet('admin/docker/overview')
    if (res.status === 200 && res.body) {
      const text: string = res.body.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')
      const cm = text.match(/Containers\s+(\d+)\s*\/\s*(\d+)/)
      if (cm) {
        overview['containers_running'] = parseInt(cm[1]) || 0
        overview['containers_total'] = parseInt(cm[2]) || 0
        if (parseInt(cm[1]) > 0) {
          overview['daemon_status'] = 'running'
        }
      }
      const im = text.match(/Images\s+(\d+)\s*\/\s*(\d+)/)
      if (im) {
        overview['images_total'] = parseInt(im[2]) || parseInt(im[1]) || 0
      }
      const vm = res.body.match(/value="Docker Version"[\s\S]{0,600}?value="([^"]*)"/)
      if (vm && vm[1]) {
        overview['docker_version'] = vm[1]
      }
    }
    return overview as Object
  }

  /**
   * 获取 iStoreOS quickstart 系统状态（cpuTemperature/cpuUsage/内存百分比）
   * 与 iStoreOS 网页首页同源接口；非 iStoreOS 系统返回 null（3 秒 TTL 缓存避免重复请求）
   */
  private async fetchIStoreSystemStatus(): Promise<Object | null> {
    // 3 秒 TTL 缓存（system_info 与 cpu_info 在同一轮询周期内复用一次请求；null 也缓存）
    if (this.iStoreStatusTime > 0 && Date.now() - this.iStoreStatusTime < 3000) {
      return this.iStoreStatusCache
    }
    let result: Object | null = null
    const res: LuciHttpResult = await this.luciGet('istore/system/status/')
    if (res.status === 200 && res.body) {
      try {
        const parsed = JSON.parse(res.body) as Record<string, Object>
        const inner = parsed['result']
        if (inner && typeof inner === 'object') {
          result = inner as Object
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `fetchIStoreSystemStatus parse error: ${e}`)
      }
    }
    this.iStoreStatusCache = result
    this.iStoreStatusTime = Date.now()
    return result
  }

  /**
   * 构建 iStore 已安装应用列表
   * 经 LuCI 网页通道调用 iStore 商店接口（非 iStoreOS 系统返回空列表）
   */
  private async buildIStoreApps(): Promise<Object> {
    const list: Object[] = []
    const res: LuciHttpResult = await this.luciGet('admin/store/installed')
    if (res.status === 200 && res.body) {
      try {
        const parsed = JSON.parse(res.body) as Object
        if (Array.isArray(parsed)) {
          const arr = parsed as Object[]
          for (let i = 0; i < arr.length; i++) {
            const a = arr[i] as Record<string, Object>
            if (!a || typeof a !== 'object') {
              continue
            }
            const name: string = ApiUtils.strOf(a, 'name')
            if (!name) {
              continue
            }
            const item: Record<string, Object> = {}
            item['name'] = name
            item['title'] = ApiUtils.strOf(a, 'title') || ApiUtils.strOf(a, 'title_en')
            item['version'] = ApiUtils.strOf(a, 'version')
            item['icon'] = `/luci-static/resources/app-icons/${name}.png`
            item['link'] = ApiUtils.strOf(a, 'entry')
            // 分类：兼容多种字段名（iStoreOS 不同版本返回不同）
            item['category'] = ApiUtils.strOf(a, 'category') ||
              ApiUtils.strOf(a, 'package_category') ||
              ApiUtils.strOf(a, 'app_category')
            list.push(item as Object)
          }
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `buildIStoreApps parse error: ${e}`)
      }
    }
    return list as Object
  }

  /** dockerman 容器行数据 */
  private parseDockerRows(html: string): DockerRow[] {
    const rows: DockerRow[] = []
    const rowRe = /<tr class="tr cbi-section-table-row[^"]*" id="cbi-table-([0-9a-f]{64})"[\s\S]*?<\/tr>/g
    let m: RegExpExecArray | null = rowRe.exec(html)
    while (m !== null) {
      const row: DockerRow = new DockerRow()
      row.fullId = m[1]
      const rowHtml: string = m[0]
      row.shortId = ApiUtils.dockerField(rowHtml, '_id') || row.fullId.substring(0, 12)
      row.name = ApiUtils.dockerField(rowHtml, '_name')
      row.image = ApiUtils.dockerField(rowHtml, '_image')
      row.command = ApiUtils.dockerField(rowHtml, '_command')
      row.status = ApiUtils.stripTags(ApiUtils.dockerField(rowHtml, '_status')).trim()
      row.running = row.status.startsWith('Up')
      rows.push(row)
      m = rowRe.exec(html)
    }
    return rows
  }

  /** 构建 Docker 容器列表（解析 dockerman 容器页表格） */
  private async buildDockerContainers(): Promise<Object> {
    const list: Object[] = []
    const res: LuciHttpResult = await this.luciGet('admin/docker/containers')
    if (res.status === 200 && res.body) {
      const rows: DockerRow[] = this.parseDockerRows(res.body)
      this.dockerIdMap.clear()
      for (let i = 0; i < rows.length; i++) {
        const r: DockerRow = rows[i]
        this.dockerIdMap.set(r.name, r.fullId)
        this.dockerIdMap.set(r.shortId, r.fullId)
        const item: Record<string, Object> = {}
        item['id'] = r.shortId
        item['name'] = r.name
        item['status'] = r.status
        item['image'] = r.image
        item['running'] = r.running
        list.push(item as Object)
      }
    }
    return list as Object
  }

  /**
   * 容器操作（start/stop/restart/kill/remove）
   * 复现 dockerman 表单：CSRF token + 勾选目标容器 + 动作按钮
   */
  private async dockerContainerActionViaLuci(name: string, action: string): Promise<boolean> {
    const labels: Map<string, string> = new Map()
    labels.set('start', 'Start')
    labels.set('stop', 'Stop')
    labels.set('restart', 'Restart')
    labels.set('kill', 'Kill')
    labels.set('remove', 'Remove')
    const label: string = labels.has(action) ? labels.get(action)! : ''
    if (!name || !label) {
      return false
    }

    // 拉取容器页：解析目标容器完整 ID + CSRF token
    const res: LuciHttpResult = await this.luciGet('admin/docker/containers')
    if (res.status !== 200 || !res.body) {
      return false
    }
    let fullId: string = this.dockerIdMap.has(name) ? this.dockerIdMap.get(name)! : ''
    if (!fullId) {
      const rows: DockerRow[] = this.parseDockerRows(res.body)
      for (let i = 0; i < rows.length; i++) {
        if (rows[i].name === name || rows[i].shortId === name) {
          fullId = rows[i].fullId
          break
        }
      }
    }
    if (!fullId) {
      return false
    }
    const tm = res.body.match(/name="token" value="([0-9a-f]+)"/)
    if (!tm || !tm[1]) {
      return false
    }

    const body: string =
      `token=${tm[1]}&cbi.submit=1` +
      `&cbid.table.${fullId}._selected=1&cbi.cbe.table.${fullId}._selected=1` +
      `&cbid.table.1._${action}=${encodeURIComponent(label)}`
    const post: LuciHttpResult = await this.luciPostForm('admin/docker/containers', body)
    return post.status === 200 || post.status === 302
  }

  // ============================================================
  //  legacy 模式（旧 router-api CGI 脚本 + Token，向后兼容）
  // ============================================================

  /**
   * legacy 连接测试：发送 system_board 请求验证 Token 有效性
   */
  private async legacyConnect(): Promise<boolean> {
    try {
      const result = await this.legacyRequest('system_board')
      if (result && result.code === 0) {
        return true
      }
      let msg: string = ''
      if (result && result.message) {
        msg = result.message
      }
      if (!msg && result) {
        const code: number = result.code
        if (code === 401 || code === 403) {
          msg = `认证失败：${code === 401 ? 'Token 未提供' : 'Token 无效或已过期'}`
        } else if (code !== 0) {
          msg = `服务器返回错误 (${code})`
        }
      }
      this.lastError = msg ? msg : '连接失败，请检查设备地址和 Token'
      return false
    } catch (e) {
      this.lastError = '无法连接到设备，请检查网络和地址'
      hilog.error(DOMAIN, TAG, `legacyConnect failed: ${e}`)
      return false
    }
  }

  /**
   * legacy HTTP GET 请求（旧 router-api 脚本）
   */
  private async legacyRequest(action: string, device?: string): Promise<RouterApiResponse | null> {
    let url = `${this.legacyUrl}?action=${action}&token=${encodeURIComponent(this.token)}`
    if (device) {
      url += `&device=${encodeURIComponent(device)}`
    }
    hilog.info(DOMAIN, TAG, `Requesting(legacy): ${url}`)

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
        let parsed: RouterApiResponse
        if (typeof resultData === 'string') {
          parsed = JSON.parse(resultData) as RouterApiResponse
          if (!parsed.message && parsed.msg) {
            parsed.message = parsed.msg
          }
        } else if (typeof resultData === 'object') {
          parsed = new RouterApiResponse()
          const obj = resultData as Record<string, Object>
          if (obj['code'] !== undefined) {
            parsed.code = Number(obj['code'])
          }
          if (typeof obj['message'] === 'string') {
            parsed.message = obj['message'] as string
          } else if (typeof obj['msg'] === 'string') {
            parsed.message = obj['msg'] as string
          }
          if (obj['data'] !== undefined) {
            parsed.data = obj['data'] as Object
          }
          if (obj['rates'] !== undefined) {
            parsed.rates = obj['rates'] as Object
          }
        } else {
          parsed = new RouterApiResponse()
        }
        req.destroy()
        return parsed
      } else {
        req.destroy()
        this.lastError = `HTTP Error: ${code}`
        return null
      }
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `legacyRequest error: ${e}`)
      this.lastError = `Request failed: ${String(e)}`
      return null
    }
  }

  // ========== 系统信息类 API ==========

  /** 获取主板信息（hostname, model, kernel 等） */
  async getSystemBoard(): Promise<Object> {
    const result = await this.request('system_board')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取系统运行信息（uptime, cpu/memory 使用率等） */
  async getSystemInfo(): Promise<Object> {
    const result = await this.request('system_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取 DHCP 租约列表 */
  async getLuciDHCPLeases(): Promise<Object> {
    const result = await this.request('dhcp_leases')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取内存详细信息 */
  async getMemoryInfo(): Promise<Object> {
    const result = await this.request('memory_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  // ========== 网络类 API ==========

  /** 获取网络接口列表 */
  async getNetworkInterfaces(): Promise<Object> {
    const result = await this.request('network_interfaces')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取网络接口列表 + 实时速率（一次请求，避免并发导致速率归零） */
  async getNetworkInterfacesWithRates(): Promise<Object> {
    const result = await this.request('network_interfaces')
    if (result) {
      return result as Object
    }
    return new EmptyRecord()
  }

  /** 获取指定接口的流量统计 */
  async getNetworkDeviceStats(device: string): Promise<Object> {
    const result = await this.request('network_devices', device)
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取各接口的实时网速（rx_rate/tx_rate, bytes/s） */
  async getNetworkRates(): Promise<Object[]> {
    const result = await this.request('network_rates')
    if (result && result.data) {
      const data = result.data
      if (Array.isArray(data)) {
        return data as Object[]
      }
    }
    return []
  }

  /** 获取 CPU 温度 */
  async getCPUTemp(): Promise<number> {
    const result = await this.request('cpu_info')
    if (result && result.data) {
      const data = result.data as Record<string, Object>
      return Number(data['cpu_temp'] || data['temp'] || data['temperature'] || 0)
    }
    return 0
  }

  /** CPU 当前频率（MHz） */
  async getCPUFreq(): Promise<number> {
    const result = await this.request('cpu_info')
    if (result && result.data) {
      return Number((result.data as Record<string, Object>)['cpu_freq'] || 0)
    }
    return 0
  }

  /** 获取存储挂载点信息 */
  async getMountPoints(): Promise<Object> {
    const result = await this.request('storage_info')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取进程列表 */
  async getProcessList(): Promise<Object> {
    const result = await this.request('processes')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取启动项列表 */
  async getStartupItems(): Promise<Object> {
    const result = await this.request('startup_items')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取路由表 */
  async getRouteTable(): Promise<Object> {
    const result = await this.request('route_table')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取无线状态（WiFi 客户端和设备信息） */
  async getWirelessStatus(): Promise<Object> {
    const result = await this.request('network_wifi')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取连接跟踪统计（NAT 连接数） */
  async getConntrackInfo(): Promise<Object> {
    const result = await this.request('conntrack')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  // ========== 网络设备相关 API ==========

  /** 获取所有网络接口状态（同 getNetworkInterfaces） */
  async networkInterfaceDump(): Promise<Object> {
    const result = await this.request('network_interfaces')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取所有网络设备状态 */
  async networkDeviceStatus(): Promise<Object> {
    const result = await this.request('network_devices')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取指定设备的实时带宽统计 */
  async getRealtimeStats(device: string): Promise<Object[]> {
    const result = await this.request('bandwidth', device)
    if (result && result.data) {
      return [result.data]
    }
    return []
  }

  /** 获取无线设备列表 */
  async getWirelessDevices(): Promise<Object> {
    const result = await this.request('network_wifi')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  // ========== WiFi 管理操作 ==========

  /**
   * 读取 wireless 配置（network.wireless status）
   * 返回各无线接口的配置：ssid/encryption/key/disabled/channel/htmode 等
   */
  async getWirelessConfig(): Promise<Object> {
    const data: Object | null = await this.ubusCall('network.wireless', 'status', new EmptyRecord())
    if (data) {
      const inner = (data as Record<string, Object>)['data']
      if (inner && typeof inner === 'object') {
        return inner as Object
      }
      return data
    }
    return new EmptyRecord()
  }

  /**
   * 修改 wireless 配置（uci set wireless.<section>.<option>=value）
   * @param section 配置段（radio0 / default_radio0 等）
   * @param option 选项名（ssid/key/disabled/channel/htmode 等）
   * @param value 新值
   */
  async setWifiConfig(section: string, option: string, value: string): Promise<boolean> {
    const p: UciSetParam = new UciSetParam()
    p.config = 'wireless'
    p.section = section
    const values: Record<string, Object> = {}
    values[option] = value as Object
    p.values = values as Object
    const data: Object | null = await this.ubusCall('uci', 'set', p)
    return data !== null
  }

  /** 提交并应用 wireless 配置变更（uci commit wireless + network.wireless reload） */
  async applyWifiConfig(): Promise<boolean> {
    const commitOk: Object | null = await this.ubusCall('uci', 'commit', this.buildUciConfigParam('wireless'))
    if (commitOk === null) {
      return false
    }
    const p: WirelessReloadParam = new WirelessReloadParam()
    p.rollback = false
    const reloadOk: Object | null = await this.ubusCall('network.wireless', 'reload', p)
    return reloadOk !== null
  }

  /**
   * 读取 UCI 配置（uci get 单段/选项）
   * @param config 配置名（wireless）
   * @param section 段（radio0 / default_radio0 等）
   * @param option 选项（ssid/key 等）
   */
  async getUciOption(config: string, section: string, option: string): Promise<string> {
    const p: UciGetParam = new UciGetParam()
    p.config = config
    p.section = section
    p.option = option
    const data: Object | null = await this.ubusCall('uci', 'get', p)
    if (data) {
      const rec = data as Record<string, Object>
      const values = rec['values'] as Record<string, Object>
      if (values) {
        return ApiUtils.strOf(values, option)
      }
      return ApiUtils.strOf(rec, 'value') || ApiUtils.strOf(rec, option)
    }
    return ''
  }

  /** 踢下线指定无线客户端（hostapd.<dev> del_client） */
  async kickWifiClient(dev: string, mac: string): Promise<boolean> {
    const p: DelClientParam = new DelClientParam()
    p.mac = mac
    const data: Object | null = await this.ubusCall(`hostapd.${dev}`, 'del_client', p)
    return data !== null
  }

  private buildUciConfigParam(config: string): Object {
    const p: Record<string, Object> = {}
    p['config'] = config
    return p as Object
  }

  async getIStoreApps(): Promise<Object[]> {
    const result = await this.request('istore_apps')
    if (result && result.data && Array.isArray(result.data)) {
      return [result.data]
    }
    return []
  }

  async getDockerOverview(): Promise<Object> {
    const result = await this.request('docker_overview')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async dockerService(action: string): Promise<Object> {
    const result = await this.request(`docker_service&service_action=${action}`)
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getDockerContainers(): Promise<Object[]> {
    const result = await this.request('docker_containers')
    if (result && result.data && Array.isArray(result.data)) {
      return [result.data]
    }
    return []
  }

  /** 获取 Docker 镜像列表（仅 Docker API 可用时返回数据） */
  async getDockerImages(): Promise<Object[]> {
    const result = await this.request('docker_images')
    if (result && result.data && Array.isArray(result.data)) {
      return [result.data]
    }
    return []
  }

  /** 获取 Docker 网络列表（仅 Docker API 可用时返回数据） */
  async getDockerNetworks(): Promise<Object[]> {
    const result = await this.request('docker_networks')
    if (result && result.data && Array.isArray(result.data)) {
      return [result.data]
    }
    return []
  }

  async dockerContainerAction(container: string, action: string): Promise<Object> {
    const result = await this.request(`docker_container&container=${container}&container_action=${action}`)
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  async getDockerStats(): Promise<Object[]> {
    const result = await this.request('docker_stats')
    if (result && result.data && Array.isArray(result.data)) {
      return [result.data]
    }
    return []
  }

  // ========== 家长控制类 API ==========

  /** 获取所有 conntrack 连接条目（用于按 IP 统计连接数） */
  async getConntrackList(): Promise<Object[]> {
    const data: Object | null = await this.ubusCall('luci', 'getConntrackList', new EmptyRecord())
    if (data) {
      const rec: Record<string, Object> = data as Record<string, Object>
      const result: Object = rec['result']
      if (result && Array.isArray(result)) {
        return result as Object[]
      }
    }
    return []
  }

  /** 获取 OAF（应用过滤引擎）运行状态 */
  async getOafStatus(): Promise<Object> {
    const result = await this.request('oaf_status')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取应用过滤基础配置 */
  async getAppFilterBase(): Promise<Object> {
    const result = await this.request('appfilter_base')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取应用分类列表（含各分类下的应用） */
  async getAppFilterClassList(): Promise<Object[]> {
    const result = await this.request('appfilter_classes')
    if (result && result.data) {
      return [result.data]
    }
    return []
  }

  /** 获取应用过滤时间段配置 */
  async getAppFilterTime(): Promise<Object> {
    const result = await this.request('appfilter_time')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取应用过滤用户配置 */
  async getAppFilterUser(): Promise<Object> {
    const result = await this.request('appfilter_user')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  /** 获取应用过滤高级配置 */
  async getAppFilterAdv(): Promise<Object> {
    const result = await this.request('appfilter_adv')
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
  }

  // ========== OAF 写操作（appfilter set_* 接口） ==========

  /**
   * 保存应用过滤基础配置（总开关/工作模式/日志）
   * @param enable 总开关
   * @param workMode 工作模式（true=旁路 bypass，false=网关 gateway）
   * @param recordEnable 日志开关
   * @returns 是否成功
   */
  async setAppFilterBase(enable: boolean, workMode: boolean, recordEnable: boolean): Promise<boolean> {
    const p: AppFilterBaseSetParam = new AppFilterBaseSetParam()
    p.enable = enable ? 1 : 0
    p.work_mode = workMode ? 1 : 0
    p.record_enable = recordEnable ? 1 : 0
    const data: Object | null = await this.ubusCall('appfilter', 'set_app_filter_base', p)
    return data !== null
  }

  /**
   * 保存应用管控规则（set_app_filter）
   * @param appIds 受管控的应用 ID 列表（写满即视为需要管控，未列出视为放行）
   * @returns 是否成功
   */
  async setAppFilter(appIds: number[]): Promise<boolean> {
    const p: AppFilterSetParam = new AppFilterSetParam()
    p.app_list = appIds
    const data: Object | null = await this.ubusCall('appfilter', 'set_app_filter', p)
    return data !== null
  }

  /**
   * 保存时间段配置（set_app_filter_time）
   * @param mode 0=固定时段 1=动态时长
   * @param weekdays 生效星期（0-6，0=周日）
   * @param fixedTimes 固定时段 [{start:"HH:MM", end:"HH:MM"}]
   * @param dynamicMinutes 动态时长分钟数（mode=1 时有效）
   * @param dynStart 动态开始 "HH:MM"
   * @param dynEnd 动态结束 "HH:MM"
   */
  async setAppFilterTime(mode: number, weekdays: number[], fixedTimes: Object[], dynamicMinutes: number,
    dynStart: string, dynEnd: string): Promise<boolean> {
    const p: AppFilterTimeSetParam = new AppFilterTimeSetParam()
    p.mode = mode
    p.weekday_list = weekdays
    p.time_list = fixedTimes as AppFilterTimeItemParam[]
    p.allow_time = dynamicMinutes
    p.start_time = dynStart
    p.end_time = dynEnd
    const data: Object | null = await this.ubusCall('appfilter', 'set_app_filter_time', p)
    return data !== null
  }

  /** 保存用户管控模式（0=auto 自动，1=manual 手动） */
  async setAppFilterUser(userMode: number): Promise<boolean> {
    const p: AppFilterUserSetParam = new AppFilterUserSetParam()
    p.mode = userMode
    const data: Object | null = await this.ubusCall('appfilter', 'set_app_filter_user', p)
    return data !== null
  }

  /** 保存高级配置（tcp_rst/lan_ifname/disable_hnat/auto_load_engine） */
  async setAppFilterAdv(tcpRst: number, lanIfname: string, disableHnat: number, autoLoadEngine: number): Promise<boolean> {
    const p: AppFilterAdvSetParam = new AppFilterAdvSetParam()
    p.tcp_rst = tcpRst
    p.lan_ifname = lanIfname
    p.disable_hnat = disableHnat
    p.auto_load_engine = autoLoadEngine
    const data: Object | null = await this.ubusCall('appfilter', 'set_app_filter_adv', p)
    return data !== null
  }

  /**
   * 获取所有用户/设备列表（get_all_users）
   * @param flag 数据详细程度：0=仅 mac/在线状态 1=+ip 2=+hostname/白名单 3=+常用应用/流量
   * @returns {list: [...], total, page, page_size, total_pages}
   */
  async getAllUsers(flag: number = 3): Promise<Object> {
    const p: UsersPageParam = new UsersPageParam()
    p.flag = flag
    const data: Object | null = await this.ubusCall('appfilter', 'get_all_users', p)
    if (data) {
      const inner = (data as Record<string, Object>)['data']
      if (inner && typeof inner === 'object') {
        return inner as Object
      }
      return data
    }
    return new EmptyRecord()
  }

  /** 获取设备应用使用时长统计（dev_visit_time） */
  async getDeviceVisitTime(mac: string): Promise<Object> {
    const p: MacParam = new MacParam()
    p.mac = mac
    const data: Object | null = await this.ubusCall('appfilter', 'dev_visit_time', p)
    if (data) {
      const inner = (data as Record<string, Object>)['data']
      if (inner && typeof inner === 'object') {
        return inner as Object
      }
      return data
    }
    return new EmptyRecord()
  }

  /** 获取设备访问记录（dev_visit_list） */
  async getDeviceVisitList(mac: string): Promise<Object> {
    const p: MacParam = new MacParam()
    p.mac = mac
    const data: Object | null = await this.ubusCall('appfilter', 'dev_visit_list', p)
    if (data) {
      const inner = (data as Record<string, Object>)['data']
      if (inner && typeof inner === 'object') {
        return inner as Object
      }
      return data
    }
    return new EmptyRecord()
  }

  // ========== 连接管理 ==========

  /**
   * 断开连接，重置所有状态
   */
  disconnect(): void {
    this.connected = false
    this.token = ''
    this.baseUrl = ''
    this.ubusUrl = ''
    this.legacyUrl = ''
    this.lastError = ''
    this.mode = 'none'
    this.sessionId = ''
    this.sessionExpireAt = 0
    this.prevDevStats.clear()
    this.prevStatsTime = 0
    this.boardCache = null
    this.luciCookie = ''
    this.dockerIdMap.clear()
    this.dockerApiBase = ''
    this.iStoreStatusCache = null
    this.iStoreStatusTime = 0
  }

  /**
   * 获取当前连接状态
   */
  getConnected(): boolean {
    return this.connected
  }

  /**
   * 获取最近一次错误信息
   */
  getLastError(): string {
    return this.lastError
  }

  // ========== 系统操作 API ==========

  /** 重启设备 */
  async reboot(): Promise<boolean> {
    const result = await this.request('reboot')
    return result !== null && result.code === 0
  }

  /** 恢复出厂设置（需 confirm=yes 确认参数） */
  async factoryReset(): Promise<boolean> {
    const result = await this.request('factory_reset&confirm=yes')
    return result !== null && result.code === 0
  }

  // ========== 预留接口（未来扩展） ==========

  /** 检查路由器是否支持某项能力 */
  hasCapability(_cap: string): boolean {
    return true
  }

  /** 执行远程命令（受 LuCI 命令 ACL 限制，仅白名单命令可用） */
  async execCommand(command: string, params?: string[]): Promise<string> {
    try {
      return await this.ubusExec(command, params || [])
    } catch (e) {
      hilog.error(DOMAIN, TAG, `execCommand err: ${JSON.stringify(e)}`)
    }
    return ''
  }

  /** 读取路由器文件内容（受 LuCI 文件 ACL 限制） */
  async readFile(filepath: string): Promise<string> {
    try {
      return await this.ubusReadFile(filepath)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `readFile err: ${JSON.stringify(e)}`)
    }
    return ''
  }

  /** 调用 OpenWrt ubus 接口（预留） */
  callUbus(_namespace: string, _procedure: string, _params: Record<string, Object>): Promise<[number, Object | null]> {
    return Promise.resolve([0, null])
  }

  /** 调用 ubus 接口并返回第一个结果（预留） */
  callUbusFirst(_namespace: string, _procedure: string, _params: Record<string, Object>): Promise<Object> {
    return Promise.resolve(new EmptyRecord())
  }

  // ========== 设备管理（防火墙 MAC 规则）==========

  /**
   * 禁用指定 MAC 设备联网（添加防火墙 DROP 规则）
   * @param mac 设备 MAC 地址
   * @returns 是否成功
   */
  async denyDeviceNet(mac: string): Promise<boolean> {
    try {
      // 1. 添加防火墙规则（匿名 section）
      const addP: UciAddParam = new UciAddParam()
      addP.config = 'firewall'
      addP.type = 'rule'
      const added: Object | null = await this.ubusCall('uci', 'add', addP)
      if (added === null) {
        return false
      }
      const rec = added as Record<string, Object>
      const section: string = ApiUtils.strOf(rec, 'id') || ApiUtils.strOf(rec, 'section')
      if (!section) {
        return false
      }
      // 2. 设置规则属性
      const name: string = `istore_deny_${mac.replace(/[^0-9A-Fa-f]/g, '')}`
      const values: Record<string, Object> = {
        'name': name,
        'src_mac': mac.toUpperCase(),
        'target': 'DROP',
        'proto': 'all',
        'enabled': '1'
      }
      const setP: UciSetParam = new UciSetParam()
      setP.config = 'firewall'
      setP.section = section
      setP.values = values as Object
      const setOk: Object | null = await this.ubusCall('uci', 'set', setP)
      if (setOk === null) {
        return false
      }
      // 3. commit + reload
      return await this.commitFirewall()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `denyDeviceNet err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /**
   * 恢复指定 MAC 设备联网（删除对应防火墙规则）
   * @param mac 设备 MAC 地址
   * @returns 是否成功
   */
  async allowDeviceNet(mac: string): Promise<boolean> {
    try {
      // 读取防火墙配置，找到 istore_deny_ 开头的规则并删除
      const uciGetP: UciGetParam = new UciGetParam()
      uciGetP.config = 'firewall'
      const configData: Object | null = await this.ubusCall('uci', 'get', uciGetP)
      const sections: string[] = []
      if (configData) {
        const rec = configData as Record<string, Object>
        // 遍历所有 rule section（key 可能带 .name/.src_mac 后缀，遍历以 '.name' 结尾的）
        const keys: string[] = Object.keys(rec)
        const macUpper: string = mac.toUpperCase()
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i]
          if (!k.endsWith('.name')) continue
          const secName: string = k.substring(0, k.length - 5)  // 去掉 .name
          const val: string = ApiUtils.strOf(rec, k)
          if (val.startsWith('istore_deny_')) {
            // 确认 src_mac 匹配
            const macVal: string = ApiUtils.strOf(rec, `${secName}.src_mac`)
            if (macVal.toUpperCase() === macUpper) {
              sections.push(secName)
            }
          }
        }
      }
      if (sections.length === 0) {
        return true  // 无规则视为已恢复
      }
      // 删除找到的 section
      for (let i = 0; i < sections.length; i++) {
        const delP: UciDeleteParam = new UciDeleteParam()
        delP.config = 'firewall'
        delP.section = sections[i]
        const delOk: Object | null = await this.ubusCall('uci', 'delete', delP)
        if (delOk === null) {
          return false
        }
      }
      return await this.commitFirewall()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `allowDeviceNet err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /**
   * 查询设备是否被禁用联网（是否存在 istore_deny_ 规则）
   * @param mac 设备 MAC 地址
   * @returns 是否被禁用
   */
  async isDeviceDenied(mac: string): Promise<boolean> {
    try {
      const uciGetP: UciGetParam = new UciGetParam()
      uciGetP.config = 'firewall'
      const configData: Object | null = await this.ubusCall('uci', 'get', uciGetP)
      if (!configData) {
        return false
      }
      const rec = configData as Record<string, Object>
      const keys: string[] = Object.keys(rec)
      const macUpper: string = mac.toUpperCase()
      for (let i = 0; i < keys.length; i++) {
        if (!keys[i].endsWith('.name')) continue
        const secName: string = keys[i].substring(0, keys[i].length - 5)
        const name: string = ApiUtils.strOf(rec, keys[i])
        if (name.startsWith('istore_deny_')) {
          const macVal: string = ApiUtils.strOf(rec, `${secName}.src_mac`)
          if (macVal.toUpperCase() === macUpper) {
            return true
          }
        }
      }
      return false
    } catch (e) {
      hilog.error(DOMAIN, TAG, `isDeviceDenied err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /** 提交并应用防火墙配置（uci commit firewall + fw4 reload） */
  private async commitFirewall(): Promise<boolean> {
    const commitOk: Object | null = await this.ubusCall('uci', 'commit', this.buildUciConfigParam('firewall'))
    if (commitOk === null) {
      return false
    }
    const reloadP: WirelessReloadParam = new WirelessReloadParam()
    reloadP.rollback = false
    const reloadOk: Object | null = await this.ubusCall('network.reload', 'reload', reloadP)
    return reloadOk !== null
  }

  // ========== DHCP 静态绑定 ==========

  /** 提交 DHCP 配置（commit 后 dnsmasq 由 procd 自动重载） */
  private async commitDhcp(): Promise<boolean> {
    const commitOk: Object | null = await this.ubusCall('uci', 'commit', this.buildUciConfigParam('dhcp'))
    return commitOk !== null
  }

  /** 获取 DHCP 静态绑定列表（uci dhcp 下 type=host 的 section） */
  async listDhcpBindings(): Promise<DhcpBindingInfo[]> {
    const result: DhcpBindingInfo[] = []
    try {
      const p: UciGetParam = new UciGetParam()
      p.config = 'dhcp'
      const data: Object | null = await this.ubusCall('uci', 'get', p)
      if (!data) return result
      const rec = data as Record<string, Object>
      const keys: string[] = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i]
        if (!k.endsWith('.type')) continue
        if (ApiUtils.strOf(rec, k) !== 'host') continue
        const sec: string = k.substring(0, k.length - 5)
        const info: DhcpBindingInfo = {
          section: sec,
          mac: ApiUtils.strOf(rec, `${sec}.mac`),
          ip: ApiUtils.strOf(rec, `${sec}.ip`),
          name: ApiUtils.strOf(rec, `${sec}.name`)
        }
        result.push(info)
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `listDhcpBindings err: ${JSON.stringify(e)}`)
    }
    return result
  }

  /** 添加 DHCP 静态绑定（mac → 固定 ip） */
  async addDhcpBinding(mac: string, ip: string, name: string): Promise<boolean> {
    try {
      // 1. 添加 host section
      const addP: UciAddParam = new UciAddParam()
      addP.config = 'dhcp'
      addP.type = 'host'
      const added: Object | null = await this.ubusCall('uci', 'add', addP)
      if (added === null) return false
      const rec = added as Record<string, Object>
      const section: string = ApiUtils.strOf(rec, 'id') || ApiUtils.strOf(rec, 'section')
      if (!section) return false
      // 2. 设置属性
      const values: Record<string, Object> = {
        'mac': mac.toUpperCase(),
        'ip': ip,
        'name': name
      }
      const setP: UciSetParam = new UciSetParam()
      setP.config = 'dhcp'
      setP.section = section
      setP.values = values as Object
      const setOk: Object | null = await this.ubusCall('uci', 'set', setP)
      if (setOk === null) return false
      // 3. commit（dnsmasq 自动重载）
      return await this.commitDhcp()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `addDhcpBinding err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /** 移除 DHCP 静态绑定（按 mac 匹配） */
  async removeDhcpBinding(mac: string): Promise<boolean> {
    try {
      const list: DhcpBindingInfo[] = await this.listDhcpBindings()
      let found: boolean = false
      const macUpper: string = mac.toUpperCase()
      for (let i = 0; i < list.length; i++) {
        if (list[i].mac.toUpperCase() !== macUpper) continue
        const delP: UciDeleteParam = new UciDeleteParam()
        delP.config = 'dhcp'
        delP.section = list[i].section
        const delOk: Object | null = await this.ubusCall('uci', 'delete', delP)
        if (delOk === null) return false
        found = true
      }
      if (!found) return true  // 无绑定视为已移除
      return await this.commitDhcp()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `removeDhcpBinding err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /** 查询指定 MAC 是否已有静态绑定 */
  async isDhcpBound(mac: string): Promise<boolean> {
    try {
      const list: DhcpBindingInfo[] = await this.listDhcpBindings()
      const macUpper: string = mac.toUpperCase()
      for (let i = 0; i < list.length; i++) {
        if (list[i].mac.toUpperCase() === macUpper) return true
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `isDhcpBound err: ${JSON.stringify(e)}`)
    }
    return false
  }

  // ========== WiFi 访客网络 ==========

  /** 通用：add 匿名 section 并返回 section id */
  private async uciAddSection(config: string, type: string): Promise<string> {
    const addP: UciAddParam = new UciAddParam()
    addP.config = config
    addP.type = type
    const added: Object | null = await this.ubusCall('uci', 'add', addP)
    if (added === null) return ''
    const rec = added as Record<string, Object>
    return ApiUtils.strOf(rec, 'id') || ApiUtils.strOf(rec, 'section') || ''
  }

  /** 通用：设置 section 属性 */
  private async uciSetSection(config: string, section: string, values: Record<string, Object>): Promise<boolean> {
    const setP: UciSetParam = new UciSetParam()
    setP.config = config
    setP.section = section
    setP.values = values as Object
    const data: Object | null = await this.ubusCall('uci', 'set', setP)
    return data !== null
  }

  /** 获取访客网络状态（wireless 下 network=guest 的 wifi-iface） */
  async getGuestWifiStatus(): Promise<GuestWifiInfo | null> {
    try {
      const p: UciGetParam = new UciGetParam()
      p.config = 'wireless'
      const data: Object | null = await this.ubusCall('uci', 'get', p)
      if (!data) return null
      const rec = data as Record<string, Object>
      const keys: string[] = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i]
        if (!k.endsWith('.network')) continue
        if (ApiUtils.strOf(rec, k) !== 'guest') continue
        const sec: string = k.substring(0, k.length - 8)
        const info: GuestWifiInfo = {
          enabled: ApiUtils.strOf(rec, `${sec}.disabled`) !== '1',
          ssid: ApiUtils.strOf(rec, `${sec}.ssid`),
          password: ApiUtils.strOf(rec, `${sec}.key`),
          network: 'guest',
          device: ApiUtils.strOf(rec, `${sec}.device`),
          section: sec
        }
        return info
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `getGuestWifiStatus err: ${JSON.stringify(e)}`)
    }
    return null
  }

  /** 开启访客网络（独立网段 + 无线隔离 + 防火墙仅可上外网） */
  async enableGuestWifi(ssid: string, password: string, device: string): Promise<boolean> {
    try {
      // 1. network.guest 接口（命名 section）
      let netId: string = ''
      const netP: UciGetParam = new UciGetParam()
      netP.config = 'network'
      netP.section = 'guest'
      const netData: Object | null = await this.ubusCall('uci', 'get', netP)
      if (netData === null) {
        netId = await this.uciAddSection('network', 'interface')
        if (!netId) return false
        const renameP: UciRenameParam = new UciRenameParam()
        renameP.config = 'network'
        renameP.section = netId
        renameP.value = 'guest'
        const renameOk: Object | null = await this.ubusCall('uci', 'rename', renameP)
        if (renameOk === null) return false
      }
      const netVals: Record<string, Object> = {
        'proto': 'static', 'ipaddr': '192.168.2.1', 'netmask': '255.255.255.0'
      }
      if (!await this.uciSetSection('network', 'guest', netVals)) return false

      // 2. dhcp.guest（命名 section）
      const dhcpP: UciGetParam = new UciGetParam()
      dhcpP.config = 'dhcp'
      dhcpP.section = 'guest'
      const dhcpData: Object | null = await this.ubusCall('uci', 'get', dhcpP)
      if (dhcpData === null) {
        const dId: string = await this.uciAddSection('dhcp', 'dhcp')
        if (!dId) return false
        const rP: UciRenameParam = new UciRenameParam()
        rP.config = 'dhcp'
        rP.section = dId
        rP.value = 'guest'
        const rOk: Object | null = await this.ubusCall('uci', 'rename', rP)
        if (rOk === null) return false
      }
      const dhcpVals: Record<string, Object> = {
        'interface': 'guest', 'start': '100', 'limit': '150', 'leasetime': '12h', 'dhcpv4': 'server'
      }
      if (!await this.uciSetSection('dhcp', 'guest', dhcpVals)) return false

      // 3. wifi-iface（匿名 section，network=guest 识别）
      const wifiId: string = await this.uciAddSection('wireless', 'wifi-iface')
      if (!wifiId) return false
      const wifiVals: Record<string, Object> = {
        'device': device, 'mode': 'ap', 'ssid': ssid, 'encryption': 'psk2',
        'key': password, 'network': 'guest', 'isolate': '1', 'disabled': '0'
      }
      if (!await this.uciSetSection('wireless', wifiId, wifiVals)) return false

      // 4. firewall zone（guest 隔离：可出网、禁止互访内网）
      let zoneId: string = ''
      const fwP: UciGetParam = new UciGetParam()
      fwP.config = 'firewall'
      const fwData: Object | null = await this.ubusCall('uci', 'get', fwP)
      const fwRec = fwData as Record<string, Object>
      const fwKeys: string[] = fwData ? Object.keys(fwRec) : []
      for (let i = 0; i < fwKeys.length; i++) {
        if (!fwKeys[i].endsWith('.name')) continue
        const secName: string = fwKeys[i].substring(0, fwKeys[i].length - 5)
        if (ApiUtils.strOf(fwRec, fwKeys[i]) === 'guest') {
          zoneId = secName
          break
        }
      }
      if (!zoneId) {
        zoneId = await this.uciAddSection('firewall', 'zone')
        if (!zoneId) return false
      }
      const zoneVals: Record<string, Object> = {
        'name': 'guest', 'network': 'guest', 'input': 'REJECT', 'output': 'ACCEPT',
        'forward': 'REJECT', 'masq': '1'
      }
      if (!await this.uciSetSection('firewall', zoneId, zoneVals)) return false

      // 5. forwarding guest→wan
      const fwdId: string = await this.uciAddSection('firewall', 'forwarding')
      if (!fwdId) return false
      const fwdVals: Record<string, Object> = { 'src': 'guest', 'dest': 'wan' }
      if (!await this.uciSetSection('firewall', fwdId, fwdVals)) return false

      // 6. 提交全部配置
      if (!await this.ubusCall('uci', 'commit', this.buildUciConfigParam('network'))) return false
      if (!await this.ubusCall('uci', 'commit', this.buildUciConfigParam('dhcp'))) return false
      if (!await this.ubusCall('uci', 'commit', this.buildUciConfigParam('wireless'))) return false
      if (!await this.commitFirewall()) return false
      // 无线重载
      const wp: WirelessReloadParam = new WirelessReloadParam()
      wp.rollback = false
      const wOk: Object | null = await this.ubusCall('network.wireless', 'reload', wp)
      return wOk !== null
    } catch (e) {
      hilog.error(DOMAIN, TAG, `enableGuestWifi err: ${JSON.stringify(e)}`)
      return false
    }
  }

  /** 关闭访客网络（删除 guest wifi-iface，保留网络接口与防火墙区） */
  async disableGuestWifi(): Promise<boolean> {
    try {
      const p: UciGetParam = new UciGetParam()
      p.config = 'wireless'
      const data: Object | null = await this.ubusCall('uci', 'get', p)
      if (data) {
        const rec = data as Record<string, Object>
        const keys: string[] = Object.keys(rec)
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i]
          if (!k.endsWith('.network')) continue
          if (ApiUtils.strOf(rec, k) !== 'guest') continue
          const sec: string = k.substring(0, k.length - 8)
          const delP: UciDeleteParam = new UciDeleteParam()
          delP.config = 'wireless'
          delP.section = sec
          const delOk: Object | null = await this.ubusCall('uci', 'delete', delP)
          if (delOk === null) return false
          break
        }
      }
      if (!await this.ubusCall('uci', 'commit', this.buildUciConfigParam('wireless'))) return false
      const wp: WirelessReloadParam = new WirelessReloadParam()
      wp.rollback = false
      const wOk: Object | null = await this.ubusCall('network.wireless', 'reload', wp)
      return wOk !== null
    } catch (e) {
      hilog.error(DOMAIN, TAG, `disableGuestWifi err: ${JSON.stringify(e)}`)
      return false
    }
  }
}
