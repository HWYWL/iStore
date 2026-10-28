/**
 * Immich 相册 API 客户端
 * 通过 API Key（x-api-key 请求头）访问自托管的 Immich 服务器
 * 参考 https://api.immich.app
 */
import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const DOMAIN = 0x0001
const TAG = 'ImmichClient'

/** Immich 相册信息 */
export interface ImmichAlbum {
  id: string
  albumName: string
  assetCount: number
  createdAt: string
  updatedAt: string
  coverThumbnailUrl: string
}

/** Immich 服务器信息 */
export interface ImmichServerInfo {
  version: string
  serverName: string
  statistics: ImmichServerStats
}

/** Immich 服务器统计 */
export interface ImmichServerStats {
  totalImages: number
  totalVideos: number
  totalBytes: number
  totalPhotos: number
}

/** 相册内资源（照片/视频） */
export interface ImmichAsset {
  id: string
  type: string          // IMAGE / VIDEO
  originalFileName: string
  createdAt: string     // 上传/入库时间
  takenAt: string       // 拍摄时间（exifInfo.dateTimeOriginal → fileCreatedAt → createdAt 回退）
  thumbhash: string
  width: number
  height: number
  thumbnailUrl: string
  originalUrl: string
  videoUrl: string      // 视频播放地址（非视频为空）
}

/** 空搜索体（无过滤条件） */
class EmptySearchBody {
  page: number = 1
  size: number = 100
  order: string = 'desc'
}

/** 按相册过滤的搜索体 */
class AlbumSearchBody {
  page: number = 1
  size: number = 100
  order: string = 'desc'
  albumIds: string[] = []
}

/** 单页资产查询结果 */
export interface ImmichPageResult {
  items: ImmichAsset[]
  total: number
}

export class ImmichClient {
  private baseUrl: string
  private apiKey: string

  constructor(baseUrl: string, apiKey: string) {
    // 规范化：去尾部斜杠，确保含 /api 前缀（Immich API 根路径为 /api）
    let url: string = baseUrl.replace(/\/+$/, '')
    if (!url.endsWith('/api')) {
      url = `${url}/api`
    }
    this.baseUrl = url
    this.apiKey = apiKey
  }

  /**
   * 探测指定主机上是否运行 Immich（2283 端口）
   * @param host 主机地址（IP 或域名）
   * @returns 探测成功返回 Immich 基础地址（http://host:2283），失败返回 ''
   */
  static async probeHost(host: string): Promise<string> {
    const base: string = `http://${host}:2283`
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${base}/api/server/ping`, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 4000,
        readTimeout: 5000
      })
      // 200 且返回 pong 才算 Immich 服务
      if (r.responseCode === 200) {
        const body: Object = r.result as Object
        if (typeof body === 'string' && (body as string).indexOf('pong') >= 0) {
          return base
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `probe ${host} failed: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
    return ''
  }

  /**
   * 解析 http 响应体为 Object（兼容 string / ArrayBuffer）
   */
  private parseBody(result: Object): Object | null {
    try {
      if (typeof result === 'string') {
        return JSON.parse(result as string) as Object
      }
      if (result instanceof ArrayBuffer) {
        const decoder = new util.TextDecoder('utf-8')
        const ab: ArrayBuffer = result as ArrayBuffer
        const bytes: Uint8Array = new Uint8Array(ab)
        const text: string = decoder.decodeToString(bytes)
        return JSON.parse(text) as Object
      }
      // 其他情况直接返回（可能已是对象）
      return result
    } catch (e) {
      hilog.error(DOMAIN, TAG, `parseBody err: ${JSON.stringify(e)}`)
    }
    return null
  }

