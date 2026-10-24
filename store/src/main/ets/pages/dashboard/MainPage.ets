import { AppState } from '../../common/store/AppState'
import {LIGHT_THEME, ThemePalette} from '../../common/theme/ThemeColors'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit'
import { SymbolGlyphModifier, window } from '@kit.ArkUI'
import { DashboardTab } from './DashboardTab'
import { IStoreTabView } from './IStoreTabView'
import { NotificationWatcher } from '../../common/store/NotificationWatcher'
import { NotifyStore } from '../../common/store/NotifyStore'
import { applyImmersiveBar } from '../../common/utils/WindowUtils'
import { ScheduleStore } from '../../common/store/ScheduleStore'
import { DockerTab } from './DockerTab'
import { PetView } from '../pet/PetPage'

// 系统导航条高度：手势导航约 24vp，三键导航约 48vp
const NAV_BAR_GESTURE: number = 24
const NAV_BAR_THREE_KEY: number = 48
// 三键导航底栏高度通常 >= 40vp，用于区分导航模式
const NAV_BAR_THREE_KEY_THRESHOLD: number = 40
// 悬浮导航条自身高度 + 与内容的间隙
const NAV_BAR_INSET_BASE: number = 110
// 悬浮导航条与系统导航条之间的间距
const NAV_BAR_BOTTOM_GAP: number = 4
// 主 Tab 索引：首页 0 / 小管家 1 / iStore 2 / Docker 3，系统 Tab 跳转应用中心
const TAB_SYSTEM: number = 4

