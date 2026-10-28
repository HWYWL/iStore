/**
 * 今日网络运势
 * 每日一次占卜：结合真实数据（温度/负载/时间）生成宜忌与运势等级
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore } from '../../common/store/FunStore'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

const GOOD_YI: string[] = [
  '下载 4K 电影', '开视频会议', '全家联机打游戏', '备份重要数据', '看高清直播', '挂机下载大文件'
]
const BAD_YI: string[] = [
  '重启路由器', '深夜挂 BT', '同时开 8 台设备', '下载 100GB 资源', '边下边玩', '关闭 QoS'
]
const GOOD_JI: string[] = [
  '断网睡觉', '重启路由器', '给路由器散热', '升级固件', '清理缓存', '拆机清灰'
]
const BAD_JI: string[] = [
  '高峰时段下载', '挂满所有插口', '在弱信号角落打游戏', '继续超频', '满负载跑一整天', '忽略温度告警'
]

@Entry
@Component
struct FortunePageRoute {
  build() {
    Column() {
      FortunePage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct FortunePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State level: string = ''       // 大吉/吉/平/凶

  /** 运势图标配色 */
  levelColor(): string {
    if (this.level === '大吉') return '#F59E0B'
    if (this.level === '吉') return '#FBBF24'
    if (this.level === '平') return '#60A5FA'
    return '#94A3B8'
  }
  @State levelIcon: Resource = $r('sys.symbol.star')
  @State yiText: string[] = []
  @State jiText: string[] = []
  @State loaded: boolean = false
  @State todayText: string = ''
  private api: ApiService = new ApiService()
  private fun: FunStore = FunStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.load()
  }

  async load(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        await this.fun.init(hostCtx as Context)
      }
      // 每日一次：已抽过直接用
      const d: Date = new Date()
      const key: string = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
      this.todayText = key
      if (this.fun.getFortuneDate() === key && this.level) {
        this.loaded = true
        return
      }
      // 数据注入
      let temp: number = 0
      let load: number = 0
      let uptimeDays: number = 0
      try {
        const sys = await this.api.fetchSystemInfo()
        temp = sys.cpuTemp
        load = sys.cpuUsage
        uptimeDays = Math.floor(sys.uptime / 86400)
      } catch (e) {}
      const hour: number = d.getHours()
      // 运势等级：随机 + 数据修正
      let r: number = Math.floor(Math.random() * 100)
      if (temp > 65) r -= 20
      if (load > 85) r -= 15
      if (uptimeDays > 30) r += 10
      if (hour >= 1 && hour <= 5) r += 5
      r = Math.max(0, Math.min(100, r))
      let lv: string = ''
      let icon: Resource = $r('sys.symbol.star')
      if (r >= 80) { lv = '大吉'; icon = $r('sys.symbol.sun_max') }
      else if (r >= 55) { lv = '吉'; icon = $r('sys.symbol.star') }
      else if (r >= 30) { lv = '平'; icon = $r('sys.symbol.cloud') }
      else { lv = '凶'; icon = $r('sys.symbol.cloud') }
      this.level = lv
      this.levelIcon = icon
      // 宜忌抽取
      const yi: string[] = []
      const ji: string[] = []
      const pick = (arr: string[], count: number, out: string[]): void => {
        const pool: string[] = arr.slice()
        for (let i = 0; i < count && pool.length > 0; i++) {
          const idx: number = Math.floor(Math.random() * pool.length)
          out.push(pool[idx])
          pool.splice(idx, 1)
        }
      }
      if (r >= 55) {
        pick(GOOD_YI, 3, yi)
        pick(BAD_JI, 2, ji)
      } else {
        pick(GOOD_YI, 2, yi)
        pick(BAD_JI, 3, ji)
      }
      this.yiText = yi
      this.jiText = ji
      this.fun.setFortuneDate(key)
    } catch (e) {
      hilog.error(0x0001, 'Fortune', `load err: ${String(e)}`)
    }
    this.loaded = true
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('今日网络运势')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          // 运势主卡
          Column() {
            SymbolGlyph(this.levelIcon)
              .fontSize(60)
              .fontColor([this.levelColor()])
            Text(this.level)
              .fontSize(40).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
              .margin({ top: 6 })
            Text(`今日网络运势 · ${this.todayText}`)
              .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 8 })
          }
          .width('100%').padding(30).borderRadius(24).margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Center)

          // 宜
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor(['#00C853'])
              Text(' 宜').fontSize(13).fontColor('#00C853').fontWeight(FontWeight.Bold)
              Blank()
            }
            .width('100%')
            ForEach(this.yiText, (t: string) => {
              Row() {
                Text('·').fontColor('#00C853').fontSize(12)
                Text(t).fontSize(12).fontColor(this.theme.textPrimary).margin({ left: 6 })
                Blank()
              }
              .width('100%').margin({ top: 6 })
            }, (t: string): string => `yi_${t}`)
          }
          .width('100%').padding(16).borderRadius(16).margin({ top: 14 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Start)

          // 忌
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark_circle')).fontSize(14).fontColor(['#FF5252'])
              Text(' 忌').fontSize(13).fontColor('#FF5252').fontWeight(FontWeight.Bold)
              Blank()
            }
            .width('100%')
            ForEach(this.jiText, (t: string) => {
              Row() {
                Text('·').fontColor('#FF5252').fontSize(12)
                Text(t).fontSize(12).fontColor(this.theme.textPrimary).margin({ left: 6 })
                Blank()
              }
              .width('100%').margin({ top: 6 })
            }, (t: string): string => `ji_${t}`)
          }
          .width('100%').padding(16).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Start)

          Text('运势仅供参考，路由器运行愉快 😉')
            .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 14 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
