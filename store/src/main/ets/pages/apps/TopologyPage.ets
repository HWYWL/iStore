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
import { AppIcon } from '../../common/components/AppIcon'

/** 拓扑节点（胶囊）布局信息 */
interface TopoNode {
  dev: ConnectedDevice | null
  isWifi: boolean
  kind: number          // 0=本机无线 1=直连 2=经AP/交换机 3=未知有线 4=分组标签
  gi: number            // 所属分组下标
  x: number
  y: number
  sx: number
  sy: number
  w: number
  h: number
  fs: number
  text: string
}

/** 接入分组：本机无线 / 某个桥接口 / 未知有线 */
interface TopoGroup {
  key: string
  label: string
  kind: number
  devs: ConnectedDevice[]
  total: number         // 组内设备总数（折叠时 devs 不参与绘制但总数仍保留）
  angle: number
  span: number
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
  @State onlineCount: number = 0
  /** 路由器不允许执行网络命令 → 端口信息拿不到 */
  @State portAccessDenied: boolean = false
  @State repairing: boolean = false
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private canvasW: number = 360
  private canvasH: number = 420
  private deviceName: string = '路由器'
  /** 已折叠的分组 key */
  private collapsed: string[] = []
  /** 当前帧节点几何信息，用于点击命中检测 */
  private hitNodes: TopoNode[] = []
  /** 当前帧分组顺序，用于折叠状态切换 */
  private groupKeys: string[] = []

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

  /** 画布高度：在线设备越多给的高度越大，保证全部设备都能铺开 */
  private canvasHeightValue(): number {
    const n: number = this.onlineCount
    if (n <= 6) {
      return 460
    }
    return Math.min(600, 460 + (n - 6) * 20)
  }

