/**
 * PetPage — 小管家宠物养成（「C · 玻璃心电图」版式，按 HTML 原型完整还原）
 * 结构：玻璃宠物场景 → 实时网速（下载/上传） → 分段互动条 → 成长里程碑 XP → 双列任务卡
 * 动画：bob 浮动 / 喂食跳跃+粒子 / 摸头倾斜 / 换装扮
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SKINS, SkinDef } from '../../common/theme/ThemeColors'
import { PetStore, PetState } from '../../common/store/PetStore'
import { FormatUtils } from '../../common/utils/FormatUtils'
import { LIVE_REFRESH_MS } from '../../common/utils/RefreshRate'
import { LiveRateStore, RateListener } from '../../common/store/LiveRateStore'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

/** 皮肤 → 小管家配色（HTML 原型同款） */
interface PetSkinColor {
  body: string
  edge: string
  faceBg: string
}

/** 体征浮窗入参（对象按引用传递，状态变化才会刷新 @Builder） */
interface VitalChipArg {
  dot: string
  label: string
  value: number
  right: boolean
}

/** 任务勾选圈入参（同上，必须传对象，否则勾选不会刷新） */
interface QuestCheckArg {
  done: boolean
}

/** 互动条分段入参 */
interface ActionSegArg {
  idx: number
  label: string
  icon: string
}

/** 粒子（cube=二进制数据块 / heart=爱心 / spark=星星） */
interface Particle {
  id: number
  kind: string
  text: string
  dx: number    // 相对宠物中心的横向偏移
  y: number     // 起始高度（场景坐标）
  rise: number  // 上升距离
  delay: number // 错峰延迟 ms
  size: number  // 字号
}

/** 网络流量曲线：采样点数（间隔与首页 / 应用中心统一） */
const SPEED_SAMPLES: number = 32
/** 速率历史（模块级，页面反复进出仍保留，避免每次都重新铺平） */
const RATE_HISTORY: number[][] = [[], []]

/** 任务定义（HTML 原型 TASKS 同款配色） */
interface QuestDef {
  name: string
  energy: number
  icon: string
  c1: string
  c2: string
  route: string
}

const QUESTS: QuestDef[] = [
  { name: '完成一次安全体检', energy: 20, icon: 'staroflife', c1: '#9A8BFF', c2: '#6351E8', route: 'pages/apps/NetworkCheckPage' },
  { name: '和小管聊一次天', energy: 15, icon: 'message', c1: '#5FD5A8', c2: '#20A875', route: 'pages/apps/NetworkHelperPage' },
  { name: '查看今日流量', energy: 10, icon: 'wifi', c1: '#FFB36B', c2: '#F2762B', route: 'pages/apps/TrafficReportPage' },
  { name: '查看设备电量排行', energy: 10, icon: 'battery', c1: '#FFD06B', c2: '#F0A21B', route: 'pages/apps/DeviceActivityPage' },
  { name: '打开安全中心', energy: 15, icon: 'security_shield', c1: '#8FB4FF', c2: '#4C7BE8', route: 'pages/security/SecurityHubPage' }
]

const STAGE_LABELS: string[] = ['幼年期', '活泼期', '成长期', '守护期', '完全体']

