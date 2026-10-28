/**
 * NotifySettingsPage - 智能通知设置页
 * 开关：总开关 / 断网告警 / 新设备接入提醒
 * 请求系统通知权限，说明检测机制
 */
import { notificationManager } from '@kit.NotificationKit'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { NotifyStore, NotifyRecord } from '../../common/store/NotifyStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct NotifySettingsPageRoute {
  build() {
    Column() {
      NotifySettingsPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NotifySettingsPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44  // 状态栏高度（默认 44vp）
  @State masterEnabled: boolean = false
  @State offlineAlert: boolean = false
  @State newDeviceAlert: boolean = false
  @State aiHealthAlert: boolean = false
  @State notifyEnabled: boolean = true  // 系统通知权限
  // 免打扰 / 阈值 / 历史
  @State quietEnabled: boolean = false
  @State quietStart: number = 23
  @State quietEnd: number = 7
  @State thTemp: number = 75
  @State thMem: number = 85
  @State thCpu: number = 90
  @State history: NotifyRecord[] = []
  private store: NotifyStore = NotifyStore.getInstance()

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      this.store.init(hostCtx as Context)
    }
    this.masterEnabled = this.store.isEnabled()
    this.offlineAlert = this.store.isOfflineAlertOn()
    this.newDeviceAlert = this.store.isNewDeviceAlertOn()
    this.aiHealthAlert = this.store.isAiHealthAlertOn()
    this.quietEnabled = this.store.isQuietEnabled()
    this.quietStart = this.store.getQuietStart()
    this.quietEnd = this.store.getQuietEnd()
    this.thTemp = this.store.getTempThreshold()
    this.thMem = this.store.getMemThreshold()
    this.thCpu = this.store.getCpuThreshold()
    this.history = this.store.getHistory()
    this.checkNotifyPermission()
    // 获取状态栏高度（避免标题栏被遮挡）
    this.loadTopSafeArea()
  }

  /** 获取状态栏高度 */
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
      hilog.error(0x0001, 'NotifySettingsPage', `loadTopSafeArea err: ${JSON.stringify(e)}`)
    }
  }

  /** 检查系统通知权限 */
  checkNotifyPermission(): void {
    try {
      this.notifyEnabled = notificationManager.isNotificationEnabledSync()
    } catch (e) {
      hilog.error(0x0001, 'NotifySettingsPage', `isNotificationEnabledSync err: ${JSON.stringify(e)}`)
    }
  }

  /** 请求通知权限 */
  async requestNotifyPermission(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      await notificationManager.requestEnableNotification(ctx)
      this.checkNotifyPermission()
    } catch (e) {
      hilog.error(0x0001, 'NotifySettingsPage', `requestEnableNotification err: ${JSON.stringify(e)}`)
    }
  }

  @Builder
  switchRow(title: string, desc: string, checked: boolean, tag: number) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
        Text(desc)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 3 })
          .lineHeight(15)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor('#448AFF')
        .onChange((v: boolean) => {
          // tag 分发：0=总开关 1=断网告警 2=新设备提醒 3=AI健康告警
          if (tag === 0) {
            this.masterEnabled = v
            this.store.setEnabled(v)
          } else if (tag === 1) {
            this.offlineAlert = v
            this.store.setOfflineAlert(v)
          } else if (tag === 2) {
            this.newDeviceAlert = v
            this.store.setNewDeviceAlert(v)
          } else if (tag === 3) {
            this.aiHealthAlert = v
            this.store.setAiHealthAlert(v)
          } else {
            // tag 4：免打扰
            this.quietEnabled = v
            this.store.setQuietEnabled(v)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .borderRadius(14)
  }

  /** 微调行当前值（在 @Builder 内直接读状态，保证数值变化能触发刷新） */
  stepperValue(tag: number): string {
    if (tag === 0) return `${this.quietStart}:00`
    if (tag === 1) return `${this.quietEnd}:00`
    if (tag === 2) return `${this.thTemp}°C`
    if (tag === 3) return `${this.thMem}%`
    return `${this.thCpu}%`
  }

  /** 小时/阈值微调行：tag 0=免打扰开始 1=免打扰结束 2=温度 3=内存 4=CPU */
  @Builder
  stepperRow(title: string, desc: string, tag: number, step: number) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
        Text(desc)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 3 })
          .lineHeight(15)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row() {
        Text('−')
          .fontSize(17)
          .fontColor(this.theme.textSecondary)
          .width(30).height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor(this.theme.bgGlassLight)
          .onClick(() => { this.changeValue(tag, -step) })
        Text(this.stepperValue(tag))
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
          .width(58)
          .textAlign(TextAlign.Center)
        Text('+')
          .fontSize(17)
          .fontColor(this.theme.textSecondary)
          .width(30).height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor(this.theme.bgGlassLight)
          .onClick(() => { this.changeValue(tag, step) })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.theme.bgCard)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .borderRadius(14)
  }

  /** 调整数值并落盘 */
  changeValue(tag: number, delta: number): void {
    if (tag === 0) {
      this.quietStart = Math.min(23, Math.max(0, this.quietStart + delta))
      this.store.setQuietStart(this.quietStart)
    } else if (tag === 1) {
      this.quietEnd = Math.min(23, Math.max(0, this.quietEnd + delta))
      this.store.setQuietEnd(this.quietEnd)
    } else if (tag === 2) {
      this.thTemp = Math.min(100, Math.max(40, this.thTemp + delta))
      this.store.setTempThreshold(this.thTemp)
    } else if (tag === 3) {
      this.thMem = Math.min(99, Math.max(50, this.thMem + delta))
      this.store.setMemThreshold(this.thMem)
    } else {
      this.thCpu = Math.min(100, Math.max(50, this.thCpu + delta))
      this.store.setCpuThreshold(this.thCpu)
    }
  }

  /** 历史记录图标（统一符号族） */
  historySymbol(type: string): Resource {
    if (type === 'offline') return $r('sys.symbol.warning')
    if (type === 'recover') return $r('sys.symbol.checkmark_circle')
    if (type === 'newDevice') return $r('sys.symbol.plus_circle')
    if (type === 'temp') return $r('sys.symbol.thermometer')
    if (type === 'memory') return $r('sys.symbol.circle_grid_2x2')
    if (type === 'cpu') return $r('sys.symbol.gearshape')
    return $r('sys.symbol.bolt')
  }

  /** 历史记录配色 */
  historyColor(type: string): string {
    if (type === 'offline') return '#EF4444'
    if (type === 'recover') return '#10B981'
    if (type === 'newDevice') return '#3B82F6'
    if (type === 'temp') return '#F59E0B'
    if (type === 'memory') return '#8B5CF6'
    if (type === 'cpu') return '#06B6D4'
    return '#F97316'
  }

  /** 历史记录时间文案 */
  historyTime(t: number): string {
    const d: Date = new Date(t)
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.theme.textSecondary)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 6 })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text(' 智能通知')
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
          // 系统通知权限提示
          if (!this.notifyEnabled) {
            Row() {
              Column() {
                Text('🔕 通知权限未开启')
                  .fontSize(14)
                  .fontColor(this.theme.warning)
                  .fontWeight(FontWeight.Medium)
                Text('开启后才能收到断网告警和新设备提醒')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('去开启')
                .fontSize(12)
                .fontColor(Color.White)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(14)
                .backgroundColor(this.theme.primary)
                .onClick(() => {
                  this.requestNotifyPermission()
                })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor('rgba(255,152,0,0.1)')
            .border({ width: 0.5, color: 'rgba(255,152,0,0.3)' })
            .margin({ top: 8, bottom: 4 })
          }

          this.sectionTitle('推送开关')
          // 总开关
          this.switchRow('智能通知推送', '开启后检测路由器状态变化并推送通知', this.masterEnabled, 0)

          Column() {
            // 断网告警
            this.switchRow('断网告警', '路由器离线/恢复时通知你', this.offlineAlert, 1)
            // 新设备接入提醒
            this.switchRow('新设备接入提醒', '有新设备连接 WiFi 时通知你（首次建立基线不打扰）',
              this.newDeviceAlert, 2)
            // AI 健康告警
            this.switchRow('AI 健康告警', '温度过高/内存紧张/CPU 高负载/突发大流量时通知你',
              this.aiHealthAlert, 3)
          }
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          // ========== 免打扰 ==========
          this.sectionTitle('免打扰')
          Column() {
            this.switchRow('免打扰时段', '开启后只保留断网/恢复告警，健康与新设备通知静默（仍会记入历史）',
              this.quietEnabled, 4)
            if (this.quietEnabled) {
              Divider().color(this.theme.borderGlass).margin({ left: 16, right: 16 })
              this.stepperRow('开始时间', '每天从这个整点开始静默', 0, 1)
              Divider().color(this.theme.borderGlass).margin({ left: 16, right: 16 })
              this.stepperRow('结束时间', '到这个整点恢复推送（支持跨零点）', 1, 1)
            }
          }
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          // ========== 告警阈值 ==========
          this.sectionTitle('告警阈值')
          Column() {
            this.stepperRow('温度告警', 'CPU 温度超过该值提醒', 2, 5)
            Divider().color(this.theme.borderGlass).margin({ left: 16, right: 16 })
            this.stepperRow('内存告警', '内存占用超过该百分比提醒', 3, 5)
            Divider().color(this.theme.borderGlass).margin({ left: 16, right: 16 })
            this.stepperRow('CPU 告警', 'CPU 占用超过该百分比提醒', 4, 5)
          }
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          // ========== 告警历史 ==========
          this.sectionTitle('告警历史')
          Column() {
            if (this.history.length === 0) {
              Text('还没有告警记录')
                .fontSize(12).fontColor(this.theme.textTertiary)
                .width('100%').padding(20).textAlign(TextAlign.Center)
            } else {
              ForEach(this.history, (rec: NotifyRecord, idx: number) => {
                Row() {
                  Row() {
                    SymbolGlyph(this.historySymbol(rec.type))
                      .fontSize(15)
                      .fontColor([this.historyColor(rec.type)])
                  }
                  .width(30)
                  .height(30)
                  .borderRadius(9)
                  .backgroundColor('#1F' + this.historyColor(rec.type).substring(1))
                  .justifyContent(FlexAlign.Center)
                  Column() {
                    Text(rec.title)
                      .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                    Text(rec.text)
                      .fontSize(11).fontColor(this.theme.textTertiary)
                      .margin({ top: 2 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                  Text(this.historyTime(rec.t))
                    .fontSize(10).fontColor(this.theme.textTertiary)
                }
                .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .alignItems(VerticalAlign.Top)
                .border({ width: { bottom: idx === this.history.length - 1 ? 0 : 0.5 }, color: this.theme.borderGlass })
              }, (rec: NotifyRecord, idx: number): string => `${rec.t}_${idx}`)

              Divider().color(this.theme.borderGlass)
              Text('清空历史')
                .fontSize(12).fontColor('#E4572E')
                .width('100%').padding(12).textAlign(TextAlign.Center)
                .onClick(() => {
                  this.store.clearHistory()
                  this.history = []
                })
            }
          }
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          this.sectionTitle('检测说明')
          Column() {
            Row() {
              Text('🔄')
                .fontSize(16)
              Column() {
                Text('每 60 秒检测一次')
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium)
                Text('App 运行时自动检测路由器在线状态和设备列表变化')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 2 })
                  .lineHeight(15)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 10 })
              .layoutWeight(1)
            }
            .width('100%')
            .padding(14)

            Divider().color(this.theme.borderGlass)

            Row() {
              Text('🔒')
                .fontSize(16)
              Column() {
                Text('数据不出本机')
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium)
                Text('检测仅在手机与你的路由器之间进行，不上传任何服务器')
                  .fontSize(11)
                  .fontColor(this.theme.textTertiary)
                  .margin({ top: 2 })
                  .lineHeight(15)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 10 })
              .layoutWeight(1)
            }
            .width('100%')
            .padding(14)
          }
          .width('100%')
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .borderRadius(14)
          .clip(true)

          // 底部留白
          Row().width('100%').height(40)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
