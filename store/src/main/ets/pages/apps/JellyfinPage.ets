/**
 * JellyfinPage — Jellyfin 媒体首页（对齐 MaFei dev 分支视觉）
 * 结构：chip 横向选择器（最近添加 + 媒体库）→ 3 列海报网格
 * 副标题规则（MaFei 同款）：
 *  - 电影: 年份
 *  - 剧集: Sx:Ex - 名称
 */
import { AppState } from '../../common/store/AppState'
import { ThemePalette } from '../../common/theme/ThemeColors'
import { JellyfinStore, JellyfinConfig } from '../../common/store/JellyfinStore'
import { JellyfinClient, JellyfinItem, JellyfinView } from '../../api/JellyfinClient'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

const RECENT_ID: string = '__recent__'
const CARD_GAP: number = 8
const GRID_GAP: number = 12

/** chip 项 */
interface ChipTab {
  id: string
  label: string
}

@Entry
@Component
struct JellyfinPageRoute {
  build() {
    Column() {
      JellyfinPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct JellyfinPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State topSafeArea: number = 44
  // 登录态
  @State configured: boolean = false
  @State isLogging: boolean = false
  @State baseUrlInput: string = ''
  @State usernameInput: string = ''
  @State passwordInput: string = ''
  @State errText: string = ''
  // 数据
  @State chips: ChipTab[] = []
  @State selectedChipId: string = RECENT_ID
  @State items: JellyfinItem[] = []
  @State views: JellyfinView[] = []
  @State isLoading: boolean = false
  @State loadErr: string = ''
  private deviceId: string = ''
  private client: JellyfinClient | null = null
  private cfg: JellyfinConfig | null = null
  private appCtx: common.UIAbilityContext | null = null

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.appCtx = hostCtx
      const dev = AppState.getInstance().getActiveDevice()
      this.deviceId = dev ? dev.id : ''
      this.initConfig()
    }
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) {
        window.getLastWindow(ctx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  async initConfig(): Promise<void> {
    if (!this.deviceId) return
    // 先等待 Preferences 初始化（冷启动竞态修复）
    if (this.appCtx) {
      await JellyfinStore.getInstance().init(this.appCtx)
    }
    const cfg: JellyfinConfig | null = await JellyfinStore.getInstance().getConfig(this.deviceId)
    // 旧版本配置无密码：引导重新登录
    if (cfg && cfg.baseUrl && cfg.token && !cfg.password) {
      this.baseUrlInput = cfg.baseUrl
      this.usernameInput = cfg.userName
      hilog.info(0x0001, 'Jellyfin', `旧配置无密码，需重新登录: ${cfg.baseUrl}`)
      return
    }
    if (cfg && cfg.baseUrl && cfg.token) {
      this.cfg = cfg
      this.client = new JellyfinClient(cfg.baseUrl, cfg.token, cfg.userName, cfg.password || '')
      this.client.onTokenRefresh = (newToken: string, newUid: string) => {
        if (this.cfg) {
          this.cfg.token = newToken
          this.cfg.userId = newUid
          if (this.deviceId) {
            JellyfinStore.getInstance().saveConfig(this.deviceId, this.cfg)
          }
        }
      }
      this.configured = true
      this.loadHome()
    }
  }

  /** 登录 */
  async doLogin(): Promise<void> {
    const baseUrl: string = this.baseUrlInput.trim().replace(/\/+$/, '')
    const username: string = this.usernameInput.trim()
    const password: string = this.passwordInput
    if (!baseUrl || !username || !password) {
      this.errText = '请填写服务器地址、用户名和密码'
      return
    }
    this.isLogging = true
    this.errText = ''
    try {
      const tempClient = new JellyfinClient(baseUrl)
      const auth = await tempClient.login(username, password)
      this.cfg = { baseUrl: baseUrl, token: auth.token, userId: auth.userId, userName: auth.userName, password: password }
      this.client = tempClient
      this.client.onTokenRefresh = (newToken: string, newUid: string) => {
        if (this.cfg) {
          this.cfg.token = newToken
          this.cfg.userId = newUid
          if (this.deviceId) {
            JellyfinStore.getInstance().saveConfig(this.deviceId, this.cfg)
          }
        }
      }
      if (this.deviceId) {
        await JellyfinStore.getInstance().saveConfig(this.deviceId, this.cfg)
      }
      this.configured = true
      this.loadHome()
    } catch (e) {
      this.errText = `登录失败：${(e as Error).message || String(e)}`
    } finally {
      this.isLogging = false
    }
  }

  /** 登出 */
  async doLogout(): Promise<void> {
    if (this.deviceId) {
      await JellyfinStore.getInstance().clearConfig(this.deviceId)
    }
    this.configured = false
    this.cfg = null
    this.client = null
    this.chips = []
    this.items = []
    this.views = []
  }

  /** 加载首页：views → chips（最近添加 + 各媒体库）→ 选中项内容 */
  async loadHome(): Promise<void> {
    if (!this.client || !this.cfg) return
    this.isLoading = true
    this.loadErr = ''
    try {
      this.views = await this.client.getViews(this.cfg.userId)
      const tabs: ChipTab[] = [{ id: RECENT_ID, label: '最近添加' }]
      for (let i = 0; i < this.views.length; i++) {
        tabs.push({ id: this.views[i].id, label: this.views[i].name })
      }
      this.chips = tabs
      await this.loadSelectedItems()
    } catch (e) {
      this.loadErr = `加载失败：${(e as Error).message || String(e)}`
    } finally {
      this.isLoading = false
    }
  }

  /** 加载当前选中 chip 的内容 */
  async loadSelectedItems(): Promise<void> {
    if (!this.client || !this.cfg) return
    this.isLoading = true
    this.loadErr = ''
    try {
      if (this.selectedChipId === RECENT_ID) {
        this.items = await this.client.getLatest(this.cfg.userId)
      } else {
        const view: JellyfinView | undefined = this.views.find((v: JellyfinView) => v.id === this.selectedChipId)
        if (view) {
          this.items = await this.client.getItems(this.cfg.userId, view.id)
        }
      }
    } catch (e) {
      this.loadErr = `加载失败：${(e as Error).message || String(e)}`
    } finally {
      this.isLoading = false
    }
  }

  /** chip 切换 */
  selectChip(id: string): void {
    if (id === this.selectedChipId) return
    this.selectedChipId = id
    this.loadSelectedItems()
  }

  // ===== 副标题（MaFei 同款规则） =====
  itemSubtitle(item: JellyfinItem): string {
    if (item.type === 'Episode') {
      return `S${item.season}:E${item.episode} - ${item.name}`
    }
    if (item.year > 0) {
      return `${item.year}`
    }
    return ''
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('‹')
          .fontSize(24).fontColor(this.theme.textPrimary)
          .padding({ left: 4, right: 12, top: 2, bottom: 2 })
          .onClick(() => { AppNav.getInstance().back() })
        Text('Jellyfin')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
        if (this.cfg) {
          Text(this.cfg.userName)
            .fontSize(11).fontColor(this.theme.textTertiary).margin({ left: 8 })
        }
        Blank()
        if (this.configured) {
          Text('退出')
            .fontSize(12).fontColor(this.theme.textTertiary).padding(8)
            .onClick(() => { this.doLogout() })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      if (!this.configured) {
        // ===== 登录表单 =====
        Scroll() {
          Column() {
            Text('🎬')
              .fontSize(46).textAlign(TextAlign.Center).width('100%').margin({ top: 40 })
            Text('Jellyfin 媒体中心')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
              .width('100%').textAlign(TextAlign.Center).margin({ top: 10 })
            Text('连接你的电影、剧集与音乐')
              .fontSize(12).fontColor(this.theme.textTertiary)
              .width('100%').textAlign(TextAlign.Center).margin({ top: 5 })

            Column() {
              TextInput({ placeholder: '服务器地址（如 http://192.168.1.1:8096）', text: this.baseUrlInput })
                .fontSize(13).height(46).borderRadius(12)
                .backgroundColor(this.theme.bgCard).placeholderColor(this.theme.textTertiary)
                .fontColor(this.theme.textPrimary)
                .onChange((v: string) => { this.baseUrlInput = v })
              TextInput({ placeholder: '用户名', text: this.usernameInput })
                .fontSize(13).height(46).borderRadius(12)
                .backgroundColor(this.theme.bgCard).placeholderColor(this.theme.textTertiary)
                .fontColor(this.theme.textPrimary)
                .onChange((v: string) => { this.usernameInput = v })
                .margin({ top: 10 })
              TextInput({ placeholder: '密码', text: this.passwordInput })
                .fontSize(13).height(46).borderRadius(12)
                .backgroundColor(this.theme.bgCard).placeholderColor(this.theme.textTertiary)
                .fontColor(this.theme.textPrimary)
                .type(InputType.Password)
                .onChange((v: string) => { this.passwordInput = v })
                .margin({ top: 10 })
              if (this.errText) {
                Text(this.errText).fontSize(11).fontColor(this.theme.warning).margin({ top: 8 })
              }
              Text(this.isLogging ? '登录中…' : '登录')
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(14)
                .backgroundColor(this.theme.primary)
                .shadow({ radius: 10, color: 'rgba(255,138,61,0.3)', offsetY: 4 })
                .margin({ top: 16 })
                .onClick(() => { this.doLogin() })
            }
            .width('100%')
            .padding(16)
            .borderRadius(20)
            .backgroundColor(this.theme.bgCard)
            .shadow({ radius: 12, color: 'rgba(180,160,120,0.14)', offsetY: 4 })
            .margin({ top: 30 })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        // ===== 首页：chip 选择器 + 海报网格 =====
        Column() {
          // chip 横向选择器（MaFei 同款：圆角胶囊，选中主色）
          List({ space: CARD_GAP }) {
            ForEach(this.chips, (tab: ChipTab) => {
              ListItem() {
                Text(tab.label)
                  .fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(this.selectedChipId === tab.id ? '#FFFFFF' : this.theme.textSecondary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .height(36)
                  .padding({ left: 14, right: 14 })
                  .borderRadius(18)
                  .backgroundColor(this.selectedChipId === tab.id ? this.theme.primary : this.theme.bgCard)
                  .animation({ duration: 220, curve: Curve.EaseOut })
                  .onClick(() => { this.selectChip(tab.id) })
              }
            }, (tab: ChipTab) => tab.id)
          }
          .width('100%')
          .height(40)
          .padding({ left: 12, right: 12 })
          .listDirection(Axis.Horizontal)
          .scrollBar(BarState.Off)

          // 内容区：海报网格
          if (this.isLoading && this.items.length === 0) {
            // 骨架屏（MaFei 同款：灰色占位卡）
            Grid() {
              ForEach([0, 1, 2, 3, 4, 5], () => {
                GridItem() {
                  Column({ space: 8 }) {
                    Column()
                      .width('100%')
                      .aspectRatio(0.67)
                      .borderRadius(10)
                      .backgroundColor('rgba(232,226,214,0.8)')
                    Column()
                      .width('80%').height(14).borderRadius(7)
                      .backgroundColor('rgba(232,226,214,0.8)')
                  }
                  .alignItems(HorizontalAlign.Start)
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(GRID_GAP).rowsGap(GRID_GAP)
            .width('100%')
            .padding({ left: 12, right: 12, top: GRID_GAP })
            .opacity(0.7)
            .scrollBar(BarState.Off)
          } else if (this.loadErr) {
            Column() {
              Text('⚠ ' + this.loadErr).fontSize(12).fontColor(this.theme.warning).textAlign(TextAlign.Center)
              Text('点击重试').fontSize(13).fontColor(this.theme.primary).padding({ top: 10 })
                .onClick(() => { this.loadSelectedItems() })
            }
            .width('100%').padding({ top: 60 }).alignItems(HorizontalAlign.Center)
          } else if (this.items.length === 0) {
            // 空态（MaFei 同款文案）
            Row() {
              Text(this.selectedChipId === RECENT_ID ? '暂无最近添加内容' : '该媒体库暂无内容')
                .fontSize(14).fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .height(96)
            .justifyContent(FlexAlign.Center)
          } else {
            // 3 列海报网格（MaFei 同款：图 10 圆角 + 名称 + 副标题）
            Grid() {
              ForEach(this.items, (item: JellyfinItem) => {
                GridItem() {
                  Column({ space: 8 }) {
                    if (item.imageUrl) {
                      Image(item.imageUrl)
                        .width('100%')
                        .aspectRatio(0.67)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(10)
                        .border({ width: 0.5, color: 'rgba(180,160,120,0.25)' })
                        .backgroundColor('rgba(246,242,234,0.8)')
                    } else {
                      Column() {
                        AppIcon({ name: 'template_fill', iconSize: 30, colors: ['#B4AFA4'] })
                      }
                        .width('100%')
                        .aspectRatio(0.67)
                        .borderRadius(10)
                        .justifyContent(FlexAlign.Center)
                        .backgroundColor('rgba(246,242,234,0.8)')
                    }
                    Column() {
                      Text(item.name)
                        .fontSize(13).fontColor(this.theme.textPrimary)
                        .fontWeight(FontWeight.Medium)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.itemSubtitle(item))
                        .fontSize(11).fontColor(this.theme.textTertiary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => {
                    // 点击 → 详情页（对齐 MaFei：详情 → 光感界面 → 播放）
                    this.getUIContext().getRouter().pushUrl({
                      url: 'pages/apps/JellyfinDetailPage',
                      params: { id: item.id, name: item.name, image: item.imageUrl, subtitle: this.itemSubtitle(item), year: item.year }
                    })
                  })
                }
              }, (item: JellyfinItem) => `${this.selectedChipId}:${item.id}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(GRID_GAP).rowsGap(GRID_GAP)
            .width('100%')
            .padding({ left: 12, right: 12, top: GRID_GAP, bottom: 20 })
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }
}