@Entry
@Component
struct PetPageRoute {
  build() {
    Column() {
      PetPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct PetView {
  @Prop theme: ThemePalette = LIGHT_THEME
  /** 嵌入分栏时背景透明，与左右两栏共用同一块底（避免叠成两层渐变） */
  @Prop embedded: boolean = false
  @State pet: PetState = PetStore.getInstance().getState()
  @State moodText: string = '很开心'
  @State bobY: number = 0          // 常驻浮动
  @State bobRot: number = 0        // 浮动时的轻微摇摆
  @State jumping: boolean = false
  @State tilting: boolean = false
  @State eyesOpen: boolean = true   // 眨眼
  @State mouthOpen: boolean = false // 喂数据时的 O 形嘴
  @State happyEyes: boolean = false // 摸摸头时的眯眯眼
  @State munchOn: boolean = false   // 喂数据时的咀嚼缩放
  @State actIndex: number = 0       // 互动条当前选中项（0 喂数据 / 1 摸摸头 / 2 换装扮）
  @State rxRate: number = 0         // 实时下载速率（B/s）
  @State txRate: number = 0         // 实时上传速率（B/s）
  @State antAngle: number = -6      // 天线摆动
  @State ledA: number[] = [1, 1, 1] // LED 轮流脉动
  @State breatheOn: boolean = false // 呼吸缩放
  @State particles: Particle[] = []
  @State taskFlags: boolean[] = [false, false, false, false, false]
  private speedCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private store: PetStore = PetStore.getInstance()
  private timerId: number = -1
  private bobTimerId: number = -1
  private blinkTimerId: number = -1
  private taskTimerId: number = -1
  private rateListener: RateListener | null = null
  private lastSampleStamp: number = 0
  private pId: number = 0

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.store.init(hostCtx).then(() => {
        this.pet = this.store.getState()
        this.store.persistVisits()
        this.syncTasks()
        this.refreshMoodText()
      })
    } else {
      this.store.persistVisits()
      this.syncTasks()
    }
    // 任务状态同步（页面在右侧面板常驻，靠轮询感知其它入口的完成情况）
    this.taskTimerId = setInterval(() => {
      this.syncTasks()
    }, 2000)
    // 网络流量：订阅全局速率心跳（与首页 / 应用中心同一份数据、同一节奏）
    this.rateListener = (rx: number, tx: number) => { this.onRate(rx, tx) }
    LiveRateStore.getInstance().subscribe(this.rateListener)
    // 常驻动画：bob 浮动（HTML 原型 bob 3.6s ±6px ±1.2°）
    this.bobTimerId = setInterval(() => {
      this.bobY = this.bobY === 0 ? -6 : 0
      this.bobRot = this.bobRot === 0 ? -1.2 : 1.2
    }, 1800)
    // 呼吸（pet-anim breathe）
    this.getUIContext().animateTo({
      duration: 1800, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
    }, () => { this.breatheOn = true })
    // 天线摆动（pet-ant antsway）
    this.getUIContext().animateTo({
      duration: 2900, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
    }, () => { this.antAngle = 8 })
    // LED 轮流脉动（led ledpulse，错峰 320ms）
    const ledDelays: number[] = [0, 320, 640]
    for (let i = 0; i < 3; i++) {
      const idx: number = i
      this.getUIContext().animateTo({
        duration: 1900, delay: ledDelays[idx], iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
      }, () => {
        const next: number[] = this.ledA.slice()
        next[idx] = 0.32
        this.ledA = next
      })
    }
    // 眨眼（pet-eyes blink 4.6s）
    this.blinkTimerId = setInterval(() => {
      this.eyesOpen = false
      setTimeout(() => { this.eyesOpen = true }, 140)
    }, 4600)
    // 心情小话轮播
    this.timerId = setInterval(() => {
      const msgs: string[] = ['今天网速不错，小管很开心～', '设备都好好的，我盯着呢！', '想喝口水…不对，我是路由器']
      this.moodText = msgs[Math.floor(Math.random() * msgs.length)]
    }, 8000)
  }

  aboutToDisappear(): void {
    if (this.rateListener) {
      LiveRateStore.getInstance().unsubscribe(this.rateListener)
      this.rateListener = null
    }
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    if (this.bobTimerId >= 0) {
      clearInterval(this.bobTimerId)
      this.bobTimerId = -1
    }
    if (this.blinkTimerId >= 0) {
      clearInterval(this.blinkTimerId)
      this.blinkTimerId = -1
    }
    if (this.taskTimerId >= 0) {
      clearInterval(this.taskTimerId)
      this.taskTimerId = -1
    }
  }

  refreshMoodText(): void {
    if (this.pet.mood >= 95) this.moodText = '幸福爆棚'
    else if (this.pet.mood >= 70) this.moodText = '很开心'
    else if (this.pet.mood >= 40) this.moodText = '一般般'
    else this.moodText = '有点委屈…'
  }

  petColors(): PetSkinColor {
    const s: SkinDef | undefined = SKINS.find((k: SkinDef) => k.id === this.pet.skinId)
    if (!s) return { body: '#FFB37A', edge: '#FF8A3D', faceBg: '#FFF6EC' }
    const p: string = s.theme.primary
    return { body: p, edge: p, faceBg: '#FFF6EC' }
  }

  skinName(): string {
    const s: SkinDef | undefined = SKINS.find((k: SkinDef) => k.id === this.pet.skinId)
    return s ? s.name : '米色经典'
  }

  // ========== 毛玻璃材质（与首页仪表盘 cardFill/cardBlur/cardBorder 完全一致） ==========
  private cardFill(): Array<[ResourceColor, number]> {
    if (!AppState.getInstance().isGlass()) {
      return [[this.theme.bgCard, 0], [this.theme.bgCard, 1]]
    }
    return [['rgba(255, 255, 255, 0.52)', 0], ['rgba(255, 255, 255, 0.38)', 0.5],
      ['rgba(255, 255, 255, 0.28)', 1]]
  }

  private cardBlur(base: number): number {
    return AppState.getInstance().isGlass() ? base + 26 : base
  }

  private cardBorder(): BorderOptions {
    if (!AppState.getInstance().isGlass()) {
      return { width: 0.5, color: this.theme.borderGlass }
    }
    return {
      width: { top: 1, right: 0.7, bottom: 0.7, left: 0.7 },
      color: {
        top: 'rgba(255, 255, 255, 1)',
        right: 'rgba(255, 255, 255, 0.66)',
        bottom: 'rgba(255, 255, 255, 0.44)',
        left: 'rgba(255, 255, 255, 0.66)'
      }
    }
  }

  private cardShadow(): ShadowOptions {
    return { radius: this.theme.cardShadowRadius, color: this.theme.cardShadow, offsetX: 0, offsetY: 4 }
  }

  /** 任务子卡填充：玻璃模式更透，与父卡形成层次但不突兀 */
  private questInnerFill(done: boolean): ResourceColor {
    if (AppState.getInstance().isGlass()) {
      return done ? 'rgba(255,255,255,0.34)' : 'rgba(255,255,255,0.60)'
    }
    return done ? 'rgba(255,255,255,0.6)' : 'rgba(255,255,255,0.92)'
  }

  /** 喂数据：二进制数据块上升 + 跳跃咀嚼 + O 形嘴（act-feed 同款） */
  onFeed(): void {
    this.pet = this.store.feed()
    this.jumping = true
    setTimeout(() => { this.jumping = false }, 650)
    this.munchOn = true
    setTimeout(() => { this.munchOn = false }, 780)
    this.mouthOpen = true
    setTimeout(() => { this.mouthOpen = false }, 900)
    this.spawnFx('cube')
    this.moodText = '吃得好饱，嗝～ 谢谢你'
    try {
      this.getUIContext().getPromptAction().showToast({ message: '饱食度 +15 · 能量上涨 · 好饱！', duration: 1400 })
    } catch (e) {}
  }

  /** 摸摸头：爱心上升 + 眯眯眼 + 腮红放大（act-pat 同款） */
  onPat(): void {
    this.pet = this.store.pat()
    this.tilting = true
    setTimeout(() => { this.tilting = false }, 500)
    this.happyEyes = true
    setTimeout(() => { this.happyEyes = false }, 1200)
    this.spawnFx('heart')
    this.refreshMoodText()
    try {
      this.getUIContext().getPromptAction().showToast({ message: '心情 +10 · XP +3 · 呼噜呼噜噜~', duration: 1400 })
    } catch (e) {}
  }

  /** 换装扮：经典橙 ↔ 深海蓝，帽子 pop 弹出（dressed 同款）；状态持久化 */
  toggleDress(): void {
    const next: boolean = !this.pet.dress
    this.pet = this.store.setDress(next)
    this.spawnFx('spark')
    this.moodText = next ? '换上了「深海蓝」装扮' : '换回经典橙'
    try {
      this.getUIContext().getPromptAction().showToast({
        message: (next ? '换上了「深海蓝」装扮' : '换回经典橙') + ' · XP +3', duration: 1400
      })
    } catch (e) {}
  }

  /** 互动条点击：先切换选中高亮，再执行对应动作 */
  onSegTap(idx: number): void {
    this.actIndex = idx
    if (idx === 0) {
      this.onFeed()
    } else if (idx === 1) {
      this.onPat()
    } else {
      this.toggleDress()
    }
  }

  doneCount(): number {
    let n: number = 0
    for (let i = 0; i < this.taskFlags.length; i++) {
      if (this.taskFlags[i]) n++
    }
    return n
  }

  questTotalEnergy(): number {
    let n: number = 0
    for (let i = 0; i < QUESTS.length; i++) {
      n += QUESTS[i].energy
    }
    return n
  }

  /** 从存储同步任务完成状态；奖励由 PetStore 幂等结算 */
  syncTasks(): void {
    const done: boolean[] = this.store.getDoneTasks()
    let changed: boolean = false
    for (let i = 0; i < done.length; i++) {
      if (done[i] !== this.taskFlags[i]) changed = true
    }
    if (changed) {
      this.taskFlags = done
    }
    const gained: number = this.store.settleTasks()
    if (gained > 0) {
      this.pet = this.store.getState()
      this.spawnFx('spark')
      this.moodText = '任务完成，小管有能量啦 ⚡'
    }
  }

  /** 粒子（参考图同款）：
   *  cube  = 喂数据，左右两列从脚底往上喷二进制数字块
   *  heart = 摸摸头，头顶上方喷出大小不一的爱心（眯眯眼）
   *  spark = 星星，头顶周围飘散 */
  spawnFx(kind: string): void {
    const bits: string[] = ['11', '0', '1', '10', '1', '0', '11', '10', '0', '1']
    const list: Particle[] = []
    if (kind === 'cube') {
      for (let i = 0; i < 10; i++) {
        const side: number = i % 2 === 0 ? -1 : 1
        const lane: number = Math.floor(i / 2) // 0..4
        list.push({
          id: this.pId++,
          kind: 'cube',
          text: bits[i],
          dx: side * (50 + lane * 9 + Math.random() * 10),
          y: 168 + Math.random() * 16,
          rise: 62 + lane * 18,
          delay: lane * 90,
          size: 9 + (i % 3)
        })
      }
    } else if (kind === 'heart') {
      const spread: number[] = [-54, -32, -10, 14, 36, -20, 4, 28, -44, 46]
      for (let i = 0; i < 6; i++) {
        list.push({
          id: this.pId++,
          kind: 'heart',
          text: '♥',
          dx: spread[i] + Math.random() * 8,
          y: 50 + (i % 3) * 12 + Math.random() * 8,
          rise: 48 + (i % 4) * 15,
          delay: i * 80,
          size: 13 + (i % 4) * 4
        })
      }
    } else {
      const spread: number[] = [-58, -34, -12, 10, 34, 58]
      for (let i = 0; i < 6; i++) {
        list.push({
          id: this.pId++,
          kind: 'spark',
          text: '✨',
          dx: spread[i],
          y: 46 + (i % 3) * 16,
          rise: 50 + (i % 3) * 12,
          delay: i * 70,
          size: 14 + (i % 3) * 2
        })
      }
    }
    this.particles = list
    setTimeout(() => { this.particles = [] }, 1500)
  }

  levelText(): string {
    if (this.pet.level >= 10) return 'Lv.' + this.pet.level + ' 传说'
    if (this.pet.level >= 5) return 'Lv.' + this.pet.level + ' 成熟期'
    if (this.pet.level >= 2) return 'Lv.' + this.pet.level + ' 青春期'
    return 'Lv.1 幼年期'
  }

  moodChipText(): string {
    return '☀ 心情 · ' + this.moodText
  }

  // ========== 网络流量曲线（下载 / 上传 双通道渐变面积） ==========
  /** 收到全局速率心跳：刷新读数并压入曲线历史 */
  private onRate(rxRate: number, txRate: number): void {
    this.rxRate = rxRate
    this.txRate = txRate
    this.pushSample(rxRate, txRate)
  }

  /** 历史采样：首帧用当前值铺满，避免刚进页面曲线是空的 */
  private pushSample(rxRate: number, txRate: number): void {
    const now: number = Date.now()
    const fresh: boolean = now - this.lastSampleStamp >= LIVE_REFRESH_MS * 0.5
    const rx: number[] = RATE_HISTORY[0]
    const tx: number[] = RATE_HISTORY[1]
    if (rx.length === 0) {
      for (let i = 0; i < SPEED_SAMPLES; i++) {
        rx.push(rxRate)
        tx.push(txRate)
      }
      this.lastSampleStamp = now
    } else if (fresh) {
      rx.push(rxRate)
      tx.push(txRate)
      while (rx.length > SPEED_SAMPLES) {
        rx.shift()
        tx.shift()
      }
      this.lastSampleStamp = now
    } else {
      // 同一拍里的重复回调：只刷新末点，不新增采样
      rx[rx.length - 1] = rxRate
      tx[tx.length - 1] = txRate
    }
    this.drawTraffic()
  }

  /** Catmull-Rom → 三次贝塞尔，把相邻采样点连成平滑曲线 */
  private smoothTo(ctx: CanvasRenderingContext2D, pts: number[][]): void {
    for (let i = 0; i < pts.length - 1; i++) {
      const p0: number[] = i > 0 ? pts[i - 1] : pts[i]
      const p1: number[] = pts[i]
      const p2: number[] = pts[i + 1]
      const p3: number[] = i + 2 < pts.length ? pts[i + 2] : p2
      const c1x: number = p1[0] + (p2[0] - p0[0]) / 6
      const c1y: number = p1[1] + (p2[1] - p0[1]) / 6
      const c2x: number = p2[0] - (p3[0] - p1[0]) / 6
      const c2y: number = p2[1] - (p3[1] - p1[1]) / 6
      ctx.bezierCurveTo(c1x, c1y, c2x, c2y, p2[0], p2[1])
    }
  }

  /** 单通道：渐变面积 + 同色描边（参考图同款堆叠效果） */
  private drawChannel(ctx: CanvasRenderingContext2D, vals: number[], max: number, w: number, h: number,
    topColor: string, bottomColor: string, lineColor: string): void {
    const n: number = vals.length
    if (n < 2 || w <= 0 || h <= 0) {
      return
    }
    const baseY: number = h - 1
    const spanY: number = h - 8
    const stepX: number = w / (n - 1)
    const pts: number[][] = []
    for (let i = 0; i < n; i++) {
      const x: number = i * stepX
      // 开方压缩纵向比例：低流量不贴底，峰值不顶边，整卡更饱满
      const t: number = Math.sqrt(Math.min(1, vals[i] / max))
      const y: number = baseY - t * spanY
      pts.push([x, Math.max(2, y)])
    }
    // 渐变面积
    const grad: CanvasGradient = ctx.createLinearGradient(0, 0, 0, h)
    grad.addColorStop(0, topColor)
    grad.addColorStop(1, bottomColor)
    ctx.beginPath()
    ctx.moveTo(pts[0][0], baseY)
    ctx.lineTo(pts[0][0], pts[0][1])
    this.smoothTo(ctx, pts)
    ctx.lineTo(pts[n - 1][0], baseY)
    ctx.closePath()
    ctx.fillStyle = grad
    ctx.fill()
    // 描边
    ctx.beginPath()
    ctx.moveTo(pts[0][0], pts[0][1])
    this.smoothTo(ctx, pts)
    ctx.strokeStyle = lineColor
    ctx.lineWidth = 2
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'
    ctx.stroke()
  }

  /** 重绘流量曲线：上传（紫）垫底，下载（青）覆盖在上 */
  private drawTraffic(): void {
    const ctx: CanvasRenderingContext2D = this.speedCtx
    const w: number = ctx.width
    const h: number = ctx.height
    if (w <= 0 || h <= 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)
    const rx: number[] = RATE_HISTORY[0].length > 1 ? RATE_HISTORY[0] : [0, 0]
    const tx: number[] = RATE_HISTORY[1].length > 1 ? RATE_HISTORY[1] : [0, 0]
    let peak: number = 64
    for (let i = 0; i < rx.length; i++) {
      if (rx[i] > peak) peak = rx[i]
    }
    for (let i = 0; i < tx.length; i++) {
      if (tx[i] > peak) peak = tx[i]
    }
    // 量程随窗口峰值走并留 15% 顶部余量，面积始终铺满卡片
    const max: number = Math.max(peak * 1.15, 256)
    this.drawChannel(ctx, tx, max, w, h,
      'rgba(139,92,246,0.52)', 'rgba(139,92,246,0.05)', 'rgba(139,92,246,0.85)')
    this.drawChannel(ctx, rx, max, w, h,
      'rgba(56,189,248,0.58)', 'rgba(56,189,248,0.06)', 'rgba(56,189,248,0.95)')
  }

  xpHint(): string {
    return '距下一阶还需 ' + Math.max(0, 100 - this.pet.xp) + ' XP'
  }

  // ========== 小管家形象（C · 玻璃心电图 SVG 同款 200×210 画布） ==========
  /** 机身渐变三段色：换装扮 = 深海蓝，经典 = --pc1/2/3 橙，其他皮肤跟随主题色 */
  private bodyGrad(): string[] {
    if (this.pet.dress) {
      return ['#A8C8FF', '#5B86F0', '#3B56C8']
    }
    if (this.skinName() === '米色经典') {
      return ['#FFC06B', '#FF9138', '#EA6712']
    }
    const c: PetSkinColor = this.petColors()
    return [c.body, c.body, c.edge]
  }

  /** 深海蓝装扮或非经典皮肤时戴上原型同款小蓝帽 */
  private hatOn(): boolean {
    return this.pet.dress || this.skinName() !== '米色经典'
  }

  @Builder
  petBody() {
    Stack() {
      // 天线（pet-ant antsway 摆动）
      Stack() {
        Line().startPoint([148, 66]).endPoint([168, 30])
          .width(200).height(210)
          .stroke('#9FA9B6').strokeWidth(6).strokeLineCap(LineCapStyle.Round)
        Circle({ width: 16, height: 16 }).fill('#FFD166').position({ x: 161, y: 20 })
        Circle({ width: 6, height: 6 }).fill('#FFF3C4').position({ x: 166, y: 24.5 })
      }
      .width(200).height(210)
      .alignContent(Alignment.TopStart)
      .rotate({ angle: this.antAngle, centerX: '74%', centerY: '31%' })
      .hitTestBehavior(HitTestMode.None)

      // 小脚
      Rect({ width: 22, height: 12, radius: 6 }).fill('#D9630F').position({ x: 66, y: 146 })
      Rect({ width: 22, height: 12, radius: 6 }).fill('#D9630F').position({ x: 112, y: 146 })

      // 机身（--pc1/2/3 对角渐变）
      Column()
        .width(120).height(102).borderRadius(32)
        .linearGradient({
          angle: 135,
          colors: [[this.bodyGrad()[0], 0], [this.bodyGrad()[1], 0.48], [this.bodyGrad()[2], 1]]
        })
        .position({ x: 40, y: 48 })
      // 顶部高光（gl 渐变区）
      Stack({ alignContent: Alignment.TopStart }) {
        Path().commands('M0 30c0-17 13-30 30-30h52c17 0 30 13 30 30v6H0z')
          .width(112).height(36)
          .fill('rgba(255,255,255,0.30)').stroke('none')
      }
      .position({ x: 44, y: 48 })
      .hitTestBehavior(HitTestMode.None)
      Line().startPoint([52, 78]).endPoint([148, 78])
        .width(200).height(210)
        .stroke('rgba(255,255,255,0.48)').strokeWidth(3).strokeLineCap(LineCapStyle.Round)
      Line().startPoint([52, 84]).endPoint([148, 84])
        .width(200).height(210)
        .stroke('rgba(199,80,10,0.16)').strokeWidth(1.5).strokeLineCap(LineCapStyle.Round)

      // LED 三灯（ledpulse 轮流脉动）
      Stack() {
        Circle({ width: 9.2, height: 9.2 }).fill('#38D98A')
        Circle({ width: 3.4, height: 3.4 }).fill('#D9FFEC').position({ x: 2.9, y: 2.9 })
      }
      .position({ x: 61.4, y: 61.4 })
      .opacity(this.ledA[0])
      Stack() {
        Circle({ width: 9.2, height: 9.2 }).fill('#FF6B6B')
        Circle({ width: 3.4, height: 3.4 }).fill('#FFE0E0').position({ x: 2.9, y: 2.9 })
      }
      .position({ x: 77.4, y: 61.4 })
      .opacity(this.ledA[1])
      Stack() {
        Circle({ width: 9.2, height: 9.2 }).fill('#FFC94A')
        Circle({ width: 3.4, height: 3.4 }).fill('#FFF3CE').position({ x: 2.9, y: 2.9 })
      }
      .position({ x: 93.4, y: 61.4 })
      .opacity(this.ledA[2])
      Line().startPoint([124, 66]).endPoint([138, 66])
        .width(200).height(210)
        .stroke('rgba(255,255,255,0.42)').strokeWidth(3).strokeLineCap(LineCapStyle.Round)

      // 侧面接口
      Rect({ width: 7, height: 20, radius: 3 }).fill('#D9630F').position({ x: 156, y: 96 })

      // 面板脸（fc 奶油渐变）
      Column()
        .width(84).height(56).borderRadius(24)
        .linearGradient({ angle: 90, colors: [['#FFFFFF', 0], ['#FFF0E1', 1]] })
        .border({ width: 1, color: 'rgba(233,201,168,0.55)' })
        .position({ x: 58, y: 90 })

      // 眼睛（blink 眨眼，摸头时隐藏）
      Stack() {
        Ellipse().width(16.8).height(20.8).fill('#3A2E22').position({ x: 8.4, y: 1.4 })
        Ellipse().width(16.8).height(20.8).fill('#3A2E22').position({ x: 40.4, y: 1.4 })
        Circle({ width: 5.6, height: 5.6 }).fill('#FFFFFF').position({ x: 13.9, y: 5.9 })
        Circle({ width: 5.6, height: 5.6 }).fill('#FFFFFF').position({ x: 45.9, y: 5.9 })
        Circle({ width: 2.4, height: 2.4 }).fill('rgba(255,255,255,0.7)').position({ x: 9, y: 14 })
        Circle({ width: 2.4, height: 2.4 }).fill('rgba(255,255,255,0.7)').position({ x: 41, y: 14 })
      }
      .width(60).height(24).position({ x: 70, y: 106 })
      .scale({ x: 1, y: this.eyesOpen ? 1 : 0.08 })
      .opacity(this.happyEyes ? 0 : 1)
      .hitTestBehavior(HitTestMode.None)

      // 眯眯眼（act-pat）
      Stack({ alignContent: Alignment.TopStart }) {
        Path().commands('M0 9q8-9 16 0M32 9q8-9 16 0')
          .width(48).height(10)
          .stroke('#2B2118').strokeWidth(3.4).fill('none').strokeLineCap(LineCapStyle.Round)
      }
      .position({ x: 76, y: 109 })
      .opacity(this.happyEyes ? 1 : 0)
      .hitTestBehavior(HitTestMode.None)

      // 腮红（act-pat 放大）
      Stack({ alignContent: Alignment.TopStart }) {
        Ellipse().width(12).height(6.4).fill('rgba(255,154,139,0.62)').position({ x: 0, y: 0 })
        Ellipse().width(12).height(6.4).fill('rgba(255,154,139,0.62)').position({ x: 58, y: 0 })
      }
      .width(76).height(7).position({ x: 62, y: 126.8 })
      .scale(this.happyEyes ? { x: 1.3, y: 1.3 } : { x: 1, y: 1 })
      .hitTestBehavior(HitTestMode.None)

      // 嘴（act-feed 切 O 形嘴，act-pat 切大笑弧线）
      if (this.mouthOpen) {
        Ellipse().width(10).height(12).fill('rgba(138,74,52,0.9)').position({ x: 95, y: 125 })
      } else if (this.happyEyes) {
        Stack({ alignContent: Alignment.TopStart }) {
          Path().commands('M0 0q11 10 22 0')
            .width(22).height(10)
            .stroke('#6B4A34').strokeWidth(2.8).fill('none').strokeLineCap(LineCapStyle.Round)
        }
        .position({ x: 89, y: 125 })
        .hitTestBehavior(HitTestMode.None)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Path().commands('M0 0q4 4 8 0')
            .width(8).height(4)
            .stroke('#6B4A34').strokeWidth(2).fill('none').strokeLineCap(LineCapStyle.Round)
        }
        .position({ x: 96, y: 128 })
        .hitTestBehavior(HitTestMode.None)
      }

      // 装扮帽（hatpop，非经典皮肤时戴上）：圆顶用圆角矩形保证定位确定
      if (this.hatOn()) {
        Stack() {
          Ellipse().width(84).height(14).fill('#4356B8').position({ x: 58, y: 40 })
          Column()
            .width(60).height(28)
            .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 0, bottomRight: 0 })
            .backgroundColor('#6C7BFF')
            .position({ x: 70, y: 20 })
          Circle({ width: 12, height: 12 }).fill('#FFD166').position({ x: 94, y: 11 })
        }
        .width(200).height(210)
        .alignContent(Alignment.TopStart)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(200)
    .height(210)
    .alignContent(Alignment.TopStart)
    .scale(this.munchOn
      ? { x: 1.055, y: 0.935 }
      : (this.breatheOn ? { x: 1.02, y: 0.982 } : { x: 1, y: 1 }))
  }

