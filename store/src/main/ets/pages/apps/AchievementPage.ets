/**
 * 网络成就系统
 * 徽章收集：运行稳定 / 夜猫子 / 流量之王 / 设备云集 / 七日全勤 / 体检卫士
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore } from '../../common/store/FunStore'
import { TrafficStatStore } from '../../common/store/TrafficStatStore'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

interface AchDef {
  id: string
  icon: string
  color: string
  name: string
  desc: string
  hint: string
}

const ACHS: AchDef[] = [
  { id: 'health', icon: 'staroflife', color: '#10B981', name: '体检卫士', desc: '完成一次智能网络体检', hint: '去应用中心跑一次体检' },
  { id: 'stable', icon: 'medal', color: '#F59E0B', name: '稳如泰山', desc: '路由器连续运行 7 天以上', hint: '别重启，继续跑' },
  { id: 'owl', icon: 'clock', color: '#6366F1', name: '夜猫子', desc: '凌晨 0~4 点还在用 App', hint: '今晚熬个夜试试' },
  { id: 'giant', icon: 'arrow_up_right', color: '#3B82F6', name: '流量之王', desc: '某天流量超过 100GB', hint: '下一个大文件冲一冲' },
  { id: 'crowd', icon: 'person_3', color: '#EC4899', name: '门庭若市', desc: '同时在线设备 15 台以上', hint: '家里人多时解锁' },
  { id: 'week', icon: 'flame', color: '#F97316', name: '七日全勤', desc: '最近 7 天使用 App 5 天以上', hint: '每天打开一次' },
  { id: 'refresh_master', icon: 'arrow_clockwise', color: '#8B5CF6', name: '数据狂人', desc: '累计下拉刷新 50 次', hint: '首页多下拉几次' },
  { id: 'archaeologist', icon: 'magnifyingglass', color: '#0891B2', name: '数据考古学家', desc: '翻看 3 天前的历史数据', hint: '查看历史流量/排名页' },
  { id: 'midnight_flow', icon: 'waveform', color: '#14B8A6', name: '午夜洪流', desc: '凌晨 0~5 点单小时流量超 1GB', hint: '深夜下个大文件' },
  { id: 'peak_master', icon: 'calendar', color: '#EF4444', name: '准点下班', desc: '18~20 点单小时流量超 2GB', hint: '下班回家刷剧试试' }
]

@Entry
@Component
struct AchievementPageRoute {
  build() {
    Column() {
      AchievementPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct AchievementPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State doneCount: number = 0
  @State doneMap: Record<string, boolean> = {}
  @State newAch: string = ''        // 新达成徽章名（弹横幅）
  @State loaded: boolean = false
  private api: ApiService = new ApiService()
  private fun: FunStore = FunStore.getInstance()
  private traffic: TrafficStatStore = TrafficStatStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.load()
  }

  async load(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        await this.fun.init(hostCtx as Context)
        await this.traffic.init(hostCtx as Context)
      }
      // 逐项判定
      const map: Record<string, boolean> = {}
      for (let i = 0; i < ACHS.length; i++) {
        map[ACHS[i].id] = this.fun.isAchieved(ACHS[i].id)
      }
      // 体检卫士：NetworkCheckPage 完成时已标记（无则保持未达成）
      // 稳如泰山：uptime >= 7 天
      try {
        const sys = await this.api.fetchSystemInfo()
        if (sys.uptime >= 7 * 86400) {
          this.unlock(map, 'stable', '稳如泰山')
        }
      } catch (e) {}
      // 夜猫子：当前小时 0~4
      const hour: number = new Date().getHours()
      if (hour >= 0 && hour <= 4) {
        this.unlock(map, 'owl', '夜猫子')
      }
      // 流量之王：7 天内某天 >= 100GB
      try {
        const days = this.traffic.getDays(7)
        const G = 100 * 1024 * 1024 * 1024
        for (let i = 0; i < days.length; i++) {
          if ((days[i].rx + days[i].tx) >= G) {
            this.unlock(map, 'giant', '流量之王')
            break
          }
        }
      } catch (e) {}
      // 小时级成就：基于本地小时桶（近 7 天累加）
      try {
        const trend = this.traffic.getHourlyTrend(7)
        for (let h = 0; h < trend.length; h++) {
          const sum: number = trend[h].rx + trend[h].tx
          if (h <= 5 && sum >= 1073741824) {
            this.unlock(map, 'midnight_flow', '午夜洪流')
          }
          if (h >= 18 && h <= 20 && sum >= 2147483648) {
            this.unlock(map, 'peak_master', '准点下班')
          }
        }
      } catch (e) {}
      // 门庭若市：在线设备 >= 15
      try {
        const devs = await this.api.fetchConnectedDevices()
        if (devs.length >= 15) {
          this.unlock(map, 'crowd', '门庭若市')
        }
      } catch (e) {}
      // 七日全勤：最近 7 天使用 >= 5 天
      this.fun.markUsedToday()
      if (this.fun.usedDays(7) >= 5) {
        this.unlock(map, 'week', '七日全勤')
      }
      this.doneMap = map
      let c: number = 0
      for (let i = 0; i < ACHS.length; i++) {
        if (map[ACHS[i].id]) c++
      }
      this.doneCount = c
    } catch (e) {
      hilog.error(0x0001, 'Achievement', `load err: ${String(e)}`)
    }
    this.loaded = true
  }

  private unlock(map: Record<string, boolean>, id: string, name: string): void {
    if (!map[id]) {
      map[id] = true
      this.fun.setAchieved(id)
      this.newAch = name
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('网络成就')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
        Text(`${this.doneCount}/${ACHS.length}`)
          .fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
          .margin({ right: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      // 新达成横幅
      if (this.newAch) {
        Column() {
          Text(`🎉 成就达成：${this.newAch}！`)
            .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .width('100%').padding(14).borderRadius(16).margin({ left: 16, right: 16, top: 6 })
        .backgroundColor('#FF8A3D')
        .transition(TransitionEffect.opacity(0.1).combine(
          TransitionEffect.scale({ x: 0.8, y: 0.8 }).animation({ duration: 250, curve: Curve.EaseOut })))
      }

      Scroll() {
        Column() {
          ForEach(ACHS, (a: AchDef) => {
            Row() {
              Row() {
                AppIcon({ name: a.icon, iconSize: 21, colors: [this.doneMap[a.id] ? a.color : '#94A3B8'] })
              }
              .width(42)
              .height(42)
              .borderRadius(13)
              .backgroundColor('#1F' + a.color.substring(1))
              .justifyContent(FlexAlign.Center)
              .opacity(this.doneMap[a.id] ? 1 : 0.55)
              Column() {
                Row() {
                  Text(a.name)
                    .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  if (this.doneMap[a.id]) {
                    Text(' 已达成')
                      .fontSize(10).fontColor('#00C853')
                  }
                }
                .width('100%')
                Text(this.doneMap[a.id] ? a.desc : `${a.desc}（${a.hint}）`)
                  .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)
              .margin({ left: 12 })
              if (this.doneMap[a.id]) {
                AppIcon({ name: 'checkmark_circle', iconSize: 20, colors: ['#00C853', '#7CE495'] })
              } else {
                AppIcon({ name: 'lock', iconSize: 16, colors: ['#94A3B8'] })
                  .opacity(0.7)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .borderRadius(16)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
          }, (a: AchDef): string => a.id)
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
