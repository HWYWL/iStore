/**
 * TopologyPage - 网络拓扑图
 * 可视化设备连接关系：路由器在中心，无线设备（下半区）/ 有线设备（上半区）围绕分布
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ConnectedDevice } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

/** 拓扑节点（胶囊）布局信息 */
interface TopoNode {
  dev: ConnectedDevice
  isWifi: boolean
  x: number
  y: number
  sx: number
  sy: number
  w: number
  h: number
  fs: number
  text: string
}

/** 胶囊尺寸测量结果 */
interface CapMetrics {
  w: number
  fs: number
  text: string
}

@Entry
@Component
struct TopologyPageRoute {
  build() {
    Column() {
      TopologyPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct TopologyPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State devices: ConnectedDevice[] = []
  @State wifiMacs: string[] = []
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private canvasW: number = 360
  private canvasH: number = 420
  private deviceName: string = '路由器'

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        const device = AppState.getInstance().getActiveDevice()
    this.deviceName = device ? (device.label || device.host) : '路由器'
    this.loadTopSafeArea()
    this.loadData()
  }

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
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 加载设备与无线客户端（区分有线/无线） */
  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      const devs: ConnectedDevice[] = await api.fetchConnectedDevices()
      const wifiClients = await api.fetchWifiClients()
      const macs: string[] = []
      for (let i = 0; i < wifiClients.length; i++) {
        macs.push(wifiClients[i].mac.toUpperCase())
      }
      this.wifiMacs = macs
      this.devices = devs
    } catch (e) {
      this.errorText = '加载设备信息失败'
    }
    this.isLoading = false
    this.draw()
  }

  isWifiDevice(dev: ConnectedDevice): boolean {
    const m: string = dev.mac.toUpperCase()
    return this.wifiMacs.indexOf(m) >= 0
  }

  /** 按最大宽度裁剪文本（超出加省略号） */
  private fitText(ctx: CanvasRenderingContext2D, text: string, maxW: number): string {
    if (ctx.measureText(text).width <= maxW) {
      return text
    }
    let s: string = text
    while (s.length > 1 && ctx.measureText(s + '…').width > maxW) {
      s = s.substring(0, s.length - 1)
    }
    return s + '…'
  }

  /** 椭圆胶囊路径 */
  private capsulePath(ctx: CanvasRenderingContext2D, x0: number, y0: number, cw: number, ch: number, r: number): void {
    ctx.beginPath()
    ctx.moveTo(x0 + r, y0)
    ctx.lineTo(x0 + cw - r, y0)
    ctx.arc(x0 + cw - r, y0 + r, r, Math.PI * 1.5, Math.PI * 0.5)
    ctx.lineTo(x0 + r, y0 + ch)
    ctx.arc(x0 + r, y0 + r, r, Math.PI * 0.5, Math.PI * 1.5)
    ctx.closePath()
  }

  /** 测量胶囊尺寸：优先缩小字号以完整容纳设备名 */
  private capsuleMetrics(ctx: CanvasRenderingContext2D, name: string): CapMetrics {
    const maxW: number = Math.min(this.canvasW * 0.52, 176)
    const padX: number = 9
    const innerW: number = maxW - padX * 2
    let fs: number = 9
    ctx.font = fs.toString() + 'vp sans-serif'
    let text: string = name
    let tw: number = ctx.measureText(text).width
    if (tw > innerW) {
      fs = 8
      ctx.font = fs.toString() + 'vp sans-serif'
      tw = ctx.measureText(text).width
    }
    if (tw > innerW) {
      fs = 7
      ctx.font = fs.toString() + 'vp sans-serif'
      tw = ctx.measureText(text).width
    }
    if (tw > innerW) {
      text = this.fitText(ctx, text, innerW)
      tw = ctx.measureText(text).width
    }
    const capW: number = Math.min(maxW, tw + padX * 2)
    const m: CapMetrics = { w: capW, fs: fs, text: text }
    return m
  }

  /**
   * 环形节点坐标
   * side: 0=上半圆（有线） 1=下半圆（无线） 2=整圈（某一类为空时避免半边空洞）
   * 返回 [x, y, 角度]
   */
  private nodePos(i: number, n: number, side: number): number[] {
    const w: number = this.canvasW
    const h: number = this.canvasH
    const cx: number = w / 2
    const cy: number = h / 2
    const rx: number = Math.min(w * 0.40, 165)
    const ry: number = Math.min(h * 0.34, 155)
    let a: number = 0
    if (side === 2) {
      a = -Math.PI / 2 + (i * Math.PI * 2) / Math.max(n, 1)
    } else {
      const span: number = Math.PI * 0.94
      const start: number = Math.PI / 2 - span / 2
      a = n === 1 ? Math.PI / 2 : start + (i * span) / (n - 1)
    }
    const x: number = cx + Math.cos(a) * rx
    const y: number = side === 0 ? cy - Math.sin(a) * ry
      : (side === 1 ? cy + Math.sin(a) * ry : cy + Math.sin(a) * ry)
    return [x, y, a]
  }

  /** 绘制拓扑图（中心路由器 + 无线/有线半圆分布） */
  draw(): void {
    const ctx: CanvasRenderingContext2D = this.canvasCtx
    const w: number = this.canvasW
    const h: number = this.canvasH
    const cx: number = w / 2
    const cy: number = h / 2
    if (w <= 0 || h <= 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)

    // 无线设备（下半区）与有线设备（上半区）分组
    const wifiDevs: ConnectedDevice[] = []
    const wiredDevs: ConnectedDevice[] = []
    for (let i = 0; i < this.devices.length; i++) {
      const d: ConnectedDevice = this.devices[i]
      if (!d.isOnline) continue
      if (this.isWifiDevice(d)) {
        wifiDevs.push(d)
      } else {
        wiredDevs.push(d)
      }
    }
    // 两类都有 → 上下半圆；只有一类 → 整圈排布，避免半边空洞
    const bothSides: boolean = wifiDevs.length > 0 && wiredDevs.length > 0
    const showWifi: ConnectedDevice[] = bothSides ? wifiDevs.slice(0, 8) : []
    const showWired: ConnectedDevice[] = bothSides ? wiredDevs.slice(0, 8) : []
    const singleRing: ConnectedDevice[] = bothSides ? [] : wifiDevs.concat(wiredDevs).slice(0, 12)
    const ringRx: number = Math.min(w * 0.40, 165)
    const ringRy: number = Math.min(h * 0.34, 155)
    const glowR: number = Math.max(ringRx, ringRy)

    // ---- 背景光晕 ----
    const glow = ctx.createRadialGradient(cx, cy, 8, cx, cy, glowR + 60)
    glow.addColorStop(0, 'rgba(59,130,246,0.12)')
    glow.addColorStop(1, 'rgba(59,130,246,0)')
    ctx.fillStyle = glow
    ctx.beginPath()
    ctx.arc(cx, cy, glowR + 60, 0, Math.PI * 2)
    ctx.fill()

    // ---- 虚线同心圆 ----
    ctx.save()
    ctx.setLineDash([4, 7])
    ctx.lineWidth = 1
    ctx.strokeStyle = 'rgba(148,163,184,0.34)'
    for (let i = 1; i <= 2; i++) {
      ctx.beginPath()
      ctx.ellipse(cx, cy, ringRx * (i === 1 ? 0.55 : 1), ringRy * (i === 1 ? 0.55 : 1), 0, 0, Math.PI * 2)
      ctx.stroke()
    }
    ctx.restore()

    // ---- 测量胶囊尺寸并计算布局（完整名称 + 互不遮挡）----
    const capH: number = 22
    const nodes: TopoNode[] = []
    const addNodes = (list: ConnectedDevice[], side: number, wifiMode: number): void => {
      for (let i = 0; i < list.length; i++) {
        const dev: ConnectedDevice = list[i]
        const name: string = dev.hostname || dev.mac || '未知设备'
        const m: CapMetrics = this.capsuleMetrics(ctx, name)
        const p: number[] = this.nodePos(i, list.length, side)
        const isWifiDev: boolean = wifiMode === 1 ? true : (wifiMode === 0 ? false : this.isWifiDevice(dev))
        const node: TopoNode = {
          dev: dev, isWifi: isWifiDev, x: p[0], y: p[1], sx: p[0], sy: p[1],
          w: m.w, h: capH, fs: m.fs, text: m.text
        }
        nodes.push(node)
      }
    }
    if (bothSides) {
      addNodes(showWired, 0, 0)
      addNodes(showWifi, 1, 1)
    } else {
      addNodes(singleRing, 2, 2)
    }

    // 迭代消解重叠：沿重叠较小的一侧把两个胶囊对推开
    const gap: number = 6
    for (let iter = 0; iter < 60; iter++) {
      let moved: boolean = false
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const a: TopoNode = nodes[i]
          const b: TopoNode = nodes[j]
          const ox: number = (a.w + b.w) / 2 + gap - Math.abs(a.x - b.x)
          const oy: number = (a.h + b.h) / 2 + gap - Math.abs(a.y - b.y)
          if (ox <= 0 || oy <= 0) {
            continue
          }
          moved = true
          if (ox <= oy) {
            const dir: number = a.x <= b.x ? -1 : 1
            a.x += dir * ox / 2
            b.x -= dir * ox / 2
          } else {
            const dir: number = a.y <= b.y ? -1 : 1
            a.y += dir * oy / 2
            b.y -= dir * oy / 2
          }
        }
      }
      // 约束在画布内，并避开中心路由器及其名称
      for (let k = 0; k < nodes.length; k++) {
        const n: TopoNode = nodes[k]
        n.x = Math.max(n.w / 2 + 4, Math.min(w - n.w / 2 - 4, n.x))
        n.y = Math.max(n.h / 2 + 4, Math.min(h - n.h / 2 - 4, n.y))
        const limitX: number = 30 + n.w / 2
        const limitY: number = 56 + n.h / 2
        if (Math.abs(n.x - cx) < limitX && Math.abs(n.y - cy) < limitY) {
          const dirY: number = n.y <= cy ? -1 : 1
          n.y = cy + dirY * limitY
          n.y = Math.max(n.h / 2 + 4, Math.min(h - n.h / 2 - 4, n.y))
        }
      }
      if (!moved) {
        break
      }
    }

    // ---- 连线（贝塞尔，先画线，胶囊覆盖其上）----
    ctx.lineWidth = 1.2
    const drawLink = (x1: number, y1: number, x2: number, y2: number, color: string): void => {
      const mx: number = (x1 + x2) / 2
      const my: number = (y1 + y2) / 2
      const bend: number = y2 < y1 ? 12 : -12
      const grad = ctx.createLinearGradient(x1, y1, x2, y2)
      grad.addColorStop(0, color)
      grad.addColorStop(1, 'rgba(148,163,184,0.18)')
      ctx.strokeStyle = grad
      ctx.beginPath()
      ctx.moveTo(x1, y1)
      ctx.quadraticCurveTo(mx + bend * 0.4, my + bend, x2, y2)
      ctx.stroke()
    }

    const centerEdge: number = 30
    for (let i = 0; i < nodes.length; i++) {
      const n: TopoNode = nodes[i]
      const color: string = n.isWifi ? 'rgba(16,185,129,0.45)' : 'rgba(59,130,246,0.45)'
      const dx: number = n.x - cx
      const dy: number = n.y - cy
      const len: number = Math.sqrt(dx * dx + dy * dy) || 1
      drawLink(cx + (dx / len) * centerEdge, cy + (dy / len) * centerEdge, n.x, n.y, color)
    }

    // ---- 中心路由器节点 ----
    ctx.save()
    ctx.shadowColor = 'rgba(37,99,235,0.35)'
    ctx.shadowBlur = 18
    ctx.shadowOffsetY = 6
    ctx.beginPath()
    ctx.arc(cx, cy, 30, 0, Math.PI * 2)
    ctx.fillStyle = '#2563EB'
    ctx.fill()
    ctx.restore()

    // 白色 WiFi 波纹
    ctx.strokeStyle = '#FFFFFF'
    ctx.fillStyle = '#FFFFFF'
    ctx.lineCap = 'round'
    for (let i = 1; i <= 2; i++) {
      ctx.lineWidth = 2.4
      ctx.beginPath()
      ctx.arc(cx, cy + 7, 6.5 * i, Math.PI * 1.16, Math.PI * 1.84)
      ctx.stroke()
    }
    ctx.beginPath()
    ctx.arc(cx, cy + 7, 2.1, 0, Math.PI * 2)
    ctx.fill()

    // 路由器名称（圆环下方，按画布宽度截断）
    ctx.textAlign = 'center'
    ctx.textBaseline = 'top'
    ctx.fillStyle = this.theme.textPrimary
    ctx.font = 'bold 13vp sans-serif'
    ctx.fillText(this.fitText(ctx, this.deviceName, Math.min(w - 80, 220)), cx, cy + 36)

    // ---- 设备节点（椭圆胶囊，完整名称居中）----
    for (let i = 0; i < nodes.length; i++) {
      const n: TopoNode = nodes[i]
      const color: string = n.isWifi ? '#10B981' : '#3B82F6'
      const x0: number = n.x - n.w / 2
      const y0: number = n.y - n.h / 2
      const r: number = n.h / 2

      // 白色胶囊底 + 同色投影
      ctx.save()
      ctx.shadowColor = n.isWifi ? 'rgba(16,185,129,0.28)' : 'rgba(59,130,246,0.28)'
      ctx.shadowBlur = 8
      ctx.shadowOffsetY = 3
      this.capsulePath(ctx, x0, y0, n.w, n.h, r)
      ctx.fillStyle = '#FFFFFF'
      ctx.fill()
      ctx.restore()

      // 彩色胶囊描边
      this.capsulePath(ctx, x0, y0, n.w, n.h, r)
      ctx.lineWidth = 1.8
      ctx.strokeStyle = color
      ctx.stroke()

      // 设备名称：完整居中塞进胶囊
      ctx.fillStyle = color
      ctx.font = n.fs.toString() + 'vp sans-serif'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(n.text, n.x, n.y + 0.5)
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
            .fontSize(15)
            .fontColor(['#8B5CF6'])
          Text(' 网络拓扑')
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
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(13)
            .fontColor([this.theme.primary])
          Text('刷新')
            .fontSize(12).fontColor(this.theme.primary)
            .margin({ left: 4 })
        }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor('rgba(68,138,255,0.1)')
          .onClick(() => { this.loadData() })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.theme.primary)
          Text('加载中...').fontSize(13).fontColor(this.theme.textTertiary).margin({ top: 12 })
        }
        .width('100%').padding(40).alignItems(HorizontalAlign.Center).margin({ top: 60 })
      } else if (this.devices.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.moon'))
            .fontSize(34)
            .fontColor(['#94A3B8'])
          Text('还没看到在线设备，大家可能都在午休')
            .fontSize(13).fontColor(this.theme.textTertiary).margin({ top: 10 })
          if (this.errorText) {
            Text(this.errorText)
              .fontSize(12).fontColor(this.theme.warning).margin({ top: 8 })
          }
        }
        .width('100%').alignItems(HorizontalAlign.Center).margin({ top: 120 })
      } else {
        // 拓扑画布（尺寸随容器变化，避免固定宽度导致错位）
        Canvas(this.canvasCtx)
          .width('100%')
          .height(460)
          .onReady(() => {
            this.draw()
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const w: number = Number.parseFloat(newValue.width.toString())
            const h: number = Number.parseFloat(newValue.height.toString())
            if (w > 0 && h > 0) {
              this.canvasW = w
              this.canvasH = h
              this.draw()
            }
          })
          .backgroundColor('transparent')

        // 拓扑说明
        Column() {
          Row() {
            Row() {
              Circle({ width: 8, height: 8 }).fill('#10B981')
              Text(' 无线连接').fontSize(11).fontColor(this.theme.textSecondary)
            }
            Row() {
              Circle({ width: 8, height: 8 }).fill('#3B82F6')
              Text(' 有线连接').fontSize(11).fontColor(this.theme.textSecondary)
            }
            .margin({ left: 18 })
            Blank()
            Text(`共 ${this.devices.length} 台`)
              .fontSize(11).fontColor(this.theme.textTertiary)
          }
          .width('100%')

          Row() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(11).fontColor([this.theme.textTertiary])
            Text(' 每侧最多展示 8 台，名称过长自动省略')
              .fontSize(10).fontColor(this.theme.textTertiary)
          }
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
      }
      Blank()
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
