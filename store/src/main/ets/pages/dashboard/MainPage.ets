import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { mediaquery, window } from '@kit.ArkUI'
import { DashboardTab } from './DashboardTab'
import { AppsPage } from '../apps/AppsPage'
import { NotificationWatcher } from '../../common/store/NotificationWatcher'
import { NotifyStore } from '../../common/store/NotifyStore'
import { applyImmersiveBar } from '../../common/utils/WindowUtils'
import { ScheduleStore } from '../../common/store/ScheduleStore'
import { AppNav } from '../../common/utils/AppNav'
import { PageHost } from '../../common/components/PageHost'

// 系统导航条高度：手势导航约 24vp，三键导航约 48vp
const NAV_BAR_GESTURE: number = 24
const NAV_BAR_THREE_KEY: number = 48
// 三键导航底栏高度通常 >= 40vp，用于区分导航模式
const NAV_BAR_THREE_KEY_THRESHOLD: number = 40

// ===== 响应式分栏断点 =====
// < 600vp：手机单栏（只有首页，功能页全屏路由）
// >= 600vp：两栏（首页 + 应用中心/应用）
// >= 1100vp：三栏（首页 + 应用中心 + 应用），覆盖 10 英寸以上平板横屏
const BP_TWO_COLUMN: number = 600
const BP_THREE_COLUMN: number = 1100
const BORDER_WIDTH: number = 0.5

@Entry
@Component
struct MainPage {
  @State theme: ThemePalette = LIGHT_THEME
  // ===== 分栏状态 =====
  @State isTwoColumn: boolean = false
  @State isThreeColumn: boolean = false
  // ===== 右侧应用栏状态 =====
  @State recent: string[] = []
  @State panelEmpty: boolean = true
  @State bottomSafeArea: number = NAV_BAR_GESTURE

  private panelStack: NavPathStack = new NavPathStack()
  // 三栏首次进入时右栏默认打开小管家（手动关闭后不再自动弹出）
  private autoPanelLaunched: boolean = false
  private twoListener: mediaquery.MediaQueryListener | null = null
  private threeListener: mediaquery.MediaQueryListener | null = null
  private mainWin: window.Window | null = null
  private panelListener: () => void = (): void => {
    this.syncPanelState()
  }

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    // 首页常驻，广播 Tab 0 供子页做前台感知（小管家/商店/Docker 页面会临时改）
    AppState.getInstance().setCurrentTab(0)

    // 注册应用面板导航栈：宽屏时 AppNav.open 直接推入此栈，由 NavDestination 承载功能页
    AppNav.getInstance().setUIContext(this.getUIContext())
    AppNav.getInstance().attachStack(this.panelStack)
    AppNav.getInstance().onPanelChange(this.panelListener)
    this.setupColumns()

