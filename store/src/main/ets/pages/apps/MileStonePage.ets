/**
 * 运行里程碑页
 * 展示路由器连续运行天数、App 使用天数，里程碑达成撒花庆祝
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore } from '../../common/store/FunStore'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

const MILESTONES: number[] = [1, 7, 30, 100, 365]

@Entry
@Component
struct MileStonePageRoute {
  build() {
    Column() {
      MileStonePage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct MileStonePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State uptimeDays: number = 0
  @State appDays: number = 0
  @State firstDate: string = ''
  @State loaded: boolean = false
  @State celebrate: boolean = false
  @State tick: number = 0
  @State newMile: number = 0          // 本次新达成的里程碑天数
  private animTimer: number = -1
  private api: ApiService = new ApiService()
  private fun: FunStore = FunStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.load()
  }

  aboutToDisappear(): void {
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer)
      this.animTimer = -1
    }
  }

  async load(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        await this.fun.init(hostCtx as Context)
      }
      // 首次连接日期
      let fd: string = this.fun.getFirstDate()
      if (!fd) {
        const d: Date = new Date()
        const m: string = (d.getMonth() + 1).toString().padStart(2, '0')
        const day: string = d.getDate().toString().padStart(2, '0')
        fd = `${d.getFullYear()}-${m}-${day}`
        this.fun.setFirstDate(fd)
      }
      this.firstDate = fd
      // App 使用天数
      try {
        const t1: number = new Date(fd).getTime()
        const t2: number = Date.now()
        this.appDays = Math.max(0, Math.floor((t2 - t1) / 86400000)) + 1
      } catch (e) {
        this.appDays = 1
      }
      // 路由器 uptime
      const sys = await this.api.fetchSystemInfo()
      this.uptimeDays = Math.floor(sys.uptime / 86400)
      // 检查新里程碑达成 → 撒花
      const next: number = this.nextMile()
      if (next > 0 && this.uptimeDays >= next && !this.fun.isAchieved(`mile_${next}`)) {
        this.fun.setAchieved(`mile_${next}`)
        this.newMile = next
        this.celebrate = true
        this.animTimer = setInterval(() => {
          this.tick = this.tick + 1
        }, 40)
      }
    } catch (e) {
      hilog.error(0x0001, 'MileStone', `load err: ${String(e)}`)
    }
    this.loaded = true
  }

  /** 下一个未达成的里程碑 */
  private nextMile(): number {
    for (let i = 0; i < MILESTONES.length; i++) {
      if (!this.fun.isAchieved(`mile_${MILESTONES[i]}`)) {
        return MILESTONES[i]
      }
    }
    return 0
  }

  /** 粒子进度（0~1） */
  private pProgress(i: number): number {
    const phase: number = (this.tick + i * 9) % 36
    return phase / 36
  }

  /** 粒子大小 */
  private pSize(i: number): number {
    return 8 + this.pProgress(i) * 26
  }

  /** 粒子透明度 */
  private pAlpha(i: number): string {
    return (1 - this.pProgress(i)).toFixed(2)
  }

  /** 粒子 X */
  private pX(i: number): number {
    return 160 + Math.cos(i * 0.785) * this.pProgress(i) * 130
  }

  /** 粒子 Y */
  private pY(i: number): number {
    return 180 + Math.sin(i * 0.785) * this.pProgress(i) * 130
  }

  /** 撒花粒子（多个扩散圆环，由 tick 驱动） */
  @Builder
  confettiLayer() {
    if (this.celebrate) {
      Stack() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
          Circle({ width: this.pSize(i), height: this.pSize(i) })
            .fill(`rgba(255,138,61,${this.pAlpha(i)})`)
            .position({
              x: this.pX(i),
              y: this.pY(i)
            })
        }, (i: number): string => `c${i}`)
      }
      .width('100%').height(360)
      .position({ x: 0, y: 120 })
    }
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Row() {
            Text('‹')
              .fontSize(22).fontColor(this.theme.textPrimary)
              .padding({ left: 10, right: 6 })
            Text('运行里程碑')
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
            // 主卡：连续运行
            Column() {
              SymbolGlyph($r('sys.symbol.star_trophy'))
                .fontSize(40)
                .fontColor(['#F59E0B'])
              Text(`${this.uptimeDays}`)
                .fontSize(56).fontColor(this.theme.primary).fontWeight(FontWeight.Bold).fontFamily('monospace')
              Text('天连续稳定运行')
                .fontSize(14).fontColor(this.theme.textSecondary).margin({ top: 2 })
              Text('路由器一直在线，稳如泰山')
                .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 6 })
            }
            .width('100%').padding(28).borderRadius(24).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Center)

            // 里程碑进度条
            Column() {
              Row() {
                Text('里程碑进度')
                  .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                Blank()
                Text(`下一个：${this.nextMile()} 天`)
                  .fontSize(11).fontColor(this.theme.primary)
              }
              .width('100%')
              Row() {
                ForEach(MILESTONES, (m: number) => {
                  Column() {
                    SymbolGlyph(this.uptimeDays >= m ? $r('sys.symbol.star_trophy') : $r('sys.symbol.medal'))
                      .fontSize(22)
                      .fontColor([this.uptimeDays >= m ? '#F59E0B' : '#94A3B8'])
                      .opacity(this.uptimeDays >= m ? 1 : 0.45)
                    Text(`${m}天`)
                      .fontSize(10).fontColor(this.uptimeDays >= m ? this.theme.primary : this.theme.textTertiary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Center)
                }, (m: number): string => `m${m}`)
              }
              .width('100%').margin({ top: 12 })
              Row() {
                Progress({ value: Math.min(100, (this.uptimeDays / 365) * 100), total: 100 })
                  .width('100%').height(6)
                  .color('#FF8A3D')
                  .backgroundColor('#F0EBE0')
              }
              .width('100%').margin({ top: 10 })
            }
            .width('100%').padding(18).borderRadius(20).margin({ top: 14 })
            .backgroundColor(this.theme.bgCard)

            // App 使用卡
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.phone'))
                  .fontSize(26)
                  .fontColor(['#3B82F6'])
                Text(`${this.appDays}`)
                  .fontSize(24).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold).fontFamily('monospace')
                  .margin({ top: 6 })
                Text('天相伴')
                  .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 2 })
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Center)

              Column() {
                SymbolGlyph($r('sys.symbol.calendar'))
                  .fontSize(26)
                  .fontColor(['#8B5CF6'])
                Text(this.firstDate)
                  .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium).fontFamily('monospace')
                  .margin({ top: 6 })
                Text('首次连接的日子')
                  .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 2 })
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Center)
            }
            .width('100%').padding(20).borderRadius(20).margin({ top: 14 })
            .backgroundColor(this.theme.bgCard)

            // 新里程碑达成横幅
            if (this.celebrate) {
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.star_trophy')).fontSize(15).fontColor(['#FFFFFF'])
                  Text(` 达成里程碑：连续运行 ${this.newMile} 天！`)
                    .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
                Text('路由器辛苦了，给它点个赞')
                  .fontSize(11).fontColor('rgba(255,255,255,0.8)').margin({ top: 4 })
              }
              .width('100%').padding(18).borderRadius(20).margin({ top: 14 })
              .backgroundColor('#FF8A3D')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
      .width('100%').height('100%')

      // 撒花粒子层
      this.confettiLayer()
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
