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
  private cookieStr: string = ''

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
    this.cookieStr = ''
    hilog.info(DOMAIN, TAG, `Configured: ${this.baseUrl}`)
  }

  getConnected(): boolean { return this.connected }

  async connect(): Promise<boolean> {
    this.lastError = ''
    this.connected = false

    if (!await this.probe()) {
      this.lastError = '无法连接到设备，请检查地址和网络'
      return false
    }

    if (!await this.formLoginAndGetCookie()) {
      this.lastError = '登录失败，请检查用户名和密码'
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

  private async formLoginAndGetCookie(): Promise<boolean> {
    const paths: string[] = ['/cgi-bin/luci', '/cgi-bin/luci/', '/']
    for (let i = 0; i < paths.length; i++) {
      const ok: boolean = await this.tryPath(paths[i])
      if (ok) return true
    }
    return false
  }

  private async tryPath(path: string): Promise<boolean> {
    const body: string = `luci_username=${encodeURIComponent(this.username)}&luci_password=${encodeURIComponent(this.password)}`
    const req = http.createHttp()
    try {
      const r = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 4000,
        readTimeout: 4000
      })
      req.destroy()

      const code: number = r.responseCode
      hilog.info(DOMAIN, TAG, `POST ${path}: ${code}`)
      if (code < 200 || code >= 500) return false

      const rawCookies: string = r.cookies as string || ''
      hilog.info(DOMAIN, TAG, `cookies: "${rawCookies}"`)

      const headerCookies: string = this.findHeaderCookie(r)
      hilog.info(DOMAIN, TAG, `headerCookie: "${headerCookies}"`)

      const combined: string = this.mergeCookies(rawCookies, headerCookies)
      if (combined) {
        this.cookieStr = combined
        hilog.info(DOMAIN, TAG, `Got cookie: ${combined.substring(0, 40)}...`)
      }

      if (!this.cookieStr) {
        const bodyText: string = r.result as string || ''
        const sysauth: string = this.extractSysauth(bodyText)
        if (sysauth) {
          this.cookieStr = `sysauth=${sysauth}`
        }
      }

      return true
    } catch (e) {
      req.destroy()
      return false
    }
  }

  private findHeaderCookie(resp: http.HttpResponse): string {
    const h: Record<string, string> = resp.header as Record<string, string> || {}
    const keys: string[] = Object.keys(h)
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i]
      const lk: string = k.toLowerCase()
      if (lk.includes('set-cookie') || lk === 'cookie') {
        return h[k] || ''
      }
    }
    return ''
  }

  private mergeCookies(rawCookies: string, headerCookie: string): string {
    const parts: Record<string, string> = {}
    const merged: string = rawCookies + (headerCookie ? '; ' + headerCookie : '')
    const chunks: string[] = merged.split(/[;\n]+/)
    for (let i = 0; i < chunks.length; i++) {
      const c: string = chunks[i].trim()
      if (!c || c === ',') continue
      const eq: number = c.indexOf('=')
      if (eq < 0) continue
      const k: string = c.substring(0, eq).trim()
      let v: string = c.substring(eq + 1).trim().replace(/[,;]+.*$/, '').trim()
      if (k && v) {
        parts[k] = v
      }
    }

    const result: string[] = []
    const pkeys: string[] = Object.keys(parts)
    for (let i = 0; i < pkeys.length; i++) {
      result.push(`${pkeys[i]}=${parts[pkeys[i]]}`)
    }
    return result.join('; ')
  }

  private extractSysauth(text: string): string {
    if (!text) return ''
    const patterns: RegExp[] = [
      /sysauth%5b%5d=([^;&\s'"]+)/i,
      /sysauth%5B%5D=([^;&\s'"]+)/i,
      /sysauth=([^;&\s'"]+)/i
    ]
    for (let i = 0; i < patterns.length; i++) {
      const m: RegExpMatchArray | null = text.match(patterns[i])
      if (m && m[1] && m[1].length > 3) return m[1]
    }
    return ''
  }

  private async verifyCookieWorks(): Promise<boolean> {
    const data: ESObject = await this.getJSON('/cgi-bin/luci/istore/u/network/status/')
    return data && Object.keys(data).length > 0
  }

  async getJSON(path: string): Promise<ESObject> {
    const req = http.createHttp()
    try {
      const hdr: Record<string, string> = {}
      if (this.cookieStr) {
        hdr['Cookie'] = this.cookieStr
        hilog.info(DOMAIN, TAG, `GET with cookie: ${this.cookieStr.substring(0, 30)}...`)
      }
      const r = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.GET,
        header: hdr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 4000,
        readTimeout: 4000
      })
      req.destroy()
      const body: string = r.result as string || ''
      hilog.info(DOMAIN, TAG, `GET ${path}: ${r.responseCode} len=${body.length}`)
      if (r.responseCode >= 200 && r.responseCode < 400 && body.length > 5) {
        return JSON.parse(body) as ESObject
      }
    } catch (e) {
      req.destroy()
      hilog.error(DOMAIN, TAG, `getJSON ${path} err`)
    }
    const empty: ESObject = {}
    return empty
  }

  async getNetworkStatus(): Promise<ESObject> {
    return this.getJSON('/cgi-bin/luci/istore/u/network/status/')
  }
  async getSystemInfo(): Promise<ESObject> { return this.getNetworkStatus() }
  async getBoardInfo(): Promise<ESObject> { return this.getNetworkStatus() }
  async getNetworkInterfaces(): Promise<ESObject> { return this.getNetworkStatus() }
  async getWanStatus(): Promise<ESObject> { return this.getNetworkStatus() }
  async getLanStatus(): Promise<ESObject> { return this.getNetworkStatus() }
  async getDhcpLeases(): Promise<ESObject> { return this.getNetworkStatus() }
  async getWirelessDevices(): Promise<ESObject> { return this.getNetworkStatus() }
  async getConnectedClients(): Promise<ESObject> { return this.getNetworkStatus() }
  async getInstalledPackages(): Promise<ESObject> { return this.getNetworkStatus() }
  async getSystemLog(lines: number = 50): Promise<ESObject> { return this.getNetworkStatus() }
  async executeCommand(command: string): Promise<ESObject> { return this.getNetworkStatus() }
  async reboot(): Promise<ESObject> { return this.getNetworkStatus() }
  async setWifi(params: ESObject): Promise<ESObject> { return this.getNetworkStatus() }
  async restartFirewall(): Promise<ESObject> { return this.getNetworkStatus() }
  async getFirewallRules(): Promise<ESObject> { return this.getNetworkStatus() }
}