    // 初始化通知/定时任务存储并启动检测器（App 前台期间 60s 检测）
    const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      NotifyStore.getInstance().init(hostCtx as Context)
      ScheduleStore.getInstance().init(hostCtx as Context)
      NotificationWatcher.getInstance().start()
    }

    AppState.getInstance().onThemeChange(() => {
      this.theme = AppState.getInstance().getTheme()
      // 统一亮色主题：状态栏图标同步为深色
      try {
        const ctx = this.getUIContext().getHostContext()
        if (ctx) {
          applyImmersiveBar(ctx as Context, false)
        }
      } catch (e) {}
    })

    // 获取系统底部导航条高度（手势导航 24vp / 三键导航 48vp，适配各机型）
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) {
        window.getLastWindow(ctx).then((win: window.Window) => {
          this.mainWin = win
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
          let bottomPx: number = avoidArea.bottomRect.height
          // 部分机型导航指示条避让区为 0（内容未延伸到系统栏），回退取系统栏避让区
          if (bottomPx <= 0) {
            bottomPx = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height
          }
          this.applyNavBarHeight(bottomPx)
          // 导航模式切换（手势 <-> 三键）时同步刷新高度
          try {
            win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
              if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
                this.applyNavBarHeight(data.area.bottomRect.height)
              }
            })
          } catch (e) {}
        }).catch(() => {
          this.applyNavBarHeight(0)
          hilog.info(0x0001, 'MainPage', 'getLastWindow failed, use default nav bar height')
        })
      } else {
        this.applyNavBarHeight(0)
      }
    } catch (_e) {
      this.applyNavBarHeight(0)
    }
  }

  /** 监听窗口宽度断点，决定单栏 / 双栏 / 三栏 */
  private setupColumns(): void {
    try {
      this.twoListener = mediaquery.matchMediaSync(`(min-width: ${BP_TWO_COLUMN}vp)`)
      this.threeListener = mediaquery.matchMediaSync(`(min-width: ${BP_THREE_COLUMN}vp)`)
      this.applyColumns(this.twoListener.matches, this.threeListener.matches)
      this.twoListener.on('change', (res: mediaquery.MediaQueryResult) => {
        this.applyColumns(res.matches, this.isThreeColumn)
      })
      this.threeListener.on('change', (res: mediaquery.MediaQueryResult) => {
        this.applyColumns(this.isTwoColumn, res.matches)
      })
    } catch (e) {
      hilog.error(0x0001, 'MainPage', `matchMediaSync failed: ${JSON.stringify(e)}`)
      this.applyColumns(false, false)
    }
  }

  private applyColumns(two: boolean, three: boolean): void {
    this.isTwoColumn = two
    this.isThreeColumn = three
    // >= 600vp 即进入分栏形态，功能页改为在应用栏内打开
    AppState.getInstance().setWideScreen(two)
    if (!two) {
      // 回到手机单栏：清空应用面板，功能页改走全屏路由
      AppNav.getInstance().clearPanel()
    }
    this.syncPanelState()
    // 三栏首次进入：右栏默认打开小管家，避免大片空白
    if (three && !this.autoPanelLaunched && AppNav.getInstance().isPanelEmpty()) {
      this.autoPanelLaunched = true
      AppNav.getInstance().open('pages/pet/PetPage')
    }
  }

  /**
   * 按导航模式更新底部安全区高度并广播
   * 手势导航：导航条约 24vp；三键导航：底栏约 48vp（系统返回高度 >= 40vp 视为三键）
   * @param pxHeight 系统导航指示条避让区高度（px）
   */
  private applyNavBarHeight(pxHeight: number): void {
    let safe: number = NAV_BAR_GESTURE
    if (pxHeight > 0) {
      safe = px2vp(pxHeight) >= NAV_BAR_THREE_KEY_THRESHOLD ? NAV_BAR_THREE_KEY : NAV_BAR_GESTURE
    }
    this.bottomSafeArea = safe
    // 底部导航条已取消，只保留系统导航条 + 少量呼吸位
    AppState.getInstance().setBottomNavInset(safe + 16)
    hilog.info(0x0001, 'MainPage', `navBar=${safe}vp, bottomInset=${safe + 16}`)
  }

  /** 同步右栏状态（空栈 / 最近访问列表） */
  private syncPanelState(): void {
    this.panelEmpty = AppNav.getInstance().isPanelEmpty()
    this.recent = AppNav.getInstance().getRecent()
  }

  aboutToDisappear(): void {
    AppNav.getInstance().offPanelChange(this.panelListener)
    AppNav.getInstance().detachStack()
    try {
      this.twoListener?.off('change')
      this.threeListener?.off('change')
    } catch (e) {}
    this.twoListener = null
    this.threeListener = null
    NotificationWatcher.getInstance().stop()
    try {
      if (this.mainWin) {
        this.mainWin.off('avoidAreaChange')
        this.mainWin = null
      }
    } catch (e) {}
  }

  /** 页面重新可见：首页恢复为当前 Tab */
  onPageShow(): void {
    AppState.getInstance().setCurrentTab(0)
  }

  /**
   * 拦截系统返回（含侧滑返回手势）
   * 1) 相册子视图：先回相册列表
   * 2) 分栏模式下面板有页面：先出栈
   */
  onBackPress(): boolean {
    if (AppState.getInstance().isAlbumSubView()) {
      AppState.getInstance().notifyAlbumBack()
      return true
    }
    if (this.isTwoColumn && !AppNav.getInstance().isPanelEmpty()) {
      AppNav.getInstance().back()
      return true
    }
    return false
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Row() {
        // ===== 左栏：首页 =====
        Column() {
          DashboardTab({ theme: this.theme })
            .width('100%')
            .height('100%')
        }
        .height('100%')
        .width(this.isThreeColumn ? '25%' : (this.isTwoColumn ? '34%' : '100%'))
        .padding({ top: 48 })

        if (this.isTwoColumn) {
          Column()
            .width(BORDER_WIDTH)
            .height('100%')
            .backgroundColor(this.theme.borderGlass)
        }

        if (this.isThreeColumn) {
          // ===== 中栏：应用中心 =====
          Column() {
            AppsPage()
              .width('100%')
              .height('100%')
          }
          .height('100%')
          .width('30%')

          Column()
            .width(BORDER_WIDTH)
            .height('100%')
            .backgroundColor(this.theme.borderGlass)

          // ===== 右栏：应用中心打开的应用 =====
          Column() {
            this.AppPane()
          }
          .height('100%')
          .layoutWeight(1)
        } else if (this.isTwoColumn) {
          // ===== 双栏：应用中心与应用共用一个栏位（入栈即覆盖应用中心）=====
          Column() {
            this.MainPane()
          }
          .height('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
  }

  /** 三栏右栏：空栈时展示引导与最近访问，入栈后显示应用 */
  @Builder
  AppPane() {
    if (this.panelEmpty) {
      this.PanelEmpty()
    } else {
      Navigation(this.panelStack) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({ angle: 135, colors: this.theme.pageGradient })
      }
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
      .navDestination(this.PageMap)
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height('100%')
    }
  }

  /** 双栏中栏：应用中心作为根内容，打开应用时覆盖 */
  @Builder
  MainPane() {
    Navigation(this.panelStack) {
      AppsPage()
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
    .backgroundColor(Color.Transparent)
    .width('100%')
    .height('100%')
  }

  /** 三栏右栏空态 */
  @Builder
  PanelEmpty() {
    Column() {
      Text('🗂').fontSize(34)
      Text('从中间的应用中心选择要打开的应用')
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)

      if (this.recent.length > 0) {
        Text('最近访问')
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 28, bottom: 4 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.recent, (url: string) => {
            Text(AppNav.getInstance().titleOf(url))
              .fontSize(12)
              .fontColor(this.theme.primary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin(4)
              .borderRadius(100)
              .backgroundColor(this.theme.accentSoft)
              .onClick(() => AppNav.getInstance().open(url))
          }, (url: string) => url)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  /** 应用面板内的 NavDestination 分发：按路径渲染对应功能页组件 */
  @Builder
  PageMap(name: string) {
    NavDestination() {
      PageHost({ url: name })
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      AppNav.getInstance().back()
      return true
    })
  }
}
