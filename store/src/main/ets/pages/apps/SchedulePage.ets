/**
 * SchedulePage - 定时任务中心
 * 定时重启路由器 / 定时开关 WiFi
 * 配置保存到 ScheduleStore，由 NotificationWatcher 在 App 运行时到点执行
 * 注意：@Builder 参数不能为函数类型，用 tag 分发处理各行的回调
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ScheduleStore, ScheduleTask } from '../../common/store/ScheduleStore'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日']

@Entry
@Component
struct SchedulePageRoute {
  build() {
    Column() {
      SchedulePage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SchedulePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44  // 状态栏高度（默认 44vp）
  // 定时重启
  @State rebootEnabled: boolean = false
  @State rebootTime: string = '04:00'
  @State rebootDays: boolean[] = [true, true, true, true, true, true, true]
  @State showRebootPicker: boolean = false
  // 定时 WiFi
  @State wifiEnabled: boolean = false
  @State wifiOffTime: string = '23:30'
  @State wifiOnTime: string = '07:00'
  @State wifiDays: boolean[] = [true, true, true, true, true, true, true]
  @State showWifiPicker: boolean = false
  // 保存提示
  @State showToast: boolean = false
  @State toastText: string = '已保存'
  private toastTimer: number = -1
  private store: ScheduleStore = ScheduleStore.getInstance()
  private wifiPickerIsOff: boolean = true

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        const hostCtx = this.getUIContext().getHostContext()
    if (hostCtx) {
      this.store.init(hostCtx as Context)
    }
    this.loadAll()
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
      hilog.error(0x0001, 'SchedulePage', `loadTopSafeArea err: ${JSON.stringify(e)}`)
    }
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
  }

  /** 加载已保存配置 */
  loadAll(): void {
    const reboot: ScheduleTask = this.store.getRebootTask()
    this.rebootEnabled = reboot.enabled
    this.rebootTime = reboot.time
    this.rebootDays = this.weekdaysToFlags(reboot.weekdays)
    const wifiOff: ScheduleTask = this.store.getWifiOffTask()
    const wifiOn: ScheduleTask = this.store.getWifiOnTask()
    this.wifiEnabled = wifiOff.enabled || wifiOn.enabled
    this.wifiOffTime = wifiOff.time
    this.wifiOnTime = wifiOn.time
    this.wifiDays = this.weekdaysToFlags(wifiOff.weekdays.length > 0 ? wifiOff.weekdays : wifiOn.weekdays)
  }

  /** weekdays(0=周一) → 7 位开关数组 */
  weekdaysToFlags(weekdays: number[]): boolean[] {
    const flags: boolean[] = [false, false, false, false, false, false, false]
    if (weekdays.length === 0) {
      // 空 = 每天
      return [true, true, true, true, true, true, true]
    }
    for (let i = 0; i < weekdays.length; i++) {
      const d: number = weekdays[i]
      if (d >= 0 && d < 7) {
        flags[d] = true
      }
    }
    return flags
  }

  /** 7 位开关数组 → weekdays（全选=空数组表示每天） */
  flagsToWeekdays(flags: boolean[]): number[] {
    const days: number[] = []
    for (let i = 0; i < 7; i++) {
      if (flags[i]) {
        days.push(i)
      }
    }
    // 全选 = 每天（空数组）
    if (days.length === 7) {
      return []
    }
    return days
  }

  /** 保存所有任务 */
  saveAll(): void {
    const reboot: ScheduleTask = {
      enabled: this.rebootEnabled,
      time: this.rebootTime,
      weekdays: this.flagsToWeekdays(this.rebootDays)
    }
    this.store.saveRebootTask(reboot)
    const wifiOff: ScheduleTask = {
      enabled: this.wifiEnabled,
      time: this.wifiOffTime,
      weekdays: this.flagsToWeekdays(this.wifiDays)
    }
    this.store.saveWifiOffTask(wifiOff)
    const wifiOn: ScheduleTask = {
      enabled: this.wifiEnabled,
      time: this.wifiOnTime,
      weekdays: this.flagsToWeekdays(this.wifiDays)
    }
    this.store.saveWifiOnTask(wifiOn)
    this.showToastMsg('已保存')
  }

  showToastMsg(text: string): void {
    this.toastText = text
    this.showToast = false
    setTimeout(() => {
      this.showToast = true
      if (this.toastTimer !== -1) {
        clearTimeout(this.toastTimer)
      }
      this.toastTimer = setTimeout(() => {
        this.showToast = false
      }, 1500)
    }, 30)
  }

  timeToDate(time: string): Date {
    const parts: string[] = time.split(':')
    const d: Date = new Date()
    d.setHours(parseInt(parts[0]) || 0)
    d.setMinutes(parseInt(parts[1]) || 0)
    return d
  }

  pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  // ========== 时间/星期变更分发（tag: 0=重启 1=WiFi关 2=WiFi开 3=重启星期 4=WiFi星期）==========

  handleTimeChange(tag: number, h: number, m: number): void {
    const t: string = `${this.pad2(h)}:${this.pad2(m)}`
    if (tag === 0) {
      this.rebootTime = t
    } else if (tag === 1) {
      this.wifiOffTime = t
    } else if (tag === 2) {
      this.wifiOnTime = t
    }
  }

  handleWeekToggle(tag: number, idx: number): void {
    if (tag === 3) {
      const arr: boolean[] = [...this.rebootDays]
      arr[idx] = !arr[idx]
      this.rebootDays = arr
    } else {
      const arr: boolean[] = [...this.wifiDays]
      arr[idx] = !arr[idx]
      this.wifiDays = arr
    }
  }

  // ========== UI 组件 ==========

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.theme.textSecondary)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 4, right: 4, top: 16, bottom: 6 })
  }

  /** 时间选择行（tag 分发：0=重启 1=WiFi关 2=WiFi开） */
  @Builder
  timeRow(label: string, time: string, showPicker: boolean, tag: number) {
    Column() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor(this.theme.textPrimary)
        Blank()
        Text(time)
          .fontSize(16)
          .fontColor(this.theme.primary)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
        Text('▾')
          .fontSize(14)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        if (tag === 0) {
          this.showRebootPicker = !this.showRebootPicker
          this.showWifiPicker = false
        } else {
          this.wifiPickerIsOff = (tag === 1)
          this.showWifiPicker = !this.showWifiPicker
          this.showRebootPicker = false
        }
      })

      if (showPicker) {
        Divider().color(this.theme.borderGlass)
        TimePicker({
          selected: this.timeToDate(time)
        })
          .useMilitaryTime(true)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .onChange((value: TimePickerResult) => {
            this.handleTimeChange(tag, value.hour, value.minute)
          })
          .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
  }

  /** 星期多选行（tag 分发：3=重启星期 4=WiFi星期） */
  @Builder
  weekRow(flags: boolean[], tag: number) {
    Row() {
      ForEach(WEEK_LABELS, (label: string, idx: number) => {
        Text(label)
          .fontSize(13)
          .fontColor(flags[idx] ? Color.White : this.theme.textSecondary)
          .fontWeight(flags[idx] ? FontWeight.Bold : FontWeight.Normal)
          .width(34).height(34)
          .borderRadius(17)
          .backgroundColor(flags[idx] ? this.theme.primary : this.theme.bgGlassLight)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.handleWeekToggle(tag, idx)
          })
      }, (label: string, idx: number): string => `${tag}_${idx}_${label}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16, top: 6, bottom: 12 })
  }

  /** 卡片头部（开关 + 标题） */
  @Builder
  cardHeader(icon: string, title: string, desc: string, enabled: boolean, tag: number) {
    Row() {
      AppIcon({ name: icon, iconSize: 22, colors: [this.theme.primary] })
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Medium)
        Text(desc)
          .fontSize(11)
          .fontColor(this.theme.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .selectedColor('#448AFF')
        .onChange((v: boolean) => {
          if (tag === 0) {
            this.rebootEnabled = v
          } else {
            this.wifiEnabled = v
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Row() {
            Text(' 定时任务')
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
          Text('保存')
            .fontSize(13)
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .borderRadius(16)
            .backgroundColor(this.theme.primary)
            .onClick(() => {
              this.saveAll()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

        Scroll() {
          Column() {
            // ===== 定时重启卡片 =====
            Column() {
              this.cardHeader('arrow_clockwise', '定时重启', '到点自动重启路由器（如每周三凌晨 4 点）',
                this.rebootEnabled, 0)
              if (this.rebootEnabled) {
                Divider().color(this.theme.borderGlass)
                this.timeRow('重启时间', this.rebootTime, this.showRebootPicker, 0)
                Divider().color(this.theme.borderGlass)
                Row() {
                  Text('重复')
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
                this.weekRow(this.rebootDays, 3)
              }
            }
            .width('100%')
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .borderRadius(16)
            .clip(true)

            // ===== 定时 WiFi 卡片 =====
            Column() {
              this.cardHeader('wifi', '定时开关 WiFi', '到点自动关闭/开启无线网络（夜间断网更省电）',
                this.wifiEnabled, 1)
              if (this.wifiEnabled) {
                Divider().color(this.theme.borderGlass)
                this.timeRow('关闭 WiFi', this.wifiOffTime,
                  this.showWifiPicker && this.wifiPickerIsOff, 1)
                Divider().color(this.theme.borderGlass)
                this.timeRow('开启 WiFi', this.wifiOnTime,
                  this.showWifiPicker && !this.wifiPickerIsOff, 2)
                Divider().color(this.theme.borderGlass)
                Row() {
                  Text('重复')
                    .fontSize(14)
                    .fontColor(this.theme.textPrimary)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
                this.weekRow(this.wifiDays, 4)
              }
            }
            .width('100%')
            .margin({ top: 12 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .borderRadius(16)
            .clip(true)

            // ===== 说明卡片 =====
            this.sectionTitle('说明')
            Column() {
              Row() {
                AppIcon({ name: 'lightbulb', iconSize: 16, colors: ['#F59E0B'] })
                Column() {
                  Text('App 运行期间生效')
                    .fontSize(13)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                  Text('任务由 App 检测执行，建议保持 App 在后台运行（系统可能限制后台活动，属正常现象）')
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
                AppIcon({ name: 'moon', iconSize: 16, colors: ['#6366F1'] })
                Column() {
                  Text('为什么用 App 执行？')
                    .fontSize(13)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                  Text('路由器固件未开放 crontab 权限，由 App 在连接时到点调用系统接口执行，更安全可控')
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
            .borderRadius(16)
            .clip(true)

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
      .padding({ left: 16, right: 16 })

      // 保存成功提示
      if (this.showToast) {
        Text(this.toastText)
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.75)')
          .position({ x: '50%', y: '45%' })
          .translate({ x: -60 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
