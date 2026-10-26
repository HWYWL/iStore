/**
 * JellyfinDetailPage — Jellyfin 媒体详情页（对齐 MaFei dev 视觉）
 * 光感界面：全屏模糊海报背景（blur + scale + 渐变遮罩）
 * → Hero 标题/元信息 → 播放按钮 → 简介
 */
import { AppState } from '../../common/store/AppState'
import { ThemePalette } from '../../common/theme/ThemeColors'
import { JellyfinStore, JellyfinConfig } from '../../common/store/JellyfinStore'
import { JellyfinClient, JellyfinDetail, PlaybackInfo } from '../../api/JellyfinClient'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct JellyfinDetailPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State topSafeArea: number = 44
  @State itemId: string = ''
  @State itemName: string = ''
  @State imageUrl: string = ''
  @State detail: JellyfinDetail = { overview: '', genres: [], runTimeMs: 0, officialRating: '', communityRating: 0 }
  @State year: number = 0
  @State subtitle: string = ''      // 副标题（剧集 Sx:Ex）
  @State isLoading: boolean = true
  @State isPlaying: boolean = false
  private deviceId: string = ''
  private client: JellyfinClient | null = null

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.itemId = (params && params['id'] as string) || ''
    this.itemName = (params && params['name'] as string) || ''
    this.imageUrl = (params && params['image'] as string) || ''
    this.subtitle = (params && params['subtitle'] as string) || ''
    this.year = Number((params && params['year'] as number) || 0)
    if (this.year === 0) {
      this.year = this.parseYearFromName(this.itemName)
    }
    const dev = AppState.getInstance().getActiveDevice()
    this.deviceId = dev ? dev.id : ''
    this.loadDetail()
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) {
        window.getLastWindow(ctx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  async loadDetail(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (hostCtx) {
        await JellyfinStore.getInstance().init(hostCtx)
      }
      const cfg: JellyfinConfig | null = await JellyfinStore.getInstance().getConfig(this.deviceId)
      if (!cfg || !cfg.baseUrl || !cfg.token) {
        this.isLoading = false
        return
      }
      const client: JellyfinClient = new JellyfinClient(cfg.baseUrl, cfg.token, cfg.userName, cfg.password || '')
      this.client = client
      const d: JellyfinDetail = await client.getItemDetail(this.itemId)
      this.detail = d
      this.isLoading = false
    } catch (e) {
      this.isLoading = false
      hilog.error(0x0001, 'JellyfinDetail', `load err: ${String(e)}`)
    }
  }

  /** 立即播放 */
  async play(): Promise<void> {
    if (!this.client || this.isPlaying) return
    this.isPlaying = true
    try {
      const cfg: JellyfinConfig | null = await JellyfinStore.getInstance().getConfig(this.deviceId)
      if (!cfg) return
      const info: PlaybackInfo = await this.client.getPlaybackInfo(this.itemId, cfg.userId)
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/apps/JellyfinPlayerPage',
        params: { id: this.itemId, name: this.itemName, url: this.client.buildStreamUrl(info) }
      })
    } catch (e) {
      hilog.error(0x0001, 'JellyfinDetail', `play err: ${String(e)}`)
    } finally {
      this.isPlaying = false
    }
  }

  /** 时长格式化（X小时Y分钟） */
  fmtRuntime(ms: number): string {
    if (ms <= 0) return ''
    const totalMin: number = Math.floor(ms / 60000)
    const h: number = Math.floor(totalMin / 60)
    const m: number = totalMin % 60
    if (h > 0) return `${h}小时${m}分钟`
    return `${m}分钟`
  }

  /** 元信息行（MaFei 同款：年份 / 类型 / 时长） */
  infoLine(): string {
    const parts: string[] = []
    if (this.subtitle) parts.push(this.subtitle)
    if (this.year > 0) parts.push(`${this.year}`)
    if (this.detail.genres.length > 0) parts.push(this.detail.genres.join(' '))
    const rt: string = this.fmtRuntime(this.detail.runTimeMs)
    if (rt) parts.push(rt)
    return parts.join(' / ')
  }

  /** 从文件名解析年份（兜底：Jellyfin 未刮削 nfo 时） */
  parseYearFromName(name: string): number {
    const m = name.match(/(19|20)\d{2}/)
    if (m && m.length > 0) {
      return Number(m[0])
    }
    return 0
  }

  build() {
    Stack() {
      // ===== 全屏光感背景（模糊海报 + 渐变遮罩）=====
      if (this.imageUrl) {
        Image(this.imageUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: 1.18, y: 1.18 })
          .blur(128)
          .opacity(0.95)
      } else {
        Column()
          .width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [['#1A1E23', 0], ['#2B2A26', 1]] })
      }
      // 深色渐变遮罩（保证文字可读）
      Stack()
        .width('100%').height('100%')
        .linearGradient({
          angle: 0,
          colors: [
            ['rgba(20, 22, 26, 0.30)', 0],
            ['rgba(20, 22, 26, 0.55)', 0.56],
            ['rgba(12, 13, 15, 0.92)', 1]
          ]
        })

      // ===== 内容 =====
      Column() {
        // 顶部返回
        Row() {
          Text('‹')
            .fontSize(26).fontColor('#FFFFFF')
            .width(38).height(38)
            .backgroundColor('rgba(255,255,255,0.16)')
            .borderRadius(19)
            .textAlign(TextAlign.Center)
            .onClick(() => { AppNav.getInstance().back() })
        }
        .width('100%')
        .padding({ left: 16, top: this.topSafeArea + 8 })

        Blank()

        // Hero 元信息（底部）
        Column({ space: 10 }) {
          if (this.subtitle) {
            Text(this.subtitle)
              .fontSize(14).fontColor('rgba(255,255,255,0.85)')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.itemName)
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.infoLine())
            .fontSize(13).fontColor('#FFFFFF')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 8 })

        // 播放按钮（MaFei 同款：毛玻璃圆角）
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_circle_fill'))
              .fontSize(20)
              .fontColor(['#1A1E23'])
            Text(this.isPlaying ? '加载中…' : '立即播放')
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#1A1E23')
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(50)
        .borderRadius(25)
        .backgroundColor('rgba(255,255,255,0.88)')
        .shadow({ radius: 16, color: 'rgba(0,0,0,0.3)', offsetY: 4 })
        .margin({ left: 16, right: 16, top: 6 })
        .enabled(!this.isPlaying)
        .onClick(() => { this.play() })

        // 简介
        if (this.detail.overview) {
          Text(this.detail.overview)
            .fontSize(13).fontColor('rgba(255,255,255,0.78)')

            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 24 })
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Blank().height(30)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
