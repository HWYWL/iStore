import { AppState } from '../../common/store/AppState'
import {
  ThemePalette,
  cardBorder,
  cardTint
} from '../../common/theme/ThemeColors'
import { IStoreApp } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'

/** 应用分类分组 */
interface AppGroup {
  title: string
  items: IStoreApp[]
}

@Component
export struct IStoreTabView {
  @Prop theme: ThemePalette
  @State apps: IStoreApp[] = []
  @State groups: AppGroup[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  private api: ApiService = new ApiService()
  private lastScrollY: number = 0
  aboutToAppear(): void {
    this.loadApps()
  }

  async loadApps(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      this.apps = await this.api.fetchIStoreApps()
      this.buildGroups()
      if (this.apps.length === 0) {
        this.errorText = '暂无已安装的应用'
      }
    } catch (e) {
      this.errorText = '加载失败，请重试'
    }
    this.isLoading = false
  }

  /** 按分类分组（无分类的应用归入「其他」，分类为空时全部归入「应用」） */
  private buildGroups(): void {
    const map: Map<string, IStoreApp[]> = new Map()
    let hasCategory: boolean = false
    for (let i = 0; i < this.apps.length; i++) {
      const cat: string = this.apps[i].category ? this.apps[i].category.trim() : ''
      if (cat) {
        hasCategory = true
      }
      const key: string = cat || '其他'
      const arr: IStoreApp[] | undefined = map.get(key)
      if (arr) {
        arr.push(this.apps[i])
      } else {
        map.set(key, [this.apps[i]])
      }
    }
    // 无任何分类时统一为「应用」
    const keys: string[] = Array.from(map.keys())
    const groups: AppGroup[] = []
    if (!hasCategory && map.size === 1) {
      groups.push({ title: '应用', items: this.apps })
    } else {
      // 分类排序：非「其他」在前，其他最后
      keys.sort((a: string, b: string): number => {
        if (a === '其他') return 1
        if (b === '其他') return -1
        return a.localeCompare(b)
      })
      for (let i = 0; i < keys.length; i++) {
        groups.push({ title: keys[i], items: map.get(keys[i]) as IStoreApp[] })
      }
    }
    this.groups = groups
  }

  getIconUrl(app: IStoreApp): string {
    if (app.icon) {
      const device = AppState.getInstance().getActiveDevice()
      if (device) {
        const base = `http://${device.host}:${device.port}`
        return app.icon.startsWith('http') ? app.icon : `${base}${app.icon}`
      }
    }
    return ''
  }

  /** 打开应用 */
  openApp(app: IStoreApp): void {
    if (!app.link) return
    const device = AppState.getInstance().getActiveDevice()
    if (!device) return
    // 用 ApiService 的 baseUrl，端口为空时不会拼出 http://host: 这种畸形地址，也跟随 https 配置
    const base: string = this.api.getBaseUrl()
    const url = app.link.startsWith('http') ? app.link : `${base}${app.link}`
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/apps/WebViewPage',
        params: { url: url }
      })
    } catch (e) {
      hilog.error(0x0001, 'IStoreTab', `pushUrl failed: ${e}`)
    }
  }

  /** 打开 iStore 管理页（SPA 默认就停在「已安装」页签） */
  openStoreInstalled(): void {
    const base: string = this.api.getBaseUrl()
    if (!base) return
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/apps/WebViewPage',
        params: { url: `${base}/cgi-bin/luci/admin/store/` }
      })
    } catch (e) {
      hilog.error(0x0001, 'IStoreTab', `pushUrl failed: ${e}`)
    }
  }

  /** 单个应用卡片（每行两个） */
  @Builder
  appCard(app: IStoreApp): void {
    Row() {
      // 图标（无图标时显示名称首字）
      Stack() {
        if (app.icon) {
          Image(this.getIconUrl(app))
            .width(38).height(38).objectFit(ImageFit.Cover).borderRadius(11)
        } else {
          Text((app.title || app.name).substring(0, 1))
            .fontSize(18).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
        }
      }
      .width(38).height(38).borderRadius(11)
      .backgroundColor(this.theme.bgGlassLight)
      .alignContent(Alignment.Center)

      Column() {
        Text(app.title || app.name)
          .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(app.version ? `v${app.version}` : '')
            .fontSize(10).fontColor(this.theme.textTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          // 源里有更新版本：给个显眼提示，进商店即可升级
          if (app.hasUpdate) {
            Text('有新版')
              .fontSize(8)
              .fontColor('#FF8A3D')
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor('rgba(255,138,61,0.14)')
              .margin({ left: 5 })
          }
        }
        .margin({ top: 2 })
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(cardTint(this.theme))
    .backdropBlur(this.theme.material.blur)
    .border(cardBorder(this.theme))
    .onClick(() => this.openApp(app))
  }

  build() {
    Scroll() {
      Column() {
        Text('📦 iStore')
          .fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textPrimary).width('100%').margin({ top: 12 })

        Text('已安装的应用列表')
          .fontSize(13).fontColor(this.theme.textSecondary).margin({ top: 8 }).width('100%')

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.theme.primary)
            Text('加载中...').fontSize(13).fontColor(this.theme.textTertiary).margin({ top: 12 })
          }
          .width('100%').padding(40).alignItems(HorizontalAlign.Center).margin({ top: 20 })
        } else if (this.errorText) {
          Text(this.errorText)
            .fontSize(13).fontColor(this.theme.textTertiary)
            .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
        } else {
          Column() {
            // 分类分组，每行两个应用
            ForEach(this.groups, (group: AppGroup) => {
              Column() {
                // 分类标题 + 数量
                Row() {
                  Text(group.title)
                    .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                  Text(`${group.items.length} 个`)
                    .fontSize(11).fontColor(this.theme.textTertiary).margin({ left: 8 })
                }
                .width('100%')
                .padding({ top: 16, bottom: 8 })

                // 每行两个（两列网格）
                Grid() {
                  ForEach(group.items, (app: IStoreApp) => {
                    GridItem() {
                      this.appCard(app)
                    }
                  }, (app: IStoreApp): string => app.name)
                }
                .columnsTemplate('1fr 1fr')
                .columnsGap(10)
                .rowsGap(10)
                .width('100%')
              }
              .width('100%')
            }, (group: AppGroup): string => group.title)
          }
          .width('100%').margin({ top: 12 })
        }

        // 跳到 iStore 自己的「已安装」页面（升级/卸载都在那里）
        Row() {
          Text('🛍️').fontSize(13)
          Text('打开 iStore 管理已装应用')
            .fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
            .margin({ left: 6 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 12 })
        .borderRadius(14)
        .backgroundColor(this.theme.bgGlassLight)
        .border(cardBorder(this.theme))
        .margin({ top: 18 })
        .onClick(() => this.openStoreInstalled())
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 130 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
      .align(Alignment.Top)
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
}
