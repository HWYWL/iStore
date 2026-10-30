/**
 * 网络心电图
 * 每秒 ping 一次公网目标，Canvas 实时绘制延迟波形（正常绿波/卡顿红尖峰）
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

const TARGET = '223.5.5.5'   // 阿里公共 DNS
const MAX_POINTS = 30

@Entry
@Component
struct NetEcgPageRoute {
  build() {
    Column() {
      NetEcgPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct NetEcgPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State running: boolean = false
  @State lastLatency: number = 0
  @State lastStatus: string = '--'
  @State points: number[] = []
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private timer: number = -1
  private sampling: boolean = false
  private api: ApiService = new ApiService()

  aboutToDisappear(): void {
    this.stop()
  }

  start(): void {
    if (this.running) return
    this.running = true
    this.points = []
    this.sampleOnce()
    this.timer = setInterval(() => {
      this.sampleOnce()
    }, 1000)
  }

  stop(): void {
    this.running = false
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  async sampleOnce(): Promise<void> {
    if (this.sampling) return
    this.sampling = true
    try {
      const out: string = await this.api.execCommand('/bin/ping', ['-c', '1', '-W', '1', TARGET])
      let lat: number = 0
      let status: string = '--'
      if (out) {
        const m: RegExpMatchArray | null = out.match(/time=([\d.]+)\s*ms/i)
        if (m && m[1]) {
          lat = Number(m[1])
          status = '正常'
        } else {
          status = '超时'
        }
      } else {
        status = '无响应'
      }
      this.lastLatency = lat
      this.lastStatus = status
      const pts: number[] = this.points.slice()
      pts.push(lat)
      if (pts.length > MAX_POINTS) {
        pts.shift()
      }
      this.points = pts
      this.draw()
    } catch (e) {
      hilog.error(0x0001, 'NetEcg', `sample err: ${String(e)}`)
    }
    this.sampling = false
  }

  /** 绘制心电图波形 */
  draw(): void {
    try {
      const ctx: CanvasRenderingContext2D = this.canvasCtx
      const w: number = 320
      const h: number = 140
      ctx.clearRect(0, 0, w, h)
      // 基线
      ctx.strokeStyle = 'rgba(0,200,83,0.2)'
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, h / 2)
      ctx.lineTo(w, h / 2)
      ctx.stroke()
      // 波形
      if (this.points.length < 2) return
      const step: number = w / (MAX_POINTS - 1)
      ctx.beginPath()
      for (let i = 0; i < this.points.length; i++) {
        const lat: number = this.points[i]
        const x: number = i * step
        let y: number = h / 2
        if (lat > 0) {
          y = h - 6 - (Math.min(300, lat) / 300) * (h - 12)
        }
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      }
      const last: number = this.points[this.points.length - 1]
      if (last > 150) {
        ctx.strokeStyle = '#FF5252'   // 卡顿红色
      } else {
        ctx.strokeStyle = '#00C853'   // 正常绿色
      }
      ctx.lineWidth = 2
      ctx.lineJoin = 'round'
      ctx.lineCap = 'round'
      ctx.stroke()
      // 终点脉冲
      if (this.points.length >= 2) {
        const lx: number = (this.points.length - 1) * step
        const ly: number = h - 6 - (Math.min(300, last) / 300) * (h - 12)
        ctx.fillStyle = last > 150 ? '#FF5252' : '#00C853'
        ctx.beginPath()
        ctx.arc(lx, ly, 4, 0, Math.PI * 2)
        ctx.fill()
      }
    } catch (e) {}
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('网络心电图')
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
          // 状态卡
          Column() {
            Row() {
              Text(this.lastStatus)
                .fontSize(20).fontColor(this.lastLatency > 150 ? '#FF5252' : '#00C853')
                .fontWeight(FontWeight.Bold)
              if (this.lastLatency > 0) {
                Text(`  ${this.lastLatency.toFixed(1)} ms`)
                  .fontSize(14).fontColor(this.theme.textPrimary).fontFamily('monospace')
              }
            }
            Text(`目标：${TARGET}（阿里 DNS）· 每秒采样`)
              .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 6 })
          }
          .width('100%').padding(16).borderRadius(18).margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Center)

          // 波形图
          Column() {
            Row() {
              Text('📈 延迟波形')
                .fontSize(12).fontColor(this.theme.textSecondary)
              Blank()
              if (this.running) {
                Circle({ width: 6, height: 6 }).fill('#00C853')
                Text(' 采样中').fontSize(10).fontColor('#00C853')
              }
            }
            .width('100%').margin({ bottom: 8 })
            Canvas(this.canvasCtx)
              .width('100%').height(140)
              .onReady(() => {
                this.draw()
              })
            Text('波峰越高延迟越大 · 红色 = 卡顿')
              .fontSize(9).fontColor(this.theme.textTertiary).width('100%').margin({ top: 6 })
          }
          .width('100%').padding(16).borderRadius(18).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Start)

          Row() {
            if (this.running) {
              AppIcon({ name: 'pause_fill', iconSize: 18, colors: ['#FFFFFF'] })
            } else {
              AppIcon({ name: 'media_center', iconSize: 18, colors: ['#FFFFFF'] })
            }
            Text(this.running ? '  停止监测' : '  开始检测')
              .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
          .width('100%').height(48).borderRadius(24)
          .backgroundColor(this.running ? '#FF5252' : '#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })
          .onClick(() => {
            if (this.running) {
              this.stop()
            } else {
              this.start()
            }
          })
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