  /** 体征浮窗（饱食度 / 能量） */
  @Builder
  vitalsChip(arg: VitalChipArg) {
    Row() {
      Circle({ width: 6, height: 6 }).fill(arg.dot)
      Column() {
        Text(arg.label).fontSize(8).fontColor('#7A8698').letterSpacing(0.2)
        Text(`${arg.value}%`).fontSize(11).fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textPrimary).margin({ top: 1 })
      }
      .alignItems(arg.right ? HorizontalAlign.End : HorizontalAlign.Start)
      .margin({ left: 6 })
    }
    .padding({ left: 9, right: 9, top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor(AppState.getInstance().isGlass() ? 'rgba(255,255,255,0.46)' : 'rgba(255,255,255,0.92)')
    .backdropBlur(AppState.getInstance().isGlass() ? 16 : 0)
    .border(this.cardBorder())
    .shadow({ radius: 10, color: 'rgba(40,50,100,0.18)', offsetY: 4 })
  }

  /** 网络流量卡：标题图例 + 双读数 + 渐变面积曲线（曲线占满整卡） */
  @Builder
  trafficCard() {
    Column() {
      // 标题 + 图例
      Row() {
        Text('网络流量').fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
        Blank()
        Row() {
          Circle({ width: 7, height: 7 }).fill('#38BDF8')
          Text('下载').fontSize(9).fontColor('#6B7889').margin({ left: 4 })
        }
        .margin({ right: 10 })
        Row() {
          Circle({ width: 7, height: 7 }).fill('#8B5CF6')
          Text('上传').fontSize(9).fontColor('#6B7889').margin({ left: 4 })
        }
      }
      .width('100%')

      // 双读数：左右各半居中
      Row() {
        Column() {
          Text('下载速度').fontSize(9).fontColor('#8A96A8')
          Text(FormatUtils.formatSpeed(this.rxRate))
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#2E9BE8')
            .margin({ top: 2 }).maxLines(1)
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Center)

        Column() {
          Text('上传速度').fontSize(9).fontColor('#8A96A8')
          Text(FormatUtils.formatSpeed(this.txRate))
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#7C5CF0')
            .margin({ top: 2 }).maxLines(1)
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Center)
      }
      .width('100%').margin({ top: 6 })

      // 流量曲线：占满卡片剩余空间
      Canvas(this.speedCtx)
        .width('100%').layoutWeight(1)
        .margin({ top: 2 })
        .onReady(() => { this.drawTraffic() })
        .onAreaChange(() => {
          setTimeout(() => { this.drawTraffic() }, 50)
        })
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%').height(196)
    .padding({ left: 14, right: 12, top: 12, bottom: 10 })
    .borderRadius(22)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(20))
    .border(this.cardBorder())
    .shadow(this.cardShadow())
  }

  /** 互动条单个分段（选中态用毛玻璃高亮，不再用深紫实心块） */
  @Builder
  actionSeg(arg: ActionSegArg) {
    Row() {
      Row() {
        AppIcon({
          name: arg.icon, iconSize: 13,
          colors: [this.actIndex === arg.idx ? '#4B3FB5' : '#6351E8']
        })
      }
      .width(22).height(22).borderRadius(7)
      .backgroundColor(this.actIndex === arg.idx ? 'rgba(99,81,232,0.14)' : 'rgba(99,81,232,0.08)')
      .justifyContent(FlexAlign.Center)
      Text(arg.label)
        .fontSize(11).fontWeight(FontWeight.Bold)
        .fontColor(this.actIndex === arg.idx ? '#4B3FB5' : '#4A5670')
        .margin({ left: 6 })
    }
    .layoutWeight(1).height(46).borderRadius(12).justifyContent(FlexAlign.Center)
    .margin({ left: arg.idx === 0 ? 0 : 4 })
    .linearGradient({
      angle: 160,
      colors: this.actIndex === arg.idx
        ? [['rgba(255,255,255,0.78)', 0], ['rgba(232,228,255,0.52)', 1]]
        : [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0)', 1]]
    })
    .backdropBlur(this.actIndex === arg.idx ? 16 : 0)
    .border({
      width: this.actIndex === arg.idx ? 1 : 0,
      color: this.actIndex === arg.idx ? 'rgba(255,255,255,0.95)' : Color.Transparent
    })
    .shadow({
      radius: this.actIndex === arg.idx ? 8 : 0,
      color: this.actIndex === arg.idx ? 'rgba(70,80,140,0.14)' : 'rgba(0,0,0,0)',
      offsetY: 3
    })
    .onClick(() => { this.onSegTap(arg.idx) })
  }

  /** 分段互动条 */
  @Builder
  actionsBar() {
    Row() {
      this.actionSeg({ idx: 0, label: '喂数据', icon: 'fork_knife' })
      this.actionSeg({ idx: 1, label: '摸摸头', icon: 'hand_tap' })
      this.actionSeg({ idx: 2, label: '换装扮', icon: 'shirt' })
    }
    .width('100%').height(56)
    .padding(5)
    .borderRadius(16)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(18))
    .border(this.cardBorder())
  }

