/**
 * 路由器心情
 * 根据温度/负载/运行天数生成路由器「心情」表情与吐槽
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

interface MoodInfo {
  icon: Resource
  title: string
  talk: string
  color: string
}

@Entry
@Component
struct RouterMoodPageRoute {
  build() {
    Column() {
      RouterMoodPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct RouterMoodPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State temp: number = 0
  @State load: number = 0
  @State uptimeDays: number = 0
  @State mood: MoodInfo = { icon: $r('sys.symbol.face_smiling'), title: '思考中', talk: '让我想想今天心情如何...', color: '#FF8A3D' }
  @State loaded: boolean = false

  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.refresh()
  }

  async refresh(): Promise<void> {
    this.loaded = false
    try {
      const sys = await this.api.fetchSystemInfo()
      this.temp = sys.cpuTemp
      this.load = sys.cpuUsage
      this.uptimeDays = Math.floor(sys.uptime / 86400)
      this.mood = this.judge(this.temp, this.load, this.uptimeDays)
    } catch (e) {
      hilog.error(0x0001, 'RouterMood', `refresh err: ${String(e)}`)
    }
    this.loaded = true
  }

  private judge(temp: number, load: number, days: number): MoodInfo {
    if (temp >= 65) {
      return { icon: $r('sys.symbol.thermometer'), title: '热到变形', talk: `我这体温都 ${temp.toFixed(0)}°C 了，快中暑了，能不能开空调…（把风扇对着我吹也行）`, color: '#FF5252' }
    }
    if (load >= 85) {
      return { icon: $r('sys.symbol.bolt'), title: '压力山大', talk: `CPU 都飙到 ${load.toFixed(0)}% 了！家里是不是有人在开矿？`, color: '#E6A800' }
    }
    if (days >= 100) {
      return { icon: $r('sys.symbol.heart'), title: '佛系运行', talk: `已连续运行 ${days} 天，老夫稳如磐石，连觉都不用睡。`, color: '#00C853' }
    }
    if (days >= 7) {
      return { icon: $r('sys.symbol.face_smiling'), title: '心情舒畅', talk: `连续跑了一周多，温温柔柔，不急不躁，状态正好。`, color: '#00C853' }
    }
    if (load >= 60) {
      return { icon: $r('sys.symbol.clock'), title: '小忙一下', talk: `负载 ${load.toFixed(0)}%，还行还行，忙里偷闲。`, color: '#FF8A3D' }
    }
    if (temp <= 0) {
      return { icon: $r('sys.symbol.info_circle'), title: '数据缺失', talk: '传感器没传来温度，我就先装个深沉。', color: '#B0A99A' }
    }
    return { icon: $r('sys.symbol.sun_max'), title: '元气满满', talk: `温度 ${temp.toFixed(0)}°C，负载 ${load.toFixed(0)}%，本路由器今天状态拉满！`, color: '#00C853' }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('路由器心情')
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
          // 心情主卡
          Column() {
            SymbolGlyph(this.mood.icon)
              .fontSize(64)
              .fontColor([this.mood.color])
              .scale({ x: 1, y: 1 })
            Text(this.mood.title)
              .fontSize(22).fontColor(this.mood.color).fontWeight(FontWeight.Bold)
              .margin({ top: 8 })
            Text(this.mood.talk)
              .fontSize(13).fontColor(this.theme.textSecondary).lineHeight(22)
              .margin({ top: 10 }).textAlign(TextAlign.Center)
          }
          .width('100%').padding(26).borderRadius(24).margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Center)

          // 数据卡
          Row() {
            Column() {
              Text(`${this.temp.toFixed(0)}°C`)
                .fontSize(22).fontColor(this.temp >= 65 ? '#FF5252' : this.theme.textPrimary)
                .fontWeight(FontWeight.Bold).fontFamily('monospace')
              Text('温度')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)
            Column() {
              Text(`${this.load.toFixed(0)}%`)
                .fontSize(22).fontColor(this.load >= 85 ? '#E6A800' : this.theme.textPrimary)
                .fontWeight(FontWeight.Bold).fontFamily('monospace')
              Text('CPU 负载')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)
            Column() {
              Text(`${this.uptimeDays}天`)
                .fontSize(22).fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Bold).fontFamily('monospace')
              Text('已运行')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)
          }
          .width('100%').padding(18).borderRadius(18).margin({ top: 14 })
          .backgroundColor(this.theme.bgCard)

          Row() {
            Text('↻ 重新测心情')
              .fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
          }
          .width('100%').height(44).borderRadius(22)
          .backgroundColor('#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })
          .onClick(() => { this.refresh() })
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
