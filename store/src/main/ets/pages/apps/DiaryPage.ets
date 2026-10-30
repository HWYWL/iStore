/**
 * DiaryPage — 网络日记（每日网络事时间线）
 * 小管点评 + 4 格概览 + 事件时间线 + 日期翻页
 * 数据源：DiaryStore（事件）+ TrafficStatStore（流量）+ fetchConnectedDevices（在线）
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { DiaryStore, DayDiary, DiaryEvent } from '../../common/store/DiaryStore'
import { TrafficStatStore } from '../../common/store/TrafficStatStore'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice, TrafficHistory } from '../../models/Models'
import { NotifyStore } from '../../common/store/NotifyStore'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

@Entry
@Component
struct DiaryPageRoute {
  build() {
    Column() {
      DiaryPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct DiaryPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State day: DayDiary = { date: '', onlineCount: 0, newCount: 0, trafficGb: 0, abnormalCount: 0, events: [] }
  @State dateLabel: string = '今天'
  @State topSafeArea: number = 44
  @State comment: string = '今天一切平稳，小管很省心 ✨'
  private store: DiaryStore = DiaryStore.getInstance()
  private dayOffset: number = 0      // 0=今天, 1=昨天...
  private dates: string[] = []

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.store.init(hostCtx).then(() => {
        this.dates = this.store.recentDates(30)
        this.loadDay(0)
        this.collectToday()
      })
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

  /** 加载某天（offset: 0=今天） */
  loadDay(offset: number): void {
    if (offset < 0 || offset >= this.dates.length) return
    this.dayOffset = offset
    this.day = this.store.getDay(this.dates[offset])
    // 日期标签
    const d: Date = new Date()
    const target: Date = new Date(d.getTime() - offset * 86400000)
    if (offset === 0) {
      this.dateLabel = `今天 · ${target.getMonth() + 1}月${target.getDate()}日`
    } else if (offset === 1) {
      this.dateLabel = `昨天 · ${target.getMonth() + 1}月${target.getDate()}日`
    } else {
      this.dateLabel = `${target.getMonth() + 1}月${target.getDate()}日`
    }
    this.genComment(offset)
  }

  /** 生成小管点评（规则模板） */
  genComment(offset: number): void {
    const evs: DiaryEvent[] = this.day.events
    const bad: DiaryEvent[] = evs.filter((e: DiaryEvent) => e.type === 'offline' || e.type === 'peak')
    const newDev: DiaryEvent[] = evs.filter((e: DiaryEvent) => e.type === 'new_device')
    const traffic: DiaryEvent[] = evs.filter((e: DiaryEvent) => e.type === 'traffic')
    let parts: string[] = []
    if (traffic.length > 0) {
      parts.push(`「${traffic[0].title}」${traffic[0].desc}`)
    }
    if (newDev.length > 0) {
      parts.push(`来了 ${newDev.length} 台新设备，已经记下啦 ✅`)
    }
    if (bad.length > 0) {
      parts.push(`有 ${bad.length} 个异常要留意 ⚠️`)
    }
    if (parts.length === 0) {
      this.comment = offset === 0 ? '今天一切平稳，全屋设备安安稳稳，小管很省心 ✨' : '这一天很平静，没什么大事发生 ✨'
    } else {
      this.comment = parts.join('，') + '。'
    }
  }

  /** 收集今日事件（新增设备/流量/掉线/安全） */
  async collectToday(): Promise<void> {
    try {
      const today: string = this.dates[0]
      // 1. 在线设备 + 新增设备
      const api: ApiService = new ApiService()
      const devices: ConnectedDevice[] = await api.fetchConnectedDevices()
      const online: number = devices.filter((d: ConnectedDevice) => d.isOnline).length
      const notify: NotifyStore = NotifyStore.getInstance()
      const known: string[] = notify.getLastMacs()
      const now: string = new Date().toTimeString().substring(0, 5)
      for (let i = 0; i < devices.length; i++) {
        const mac: string = devices[i].mac
        if (mac && known.indexOf(mac) < 0) {
          this.store.addEvent(today, {
            type: 'new_device',
            title: '新设备接入',
            desc: `「${devices[i].hostname || devices[i].vendor || mac}」首次连接 WiFi（${devices[i].ip}）`,
            time: now,
            chips: ['智能设备', '已自动加入名单'],
            chipTone: 'info'
          })
          known.push(mac)
        }
      }
      // 2. 今日流量
      const traffic: TrafficHistory[] = await api.fetchTrafficHistory()
      let rx: number = 0
      let tx: number = 0
      if (traffic.length > 0) {
        const last: TrafficHistory = traffic[traffic.length - 1]
        rx = last.rx
        tx = last.tx
      }
      const trafficGb: number = Math.round((rx + tx) / 1073741824 * 10) / 10
      if (trafficGb >= 5) {
        this.store.addEvent(today, {
          type: 'traffic',
          title: '今日流量可观',
          desc: `全天累计 ${trafficGb} GB，网络很活跃`,
          time: '累计',
          chips: [`${trafficGb} GB`, '正常'],
          chipTone: 'up'
        })
      }
      this.store.setSummary(today, online, trafficGb)
      // 3. 重新加载今日
      this.loadDay(0)
    } catch (e) {}
  }

  // ========== UI ==========
  /** 事件圆点色 */
  dotColor(type: string): string {
    if (type === 'new_device') return '#4A7FB5'
    if (type === 'offline' || type === 'peak') return '#FF5252'
    if (type === 'traffic' || type === 'security') return '#2FBFA8'
    return '#E6A800'
  }

  dotIcon(type: string): string {
    if (type === 'new_device') return '＋'
    if (type === 'offline') return '!'
    return '✓'
  }

  chipBg(tone: string): string {
    if (tone === 'up') return '#E4F3EE'
    if (tone === 'growth') return '#FAEEDA'
    if (tone === 'warn') return '#FDF0DC'
    if (tone === 'bad') return '#FBE7E5'
    return '#E6F0FA'
  }

  chipColor(tone: string): string {
    if (tone === 'up') return '#1B7A6A'
    if (tone === 'growth') return '#8A5A00'
    if (tone === 'warn') return '#8A5A00'
    if (tone === 'bad') return '#C0392B'
    return '#2A5A8A'
  }

  build() {
    Column() {
      // 标题栏（返回 + 日期导航）
      Row() {
        Text('‹‹')
          .fontSize(15).fontColor(this.theme.textSecondary).fontWeight(FontWeight.Bold)
          .width(34).height(34).borderRadius(11)
          .backgroundColor(this.theme.bgCard)
          .textAlign(TextAlign.Center)
          .shadow({ radius: 8, color: 'rgba(180,160,120,0.15)', offsetY: 3 })
          .margin({ right: 8 })
          .onClick(() => { AppNav.getInstance().back() })
        Text('‹')
          .fontSize(18).fontColor(this.theme.textSecondary).fontWeight(FontWeight.Bold)
          .width(34).height(34).borderRadius(11)
          .backgroundColor(this.theme.bgCard)
          .textAlign(TextAlign.Center)
          .shadow({ radius: 8, color: 'rgba(180,160,120,0.15)', offsetY: 3 })
          .onClick(() => { this.loadDay(this.dayOffset + 1) })
        Text(this.dateLabel)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.theme.textSecondary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(10).backgroundColor(this.theme.bgCard)
          .margin({ left: 8, right: 8 })
        Text('›')
          .fontSize(18).fontColor(this.theme.textSecondary).fontWeight(FontWeight.Bold)
          .width(34).height(34).borderRadius(11)
          .backgroundColor(this.theme.bgCard)
          .textAlign(TextAlign.Center)
          .shadow({ radius: 8, color: 'rgba(180,160,120,0.15)', offsetY: 3 })
          .enabled(this.dayOffset > 0)
          .opacity(this.dayOffset > 0 ? 1 : 0.3)
          .onClick(() => { this.loadDay(this.dayOffset - 1) })
        Blank()
        Text('网络日记')
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea, bottom: 6 })

      Scroll() {
        Column() {
          // 小管点评卡
          Row() {
            Row() {
              AppIcon({ name: 'face_smiling', iconSize: 19, colors: ['#FFFFFF'] })
            }
            .width(38).height(38).borderRadius(13)
            .backgroundColor(this.theme.primary)
            .justifyContent(FlexAlign.Center)
            Column() {
              Text('小管今日点评')
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#B0567A')
              Text(this.comment)
                .fontSize(12).fontColor(this.theme.textPrimary).lineHeight(19)
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 10 })
          }
          .width('100%')
          .padding(14)
          .borderRadius(22)
          .linearGradient({ angle: 135, colors: [['#FFF3E8', 0], ['#FFE9D5', 1]] })
          .shadow({ radius: 12, color: 'rgba(180,160,120,0.14)', offsetY: 4 })
          .margin({ top: 8 })

          // 4 格概览
          Row() {
            this.summaryItem(`${this.day.onlineCount}`, '在线设备', this.day.onlineCount > 0 ? 'up' : '')
            this.summaryItem(`${this.day.newCount}`, '新增设备', this.day.newCount > 0 ? 'warn' : '')
            this.summaryItem(`${this.day.trafficGb}`, '总流量 GB', '')
            this.summaryItem(`${this.day.abnormalCount}`, '异常事件', this.day.abnormalCount > 0 ? 'warn' : '')
          }
          .width('100%')
          .margin({ top: 12 })

          // 事件时间线
          if (this.day.events.length > 0) {
            Row() {
              Text(`${this.day.date}`).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
              Text(`${this.day.events.length} 条`)
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ left: 6 })
              Row().layoutWeight(1).height(1).backgroundColor('rgba(180,160,120,0.25)').margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 18, bottom: 6 })

            ForEach(this.day.events, (ev: DiaryEvent, idx: number) => {
              Row() {
                // 圆点 + 竖线
                Column() {
                  Text(this.dotIcon(ev.type))
                    .fontSize(8).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                    .width(14).height(14).borderRadius(7)
                    .backgroundColor(this.dotColor(ev.type))
                    .textAlign(TextAlign.Center)
                }
                .width(22)
                .alignItems(HorizontalAlign.Start)
                Column() {
                  Row() {
                    Text(ev.title)
                      .fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
                    Blank()
                    Text(ev.time)
                      .fontSize(10).fontColor(this.theme.textTertiary)
                  }
                  .width('100%')
                  Text(ev.desc)
                    .fontSize(11).fontColor(this.theme.textSecondary).lineHeight(16)
                    .width('100%').margin({ top: 5 })
                  if (ev.chips.length > 0) {
                    Row() {
                      ForEach(ev.chips, (c: string) => {
                        Text(c)
                          .fontSize(9).fontWeight(FontWeight.Bold)
                          .fontColor(this.chipColor(ev.chipTone))
                          .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                          .borderRadius(7)
                          .backgroundColor(this.chipBg(ev.chipTone))
                          .margin({ right: 6 })
                      }, (c: string) => c)
                    }
                    .width('100%').margin({ top: 8 })
                  }
                }
                .layoutWeight(1)
                .padding(12)
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .shadow({ radius: 10, color: 'rgba(180,160,120,0.12)', offsetY: 3 })
                .margin({ bottom: 10 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (ev: DiaryEvent, idx: number) => `${ev.type}_${idx}`)
          } else {
            // 空状态
            Column() {
              AppIcon({ name: 'archivebox', iconSize: 36, colors: ['#94A3B8'] })
              Text('这一天没有记录到事件')
                .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 10 })
              Text('连接路由器后会自动记录设备/流量/异常')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 4 })
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Center)
          }

          Blank().height(30)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  /** 概览格 */
  @Builder
  summaryItem(num: string, label: string, tone: string) {
    Column() {
      Text(num)
        .fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(tone === 'up' ? '#2FBFA8' : (tone === 'warn' ? '#E6A800' : this.theme.textPrimary))
      Text(label)
        .fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 3 })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.theme.bgCard)
    .shadow({ radius: 10, color: 'rgba(180,160,120,0.12)', offsetY: 3 })
    .margin({ right: 8 })
  }
}
