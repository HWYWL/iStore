/**
 * PetPage — 小管家宠物养成（路由器拟人，按 HTML 原型完整还原）
 * 动画：bob 浮动 / 云漂移 / 太阳旋转 / 星光闪烁 / 喂食跳跃+粒子 / 摸头倾斜+爱心 / 升级爆发
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SKINS, SkinDef } from '../../common/theme/ThemeColors'
import { PetStore, PetState } from '../../common/store/PetStore'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'

/** 皮肤 → 小管家配色（HTML 原型同款） */
interface PetSkinColor {
  body: string
  edge: string
  faceBg: string
}

/** 粒子 */
interface Particle {
  id: number
  emoji: string
  x: number
  y: number
}

/** 星光 */
interface Spark {
  id: number
  x: number
  y: number
  delay: number
}

@Component
export struct PetView {
  @Prop theme: ThemePalette = LIGHT_THEME
  @State pet: PetState = PetStore.getInstance().getState()
  @State moodText: string = '很开心'
  @State bobY: number = 0          // 常驻浮动
  @State cloudX1: number = 0       // 云漂移
  @State sunAngle: number = 0      // 太阳旋转
  @State sparksAlpha: number[] = [] // 星光闪烁
  @State jumping: boolean = false
  @State tilting: boolean = false
  @State particles: Particle[] = []
  @State taskFlags: boolean[] = [true, true, false, false, false]
  @State showDress: boolean = false
  private store: PetStore = PetStore.getInstance()
  private timerId: number = -1
  private bobTimerId: number = -1
  private pId: number = 0

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.store.init(hostCtx).then(() => {
        this.pet = this.store.getState()
        this.taskFlags = this.store.getDoneTasks()
        this.refreshMoodText()
      })
    }
    // 常驻动画：bob 浮动（定时器驱动 bobY 交替，translate 属性重新求值才会动）
    this.bobTimerId = setInterval(() => {
      this.bobY = this.bobY === 0 ? -9 : 0
    }, 1100)
    // 云漂移
    animateTo({
      duration: 9000, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
    }, () => { this.cloudX1 = 24 })
    // 太阳光晕（Alternate 往返旋转模拟脉动）
    animateTo({
      duration: 3000, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
    }, () => { this.sunAngle = 24 })
    // 星光闪烁
    const sparks: number[] = [0.9, 0.5, 0.7, 0.3, 0.8, 0.6, 0.4, 0.2]
    this.sparksAlpha = sparks
    for (let i = 0; i < sparks.length; i++) {
      const delay: number = 400 + i * 260
      animateTo({
        duration: 1400, delay: delay, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut
      }, () => {
        const next: number[] = this.sparksAlpha.slice()
        next[i] = next[i] > 0.5 ? 0.15 : 0.95
        this.sparksAlpha = next
      })
    }
    // 心情小话轮播
    this.timerId = setInterval(() => {
      const msgs: string[] = ['今天网速不错，小管很开心～', '设备都好好的，我盯着呢！', '想喝口水…不对，我是路由器']
      this.moodText = msgs[Math.floor(Math.random() * msgs.length)]
    }, 8000)
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    if (this.bobTimerId >= 0) {
      clearInterval(this.bobTimerId)
      this.bobTimerId = -1
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

  /** 喂数据：饱食+15 XP+5 跳跃+粒子 */
  onFeed(): void {
    this.pet = this.store.feed()
    this.jumping = true
    setTimeout(() => { this.jumping = false }, 650)
    this.spawnParticles(['🍚', '✨', '💛', '🍙', '⭐'], 8)
    this.moodText = '吃得好饱，嗝～ 谢谢你'
    promptAction.showToast({ message: '饱食度 +15', duration: 1200 })
  }

  /** 摸摸头：心情+10 倾斜+爱心 */
  onPat(): void {
    this.pet = this.store.pat()
    this.tilting = true
    setTimeout(() => { this.tilting = false }, 500)
    this.spawnParticles(['💗', '🩷', '✨', '❤️'], 7)
    this.refreshMoodText()
    promptAction.showToast({ message: '心情 +10 💗', duration: 1200 })
  }

  /** 换装扮：粒子 + 关闭 */
  selectSkin(id: string): void {
    this.pet = this.store.setSkin(id)
    this.spawnParticles(['✨', '🌟', '💫'], 8)
    this.moodText = '新衣服真好看！'
  }

  /** 关闭抽屉：恢复导航条 */
  closeDress(): void {
    this.showDress = false
    AppState.getInstance().showNav()
  }

  doneCount(): number {
    let n: number = 0
    for (let i = 0; i < this.taskFlags.length; i++) {
      if (this.taskFlags[i]) n++
    }
    return n
  }

  onTask(idx: number, energy: number): void {
    if (this.taskFlags[idx]) return
    const flags: boolean[] = this.taskFlags.slice()
    flags[idx] = true
    this.taskFlags = flags
    this.store.markTaskDone(idx)
    this.pet = this.store.completeTask(energy)
    this.spawnParticles(['⚡', '✨'], 4)
    this.moodText = '任务完成，小管有能量啦 ⚡'
  }

  /** 粒子生成（HTML 同款动画） */
  spawnParticles(emojis: string[], count: number): void {
    for (let i = 0; i < count; i++) {
      const p: Particle = {
        id: this.pId++,
        emoji: emojis[Math.floor(Math.random() * emojis.length)],
        x: 60 + Math.random() * 220,
        y: 120 + Math.random() * 60
      }
      this.particles = this.particles.concat([p])
    }
    // 1.4s 后清理
    setTimeout(() => {
      this.particles = []
    }, 1400)
  }

  levelText(): string {
    if (this.pet.level >= 10) return 'Lv.' + this.pet.level + ' 传说'
    if (this.pet.level >= 5) return 'Lv.' + this.pet.level + ' 成熟期'
    if (this.pet.level >= 2) return 'Lv.' + this.pet.level + ' 青春期'
    return 'Lv.1 幼年期'
  }

  // ========== 路由器拟人（HTML SVG 同款：圆润机身） ==========
  @Builder
  petBody() {
    Stack() {
      // 天线
      Line().startPoint([48, 46]).endPoint([38, 22]).stroke('#B4AFA4').strokeWidth(5).strokeLineCap(LineCapStyle.Round)
      Line().startPoint([102, 46]).endPoint([112, 22]).stroke('#B4AFA4').strokeWidth(5).strokeLineCap(LineCapStyle.Round)
      Circle({ width: 12, height: 12 }).fill(this.petColors().edge).position({ x: 31, y: 10 })
      Circle({ width: 12, height: 12 }).fill(this.petColors().edge).position({ x: 107, y: 10 })
      // 信号波纹（动画：opacity 脉动）
      Path().commands('M37 32 a6 6 0 0 1 0 -8')
        .stroke('#FFB37A').strokeWidth(2.5).fill('none').strokeLineCap(LineCapStyle.Round)
        .opacity(0.9)
        .animation({ duration: 1000, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut })
      Path().commands('M113 32 a6 6 0 0 0 0 -8')
        .stroke('#FFB37A').strokeWidth(2.5).fill('none').strokeLineCap(LineCapStyle.Round)
        .opacity(0.9)
        .animation({ duration: 1000, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut })
      // 机身（圆润大圆角 rx=16，与 HTML 一致）
      Rect({ width: 90, height: 68, radius: 18 }).fill(this.petColors().body).stroke(this.petColors().edge).strokeWidth(3).position({ x: 30, y: 44 })
      // 机身光带
      Rect({ width: 90, height: 8 }).fill('#FFF6EC').opacity(0.5).position({ x: 30, y: 60 })
      // 指示灯（绿灯呼吸动画）
      Circle({ width: 10, height: 10 }).fill('#00C853').position({ x: 47, y: 92 })
        .animation({ duration: 1400, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut })
      Circle({ width: 10, height: 10 }).fill('#FFD66B').position({ x: 63, y: 92 })
      Circle({ width: 10, height: 10 }).fill('#FF8A3D').position({ x: 79, y: 92 })
      // 屏幕脸
      Rect({ width: 62, height: 40, radius: 10 }).fill(this.petColors().faceBg).stroke(this.petColors().edge).strokeWidth(2).position({ x: 44, y: 106 })
      // 眼睛（带高光）
      Circle({ width: 12, height: 12 }).fill('#2B2A26').position({ x: 57, y: 116 })
      Circle({ width: 12, height: 12 }).fill('#2B2A26').position({ x: 81, y: 116 })
      Circle({ width: 4.4, height: 4.4 }).fill('#FFFFFF').position({ x: 61.5, y: 114 })
      Circle({ width: 4.4, height: 4.4 }).fill('#FFFFFF').position({ x: 85.5, y: 114 })
      // 嘴（微笑）
      Path().commands('M68 136 Q75 143 82 136').stroke('#2B2A26').strokeWidth(2.6).fill('none').strokeLineCap(LineCapStyle.Round)
      // 腮红
      Circle({ width: 9, height: 9 }).fill('#FFD0C4').opacity(0.85).position({ x: 50, y: 124 })
      Circle({ width: 9, height: 9 }).fill('#FFD0C4').opacity(0.85).position({ x: 91, y: 124 })
      // 小脚
      Ellipse().width(28).height(12).fill(this.petColors().body).position({ x: 46, y: 140 })
      Ellipse().width(28).height(12).fill(this.petColors().body).position({ x: 76, y: 140 })
    }
    .width(150)
    .height(164)
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('🤖').fontSize(20)
          Text(' 小管家').fontSize(20).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('  宠物养成').fontSize(11).fontColor(this.theme.textTertiary).margin({ left: 4, top: 3 })
        }
        Blank()
        Text(this.levelText())
          .fontSize(11).fontColor('#8A5A00').fontWeight(FontWeight.Bold)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(10).backgroundColor('#FAEEDA')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Scroll() {
        Column() {
          // ========== 主场景（HTML 同款：天空/云/太阳/星光/草地） ==========
          Stack() {
            // 天空渐变
            Column().width('100%').height('100%')
              .linearGradient({ angle: 180, colors: [['#FDF6EC', 0], ['#FBE9D8', 0.55], ['#E8DCC4', 1]] })
            // 星光
            ForEach(this.sparksAlpha, (alpha: number, idx: number) => {
              Circle({ width: 6, height: 6 }).fill('#FFD66B')
                .opacity(alpha)
                .position({ x: 24 + idx * 40, y: 18 + (idx % 2) * 22 })
            }, (alpha: number, idx: number) => `${idx}_${alpha}`)
            // 云 1（漂移）
            Row().width(70).height(22).borderRadius(50).backgroundColor('rgba(255,255,255,0.7)')
              .position({ x: 30 + this.cloudX1, y: 30 })
              .animation({ duration: 100, curve: Curve.Linear })
            // 云 2
            Row().width(50).height(16).borderRadius(50).backgroundColor('rgba(255,255,255,0.6)')
              .position({ x: 280 - this.cloudX1 * 0.7, y: 60 })
              .animation({ duration: 100, curve: Curve.Linear })
            // 太阳（旋转光晕）
            Stack() {
              Circle({ width: 50, height: 50 }).fill('#FFD66B').opacity(0.25)
              Circle({ width: 38, height: 38 }).fill('#FFD66B')
              Circle({ width: 22, height: 22 }).fill('#FFE9A8')
            }
            .position({ x: 300, y: 14 })
            .rotate({ angle: this.sunAngle })
            .animation({ duration: 100, curve: Curve.Linear })
            // 草地
            Column().width('100%').height(74)
              .linearGradient({ angle: 180, colors: [['#C9E4C0', 0], ['#B5D8AA', 1]] })
              .position({ x: 0, y: 226 })
            // 小管固定阴影（不随 bob 动画移动；居中在宠物脚下）
            Ellipse().width(120).height(18).fill('rgba(90,80,60,0.2)')
              .position({ x: 115, y: 242 })
            // 小管（居中 + 底部 70；bob/jump/tilt 动画在组件层；点击跳网络日记）
            Column() {
              Column() {
                this.petBody()
              }
              .width(150).height(164)
              .translate({ y: this.bobY + (this.jumping ? -46 : 0) })
              .rotate({ angle: this.tilting ? -12 : 0 })
              .animation({ duration: 1100, curve: Curve.EaseInOut })
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/apps/DiaryPage' })
              })
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 74 })
            // 心情小字条（仿首页副标题：无背景小字，嵌在草坪上）
            Text(this.moodText)
              .fontSize(11)
              .fontColor('rgba(43,42,38,0.55)')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 200 })
              .position({ x: 95, y: 228 })
            // 粒子层
            ForEach(this.particles, (p: Particle) => {
              Text(p.emoji)
                .fontSize(22)
                .position({ x: p.x, y: p.y })
                .transition(TransitionEffect.translate({ y: -60 }).combine(TransitionEffect.opacity(0)).animation({ duration: 1100, curve: Curve.EaseOut }))
            }, (p: Particle) => p.id.toString())
          }
          .width('100%').height(300)
          .borderRadius(22).clip(true).margin({ top: 8 })

          // 状态三连条
          Row() {
            Column() {
              Row() {
                Circle({ width: 8, height: 8 }).fill('#2FBFA8')
                Text('饱食度').fontSize(10).fontColor(this.theme.textSecondary).margin({ left: 4 })
              }
              Progress({ value: this.pet.full, total: 100, type: ProgressType.Linear })
                .width('100%').height(7).margin({ top: 6 })
                .color('#2FBFA8').backgroundColor('#F0EBE0')
              Text(`${this.pet.full}%`).fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).margin({ top: 4 })
            }
            .layoutWeight(1).padding(10).borderRadius(14)
            .backgroundColor(this.theme.bgCard)
            .shadow({ radius: 12, color: 'rgba(180,160,120,0.12)', offsetY: 4 })
            Column() {
              Row() {
                Circle({ width: 8, height: 8 }).fill('#F5A623')
                Text('能量').fontSize(10).fontColor(this.theme.textSecondary).margin({ left: 4 })
              }
              Progress({ value: this.pet.energy, total: 100, type: ProgressType.Linear })
                .width('100%').height(7).margin({ top: 6 })
                .color('#F5A623').backgroundColor('#F0EBE0')
              Text(`${this.pet.energy}%`).fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).margin({ top: 4 })
            }
            .layoutWeight(1).padding(10).borderRadius(14).margin({ left: 10 })
            .backgroundColor(this.theme.bgCard)
            .shadow({ radius: 12, color: 'rgba(180,160,120,0.12)', offsetY: 4 })
            Column() {
              Row() {
                Circle({ width: 8, height: 8 }).fill('#FF6E9C')
                Text('心情').fontSize(10).fontColor(this.theme.textSecondary).margin({ left: 4 })
              }
              Progress({ value: this.pet.mood, total: 100, type: ProgressType.Linear })
                .width('100%').height(7).margin({ top: 6 })
                .color('#FF6E9C').backgroundColor('#F0EBE0')
              Text(this.moodText.length > 5 ? this.moodText.substring(0, 5) : this.moodText)
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).margin({ top: 4 })
            }
            .layoutWeight(1).padding(10).borderRadius(14).margin({ left: 10 })
            .backgroundColor(this.theme.bgCard)
            .shadow({ radius: 12, color: 'rgba(180,160,120,0.12)', offsetY: 4 })
          }
          .width('100%').margin({ top: 12 })

          // 互动按钮
          Row() {
            Column() {
              Text('🍚').fontSize(20)
              Text('喂数据').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#1B7A6A').margin({ top: 4 })
            }
            .layoutWeight(1).padding({ top: 13, bottom: 13 }).borderRadius(16)
            .backgroundColor('#E4F3EE')
            .onClick(() => { this.onFeed() })
            Column() {
              Text('🖐').fontSize(20)
              Text('摸摸头').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#B0567A').margin({ top: 4 })
            }
            .layoutWeight(1).padding({ top: 13, bottom: 13 }).borderRadius(16).margin({ left: 10 })
            .backgroundColor('#FBEAF0')
            .onClick(() => { this.onPat() })
            Column() {
              Text('🎽').fontSize(20)
              Text('换装扮').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#8A5A00').margin({ top: 4 })
            }
            .layoutWeight(1).padding({ top: 13, bottom: 13 }).borderRadius(16).margin({ left: 10 })
            .backgroundColor('#FAEEDA')
            .onClick(() => {
              this.showDress = true
              AppState.getInstance().hideNav()  // 隐藏底部导航条，让抽屉覆盖
            })
          }
          .width('100%').margin({ top: 12 })

          // 成长条
          Row() {
            Text('成长').fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.theme.textSecondary)
            Progress({ value: this.pet.xp, total: 100, type: ProgressType.Linear })
              .layoutWeight(1).height(8).margin({ left: 10, right: 10 })
              .color('#FF8A3D').backgroundColor('#F0EBE0')
            Text(`${this.pet.xp} / 100 XP`).fontSize(11).fontColor(this.theme.textSecondary)
          }
          .width('100%').padding(12).borderRadius(14).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
          .shadow({ radius: 12, color: 'rgba(180,160,120,0.12)', offsetY: 4 })

          // 每日任务
          Column() {
            Row() {
              Text('今日陪伴任务').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
              Blank()
              Text(`${this.doneCount()} / 5 完成`).fontSize(11).fontColor('#2FBFA8').fontWeight(FontWeight.Bold)
            }
            .width('100%').margin({ bottom: 6 })
            this.taskRow(0, '🩺', '完成一次安全体检', '+20 能量', 20, 'pages/security/SecurityHubPage')
            this.taskRow(1, '💬', '和小管聊一次天', '+15 能量', 15, 'pages/apps/NetworkHelperPage')
            this.taskRow(2, '📶', '查看今日流量', '+10 能量', 10, 'pages/apps/TrafficReportPage')
            this.taskRow(3, '🔋', '查看设备电量排行', '+10 能量', 10, 'pages/apps/DeviceActivityPage')
            this.taskRow(4, '🛡', '打开安全中心', '+15 能量', 15, 'pages/security/SecurityHubPage')
          }
          .width('100%').padding(16).borderRadius(22).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)
          .shadow({ radius: 12, color: 'rgba(180,160,120,0.12)', offsetY: 4 })

          Blank().height(AppState.getInstance().getBottomNavInset())
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 20 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)

      // 换装抽屉（从下往上弹出，打开时隐藏导航条）
      if (this.showDress) {
        Stack() {
          Column().width('100%').height('100%')
            .backgroundColor('rgba(43,42,38,0.25)')
            .onClick(() => { this.closeDress() })
          Column() {
            Row().width(40).height(4).borderRadius(2).backgroundColor('#E5DFD2').margin({ top: 8, bottom: 14 })
            Row() {
              Text('小管家装扮').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
              Blank()
              Text('完成').fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
                .onClick(() => { this.closeDress() })
            }
            .width('100%').margin({ bottom: 14 })
            Grid() {
              ForEach(SKINS, (s: SkinDef) => {
                GridItem() {
                  Column() {
                    Row().width(52).height(52).borderRadius(14).backgroundColor(s.preview[0])
                      .justifyContent(FlexAlign.Center)
                    Text(s.name)
                      .fontSize(11)
                      .fontColor(this.pet.skinId === s.id ? this.theme.primary : this.theme.textSecondary)
                      .fontWeight(FontWeight.Bold).margin({ top: 6 })
                    if (this.pet.skinId === s.id) {
                      Text('✓ 使用中').fontSize(9).fontColor('#2FBFA8').margin({ top: 2 })
                    }
                  }
                  .padding(8).borderRadius(14)
                  .border({ width: this.pet.skinId === s.id ? 2 : 0, color: this.theme.primary })
                  .onClick(() => { this.selectSkin(s.id) })
                }
              }, (s: SkinDef) => s.id)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsTemplate('1fr 1fr')
            .columnsGap(8).rowsGap(8)
            .height(196).width('100%')
          }
          .width('100%').padding(18)
          .borderRadius({ topLeft: 26, topRight: 26 })
          .backgroundColor('#FFFFFF')
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%' })
          .transition(TransitionEffect.translate({ y: 60 }).animation({ duration: 250, curve: Curve.EaseOut }))
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(99)
      }
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  /** 任务行 */
  @Builder
  taskRow(idx: number, ico: string, name: string, reward: string, energy: number, route: string) {
    Row() {
      Text(ico).fontSize(16).width(34).height(34).borderRadius(11)
        .backgroundColor('#F0EBE0').textAlign(TextAlign.Center)
      Text(name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        .layoutWeight(1).margin({ left: 10 })
      Text(reward).fontSize(11).fontColor('#E6A800').fontWeight(FontWeight.Bold)
      Text(this.taskFlags[idx] ? '✓ 完成' : '去做')
        .fontSize(11).fontWeight(FontWeight.Bold)
        .fontColor(this.taskFlags[idx] ? '#B4AFA4' : '#FFFFFF')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(10)
        .backgroundColor(this.taskFlags[idx] ? '#F0EBE0' : this.theme.primary)
        .margin({ left: 8 })
        .onClick(() => {
          if (this.taskFlags[idx]) return
          this.onTask(idx, energy)
          // 跳转对应页面（tab:N 切换主 Tab，其余为页面路由）
          try {
            if (route.startsWith('tab:')) {
              AppState.getInstance().setCurrentTab(Number(route.substring(4)))
            } else {
              this.getUIContext().getRouter().pushUrl({ url: route })
            }
          } catch (e) {}
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }
}

/** 独立路由页（应用中心进入） */
@Entry
@Component
struct PetPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State topSafeArea: number = 44

  aboutToAppear(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        import('@kit.ArkUI').then((m: Object) => {})
      }
    } catch (e) {}
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('🤖').fontSize(20)
          Text(' 小管家').fontSize(20).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
        }
        .onClick(() => { this.getUIContext().getRouter().back() })
        Blank()
        Text('返回').fontSize(12).fontColor(this.theme.primary)
          .onClick(() => { this.getUIContext().getRouter().back() })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      PetView({ theme: this.theme })
        .layoutWeight(1)
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }
}