@Entry
@Component
struct MainPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State deviceName: string = ''
  @State navHidden: boolean = false
  @State bottomSafeArea: number = NAV_BAR_GESTURE  // 系统导航条占用高度（手势 24vp / 三键 48vp）
  @State lastTabIndex: number = 0  // 进入应用中心前的 Tab（返回时恢复）
  @State tabOpacity: number = 1      // Tab 内容过渡动画：透明度
  @State tabTranslateY: number = 0   // Tab 内容过渡动画：垂直位移
  private lastScrollOffset: number = 0
  private tabsController: HdsTabsController = new HdsTabsController()
  private mainWin: window.Window | null = null

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    const device = AppState.getInstance().getActiveDevice()
    this.deviceName = device ? (device.label || device.host) : '未连接'
    // 初始 Tab 为首页，广播给子页做前台感知
    AppState.getInstance().setCurrentTab(0)

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

    // 订阅外部主 Tab 切换请求（首页快捷区：iStore 商店 / Docker）
    AppState.getInstance().onTabChange((tab: number) => {
      if (tab >= 0 && tab < TAB_SYSTEM) {
        this.tabsController.changeIndex(tab)
      }
    })

    AppState.getInstance().onNavChange(() => {
      // 用 duration 0 的显式动画覆盖 .animation(300) 隐式动画，
      // 避免导航条 barBottomMargin 从底部位置突变到 -100 时播放"从顶部滑下"的大位移动画
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.navHidden = AppState.getInstance().isNavHidden()
      })
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
    // 广播悬浮主导航条占用的底部空间（系统导航条 + 悬浮间距 + 条自身高度 + 内容间隙）
    AppState.getInstance().setBottomNavInset(safe + NAV_BAR_INSET_BASE)
    hilog.info(0x0001, 'MainPage', `navBar=${safe}vp, navInset=${safe + NAV_BAR_INSET_BASE}`)
  }

  aboutToDisappear(): void {
    AppState.getInstance().offNavChange(() => {})
    NotificationWatcher.getInstance().stop()
    try {
      if (this.mainWin) {
        this.mainWin.off('avoidAreaChange')
        this.mainWin = null
      }
    } catch (e) {}
  }

  /** 页面重新可见（从应用中心返回等）：恢复进入前的 Tab */
  onPageShow(): void {
    // 从应用中心返回时，从系统占位 Tab 恢复到进入前的 Tab（设备→系统→返回→设备）
    if (this.lastTabIndex !== TAB_SYSTEM && this.lastTabIndex >= 0 && this.lastTabIndex < TAB_SYSTEM) {
      this.tabsController.changeIndex(this.lastTabIndex)
      AppState.getInstance().setCurrentTab(this.lastTabIndex)
    }
  }

  /**
   * 拦截系统返回（含侧滑返回手势）
   * 当相册处于子视图（相册详情/全部照片/全屏查看）时，先返回相册列表，不退出应用
   */
  onBackPress(): boolean {
    if (AppState.getInstance().isAlbumSubView()) {
      AppState.getInstance().notifyAlbumBack()
      return true
    }
    return false
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        Row()
          .width('100%')
          .height(48)

        HdsTabs({ controller: this.tabsController }) {
          TabContent() {
            Stack() {
              DashboardTab({ theme: this.theme })
            }
            .width('100%').height('100%')
            .opacity(this.tabOpacity)
            .translate({ y: this.tabTranslateY })
          }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.house_fill')),
            selected: new SymbolGlyphModifier($r('sys.symbol.house_fill'))
          }, '首页'))

          TabContent() {
            Stack() {
              PetView({ theme: this.theme })
            }
            .width('100%').height('100%')
            .opacity(this.tabOpacity)
            .translate({ y: this.tabTranslateY })
          }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.media_center')),
            selected: new SymbolGlyphModifier($r('sys.symbol.media_center'))
          }, '小管家'))

          TabContent() {
            Stack() {
              IStoreTabView({ theme: this.theme })
            }
            .width('100%').height('100%')
            .opacity(this.tabOpacity)
            .translate({ y: this.tabTranslateY })
          }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.bag_fill')),
            selected: new SymbolGlyphModifier($r('sys.symbol.bag_fill'))
          }, 'iStore'))

          TabContent() {
            Stack() {
              DockerTab({ theme: this.theme })
            }
            .width('100%').height('100%')
            .opacity(this.tabOpacity)
            .translate({ y: this.tabTranslateY })
          }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.archivebox_fill')),
            selected: new SymbolGlyphModifier($r('sys.symbol.archivebox_fill'))
          }, 'Docker'))

          TabContent() {
            Column() {
              Text('🛠').fontSize(32).margin({ bottom: 12 })
              Text('系统工具')
                .fontSize(14).fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.gearshape_fill')),
            selected: new SymbolGlyphModifier($r('sys.symbol.gearshape_fill'))
          }, '系统'))
        }
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .onChange((index: number) => {
          if (index === TAB_SYSTEM) {
            // 系统 Tab：跳转应用中心，保持当前 Tab 高亮（不切回首页，避免"乱跳"）
            try {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/apps/AppsPage' })
            } catch (e) {
              hilog.error(0x0001, 'MainPage', `pushUrl failed: ${e}`)
            }
            return
          }
          // 相册查看器/子视图打开时：拦截 Tab 滑动穿透，强制停留在相册 Tab
          if (AppState.getInstance().isAlbumSubView()) {
            if (index !== 2) {
              this.tabsController.changeIndex(2)
            }
            return
          }
          // 切换过场动画：内容淡入 + 轻微上移（遮住切换瞬间的加载感）
          this.tabOpacity = 0.2
          this.tabTranslateY = 14
          this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
            this.tabOpacity = 1
            this.tabTranslateY = 0
          })
          // 广播当前 Tab，供各子页做前台感知（暂停/恢复轮询）
          AppState.getInstance().setCurrentTab(index)
          // 记录当前 Tab（点"系统"跳应用中心时记住，返回时恢复）
          if (index >= 0 && index < TAB_SYSTEM) {
            this.lastTabIndex = index
          }
        })
        .barFloatingStyle({
          barWidth: { smallWidth: 320, mediumWidth: 400, largeWidth: 480 },
          barBottomMargin: this.navHidden ? -100 : (this.bottomSafeArea + NAV_BAR_BOTTOM_GAP),
          gradientMask: { maskColor: '#33F5F1EE', maskHeight: 88 },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