  /** 成长里程碑 XP 卡 */
  @Builder
  xpCard() {
    Column() {
      Row() {
        Text('成长里程碑').fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
        Text(this.xpHint()).fontSize(9).fontColor('#6B7889').margin({ left: 6 })
        Blank()
        Text(`${this.pet.xp} / 100`).fontSize(10).fontWeight(FontWeight.Bold).fontColor('#6351E8')
      }
      .width('100%')

      // 轨道 + 刻度（刻度圆心落在 0/25/50/75/100% 上）
      Column() {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%').height(7).borderRadius(4)
            .backgroundColor('rgba(99,81,232,0.12)')
          Row()
            .height(7).borderRadius(4)
            .width(`${this.pet.xp}%`)
            .linearGradient({ angle: 90, colors: [['#A79BFF', 0], ['#6351E8', 1]] })
          // 刻度：放在 5 等分段的边界上
          Row() {
            ForEach([0, 1, 2, 3, 4], (idx: number) => {
              Stack({ alignContent: idx === 4 ? Alignment.End : Alignment.Start }) {
                Row() {
                  if (this.pet.level > idx) {
                    Text('✓').fontSize(9).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                  } else {
                    Text(`${idx + 1}`).fontSize(9).fontWeight(FontWeight.Bold).fontColor('#8A96A8')
                  }
                }
                .width(17).height(17).borderRadius('50%')
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.pet.level > idx ? '#6351E8' : '#FFFFFF')
                .shadow({ radius: 5, color: 'rgba(60,60,120,0.35)', offsetY: 2 })
              }
              .layoutWeight(1).height(17)
            }, (idx: number) => `${idx}_${this.pet.level}`)
          }
          .width('100%').height(17)
        }
        .width('100%').height(17).margin({ top: 16 })
      }
      .width('100%')

