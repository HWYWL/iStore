/**
 * RouterLevelPage - 路由器等级（Lv.1 新手上路 → Lv.99 网络之神）
 * 按使用天数 + 操作次数升级，数据存 FunStore
 */
import { AppNav } from '../../common/utils/AppNav'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore } from '../../common/store/FunStore'
import { ApiService } from '../../api/ApiService'

const DOMAIN = 0x0001
const TAG = 'RouterLevel'

@Entry
@Component
struct RouterLevelPageRoute {
  build() {
    Column() {
      RouterLevelPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct RouterLevelPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44   // 状态栏安全区高度
  @State level: number = 1
  @State upDays: number = 0
  @State actions: number = 0
  @State uptime: number = 0
  @State levelUp: boolean = false   // 升级动画
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      FunStore.getInstance().init(hostCtx).then(() => {
        this.upDays = FunStore.getInstance().getLevelUpDays()
        this.actions = FunStore.getInstance().getLevelActions()
        FunStore.getInstance().addLevelAction()
        this.actions = FunStore.getInstance().getLevelActions()
        this.level = this.calcLevel()
      })
    }
    this.fetchUptime()
  }

  private async fetchUptime(): Promise<void> {
    try {
      const sys = await this.api.fetchSystemInfo()
      this.uptime = sys.uptime
    } catch (e) {
      hilog.error(DOMAIN, TAG, `uptime err: ${String(e)}`)
    }
  }

  /** 等级计算：基础 1 + 每 3 天 +1 + 每 20 次操作 +1，封顶 99 */
  private calcLevel(): number {
    let lv: number = 1 + Math.floor(this.upDays / 3) + Math.floor(this.actions / 20)
    if (lv > 99) lv = 99
    if (lv < 1) lv = 1
    return lv
  }

  /** 称号 */
  private title(): string {
    if (this.level >= 99) return '网络之神 👑'
    if (this.level >= 80) return '网络尊者 🧙'
    if (this.level >= 60) return '网络工程师 🛠'
    if (this.level >= 40) return '带宽大师 🚀'
    if (this.level >= 20) return '网络管家 🏠'
    if (this.level >= 10) return '网络熟客 👍'
    return '新手上路 🌱'
  }

  /** 升级经验值：当前等级所需的「活跃值」与总活跃值 */
  private expNow(): number {
    // 活跃值 = 使用天数*3 + 操作次数*1.5（与等级公式同源）
    return this.upDays * 3 + this.actions * 1.5
  }

  private expNext(): number {
    const cur: number = (this.level - 1) * 3
    return cur + 3
  }

  private expProgress(): number {
    const total: number = this.expNext()
    if (total <= 0) return 0
    const p: number = this.expNow() / total
    return Math.max(0, Math.min(1, p))
  }

  /** 连续运行天数 */
  private upDaysRun(): number {
    if (this.uptime <= 0) return 0
    return Math.floor(this.uptime / 86400)
  }

  /** 升到下一级还需 */
  private toNext(): number {
    const need: number = this.expNext()
    const now: number = this.expNow()
    const remain: number = need - now
    if (remain <= 0) return 0
    return Math.ceil(remain / 3)  // 约等于还需的天数
  }

  /** 读取状态栏安全区高度（避免标题栏与状态栏重叠） */
  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.app_bell')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('路由器等级').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('用越久等级越高').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)

        Text('返回')
          .fontSize(13).fontColor(this.theme.primary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('rgba(255,138,61,0.1)')
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%').padding({ left: 16, right: 16, top: this.topSafeArea + 4 })

      Scroll() {
        Column() {
          // 等级大卡
          Column() {
            Text(this.title()).fontSize(15).fontColor('rgba(255,255,255,0.9)')
            Row() {
              Text(`Lv.`).fontSize(22).fontColor('#FFFFFF').margin({ bottom: 10 })
              Text(`${this.level}`)
                .fontSize(88).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
              Text(`/ 99`).fontSize(16).fontColor('rgba(255,255,255,0.7)').margin({ bottom: 18 })
            }
            .alignItems(VerticalAlign.Bottom)
            // 进度条
            Progress({ value: this.expProgress() * 100, total: 100 })
              .width('80%').height(8).margin({ top: 4 })
              .color('#FFFFFF').backgroundColor('rgba(255,255,255,0.25)')
            Text(this.toNext() > 0 ? `再活跃约 ${this.toNext()} 天升级` : '已达当前顶级')
              .fontSize(10).fontColor('rgba(255,255,255,0.8)').margin({ top: 8 })
          }
          .width('100%').padding({ top: 28, bottom: 26 }).borderRadius(24).margin({ top: 12 })
          .linearGradient({
            angle: 135,
            colors: [['#FF9A5C', 0], ['#FF8A3D', 0.55], ['#FF7043', 1]]
          })
          .alignItems(HorizontalAlign.Center)

          // 统计卡
          Row({ space: 10 }) {
            this.stat($r('sys.symbol.calendar'), `${this.upDays}`, '使用天数')
            this.stat($r('sys.symbol.bolt'), `${this.actions}`, '活跃次数')
            this.stat($r('sys.symbol.clock'), `${this.upDaysRun()}`, '连续运行(天)')
          }
          .width('100%').margin({ top: 12 })

          // 升级规则
          Column() {
            Text('升级规则').fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              .width('100%')
            Text('· 每天打开趣味功能 +1 活跃\n· 每 3 天使用 +1 级，每 20 次活跃 +1 级\n· 最高 Lv.99「网络之神」')
              .fontSize(11).fontColor(this.theme.textSecondary).lineHeight(20).margin({ top: 10 })
              .width('100%')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 称号表
          Column() {
            Text('称号一览').fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              .width('100%')
            this.titleRow('Lv.1-9', '新手上路 🌱')
            this.titleRow('Lv.10-19', '网络熟客 👍')
            this.titleRow('Lv.20-39', '网络管家 🏠')
            this.titleRow('Lv.40-59', '带宽大师 🚀')
            this.titleRow('Lv.60-79', '网络工程师 🛠')
            this.titleRow('Lv.80-98', '网络尊者 🧙')
            this.titleRow('Lv.99', '网络之神 👑')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }

  @Builder
  stat(icon: Resource, value: string, label: string) {
    Column() {
      SymbolGlyph(icon).fontSize(18).fontColor([this.theme.primary])
      Text(value).fontSize(22).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold).fontFamily('monospace')
        .margin({ top: 4 })
      Text(label).fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
    }
    .layoutWeight(1).padding({ top: 14, bottom: 14 }).borderRadius(16)
    .backgroundColor(this.theme.bgCard)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  titleRow(range: string, title: string) {
    Row() {
      Text(range).fontSize(11).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
      Text(title).fontSize(12).fontColor(this.theme.textSecondary).margin({ left: 12 })
    }
    .width('100%').padding({ top: 8, bottom: 8 })
    .border({ width: 0.5, color: 'rgba(180,160,120,0.15)' })
    .borderRadius(10)
    .margin({ top: 6 })
    .padding({ left: 10, right: 10 })
  }
}