  /**
   * 通用 JSON GET 请求
   * @param path 端点路径（如 /albums）
   */
  private async jsonGet(path: string): Promise<Object | null> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.GET,
        header: {
          'x-api-key': this.apiKey,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 15000
      })
      if (r.responseCode === 200) {
        return this.parseBody(r.result)
      }
      hilog.error(DOMAIN, TAG, `GET ${path} failed: ${r.responseCode}`)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `GET ${path} err: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
    return null
  }

  /**
   * 通用 JSON POST 请求
   * @param path 端点路径（如 /search/metadata）
   * @param body 请求体对象
   */
  private async jsonPost(path: string, body: Object): Promise<Object | null> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.POST,
        header: {
          'x-api-key': this.apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 20000
      })
      if (r.responseCode === 200) {
        return this.parseBody(r.result)
      }
      hilog.error(DOMAIN, TAG, `POST ${path} failed: ${r.responseCode}`)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `POST ${path} err: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
    return null
  }

  /**
   * Ping 服务器（无需认证）
   * @returns 服务器可达返回 true；网络错误/服务未运行返回 false
   */
  async ping(): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}/server/ping`, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 4000,
        readTimeout: 5000
      })
      return r.responseCode === 200
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ping err: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
    return false
  }

  /**
   * 验证 API Key 是否有效（通过读取相册列表判断）
   * 返回 true 表示 Key 有效；false 表示 Key 无效/权限不足
   */
  async validateApiKey(): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}/albums`, {
        method: http.RequestMethod.GET,
        header: {
          'x-api-key': this.apiKey,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 15000
      })
      // 200：Key 有效；401：Key 无效；403：权限不足（但 Key 本身有效）
      return r.responseCode === 200 || r.responseCode === 403
    } catch (e) {
      hilog.error(DOMAIN, TAG, `validateApiKey err: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
    return false
  }

  /** 生成资源缩略图 URL（带 API Key 认证参数，供 Image 组件直接加载） */
  thumbnailUrl(assetId: string): string {
    return `${this.baseUrl}/assets/${assetId}/thumbnail?apiKey=${this.apiKey}`
  }

  /** 生成资源原图 URL（带 API Key 认证参数，供 Image 组件直接加载） */
  originalUrl(assetId: string): string {
    return `${this.baseUrl}/assets/${assetId}/original?apiKey=${this.apiKey}`
  }

  /** 生成视频播放 URL（带 API Key 认证参数，供 Video 组件播放） */
  videoUrl(assetId: string): string {
    return `${this.baseUrl}/assets/${assetId}/video/playback?apiKey=${this.apiKey}`
  }

  /**
   * 获取服务器信息 + 统计
   * 注意：about/statistics 需要 server.about / server.statistics 权限（statistics 仅管理员）。
   * 权限不足时返回 null，不影响相册浏览（相册只需 album.read / asset.view）。
   */
  async fetchServerInfo(): Promise<ImmichServerInfo | null> {
    const about = await this.jsonGet('/server/about')
    if (!about) {
      return null
    }
    const aboutRec = about as Record<string, Object>
    const info: ImmichServerInfo = {
      version: this.strOf(aboutRec, 'version'),
      serverName: this.strOf(aboutRec, 'name'),
      statistics: {
        totalImages: 0,
        totalVideos: 0,
        totalBytes: 0,
        totalPhotos: 0
      }
    }
    // 统计信息需要管理员权限，失败时静默降级（统计显示 0）
    const stats = await this.jsonGet('/server/statistics')
    if (stats) {
      const statsRec = stats as Record<string, Object>
      // Immich /server/statistics 返回字段：photos / videos / usage / usagePhotos / usageVideos
      info.statistics = {
        totalImages: this.numOf(statsRec, 'photos'),
        totalVideos: this.numOf(statsRec, 'videos'),
        totalBytes: this.numOf(statsRec, 'usage'),
        totalPhotos: this.numOf(statsRec, 'photos')
      }
    }
    return info
  }

  /**
   * 获取所有相册列表
   */
  async fetchAlbums(): Promise<ImmichAlbum[]> {
    const data = await this.jsonGet('/albums')
    if (!data || !Array.isArray(data)) {
      return []
    }
    const list: ImmichAlbum[] = []
    for (const item of data as Object[]) {
      const rec = item as Record<string, Object>
      const id: string = this.strOf(rec, 'id')
      if (!id) continue
      const albumName: string = this.strOf(rec, 'albumName') || '未命名相册'
      const coverAssetId: string = this.strOf(rec, 'albumThumbnailAssetId') || ''
      list.push({
        id: id,
        albumName: albumName,
        assetCount: this.numOf(rec, 'assetCount'),
        createdAt: this.strOf(rec, 'createdAt'),
        updatedAt: this.strOf(rec, 'updatedAt'),
        coverThumbnailUrl: coverAssetId ? this.thumbnailUrl(coverAssetId) : ''
      })
    }
    return list
  }

  /**
   * 获取相册内资源列表
   * 注意：GET /albums/{id} 新版不返回 assets，必须用 search/metadata + albumIds 过滤
   * @param albumId 相册 ID
   */
  async fetchAlbumAssets(albumId: string): Promise<ImmichAsset[]> {
    const body: AlbumSearchBody = new AlbumSearchBody()
    body.albumIds = [albumId]
    return this.searchAssets(body as Object)
  }

  /**
   * 获取全部照片（search/metadata 分页拉取）
   * 返回时间线所有资产（不限于相册）
   */
  async fetchAllAssets(): Promise<ImmichAsset[]> {
    const body: EmptySearchBody = new EmptySearchBody()
    return this.searchAssets(body as Object)
  }

  /**
   * 诊断：检查各关键端点的 HTTP 状态码
   * 返回 JSON 字符串便于直接展示
   */
  async diagnose(): Promise<string> {
    const lines: string[] = []
    // 1. ping
    try {
      const r1: http.HttpResponse = await this.rawGet('/server/ping')
      lines.push(`ping: ${r1.responseCode}`)
    } catch (e) {
      lines.push(`ping: 异常 ${JSON.stringify(e)}`)
    }
    // 2. albums
    try {
      const r2: http.HttpResponse = await this.rawGet('/albums')
      lines.push(`albums: ${r2.responseCode}`)
    } catch (e) {
      lines.push(`albums: 异常 ${JSON.stringify(e)}`)
    }
    // 3. search/metadata（关键）
    try {
      const r3: http.HttpResponse = await this.rawPost('/search/metadata',
        '{"page":1,"size":5,"order":"desc"}')
      lines.push(`search/metadata: ${r3.responseCode}`)
      const body = r3.result
      let text: string = ''
      if (typeof body === 'string') {
        text = body
      } else if (body instanceof ArrayBuffer) {
        const ab: ArrayBuffer = body as ArrayBuffer
        const bytes: Uint8Array = new Uint8Array(ab)
        text = new util.TextDecoder('utf-8').decodeToString(bytes)
      } else {
        text = JSON.stringify(body)
      }
      // 截断展示
      lines.push(`search响应: ${text.length > 200 ? text.substring(0, 200) + '...' : text}`)
    } catch (e) {
      lines.push(`search/metadata: 异常 ${JSON.stringify(e)}`)
    }
    return lines.join('\n')
  }

  /** 原始 GET（返回 HttpResponse 用于诊断） */
  private async rawGet(path: string): Promise<http.HttpResponse> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.GET,
        header: { 'x-api-key': this.apiKey, 'Accept': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 15000
      })
      return r
    } catch (e) {
      throw new Error(`GET ${path} 失败：${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
  }

  /** 原始 POST（返回 HttpResponse 用于诊断） */
  private async rawPost(path: string, bodyStr: string): Promise<http.HttpResponse> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const r: http.HttpResponse = await req.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.POST,
        header: { 'x-api-key': this.apiKey, 'Content-Type': 'application/json', 'Accept': 'application/json' },
        extraData: bodyStr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 20000
      })
      return r
    } catch (e) {
      throw new Error(`POST ${path} 失败：${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
  }

  /**
   * 分页搜索资产（search/metadata）
   * @param extraFilter 额外过滤条件（如 albumIds）
   */
  private async searchAssets(extraFilter: Object): Promise<ImmichAsset[]> {
    const all: ImmichAsset[] = []
    const pageSize: number = 100
    let page: number = 1
    let total: number = -1
    while (total < 0 || all.length < total) {
      const pageResult: ImmichPageResult | null = await this.searchAssetsPage(extraFilter, page, pageSize)
      if (!pageResult || pageResult.items.length === 0) {
        break
      }
      all.push(...pageResult.items)
      total = pageResult.total
      page++
      // 安全上限，防止异常循环
      if (page > 100) {
        break
      }
    }
    return all
  }

  /**
   * 单页搜索资产（search/metadata，分页用）
   * @param extraFilter 额外过滤条件（如 albumIds）
   * @param page 页码（从 1 开始）
   * @param size 每页数量
   * @returns 单页资产与总数；失败返回 null
   */
  async searchAssetsPage(extraFilter: Object, page: number, size: number): Promise<ImmichPageResult | null> {
    try {
      const body: Record<string, Object> = {
        'page': page as Object,
        'size': size as Object,
        'order': 'desc' as Object
      }
      // 合并额外过滤条件
      const extraRec = extraFilter as Record<string, Object>
      const keys: string[] = Object.keys(extraRec)
      for (let i = 0; i < keys.length; i++) {
        body[keys[i]] = extraRec[keys[i]]
      }
      const data: Object | null = await this.jsonPost('/search/metadata', body as Object)
      if (!data) {
        return null
      }
      const rec = data as Record<string, Object>
      const assetsResp = rec['assets'] as Record<string, Object>
      if (!assetsResp) {
        return null
      }
      const items: Object[] = (assetsResp['items'] as Object[]) || []
      const total: number = this.numOf(assetsResp, 'total')
      const result: ImmichPageResult = {
        items: this.parseAssets(items),
        total: total
      }
      return result
    } catch (e) {
      hilog.error(DOMAIN, TAG, `searchAssetsPage err: ${JSON.stringify(e)}`)
      return null
    }
  }

  /** 解析资产数组为 ImmichAsset 列表 */
  private parseAssets(assets: Object[]): ImmichAsset[] {
    const list: ImmichAsset[] = []
    for (const item of assets) {
      const a = item as Record<string, Object>
      const id: string = this.strOf(a, 'id')
      if (!id) continue
      // 拍摄时间：优先 EXIF 拍摄时间，其次文件创建时间，最后回退上传时间
      let takenAt: string = ''
      const exif = a['exifInfo'] as Record<string, Object>
      if (exif && typeof exif === 'object') {
        takenAt = this.strOf(exif, 'dateTimeOriginal')
      }
      if (!takenAt) {
        takenAt = this.strOf(a, 'fileCreatedAt')
      }
      if (!takenAt) {
        takenAt = this.strOf(a, 'createdAt')
      }
      list.push({
        id: id,
        type: this.strOf(a, 'type'),
        originalFileName: this.strOf(a, 'originalFileName'),
        createdAt: this.strOf(a, 'createdAt'),
        takenAt: takenAt,
        thumbhash: this.strOf(a, 'thumbhash'),
        width: this.numOf(a, 'width'),
        height: this.numOf(a, 'height'),
        thumbnailUrl: this.thumbnailUrl(id),
        originalUrl: this.originalUrl(id),
        videoUrl: this.strOf(a, 'type') === 'VIDEO' ? this.videoUrl(id) : ''
      })
    }
    return list
  }

  /** 安全读取字符串字段 */
  private strOf(rec: Record<string, Object>, key: string): string {
    const v = rec[key]
    if (v === undefined || v === null) return ''
    return String(v)
  }

  /** 安全读取数字字段 */
  private numOf(rec: Record<string, Object>, key: string): number {
    const v = rec[key]
    if (v === undefined || v === null) return 0
    const n = Number(v)
    return isNaN(n) ? 0 : n
  }
}