      Row() {
        ForEach(STAGE_LABELS, (s: string) => {
          Text(s).fontSize(8).fontColor('#8A96A8')
        }, (s: string) => s)
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .borderRadius(20)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(20))
    .border(this.cardBorder())
    .shadow(this.cardShadow())
  }

  /** 任务卡（未完成圆圈 → 完成紫色对勾）；对象传参，状态变化能刷新 */
  @Builder
  questCheck(arg: QuestCheckArg) {
    Row() {
      if (arg.done) {
        Text('✓').fontSize(9).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      }
    }
    .width(17).height(17).borderRadius('50%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(arg.done ? '#6351E8' : Color.Transparent)
    .border({ width: arg.done ? 0 : 1.5, color: '#CCD5E5' })
  }

  /** 双列任务卡（第 5 张通栏） */
  @Builder
  questsCard() {
    Column() {
      Row() {
        Text('今日陪伴任务').fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
        Blank()
        Text(`${this.doneCount()} / 5 完成 · 共 ${this.questTotalEnergy()} 能量`)
          .fontSize(9).fontColor('#6B7889')
      }
      .width('100%').margin({ bottom: 10 })

      Row() {
        this.questCard(0)
        this.questCard(1)
      }
      .width('100%')

      Row() {
        this.questCard(2)
        this.questCard(3)
      }
      .width('100%').margin({ top: 8 })

      // 第 5 张通栏宽卡
      Row() {
        Row() {
          AppIcon({ name: QUESTS[4].icon, iconSize: 15, colors: ['#FFFFFF'] })
        }
        .width(27).height(27).borderRadius(9).justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 140, colors: [[QUESTS[4].c1, 0], [QUESTS[4].c2, 1]] })

        Column() {
          Text(QUESTS[4].name).fontSize(10.5).fontWeight(FontWeight.Bold)
            .fontColor(this.theme.textPrimary).maxLines(1)
          Row() {
            Text('奖励 ').fontSize(9).fontColor('#6B7889')
            Text(`+${QUESTS[4].energy}`).fontSize(9).fontWeight(FontWeight.Bold).fontColor('#E1701F')
            Text(' 能量').fontSize(9).fontColor('#6B7889')
          }.margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1).margin({ left: 10 })

        this.questCheck({ done: this.taskFlags[4] })
      }
      .width('100%').height(58).padding({ left: 11, right: 11 })
      .borderRadius(15)
      .backgroundColor(this.questInnerFill(this.taskFlags[4]))
      .margin({ top: 8 })
      .onClick(() => { this.openQuest(4) })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 10 })
    .borderRadius(22)
    .linearGradient({ angle: 160, colors: this.cardFill() })
    .backdropBlur(this.cardBlur(20))
    .border(this.cardBorder())
    .shadow(this.cardShadow())
  }

  /** 双列任务卡里的单个卡片 */
  @Builder
  questCard(idx: number) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          AppIcon({ name: QUESTS[idx].icon, iconSize: 15, colors: ['#FFFFFF'] })
        }
        .width(27).height(27).borderRadius(9).justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 140, colors: [[QUESTS[idx].c1, 0], [QUESTS[idx].c2, 1]] })
        Row() {
          this.questCheck({ done: this.taskFlags[idx] })
        }
        .width('100%').justifyContent(FlexAlign.End)
      }
      .width('100%')

      Text(QUESTS[idx].name).fontSize(10.5).fontWeight(FontWeight.Bold)
        .fontColor(this.taskFlags[idx] ? this.theme.textSecondary : this.theme.textPrimary)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 7 })

      Row() {
        Text('奖励 ').fontSize(9).fontColor('#6B7889')
        Text(`+${QUESTS[idx].energy}`).fontSize(9).fontWeight(FontWeight.Bold).fontColor('#E1701F')
        Text(' 能量').fontSize(9).fontColor('#6B7889')
      }.margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(86)
    .padding({ left: 10, right: 10, top: 10, bottom: 9 })
    .borderRadius(15)
    .backgroundColor(this.questInnerFill(this.taskFlags[idx]))
    .onClick(() => { this.openQuest(idx) })
  }

  /** 任务跳转（tab:N 切换主 Tab，其余为页面路由）；页面真正打开后由埋点记为完成。
   *  已完成的卡片仍可点击重复进入，只是不再重复发奖。 */
  openQuest(idx: number): void {
    try {
      const route: string = QUESTS[idx].route
      if (route.startsWith('tab:')) {
        AppState.getInstance().setCurrentTab(Number(route.substring(4)))
      } else {
        AppNav.getInstance().open(route)
      }
    } catch (e) {}
    this.syncTasks()
  }

  build() {
    Column() {
      // 标题栏（HTML .hdr 同款）
      Row() {
        Text('🤖').fontSize(18)
        Text(' 小管家').fontSize(19).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
        Text('  宠物养成').fontSize(10).fontColor(this.theme.textTertiary).margin({ left: 4, top: 3 })
        Blank()
        Text(`${this.levelText()} · ${this.pet.xp}/100 XP`)
          .fontSize(10).fontColor('#6351E8').fontWeight(FontWeight.Bold)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(10)
          .backgroundColor('rgba(99,81,232,0.10)')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Scroll() {
        Column() {
          // ========== 玻璃宠物场景 ==========
          Stack({ alignContent: Alignment.TopStart }) {
            // 暖色光晕（圆形软渐变，边缘完全淡出，不再有方形割裂感）
            Column()
              .width(236).height(236).borderRadius(118)
              .radialGradient({
                center: ['50%', '50%'],
                radius: 118,
                colors: [
                  ['rgba(255,178,110,0.30)', 0],
                  ['rgba(255,178,110,0.16)', 0.45],
                  ['rgba(255,178,110,0.0)', 1]
                ]
              })
              .position({ x: '50%', y: 0 })
              .translate({ x: '-50%' })
              .hitTestBehavior(HitTestMode.None)
            // 小管（浮动 / 跳跃 / 倾斜；画布 200×210 按 0.8 缩放为 160×168）
            Column() {
              Column() {
                this.petBody()
              }
              .width(200).height(210)
              .scale({ x: 0.8, y: 0.8 })
              .translate({ y: this.bobY + (this.jumping ? -46 : 0) })
              .rotate({ angle: this.tilting ? -12 : this.bobRot })
              .animation({ duration: 1100, curve: Curve.EaseInOut })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .position({ x: 0, y: 20 })
            .hitTestBehavior(HitTestMode.None)
            // 点击热区（宠物本体）
            Column()
              .width(170).height(180)
              .position({ x: '50%', y: 16 })
              .translate({ x: '-50%' })
              .onClick(() => { AppNav.getInstance().open('pages/apps/DiaryPage') })
            // 体征浮窗
            Column() {
              this.vitalsChip({ dot: '#4ADE9B', label: '饱食度', value: this.pet.full, right: false })
            }
            .position({ x: 14, y: 52 })
            // 右侧浮窗：整行右对齐 + 右边距，避免溢出裁切
            Row() {
              this.vitalsChip({ dot: '#FFB24D', label: '能量', value: this.pet.energy, right: true })
            }
            .width('100%').justifyContent(FlexAlign.End)
            .padding({ right: 14 })
            .position({ x: 0, y: 86 })
            // 心情浮窗（唯一一处心情展示）
            Text(this.moodChipText())
              .fontSize(10).fontColor('#6B5A4A')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(12)
              .backgroundColor(AppState.getInstance().isGlass() ? 'rgba(255,255,255,0.46)' : 'rgba(255,255,255,0.92)')
              .backdropBlur(AppState.getInstance().isGlass() ? 16 : 0)
              .border(this.cardBorder())
              .constraintSize({ maxWidth: 200 })
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .position({ x: 16, y: 186 })
            // 粒子层（参考图同款：cube 数字块从脚底两侧上喷 / heart 头顶喷爱心 / spark 星星）
            // 外层容器以宠物中心定位并做横向偏移，内层 Text 只做上升+淡出的 transition
            ForEach(this.particles, (p: Particle) => {
              Row() {
                if (p.kind === 'cube') {
                  Text(p.text)
                    .fontSize(p.size).fontWeight(FontWeight.Bold).fontColor('#8A4A16')
                    .padding({ left: 3.5, right: 3.5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor('rgba(255,183,94,0.97)')
                    .shadow({ radius: 5, color: 'rgba(240,140,40,0.55)', offsetY: 2 })
                    .transition(TransitionEffect.translate({ y: -p.rise })
                      .combine(TransitionEffect.opacity(0))
                      .animation({ duration: 950, curve: Curve.EaseOut, delay: p.delay }))
                } else if (p.kind === 'heart') {
                  Text('♥')
                    .fontSize(p.size).fontColor('#FF6E9C')
                    .shadow({ radius: 6, color: 'rgba(255,110,156,0.5)', offsetY: 2 })
                    .transition(TransitionEffect.translate({ y: -p.rise })
                      .combine(TransitionEffect.opacity(0))
                      .animation({ duration: 1000, curve: Curve.EaseOut, delay: p.delay }))
                } else {
                  Text('✨')
                    .fontSize(p.size)
                    .transition(TransitionEffect.translate({ y: -p.rise })
                      .combine(TransitionEffect.opacity(0))
                      .animation({ duration: 950, curve: Curve.EaseOut, delay: p.delay }))
                }
              }
              .position({ x: '50%', y: p.y })
              .markAnchor({ x: '50%' })
              .translate({ x: p.dx })
              .hitTestBehavior(HitTestMode.None)
            }, (p: Particle) => p.id.toString())
          }
          .width('100%').height(236)
          .borderRadius(26).clip(true).margin({ top: 4 })
          .linearGradient({ angle: 160, colors: this.cardFill() })
          .backdropBlur(this.cardBlur(22))
          .border(this.cardBorder())
          .shadow(this.cardShadow())

          // 网络流量曲线
          Column() {
            this.trafficCard()
          }
          .width('100%').margin({ top: 12 })

          // 分段互动
          Column() {
            this.actionsBar()
          }
          .width('100%').margin({ top: 12 })

          // 成长里程碑
          Column() {
            this.xpCard()
          }
          .width('100%').margin({ top: 12 })

          // 今日任务
          Column() {
            this.questsCard()
          }
          .width('100%').margin({ top: 12 })

          Blank().height(AppState.getInstance().getBottomNavInset())
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 20 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%').height('100%')
    .padding({ top: 34 })
    .linearGradient({
      angle: 135,
      colors: this.embedded
        ? [[Color.Transparent, 0], [Color.Transparent, 1]]
        : this.theme.pageGradient
    })
  }
}

/** 独立路由页（应用中心进入，也可作为组件挂到宽屏应用面板） */
@Component
export struct PetPage {
  /** 嵌入分栏时透明背景，与其它栏共用同一块底 */
  @Prop embedded: boolean = false
  @State theme: ThemePalette = AppState.getInstance().getTheme()

  build() {
    Column() {
      PetView({ theme: this.theme, embedded: this.embedded })
        .layoutWeight(1)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.embedded && AppState.getInstance().isGlass()
        ? [[Color.Transparent, 0], [Color.Transparent, 1]]
        : this.theme.pageGradient
    })
  }
}