  /** 加载设备与无线客户端（区分有线/无线） */
  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      // 每次进入/刷新都重新读一次转发表，避免 30s 缓存挡住刚接入的设备
      api.refreshBridgeCache()
      const devs: ConnectedDevice[] = await api.fetchConnectedDevices()
      const wifiClients = await api.fetchWifiClients()
      const macs: string[] = []
      for (let i = 0; i < wifiClients.length; i++) {
        macs.push(wifiClients[i].mac.toUpperCase())
      }
      this.wifiMacs = macs
      this.devices = devs
      let online: number = 0
      let withPort: number = 0
      let wireless: number = 0
      for (let i = 0; i < devs.length; i++) {
        if (devs[i].isOnline) {
          online++
        }
        const bpOpt: string | undefined = devs[i].bridgePort
        const bp: string = bpOpt === undefined ? '' : bpOpt
        if (bp.length > 0) {
          withPort++
        }
        if (this.isWifiDevice(devs[i])) {
          wireless++
        }
      }
      this.onlineCount = online
      // 一个端口/无线都识别不出来，说明路由器没放行执行网络命令
      this.portAccessDenied = devs.length > 0 && withPort === 0 && wireless === 0
    } catch (e) {
      this.errorText = '加载设备信息失败'
    }
    this.isLoading = false
    this.draw()
  }

  /** 一键修复端口读取权限：通过 SSH 重写路由器 ACL（需设备开启 SSH） */
  async repairAccess(): Promise<void> {
    if (this.repairing) {
      return
    }
    this.repairing = true
    this.errorText = ''
    try {
      const api = new ApiService()
      const ok: boolean = await api.repairPortAccess()
      this.repairing = false
      if (ok) {
        await this.loadData()
        return
      }
      this.errorText = api.getLastError() || '修复失败：请确认路由器已开启 SSH，且账号密码正确'
    } catch (e) {
      this.repairing = false
      this.errorText = '修复失败，请稍后重试'
    }
  }

  /** 端口名是否属于无线接口（wlan0 / phy0-ap0 / ra0 / ath0 …） */
  private isWifiPort(port: string): boolean {
    const p: string = port.toLowerCase()
    if (p.length === 0) {
      return false
    }
    const prefixes: string[] = ['wlan', 'phy', 'ra', 'rai', 'ath', 'wl', 'mt', 'apcli']
    for (let i = 0; i < prefixes.length; i++) {
      if (p.indexOf(prefixes[i]) === 0) {
        return true
      }
    }
    return false
  }

  /**
   * 判定无线设备：三重依据，任一命中即可
   * 1) iwinfo assoclist 关联列表命中 MAC
   * 2) 有信号强度（无线才会合并到负值 dBm，有线恒为 0）
   * 3) 转发表学习端口是无线接口（wlan0/phy0-ap0…）
   */
  isWifiDevice(dev: ConnectedDevice): boolean {
    const m: string = dev.mac.toUpperCase()
    if (this.wifiMacs.indexOf(m) >= 0) {
      return true
    }
    if (dev.signalStrength < 0) {
      return true
    }
    const port: string = dev.bridgePort ? dev.bridgePort : ''
    return port.length > 0 && this.isWifiPort(port)
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
  private capsuleMetrics(ctx: CanvasRenderingContext2D, name: string, maxWOverride: number = 0): CapMetrics {
    const maxW: number = maxWOverride > 0 ? maxWOverride : Math.min(this.canvasW * 0.48, 168)
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
   * 按接入点分组
   * 本机无线（iwinfo assoclist 命中）→ 各桥接口（lan1/lan2…）→ 未知有线
   * 端口下挂多台设备说明该端口接的是交换机/AP，UI 上用独立颜色区分
   */
  private buildGroups(all: ConnectedDevice[]): TopoGroup[] {
    const groups: TopoGroup[] = []
    const wifi: TopoGroup = { key: 'wifi', label: 'WiFi', kind: 0, devs: [], total: 0, angle: 0, span: 0 }
    const portMap: Map<string, ConnectedDevice[]> = new Map()
    const unknown: ConnectedDevice[] = []
    for (let i = 0; i < all.length; i++) {
      const d: ConnectedDevice = all[i]
      if (!d.isOnline) {
        continue
      }
      if (this.isWifiDevice(d)) {
        wifi.devs.push(d)
        continue
      }
      const port: string = d.bridgePort ? d.bridgePort : ''
      if (port.length === 0) {
        unknown.push(d)
        continue
      }
      const list: ConnectedDevice[] | undefined = portMap.get(port)
      if (list) {
        list.push(d)
      } else {
        const created: ConnectedDevice[] = [d]
        portMap.set(port, created)
      }
    }
    if (wifi.devs.length > 0) {
      wifi.total = wifi.devs.length
      groups.push(wifi)
    }
    const ports: string[] = []
    portMap.forEach((list: ConnectedDevice[], key: string) => {
      if (key.length > 0) {
        ports.push(key)
      }
    })
    ports.sort()
    for (let i = 0; i < ports.length; i++) {
      const devs: ConnectedDevice[] | undefined = portMap.get(ports[i])
      if (!devs || devs.length === 0) {
        continue
      }
      const g: TopoGroup = {
        key: ports[i], label: ports[i], kind: devs.length > 1 ? 2 : 1,
        devs: devs, total: devs.length, angle: 0, span: 0
      }
      groups.push(g)
    }
    if (unknown.length > 0) {
      const g: TopoGroup = {
        key: 'wired', label: '有线', kind: 3, devs: unknown, total: unknown.length, angle: 0, span: 0
      }
      groups.push(g)
    }
    return groups
  }

  /** 端口名美化：brctl 只给出序号时显示「端口 N」 */
  private prettyPort(port: string): string {
    const m: RegExpMatchArray | null = port.match(/^port(\d+)$/)
    return m ? `端口 ${m[1]}` : port
  }

  /** 分组是否已折叠 */
  private isCollapsed(key: string): boolean {
    return this.collapsed.indexOf(key) >= 0
  }

  /** 分组在圆环上占用的角度权重 */
  private groupWeight(g: TopoGroup): number {
    if (this.isCollapsed(g.key)) {
      return 1
    }
    return Math.max(1, g.total)
  }

  /** 折叠 / 展开某个分组 */
  private toggleGroup(gi: number): void {
    if (gi < 0 || gi >= this.groupKeys.length) {
      return
    }
    const key: string = this.groupKeys[gi]
    const idx: number = this.collapsed.indexOf(key)
    if (idx >= 0) {
      const next: string[] = this.collapsed.slice()
      next.splice(idx, 1)
      this.collapsed = next
    } else {
      this.collapsed = this.collapsed.concat([key])
    }
    this.draw()
  }

  /** 点击命中检测：只有分组标签可切换折叠 */
  private handleTap(px: number, py: number): void {
    for (let i = 0; i < this.hitNodes.length; i++) {
      const n: TopoNode = this.hitNodes[i]
      if (n.kind !== 4) {
        continue
      }
      // 分组胶囊较窄，命中区向外扩一圈，方便手指点中
      if (Math.abs(px - n.x) <= n.w / 2 + 14 && Math.abs(py - n.y) <= n.h / 2 + 18) {
        this.toggleGroup(n.gi)
        return
      }
    }
  }

  /** 分组标签文字（带展开/收起指示） */
  private groupLabel(g: TopoGroup): string {
    const folded: boolean = this.isCollapsed(g.key)
    let head: string = ''
    if (g.kind === 0) {
      head = `WiFi ${g.total}`
    } else if (g.kind === 3) {
      head = `未识别 ${g.total}`
    } else {
      const name: string = this.prettyPort(g.label)
      head = g.total > 1 ? `${name} · ${g.total}` : name
    }
    // Canvas 字体对 ▾/▸ 支持不稳定，统一用 ASCII 符号表示可收起/可展开
    return folded ? `${head} +` : `${head} -`
  }

  private linkColor(kind: number): string {
    if (kind === 0) {
      return 'rgba(16,185,129,0.42)'
    }
    if (kind === 2) {
      return 'rgba(139,92,246,0.42)'
    }
    if (kind === 3) {
      return 'rgba(148,163,184,0.42)'
    }
    return 'rgba(59,130,246,0.42)'
  }

  private nodeColor(kind: number): string {
    if (kind === 0) {
      return '#10B981'
    }
    if (kind === 2) {
      return '#8B5CF6'
    }
    if (kind === 3) {
      return '#94A3B8'
    }
    return '#3B82F6'
  }

  private findGroupNode(list: TopoNode[], gi: number): TopoNode | null {
    for (let i = 0; i < list.length; i++) {
      if (list[i].gi === gi) {
        return list[i]
      }
    }
    return null
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

    // 按「接入点」分组：本机无线 / 各桥接口（lan1/lan2…）/ 未知有线
    const groups: TopoGroup[] = this.buildGroups(this.devices)
    const ringRx: number = Math.min(w * 0.40, Math.max(150, h * 0.52))
    const ringRy: number = Math.min(h * 0.36, 190)
    const glowR: number = Math.max(ringRx, ringRy)

    // 记录分组顺序，供点击折叠命中后定位分组
    const keys: string[] = []
    for (let i = 0; i < groups.length; i++) {
      keys.push(groups[i].key)
    }
    this.groupKeys = keys

    // 角度分配：按组内实际设备数加权（已折叠的组只占最小份额），避免大组挤在一起
    let totalWeight: number = 0
    for (let i = 0; i < groups.length; i++) {
      totalWeight += this.groupWeight(groups[i])
    }
    let cursor: number = -Math.PI / 2
    for (let i = 0; i < groups.length; i++) {
      const g: TopoGroup = groups[i]
      const weight: number = this.groupWeight(g)
      const span: number = (Math.PI * 2) * weight / Math.max(totalWeight, 1)
      g.angle = cursor + span / 2
      g.span = span
      cursor += span
    }

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

    // ---- 生成节点：内圈分组标签 + 外圈设备 ----
    const capH: number = 22
    const nodes: TopoNode[] = []
    for (let gi = 0; gi < groups.length; gi++) {
      const g: TopoGroup = groups[gi]
      const gx: number = cx + Math.cos(g.angle) * ringRx * 0.54
      const gy: number = cy + Math.sin(g.angle) * ringRy * 0.54
      const gName: string = this.groupLabel(g)
      const gm: CapMetrics = this.capsuleMetrics(ctx, gName, Math.min(this.canvasW * 0.34, 116))
      const gNode: TopoNode = {
        dev: null, isWifi: g.kind === 0, kind: 4, gi: gi,
        x: gx, y: gy, sx: gx, sy: gy, w: gm.w, h: capH - 4, fs: gm.fs, text: gm.text
      }
      nodes.push(gNode)

      const shown: ConnectedDevice[] = this.isCollapsed(g.key) ? [] : g.devs.slice()
      const spread: number = Math.min(g.span * 0.90, Math.PI * 1.9)
      const step: number = shown.length > 1 ? spread / (shown.length - 1) : 0
      for (let i = 0; i < shown.length; i++) {
        const dev: ConnectedDevice = shown[i]
        const name: string = dev.hostname || dev.mac || '未知设备'
        const m: CapMetrics = this.capsuleMetrics(ctx, name)
        const off: number = shown.length === 1 ? 0 : (i - (shown.length - 1) / 2) * step
        const a: number = g.angle + off
        const x: number = cx + Math.cos(a) * ringRx
        const y: number = cy + Math.sin(a) * ringRy
        const node: TopoNode = {
          dev: dev, isWifi: g.kind === 0, kind: g.kind, gi: gi,
          x: x, y: y, sx: x, sy: y, w: m.w, h: capH, fs: m.fs, text: m.text
        }
        nodes.push(node)
      }
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
    const groupNodes: TopoNode[] = []
    const devNodes: TopoNode[] = []
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].kind === 4) {
        groupNodes.push(nodes[i])
      } else {
        devNodes.push(nodes[i])
      }
    }
    // 中心 → 接入分组
    for (let i = 0; i < groupNodes.length; i++) {
      const gn: TopoNode = groupNodes[i]
      const gk: number = groups[gn.gi].kind
      const dx: number = gn.x - cx
      const dy: number = gn.y - cy
      const len: number = Math.sqrt(dx * dx + dy * dy) || 1
      drawLink(cx + (dx / len) * centerEdge, cy + (dy / len) * centerEdge, gn.x, gn.y, this.linkColor(gk))
    }
    // 接入分组 → 该组设备
    for (let i = 0; i < devNodes.length; i++) {
      const dn: TopoNode = devNodes[i]
      const gn: TopoNode | null = this.findGroupNode(groupNodes, dn.gi)
      if (gn) {
        drawLink(gn.x, gn.y, dn.x, dn.y, this.linkColor(groups[dn.gi].kind))
      }
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
      const kind: number = n.kind === 4 ? groups[n.gi].kind : n.kind
      const color: string = this.nodeColor(kind)
      const x0: number = n.x - n.w / 2
      const y0: number = n.y - n.h / 2
      const r: number = n.h / 2

      // 白色胶囊底 + 同色投影
      ctx.save()
      ctx.shadowColor = n.kind === 4 ? 'rgba(100,116,139,0.22)'
        : (kind === 0 ? 'rgba(16,185,129,0.28)'
          : (kind === 2 ? 'rgba(139,92,246,0.28)'
            : (kind === 3 ? 'rgba(148,163,184,0.28)' : 'rgba(59,130,246,0.28)')))
      ctx.shadowBlur = 8
      ctx.shadowOffsetY = 3
      this.capsulePath(ctx, x0, y0, n.w, n.h, r)
      ctx.fillStyle = n.kind === 4 ? 'rgba(255,255,255,0.94)' : '#FFFFFF'
      ctx.fill()
      ctx.restore()

      // 彩色胶囊描边（分组标签略细，视觉上退到设备之后）
      this.capsulePath(ctx, x0, y0, n.w, n.h, r)
      ctx.lineWidth = n.kind === 4 ? 1.2 : 1.8
      ctx.strokeStyle = color
      ctx.stroke()

      // 设备名称：完整居中塞进胶囊
      ctx.fillStyle = color
      ctx.font = (n.kind === 4 ? 'bold ' : '') + n.fs.toString() + 'vp sans-serif'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(n.text, n.x, n.y + 0.5)
    }

    // 保存本帧节点几何信息，供点击命中检测
    this.hitNodes = nodes
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          AppIcon({ name: 'circle_grid_2x2', iconSize: 15, colors: ['#8B5CF6'] })
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
          AppIcon({ name: 'arrow_clockwise', iconSize: 13, colors: [this.theme.primary] })
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
          AppIcon({ name: 'moon', iconSize: 34, colors: ['#94A3B8'] })
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
          .height(this.canvasHeightValue())
          .onReady(() => {
            this.draw()
          })
          .onClick((event: ClickEvent) => {
            this.handleTap(event.x, event.y)
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
              Text(' 无线').fontSize(11).fontColor(this.theme.textSecondary)
            }
            Row() {
              Circle({ width: 8, height: 8 }).fill('#3B82F6')
              Text(' 直连').fontSize(11).fontColor(this.theme.textSecondary)
            }
            .margin({ left: 14 })
            Row() {
              Circle({ width: 8, height: 8 }).fill('#8B5CF6')
              Text(' 经 AP/交换机').fontSize(11).fontColor(this.theme.textSecondary)
            }
            .margin({ left: 14 })
            Row() {
              Circle({ width: 8, height: 8 }).fill('#94A3B8')
              Text(' 未识别').fontSize(11).fontColor(this.theme.textSecondary)
            }
            .margin({ left: 14 })
            Blank()
            Text(`共 ${this.onlineCount} 台在线`)
              .fontSize(11).fontColor(this.theme.textTertiary)
          }
          .width('100%')

          Row() {
            AppIcon({ name: 'info_circle', iconSize: 11, colors: [this.theme.textTertiary] })
            Text(' 无线设备归入 WiFi 组；有线按路由器 LAN 端口分组，同一端口下多台设备视为经交换机/AP 接入；未识别表示转发表暂无该设备端口信息；点击分组节点可收起或展开')
              .fontSize(10).fontColor(this.theme.textTertiary)
              .layoutWeight(1)
          }
          .margin({ top: 8 })

          if (this.portAccessDenied) {
            Column() {
              Row() {
                AppIcon({ name: 'info_circle', iconSize: 11, colors: [this.theme.warning] })
                Text(' 路由器未放行端口查询命令，暂时读不到设备接在哪个口')
                  .fontSize(10).fontColor(this.theme.warning)
                  .layoutWeight(1)
                if (this.repairing) {
                  LoadingProgress().width(14).height(14).color(this.theme.primary)
                    .margin({ left: 6 })
                } else {
                  Text('立即修复')
                    .fontSize(10).fontColor(this.theme.primary)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(10)
                    .backgroundColor('rgba(68,138,255,0.1)')
                    .margin({ left: 6 })
                }
              }
              .width('100%')
              // 整行可点，避免小字按钮点不中
              .onClick(() => { this.repairAccess() })

              if (this.errorText.length > 0) {
                Text(this.errorText)
                  .fontSize(10).fontColor(this.theme.warning)
                  .margin({ top: 4 })
              }
            }
            .width('100%')
            .margin({ top: 8 })
          }
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
