/**
 * API 客户端（单例）
 * 负责与路由器 CGI API 的底层 HTTP 通信
 * 提供各类数据的底层请求方法，返回原始 JSON 数据
 *
 * 架构说明：
 * - ApiClient：底层 HTTP 通信层（本文件）
 * - ApiService：业务逻辑层，调用 ApiClient 并解析数据为 Models 类型
 */
import { http } from '@kit.NetworkKit'
import { ConnectionConfig } from '../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'iStoreApi'
const DOMAIN = 0x0001

/**
 * 路由器 API 标准响应格式
 */
class RouterApiResponse {
  code: number = 0       // 0 表示成功
  message: string = ''   // 响应消息
  data: Object = new EmptyRecord()  // 响应数据
}

/**
 * 空对象占位符，用于无数据时的默认返回值
 */
class EmptyRecord {
}

export class ApiClient {
  baseUrl: string = ''       // API 基础 URL
  token: string = ''         // 认证令牌
  connected: boolean = false // 连接状态
  lastError: string = ''     // 最近一次错误信息

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
   * @param config 连接配置（host, port, token, useHttps）
   */
  configure(config: ConnectionConfig): void {
    const protocol: string = config.useHttps ? 'https' : 'http'
    this.baseUrl = `${protocol}://${config.host}:${config.port}/cgi-bin/router-api`
    this.token = config.token
    this.connected = false
    this.lastError = ''
  }

  /**
   * 测试连接：发送 ping 请求验证连通性
   * @returns 连接是否成功
   */
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

  /**
   * 底层 HTTP GET 请求方法
   * @param action API 操作名称（如 'ping', 'system_info' 等）
   * @param device 可选设备参数（如网络接口名）
   * @returns 解析后的 API 响应，失败时返回 null
   */
  async request(action: string, device?: string): Promise<RouterApiResponse | null> {
    // 构建请求 URL：基础路径 + action + token
    let url = `${this.baseUrl}?action=${action}&token=${encodeURIComponent(this.token)}`
    if (device) {
      url += `&device=${encodeURIComponent(device)}`
    }
    hilog.info(DOMAIN, TAG, `Requesting: ${url}`)

    const req: http.HttpRequest = http.createHttp()
    try {
      // 发送 GET 请求，设置超时和认证头
      const r: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json',
          'X-Auth-Token': this.token
        },
        connectTimeout: 5000,   // 连接超时 5 秒
        readTimeout: 10000      // 读取超时 10 秒
      })

      const code = r.responseCode
      if (code === 200) {
        // 处理不同格式的响应体（字符串或对象）
        const resultData = r.result as Object
        let respBody = ''
        if (typeof resultData === 'string') {
          respBody = resultData
        } else {
          respBody = String(resultData)
        }
        req.destroy()  // 释放 HTTP 资源
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

  /** 获取指定接口的流量统计 */
  async getNetworkDeviceStats(device: string): Promise<Object> {
    const result = await this.request('network_devices', device)
    if (result && result.data) {
      return result.data
    }
    return new EmptyRecord()
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

  // ========== 家长控制类 API ==========

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

  // ========== 连接管理 ==========

  /**
   * 断开连接，重置所有状态
   */
  disconnect(): void {
    this.connected = false
    this.token = ''
    this.baseUrl = ''
    this.lastError = ''
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

  // ========== 预留接口（未来扩展） ==========

  /** 检查路由器是否支持某项能力 */
  hasCapability(_cap: string): boolean {
    return true
  }

  /** 执行远程命令（预留） */
  async execCommand(_command: string, _params?: string[]): Promise<string> {
    return ''
  }

  /** 读取路由器文件（预留） */
  async readFile(_filepath: string): Promise<string> {
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
}
