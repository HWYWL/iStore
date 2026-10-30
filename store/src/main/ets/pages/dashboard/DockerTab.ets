import { AppState } from '../../common/store/AppState'
import {ThemePalette} from '../../common/theme/ThemeColors'
import { DockerOverview, DockerContainer, DockerStats, DockerImage, DockerNetwork } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { Poller } from '../../common/utils/Poller'
import { AppIcon } from '../../common/components/AppIcon'

@Component
export struct DockerTab {
  @Prop theme: ThemePalette
  @State overview: DockerOverview = { dockerVersion: '', daemonStatus: 'stopped', containersTotal: 0, containersRunning: 0, imagesTotal: 0, diskUsed: '0', memUsedMb: '0' }
  @State containers: DockerContainer[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State actionContainer: string = ''
  @State dockerStarting: boolean = false
  @State isRefreshing: boolean = false
  @State statsMap: Map<string, DockerStats> = new Map()
  @State istoreIcons: Map<string, string> = new Map()
  @State apiAvailable: boolean = false
  @State showApiConfirm: boolean = false
  @State apiEnabling: boolean = false
  @State iconFailed: string[] = []  // 远程 logo 加载失败的容器（回退默认 docker_logo）
  @State viewIndex: number = 0  // 0=容器 / 1=镜像 / 2=网络
  @State images: DockerImage[] = []
  @State imagesLoading: boolean = false
  @State networks: DockerNetwork[] = []
  @State networksLoading: boolean = false
  private api: ApiService = ApiService.getInstance()
  private lastScrollY: number = 0

  /** 格式化镜像大小 */
  fmtImageSize(bytes: number): string {
    if (bytes >= 1073741824) return `${(bytes / 1073741824).toFixed(2)} GB`
    if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`
    if (bytes >= 1024) return `${(bytes / 1024).toFixed(0)} KB`
    return `${bytes} B`
  }

  /** 格式化镜像创建时间 */
  fmtImageCreated(ts: number): string {
    if (!ts) return '--'
    const d: Date = new Date(ts * 1000)
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
  }

  /** 加载镜像列表 */
  async loadImages(): Promise<void> {
    this.imagesLoading = true
    try {
      this.images = await this.api.fetchDockerImages()
    } catch (e) {
      hilog.error(0x0001, 'DockerTab', `loadImages err: ${JSON.stringify(e)}`)
    }
    this.imagesLoading = false
  }

  /** 加载网络列表 */
  async loadNetworks(): Promise<void> {
    this.networksLoading = true
    try {
      this.networks = await this.api.fetchDockerNetworks()
    } catch (e) {
      hilog.error(0x0001, 'DockerTab', `loadNetworks err: ${JSON.stringify(e)}`)
    }
    this.networksLoading = false
  }

  /** 切换 容器/镜像/网络 视图 */
  switchView(idx: number): void {
    if (this.viewIndex === idx) return
    this.viewIndex = idx
    if (idx === 1 && this.images.length === 0) {
      this.loadImages()
    } else if (idx === 2 && this.networks.length === 0) {
      this.loadNetworks()
    }
  }

  /** 标记远程图标加载失败（回退默认图标） */
  markIconFailed(name: string): void {
    if (this.iconFailed.indexOf(name) < 0) {
      this.iconFailed.push(name)
    }
  }

  /** 加载 iStore 已安装应用图标映射（容器名 → iStore 应用图标 URL） */
  private istoreIconsLoaded: boolean = false
  private async loadIStoreIcons(): Promise<void> {
    if (this.istoreIconsLoaded) {
      return
    }
    try {
      const apps = await this.api.fetchIStoreApps()
      const base = this.api.getBaseUrl()
      const map: Map<string, string> = new Map()
      for (let i = 0; i < apps.length; i++) {
        const app = apps[i]
        if (app && app.name) {
          map.set(app.name.toLowerCase(), `${base}/luci-static/resources/app-icons/${app.name}.png`)
        }
      }
      if (map.size > 0) {
        this.istoreIcons = map
      }
      this.istoreIconsLoaded = true
    } catch (e) {
      hilog.error(0x0001, 'DockerTab', `loadIStoreIcons err: ${String(e)}`)
      this.istoreIconsLoaded = true
    }
  }
  private poller: Poller | null = null
  private isVisible: boolean = false
  private tabChangeListener: ((tab: number) => void) | null = null

  aboutToAppear(): void {
    this.apiAvailable = this.api.hasDockerApi()
    // 前台感知：仅当本 Tab（Docker index 3）可见时轮询
    this.isVisible = AppState.getInstance().getCurrentTab() === 3
    // 统一轮询器：静默刷新 + 上轮未返回则跳过
    this.poller = new Poller((): Promise<void> => this.refreshSilently(), 5000)
    this.tabChangeListener = (tab: number) => {
      const visible: boolean = tab === 3
      if (visible && !this.isVisible) {
        this.isVisible = true
        this.loadData()
        if (this.poller) {
          this.poller.start()
        }
      } else if (!visible && this.isVisible) {
        this.isVisible = false
        if (this.poller) {
          this.poller.stop()
        }
      }
    }
    AppState.getInstance().onTabChange(this.tabChangeListener)
    this.loadData()
    if (this.isVisible && this.poller) {
      this.poller.start()
    }
  }

  aboutToDisappear(): void {
    if (this.poller) {
      this.poller.dispose()
      this.poller = null
    }
    if (this.tabChangeListener) {
      AppState.getInstance().offTabChange(this.tabChangeListener)
      this.tabChangeListener = null
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      this.overview = await this.api.fetchDockerOverview()
      if (this.overview.daemonStatus === 'running') {
        this.containers = await this.api.fetchDockerContainers()
        this.fetchStats()
      }
      this.loadIStoreIcons()
    } catch (e) {
      // 统一错误层：优先展示底层给出的可读原因（超时/权限/会话失效等）
      this.errorText = this.api.getLastError() || '加载失败'
    }
    this.isLoading = false
  }

  async refreshSilently(): Promise<void> {
    try {
      this.overview = await this.api.fetchDockerOverview()
      if (this.overview.daemonStatus === 'running') {
        this.containers = await this.api.fetchDockerContainers()
        this.fetchStats()
      }
      this.loadIStoreIcons()
    } catch (e) {
      hilog.error(0x0001, 'DockerTab', `refreshSilently err: ${String(e)}`)
    }
  }

  /** 拉取容器实时统计（CPU%/MEM%），仅 Docker API 可用时有数据 */
  async fetchStats(): Promise<void> {
    try {
      if (this.overview.daemonStatus !== 'running' || this.containers.length === 0) {
        return
      }
      const stats = await this.api.fetchDockerStats()
      if (stats.length === 0) {
        return
      }
      const newMap = new Map<string, DockerStats>()
      for (let i = 0; i < stats.length; i++) {
        newMap.set(stats[i].name, stats[i])
      }
      this.statsMap = newMap
    } catch (e) {
      hilog.error(0x0001, 'DockerTab', `fetchStats err: ${String(e)}`)
    }
  }

  async startDocker(): Promise<void> {
    this.dockerStarting = true
    const ok = await this.api.dockerServiceAction('start')
    if (ok) {
      await this.loadData()
    } else {
      this.errorText = '启动 Docker 失败'
    }
    this.dockerStarting = false
  }

  /** 开启 Docker Remote API（容器会短暂重启） */
  async enableApi(): Promise<void> {
    this.apiEnabling = true
    const ok = await this.api.enableDockerApi()
    this.apiAvailable = this.api.hasDockerApi()
    if (!this.apiAvailable) {
      this.errorText = ok ? 'Docker API 已开启，但探测失败，请稍后重试' : '开启 Docker API 失败'
    }
    this.apiEnabling = false
    this.showApiConfirm = false
    await this.loadData()
  }

  async onRefresh(): Promise<void> {
    this.isRefreshing = true
    await this.loadData()
    this.isRefreshing = false
  }

  async containerAction(container: string, action: string): Promise<void> {
    this.actionContainer = container
    const ok = await this.api.dockerContainerAction(container, action)
    if (ok) {
      this.containers = this.containers.map((c: DockerContainer): DockerContainer => {
        if (c.name === container) {
          const updated: DockerContainer = { id: c.id, name: c.name, image: c.image, running: c.running, status: c.status }
          switch (action) {
            case 'start':
              updated.status = 'Starting...'
              break
            case 'stop':
              updated.status = 'Stopping...'
              break
            case 'restart':
              updated.status = 'Restarting...'
              updated.running = false
              break
          }
          return updated
        }
        return c
      })
      setTimeout(async () => {
        await this.refreshSilently()
        this.actionContainer = ''
        this.isRefreshing = true
        setTimeout(() => { this.isRefreshing = false }, 400)
      }, 2000)
    } else {
      this.errorText = `${action} ${container} 失败`
      this.actionContainer = ''
    }
  }

  /** 由语义色生成半透明底色（随皮肤切换） */
  tint(hex: string, alpha: number): string {
    let c: string = hex
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    let r: number = 0
    let g: number = 0
    let b: number = 0
    try {
      r = parseInt(c.substring(0, 2), 16)
      g = parseInt(c.substring(2, 4), 16)
      b = parseInt(c.substring(4, 6), 16)
    } catch (e) {
      return 'rgba(0,0,0,0.08)'
    }
    return `rgba(${r},${g},${b},${alpha})`
  }

  getStatusColor(): string {
    return this.overview.daemonStatus === 'running' ? this.theme.success : this.theme.danger
  }

  getStatusText(): string {
    return this.overview.daemonStatus === 'running' ? '运行中' : '已停止'
  }

  /**
   * 容器图标：仅使用 iStore 已安装应用的图标（容器名 == iStore 应用名，
   * 即 iStore 商店安装的容器，图标取路由器本地 /luci-static/resources/app-icons/<app>.png）。
   * 未匹配返回空串 → 使用默认 Docker 图标
   */
  containerIcon(c: DockerContainer): string {
    if (c && c.name) {
      const istoreUrl = this.istoreIcons.get(c.name.toLowerCase())
      if (istoreUrl && istoreUrl.length > 0) {
        return istoreUrl
      }
    }
    return ''
  }

  cpuText(c: DockerContainer): string {
    const s = this.statsMap.get(c.name)
    return s ? s.cpuPercent.toFixed(1) : ''
  }

  memText(c: DockerContainer): string {
    const s = this.statsMap.get(c.name)
    return s ? s.memPercent.toFixed(1) : ''
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          Row() {
            Image($r('app.media.docker_logo')).width(28).height(28).margin({ right: 8 })
            Text('Docker')
              .fontSize(24).fontWeight(FontWeight.Bold)
              .fontColor(this.theme.textPrimary)
          }
          .width('100%').margin({ top: 12 })

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.theme.primary)
            Text('加载中...').fontSize(13).fontColor(this.theme.textTertiary).margin({ top: 12 })
          }
          .width('100%').padding(40).alignItems(HorizontalAlign.Center).margin({ top: 20 })
        } else if (this.errorText && this.containers.length === 0 && this.overview.daemonStatus !== 'running') {
          Text(this.errorText)
            .fontSize(13).fontColor(this.theme.textTertiary)
            .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
        } else {
          // ========== 概览卡片 ==========
          Row() {
            Column() {
              Text('Daemon')
                .fontSize(12).fontColor(this.theme.textTertiary)
              Row() {
                Circle({ width: 8, height: 8 }).foregroundColor(this.getStatusColor())
                Text(this.getStatusText())
                  .fontSize(20).fontColor(this.getStatusColor()).fontWeight(FontWeight.Bold)
                  .margin({ left: 6 })
              }
              .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center).layoutWeight(1)

            Column() {
              Text('容器')
                .fontSize(12).fontColor(this.theme.textTertiary)
              Text(`${this.overview.containersRunning}/${this.overview.containersTotal}`)
                .fontSize(20).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            }
            .alignItems(HorizontalAlign.Center).layoutWeight(1)

            Column() {
              Text('镜像')
                .fontSize(12).fontColor(this.theme.textTertiary)
              Text(`${this.overview.imagesTotal}`)
                .fontSize(20).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            }
            .alignItems(HorizontalAlign.Center).layoutWeight(1)

            Column() {
              Text('版本')
                .fontSize(12).fontColor(this.theme.textTertiary)
              Text(this.overview.dockerVersion || '-')
                .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            }
            .alignItems(HorizontalAlign.Center).layoutWeight(1)
          }
          .width('100%').padding(20).borderRadius(24).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard).backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })

          if (this.overview.daemonStatus !== 'running') {
            Row() {
              Text('Docker 服务未运行')
                .fontSize(13).fontColor(this.theme.textSecondary).layoutWeight(1)
              if (this.dockerStarting) {
                Row() {
                  LoadingProgress().width(14).height(14).color(this.theme.primary)
                  Text('启动中...').fontSize(13).fontColor(this.theme.primary).margin({ left: 6 })
                }
                .padding({ top: 8, bottom: 8, left: 16, right: 16 }).borderRadius(8)
                .backgroundColor(this.theme.bgGlassLight)
              } else {
                Text('启动 Docker')
                  .fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
                  .padding({ top: 8, bottom: 8, left: 16, right: 16 }).borderRadius(8)
                  .backgroundColor(this.theme.bgGlassLight)
                  .onClick(() => { this.startDocker() })
              }
            }
            .width('100%').padding(18).borderRadius(20).margin({ top: 12 })
            .backgroundColor(this.theme.bgCard).backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          } else {
            // ========== Docker API 开启引导（未开启时显示） ==========
            if (!this.apiAvailable) {
              Column() {
                Row() {
                  AppIcon({ name: 'lightbulb', iconSize: 14, colors: ['#F59E0B'] })
                  Text('开启 Docker API 后，可显示容器 CPU / 内存实时统计')
                    .fontSize(12).fontColor(this.theme.textSecondary)
                    .layoutWeight(1).margin({ left: 8 })
                }
                .width('100%')

                if (this.apiEnabling) {
                  Row() {
                    LoadingProgress().width(14).height(14).color(this.theme.primary)
                    Text('正在开启（约 10 秒，容器会短暂重启）...')
                      .fontSize(12).fontColor(this.theme.primary).margin({ left: 8 })
                  }
                  .margin({ top: 10 })
                } else if (this.showApiConfirm) {
                  Row() {
                    Text('容器将短暂重启，确认开启？')
                      .fontSize(12).fontColor(this.theme.warning).layoutWeight(1)
                    Text('取消')
                      .fontSize(12).fontColor(this.theme.textTertiary)
                      .padding({ top: 6, bottom: 6, left: 12, right: 12 })
                      .onClick(() => { this.showApiConfirm = false })
                    Text('确认开启')
                      .fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                      .padding({ top: 6, bottom: 6, left: 12, right: 12 }).borderRadius(8)
                      .backgroundColor(this.theme.primary).margin({ left: 8 })
                      .onClick(() => { this.enableApi() })
                  }
                  .width('100%').margin({ top: 10 })
                } else {
                  Row() {
                    Blank()
                    Text('立即开启')
                      .fontSize(12).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
                      .padding({ top: 6, bottom: 6, left: 14, right: 14 }).borderRadius(8)
                      .backgroundColor(this.theme.bgGlassLight)
                      .onClick(() => { this.showApiConfirm = true })
                  }
                  .width('100%').margin({ top: 8 })
                }
              }
              .width('100%').padding(16).borderRadius(20).margin({ top: 12 })
              .backgroundColor(this.theme.bgCard).backdropBlur(20)
              .border({ width: 0.5, color: this.theme.borderGlass })
            }

            // ========== 容器 / 镜像 / 网络 切换 ==========
            Row() {
              Row() {
                AppIcon({ name: 'rectangle_stack', iconSize: 13, colors: [this.viewIndex === 0 ? '#3B82F6' : this.theme.textTertiary] })
                Text(' 容器')
                  .fontSize(12)
                  .fontColor(this.viewIndex === 0 ? this.theme.textPrimary : this.theme.textTertiary)
                  .fontWeight(this.viewIndex === 0 ? FontWeight.Medium : FontWeight.Normal)
              }
              .padding({ left: 18, right: 18, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor(this.viewIndex === 0 ? this.theme.bgCardHover : 'transparent')
              .border(this.viewIndex === 0 ? { width: 0.5, color: this.theme.primary } : {})
              .onClick(() => { this.switchView(0) })

              Row() {
                AppIcon({ name: 'archivebox', iconSize: 13, colors: [this.viewIndex === 1 ? '#8B5CF6' : this.theme.textTertiary] })
                Text(' 镜像')
                  .fontSize(12)
                  .fontColor(this.viewIndex === 1 ? this.theme.textPrimary : this.theme.textTertiary)
                  .fontWeight(this.viewIndex === 1 ? FontWeight.Medium : FontWeight.Normal)
              }
              .padding({ left: 18, right: 18, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor(this.viewIndex === 1 ? this.theme.bgCardHover : 'transparent')
              .border(this.viewIndex === 1 ? { width: 0.5, color: this.theme.primary } : {})
              .margin({ left: 10 })
              .onClick(() => { this.switchView(1) })

              Row() {
                AppIcon({ name: 'globe_badge_message', iconSize: 13, colors: [this.viewIndex === 2 ? '#10B981' : this.theme.textTertiary] })
                Text(' 网络')
                  .fontSize(12)
                  .fontColor(this.viewIndex === 2 ? this.theme.textPrimary : this.theme.textTertiary)
                  .fontWeight(this.viewIndex === 2 ? FontWeight.Medium : FontWeight.Normal)
              }
              .padding({ left: 18, right: 18, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor(this.viewIndex === 2 ? this.theme.bgCardHover : 'transparent')
              .border(this.viewIndex === 2 ? { width: 0.5, color: this.theme.primary } : {})
              .margin({ left: 10 })
              .onClick(() => { this.switchView(2) })

              Blank()
              Text(this.viewIndex === 0 ? `${this.containers.length} 个容器`
                : this.viewIndex === 1 ? `${this.images.length} 个镜像`
                  : `${this.networks.length} 个网络`)
                .fontSize(11).fontColor(this.theme.textTertiary)
            }
            .width('100%')
            .padding({ left: 4, top: 12, bottom: 6 })

            // ========== 容器视图 ==========
            if (this.viewIndex === 0) {
              if (this.containers.length > 0) {
              ForEach(this.containers, (c: DockerContainer) => {
                Column() {
                  Row() {
                    Column() {
                      if (this.actionContainer === c.name) {
                        LoadingProgress().width(18).height(18).color(this.theme.primary)
                      } else if (this.iconFailed.indexOf(c.name) >= 0 || !this.containerIcon(c)) {
                        // 无 iStore 图标或加载失败 → 默认 Docker 图标
                        Image($r('app.media.docker_logo'))
                          .width(28).height(28).objectFit(ImageFit.Contain)
                      } else {
                        Image(this.containerIcon(c))
                          .width(40).height(40).objectFit(ImageFit.Cover).borderRadius(12)
                          .onError(() => { this.markIconFailed(c.name) })
                      }
                    }
                    .width(40).height(40)
                    .justifyContent(FlexAlign.Center)

                    Column() {
                      Text(c.name)
                        .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        Circle({ width: 6, height: 6 })
                          .foregroundColor(c.running ? this.theme.success : this.theme.textTertiary)
                        Text(this.actionContainer === c.name ? '操作中...' : c.status)
                          .fontSize(11).fontColor(this.theme.textTertiary)
                          .margin({ left: 5 })
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .margin({ top: 3 })
                    }
                    .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })

                    if (this.actionContainer !== c.name) {
                      if (c.running) {
                        Text('停止')
                          .fontSize(11).fontColor(this.theme.danger).fontWeight(FontWeight.Medium)
                          .padding({ top: 8, bottom: 8, left: 14, right: 14 }).borderRadius(10)
                          .backgroundColor(this.theme.bgGlassLight)
                          .onClick(() => { this.containerAction(c.name, 'stop') })
                        Text('重启')
                          .fontSize(11).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
                          .padding({ top: 8, bottom: 8, left: 14, right: 14 }).borderRadius(10)
                          .backgroundColor(this.theme.bgGlassLight).margin({ left: 6 })
                          .onClick(() => { this.containerAction(c.name, 'restart') })
                      } else {
                        Text('启动')
                          .fontSize(11).fontColor(this.theme.success).fontWeight(FontWeight.Medium)
                          .padding({ top: 8, bottom: 8, left: 18, right: 18 }).borderRadius(10)
                          .backgroundColor(this.theme.bgGlassLight)
                          .onClick(() => { this.containerAction(c.name, 'start') })
                      }
                    }
                  }
                  .width('100%')

                  Row() {
                    Text(c.image)
                      .fontSize(10).fontColor(this.theme.textTertiary)
                      .layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (c.running && this.cpuText(c) !== '') {
                      Text(`CPU ${this.cpuText(c)}%`)
                        .fontSize(10).fontColor(this.theme.warning)
                        .padding({ top: 3, bottom: 3, left: 8, right: 8 }).borderRadius(8)
                        .backgroundColor(this.tint(this.theme.warning, 0.12))
                      Text(`MEM ${this.memText(c)}%`)
                        .fontSize(10).fontColor(this.theme.info)
                        .padding({ top: 3, bottom: 3, left: 8, right: 8 }).borderRadius(8)
                        .backgroundColor(this.tint(this.theme.info, 0.12)).margin({ left: 6 })
                    }
                  }
                  .width('100%').margin({ top: 10 })
                }
                .width('100%').padding(16).borderRadius(20).margin({ top: 10 })
                .backgroundColor(this.theme.bgCard).backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
              }, (c: DockerContainer): string => c.id)
              } else {
                Text('暂无容器')
                  .fontSize(12).fontColor(this.theme.textTertiary)
                  .width('100%').textAlign(TextAlign.Center).padding(20)
              }
            } else if (this.viewIndex === 1) {
              // ========== 镜像视图 ==========
              if (this.imagesLoading) {
                Row() {
                  LoadingProgress().width(18).height(18).color(this.theme.primary)
                  Text(' 加载镜像中…').fontSize(12).fontColor(this.theme.textTertiary)
                }
                .width('100%').justifyContent(FlexAlign.Center).padding(24)
              } else if (this.images.length > 0) {
                ForEach(this.images, (img: DockerImage) => {
                  Column() {
                    Row() {
                      Column() {
                        Image($r('app.media.docker_logo'))
                          .width(24).height(24).objectFit(ImageFit.Contain)
                      }
                      .width(40).height(40)
                      .justifyContent(FlexAlign.Center)

                      Column() {
                        // 悬空镜像（无标签）用 ID 作标题
                        Text(img.repoTag === '<none>:<none>' ? img.id : img.repoTag)
                          .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (img.repoTag === '<none>:<none>') {
                          Text('悬空镜像（无标签）')
                            .fontSize(10).fontColor(this.theme.warning)
                            .margin({ top: 3 })
                        } else {
                          Text(`ID ${img.id}`)
                            .fontSize(10).fontColor(this.theme.textTertiary)
                            .margin({ top: 3 })
                            .fontFamily('monospace')
                        }
                      }
                      .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })

                      Column() {
                        Text(this.fmtImageSize(img.size))
                          .fontSize(12).fontColor(this.theme.textPrimary)
                        Text(this.fmtImageCreated(img.created))
                          .fontSize(10).fontColor(this.theme.textTertiary)
                          .margin({ top: 3 })
                      }
                      .alignItems(HorizontalAlign.End)
                    }
                    .width('100%')
                  }
                  .width('100%').padding(16).borderRadius(20).margin({ top: 10 })
                  .backgroundColor(this.theme.bgCard).backdropBlur(20)
                  .border({ width: 0.5, color: this.theme.borderGlass })
                }, (img: DockerImage): string => img.id)
              } else {
                Column() {
                  Text('暂无镜像')
                    .fontSize(12).fontColor(this.theme.textTertiary)
                    .width('100%').textAlign(TextAlign.Center).padding({ top: 20 })
                  if (!this.api.hasDockerApi()) {
                    Text('开启 Docker API 后可查看镜像列表')
                      .fontSize(11).fontColor(this.theme.warning)
                      .width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 20 })
                  }
                }
                .width('100%')
              }
            } else {
              // ========== 网络视图 ==========
              if (this.networksLoading) {
                Row() {
                  LoadingProgress().width(18).height(18).color(this.theme.primary)
                  Text(' 加载网络中…').fontSize(12).fontColor(this.theme.textTertiary)
                }
                .width('100%').justifyContent(FlexAlign.Center).padding(24)
              } else if (this.networks.length > 0) {
                ForEach(this.networks, (nw: DockerNetwork) => {
                  Column() {
                    Row() {
                      Column() {
                        AppIcon({ name: 'globe_badge_message', iconSize: 20, colors: ['#10B981'] })
                      }
                      .width(40).height(40)
                      .justifyContent(FlexAlign.Center)

                      Column() {
                        Text(nw.name)
                          .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`ID ${nw.id}`)
                          .fontSize(10).fontColor(this.theme.textTertiary)
                          .margin({ top: 3 })
                          .fontFamily('monospace')
                      }
                      .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })

                      Column() {
                        Text(nw.driver)
                          .fontSize(11).fontColor(this.theme.primary)
                          .padding({ top: 3, bottom: 3, left: 10, right: 10 })
                          .borderRadius(8)
                          .backgroundColor(this.tint(this.theme.info, 0.12))
                        Text(nw.scope === 'local' ? '本地' : nw.scope)
                          .fontSize(10).fontColor(this.theme.textTertiary)
                          .margin({ top: 4 })
                      }
                      .alignItems(HorizontalAlign.End)
                    }
                    .width('100%')
                  }
                  .width('100%').padding(16).borderRadius(20).margin({ top: 10 })
                  .backgroundColor(this.theme.bgCard).backdropBlur(20)
                  .border({ width: 0.5, color: this.theme.borderGlass })
                }, (nw: DockerNetwork): string => nw.id)
              } else {
                Column() {
                  Text('暂无网络')
                    .fontSize(12).fontColor(this.theme.textTertiary)
                    .width('100%').textAlign(TextAlign.Center).padding({ top: 20 })
                  if (!this.api.hasDockerApi()) {
                    Text('开启 Docker API 后可查看网络列表')
                      .fontSize(11).fontColor(this.theme.warning)
                      .width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 20 })
                  }
                }
                .width('100%')
              }
            }
          }
        }
      }
      .width('100%').padding({ left: 16, right: 16, bottom: AppState.getInstance().getBottomNavInset() })
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
      .onDidScroll((y: number, _state: ScrollState) => {
        const diff = y - this.lastScrollY
        this.lastScrollY = y
        if (diff > 10 && y > 120) {
          AppState.getInstance().hideNav()
        } else if (diff < -10 && y < 80) {
          AppState.getInstance().showNav()
        }
      })
    }
    .onRefreshing(() => { this.onRefresh() })
  }
}
