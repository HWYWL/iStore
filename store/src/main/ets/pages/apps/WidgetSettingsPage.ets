/**
 * WidgetSettingsPage - 桌面小组件设置
 * 选择卡片主指标：实时速率 / 今日流量 / CPU·内存 / 在线设备
 * 配置写入 WidgetDataStore，卡片下次刷新（onUpdateForm）时生效
 */
import { window } from '@kit.ArkUI'
import { promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { WidgetDataStore } from '../../common/store/WidgetDataStore'
import { AppNav } from '../../common/utils/AppNav'

/** 指标选项 */
interface MetricOption {
  key: string
  icon: Resource
  tint: string
  title: string
  desc: string
}

const OPTIONS: MetricOption[] = [
  { key: 'speed', icon: $r('app.media.w_metric_speed'), tint: 'rgba(37,99,235,0.12)', title: '实时网速', desc: '下载 / 上传速率（默认）' },
  { key: 'traffic', icon: $r('app.media.w_metric_traffic'), tint: 'rgba(124,58,237,0.12)', title: '今日流量', desc: '今天累计消耗的流量' },
  { key: 'cpu', icon: $r('app.media.w_metric_cpu'), tint: 'rgba(245,158,11,0.14)', title: 'CPU / 内存', desc: '路由器负载与内存占用' },
  { key: 'devices', icon: $r('app.media.w_metric_devices'), tint: 'rgba(16,185,129,0.14)', title: '在线设备', desc: '当前在线的设备数量' }
]

@Entry
@Component
struct WidgetSettingsPageRoute {
  build() {
    Column() {
      WidgetSettingsPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct WidgetSettingsPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State metric: string = 'speed'

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    this.loadMetric()
  }

  /** 获取状态栏高度（避免标题栏被遮挡） */
  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => { /* 保持默认值 */ })
      }
    } catch (e) {
      hilog.error(0x0001, 'WidgetSettingsPage', `loadTopSafeArea err: ${JSON.stringify(e)}`)
    }
  }

  /** 读取已保存的主指标 */
  loadMetric(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (!hostCtx) return
      WidgetDataStore.init(hostCtx as Context).then(() => {
        this.metric = WidgetDataStore.loadMetric()
      }).catch((err: Error) => {
        hilog.error(0x0001, 'WidgetSettingsPage', `loadMetric err: ${err.message}`)
      })
    } catch (e) {
      hilog.error(0x0001, 'WidgetSettingsPage', `loadMetric err: ${JSON.stringify(e)}`)
    }
  }

  /** 切换主指标 */
  select(key: string): void {
    if (this.metric === key) return
    this.metric = key
    try {
      WidgetDataStore.setMetric(key)
      this.getUIContext().getPromptAction().showToast({ message: '已保存，卡片下次刷新后生效', duration: 1800 })
    } catch (e) {
      hilog.error(0x0001, 'WidgetSettingsPage', `setMetric err: ${JSON.stringify(e)}`)
      try {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试', duration: 1800 })
      } catch (_e) {}
    }
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor(this.theme.textTertiary)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 4, top: 18, bottom: 6 })
  }

  @Builder
  metricRow(opt: MetricOption) {
    Row() {
      Row() {
        Image(opt.icon)
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
      }
      .width(30)
      .height(30)
      .borderRadius(9)
      .backgroundColor(opt.tint)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })
      Column() {
        Text(opt.title)
          .fontSize(15)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
        Text(opt.desc)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.metric === opt.key) {
        Text('✓')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.primary)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.metric === opt.key ? this.theme.bgCardHover : '#00000000')
    .onClick(() => {
      this.select(opt.key)
    })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text(' 小组件设置')
            .fontSize(16)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 12, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          this.sectionTitle('卡片主指标')
          Column() {
            ForEach(OPTIONS, (opt: MetricOption, idx: number) => {
              if (idx > 0) {
                Divider().color(this.theme.borderGlass).margin({ left: 46, right: 16 })
              }
              this.metricRow(opt)
            }, (opt: MetricOption) => opt.key)
          }
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          Text('卡片支持 2*2 与 2*4 两种尺寸，主指标会在卡片中部大字展示；选择「实时网速」以外的指标时，下方会补充一行 ↓/↑ 实时速率。')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .lineHeight(16)
            .width('100%')
            .padding({ left: 4, right: 4, top: 12 })

          Text('提示：卡片由系统定时刷新（最长约 30 分钟），修改后请稍候查看效果。')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .lineHeight(16)
            .width('100%')
            .padding({ left: 4, right: 4, top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.bgDark)
  }
}
