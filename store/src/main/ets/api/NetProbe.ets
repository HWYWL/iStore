/**
 * NetProbe —— 面向"非路由器"端点的网络探测/抓取
 *
 * 页面不允许直接 import `@kit.NetworkKit`（见 architecture 的网络访问约定）；
 * 需要访问外网或非路由器地址时统一走这里：
 * - `reachable()`：HEAD 探测（智能管家检测网关/外网连通性）
 * - `getText()`：GET 文本（检查更新读版本 JSON）
 * - `getBytes()`：GET 二进制（测速下载、图片字节）
 *
 * 路由器本身的数据一律走 `ApiService`；局域网媒体服务走 `ImmichClient`/`JellyfinClient`。
 */
import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'NetProbe'

export class NetProbe {
  /** HEAD 探测：拿到任何 HTTP 响应即视为可达；连不上/超时返回 false */
  static async reachable(url: string, timeoutMs: number = 3000): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.HEAD,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      })
      return resp.responseCode >= 0
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `HEAD ${url} failed: ${JSON.stringify(e)}`)
      return false
    } finally {
      try { req.destroy() } catch (e) {}
    }
  }

  /** GET 文本；失败或超时返回 null（调用方按"检查失败"处理，不要静默当成功） */
  static async getText(url: string, timeoutMs: number = 4000): Promise<string | null> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      })
      if (resp.responseCode !== 200) {
        return null
      }
      if (typeof resp.result === 'string') {
        return resp.result as string
      }
      return null
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `GET ${url} failed: ${JSON.stringify(e)}`)
      return null
    } finally {
      try { req.destroy() } catch (e) {}
    }
  }

  /**
   * GET 二进制（Range 分块也可用）；返回 [数据, 耗时ms]，失败返回 null。
   * 测速需要精确耗时，所以把耗时一并返回，避免调用方各自计时的偏差。
   */
  static async getBytes(url: string, timeoutMs: number = 8000, rangeHeader: string = ''): Promise<ArrayBuffer | null> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {}
      if (rangeHeader.length > 0) {
        header['Range'] = rangeHeader
      }
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        header: header
      })
      if (resp.responseCode !== 200 && resp.responseCode !== 206) {
        hilog.warn(DOMAIN, TAG, `GET ${url} code=${resp.responseCode}`)
        return null
      }
      return resp.result as ArrayBuffer
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `GET bytes ${url} failed: ${JSON.stringify(e)}`)
      return null
    } finally {
      try { req.destroy() } catch (e) {}
    }
  }
}
