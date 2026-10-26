/**
 * 设备外号生成器
 * 根据设备厂商 / 类型 / 信号 / 速率生成趣味「社交外号」，图标统一为系统符号 + 同色系底座
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

interface AliasItem {
  alias: string
  icon: Resource
  /** 用自绘的鸿蒙标志替代系统符号 */
  harmony?: boolean
}

interface AliasDef {
  alias: string
  icon: Resource
  color: string
  harmony?: boolean
}

interface AliasRow {
  name: string
  alias: string
  icon: Resource
  color: string
  isOnline: boolean
  harmony: boolean
}

/** 兜底外号池（每个外号一个专属图标，刷新会重新洗牌） */
const GENERIC_POOL: AliasDef[] = [
  { alias: '神秘访客', icon: $r('sys.symbol.person_shield'), color: '#64748B' },
  { alias: '网速刺客', icon: $r('sys.symbol.bolt'), color: '#F97316' },
  { alias: '隐形设备', icon: $r('sys.symbol.eye_slash'), color: '#8B5CF6' },
  { alias: '蹭网嫌疑犯', icon: $r('sys.symbol.link'), color: '#EC4899' },
  { alias: '深夜下载党', icon: $r('sys.symbol.moon'), color: '#6366F1' },
  { alias: '老实巴交设备', icon: $r('sys.symbol.checkmark_circle'), color: '#10B981' },
  { alias: '局域网宅', icon: $r('sys.symbol.house'), color: '#0EA5E9' },
  { alias: '待机之王', icon: $r('sys.symbol.battery'), color: '#94A3B8' },
  { alias: '摸鱼达人', icon: $r('sys.symbol.fish'), color: '#06B6D4' },
  { alias: '早起打卡机', icon: $r('sys.symbol.sun_max'), color: '#F59E0B' },
  { alias: '夜间冲浪者', icon: $r('sys.symbol.waveform'), color: '#14B8A6' },
  { alias: '沉默的网线', icon: $r('sys.symbol.arrow_left_arrow_right'), color: '#3B82F6' }
]

/** Apple 系 */
const APPLE_POOL: AliasItem[] = [
  { alias: '果粉大户', icon: $r('sys.symbol.crown') },
  { alias: '全家桶信徒', icon: $r('sys.symbol.rectangle_stack') },
  { alias: '灵动岛居民', icon: $r('sys.symbol.phone') },
  { alias: 'iCloud 搬运工', icon: $r('sys.symbol.download') }
]

/** 小米系 */
const XIAOMI_POOL: AliasItem[] = [
  { alias: '小米钉子户', icon: $r('sys.symbol.pin') },
  { alias: '为发烧而生', icon: $r('sys.symbol.bolt') },
  { alias: '性价比战士', icon: $r('sys.symbol.yuansign_moneybag') },
  { alias: 'MIUI 老兵', icon: $r('sys.symbol.medal') }
]

/** 华为 / 荣耀 */
const HUAWEI_POOL: AliasItem[] = [
  { alias: '国产之光', icon: $r('sys.symbol.flag') },
  { alias: '鸿蒙先锋', icon: $r('sys.symbol.arrow_up_right'), harmony: true },
  { alias: '信号堡垒', icon: $r('sys.symbol.wifi') },
  { alias: '多屏协同官', icon: $r('sys.symbol.square_grid_2x2') }
]

/** NAS / 存储 */
const NAS_POOL: AliasItem[] = [
  { alias: '数据仓库管理员', icon: $r('sys.symbol.folder') },
  { alias: '备份狂魔', icon: $r('sys.symbol.archivebox') },
  { alias: '硬盘守夜人', icon: $r('sys.symbol.externaldrive') },
  { alias: '全家照片保管员', icon: $r('sys.symbol.ohos_photo') }
]

/** 电视 / 盒子 */
const TV_POOL: AliasItem[] = [
  { alias: '客厅剧粉', icon: $r('sys.symbol.movie') },
  { alias: '投屏主任', icon: $r('sys.symbol.share') },
  { alias: '沙发土豆', icon: $r('sys.symbol.face_smiling') },
  { alias: '追剧永动机', icon: $r('sys.symbol.play_circle') }
]

/** 打印机 */
const PRINTER_POOL: AliasItem[] = [
  { alias: '打印小工', icon: $r('sys.symbol.printer') },
  { alias: '卡纸克星', icon: $r('sys.symbol.doc_text') },
  { alias: '作业救星', icon: $r('sys.symbol.book') }
]

/** 摄像头 */
const CAMERA_POOL: AliasItem[] = [
  { alias: '监控探头', icon: $r('sys.symbol.camera') },
  { alias: '门口哨兵', icon: $r('sys.symbol.security_shield') },
  { alias: '夜视担当', icon: $r('sys.symbol.moon') }
]

/** 音箱 / 语音助手 */
const SPEAKER_POOL: AliasItem[] = [
  { alias: '语音小助手', icon: $r('sys.symbol.speaker') },
  { alias: '喊麦担当', icon: $r('sys.symbol.message') },
  { alias: '闹钟管理员', icon: $r('sys.symbol.clock') }
]

/** 手表 / 手环 */
const WATCH_POOL: AliasItem[] = [
  { alias: '腕上健康管家', icon: $r('sys.symbol.heart') },
  { alias: '步数卷王', icon: $r('sys.symbol.medal') }
]

/** 电脑 */
const PC_POOL: AliasItem[] = [
  { alias: '远程办公侠', icon: $r('sys.symbol.display') },
  { alias: '键盘侠', icon: $r('sys.symbol.code_square') },
  { alias: '生产力工具人', icon: $r('sys.symbol.gearshape') }
]

/** 中继 / AP */
const AP_POOL: AliasItem[] = [
  { alias: '信号中继站', icon: $r('sys.symbol.wifi_router') },
  { alias: '穿墙小能手', icon: $r('sys.symbol.wifi') }
]

/** 速率大户 */
const FAST_POOL: AliasItem[] = [
  { alias: '大水管', icon: $r('sys.symbol.arrow_down') },
  { alias: '带宽吞噬者', icon: $r('sys.symbol.arrow_up_and_down_square_portrait') },
  { alias: '下载永动机', icon: $r('sys.symbol.arrow_clockwise') }
]

/** 弱信号 */
const WEAK_POOL: AliasItem[] = [
  { alias: '信号难民', icon: $r('sys.symbol.wifi') },
  { alias: '墙角蹲守者', icon: $r('sys.symbol.circle_grid_2x2') },
  { alias: '隔墙听雨', icon: $r('sys.symbol.waveform') }
]

/** 贴脸蹭网 */
const NEAR_POOL: AliasItem[] = [
  { alias: '贴脸蹭网选手', icon: $r('sys.symbol.hand_tap') },
  { alias: '带宽独占者', icon: $r('sys.symbol.crown') },
  { alias: '路由器邻居', icon: $r('sys.symbol.house') }
]

/** 鸿蒙标志（自绘）：与系统符号一致的单色描边风格 */
@Component
struct HarmonyMark {
  @Prop markColor: string = '#EF4444'
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  build() {
    Canvas(this.ctx)
      .width(21)
      .height(21)
      .onReady(() => {
        const c: CanvasRenderingContext2D = this.ctx
        c.clearRect(0, 0, 21, 21)
        c.strokeStyle = this.markColor
        c.lineWidth = 1.8
        c.lineCap = 'round'
        // 左环（开口朝右）与右环（开口朝左）两端交叉，构成鸿蒙标志的"∞"意象
        const gap: number = Math.PI * 0.222
        c.beginPath()
        c.arc(6.4, 10.5, 5.9, gap, Math.PI * 2 - gap)
        c.stroke()
        c.beginPath()
        c.arc(14.6, 10.5, 5.9, Math.PI + gap, Math.PI * 3 - gap)
        c.stroke()
      })
  }
}

@Entry
@Component
export struct DeviceAliasPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State rows: AliasRow[] = []
  @State loading: boolean = false
  @State seed: number = 0
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      const devs: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      const list: AliasRow[] = []
      for (let i = 0; i < devs.length; i++) {
        const d: ConnectedDevice = devs[i]
        const def: AliasDef = this.genAlias(d, i)
        list.push({
          name: d.hostname || d.vendor || d.ip,
          alias: def.alias,
          icon: def.icon,
          color: def.color,
          isOnline: d.isOnline,
          harmony: def.harmony === true
        })
      }
      this.rows = list
    } catch (e) {
      hilog.error(0x0001, 'DeviceAlias', `load err: ${String(e)}`)
    }
    this.loading = false
  }

  /** 重新洗牌后重新起名 */
  reroll(): void {
    this.seed = this.seed + 1
    const list: AliasRow[] = []
    for (let i = 0; i < this.rows.length; i++) {
      const row: AliasRow = this.rows[i]
      const def: AliasDef = this.pickGeneric(i + this.seed * 3)
      list.push({
        name: row.name, alias: def.alias, icon: def.icon, color: def.color,
        isOnline: row.isOnline, harmony: def.harmony === true
      })
    }
    this.rows = list
  }

  /** 从兜底池按序号取（洗牌用） */
  private pickGeneric(n: number): AliasDef {
    return GENERIC_POOL[Math.abs(n) % GENERIC_POOL.length]
  }

  /** 按关键词 + 信号 + 速率生成外号 */
  private genAlias(d: ConnectedDevice, idx: number): AliasDef {
    const vendor: string = (d.vendor || '').toLowerCase()
    const host: string = (d.hostname || '').toLowerCase()
    const sig: number = d.signalStrength
    const rx: number = d.rxRate

    // Apple
    if (vendor.includes('apple') || host.includes('iphone') || host.includes('ipad') || host.includes('mac')) {
      return this.pick(APPLE_POOL, '#3B82F6', idx)
    }
    // 小米
    if (vendor.includes('xiaomi') || host.includes('mi ') || host.includes('redmi') || host.includes('poco')) {
      return this.pick(XIAOMI_POOL, '#F97316', idx)
    }
    // 华为 / 荣耀
    if (vendor.includes('huawei') || host.includes('huawei') || host.includes('honor')) {
      return this.pick(HUAWEI_POOL, '#EF4444', idx)
    }
    // NAS / 存储
    if (host.includes('nas') || host.includes('synology') || host.includes('qnap') || host.includes('omv')) {
      return this.pick(NAS_POOL, '#6366F1', idx)
    }
    // 电视 / 盒子
    if (host.includes('tv') || host.includes('box') || host.includes('miot') || host.includes('dangbei')) {
      return this.pick(TV_POOL, '#F59E0B', idx)
    }
    // 打印机
    if (host.includes('printer') || host.includes('print') || host.includes('hp-')) {
      return this.pick(PRINTER_POOL, '#8B5CF6', idx)
    }
    // 摄像头
    if (host.includes('camera') || host.includes('ipc') || host.includes('doorbell') || host.includes('cam')) {
      return this.pick(CAMERA_POOL, '#EC4899', idx)
    }
    // 音箱 / 语音助手
    if (host.includes('xiaodu') || host.includes('tianmao') || host.includes('genie') ||
      host.includes('speaker') || host.includes('echo')) {
      return this.pick(SPEAKER_POOL, '#14B8A6', idx)
    }
    // 手表 / 手环
    if (host.includes('watch') || host.includes('band') || host.includes('bracelet')) {
      return this.pick(WATCH_POOL, '#06B6D4', idx)
    }
    // 电脑
    if (host.includes('laptop') || host.includes('macbook') || host.includes('pc') || host.includes('desktop')) {
      return this.pick(PC_POOL, '#0EA5E9', idx)
    }
    // 中继 / AP
    if (host.includes('repeater') || host.includes('ap-') || host.includes('mesh')) {
      return this.pick(AP_POOL, '#10B981', idx)
    }
    // 速率大户
    if (rx >= 500000) {
      return this.pick(FAST_POOL, '#2563EB', idx)
    }
    // 弱信号
    if (sig < -75 && sig !== 0) {
      return this.pick(WEAK_POOL, '#94A3B8', idx)
    }
    // 贴脸蹭网
    if (sig > -45) {
      return this.pick(NEAR_POOL, '#10B981', idx)
    }
    return this.pickGeneric(idx + this.seed * 3)
  }

  /** 从外号池挑一个（每个外号自带图标，按序号 + 洗牌种子轮换） */
  private pick(pool: AliasItem[], color: string, idx: number): AliasDef {
    const it: AliasItem = pool[Math.abs(idx + this.seed) % pool.length]
    return { alias: it.alias, icon: it.icon, color: color, harmony: it.harmony === true }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('设备外号')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
        Text(`${this.rows.length} 台`)
          .fontSize(11).fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          ForEach(this.rows, (row: AliasRow) => {
            Row() {
              // 彩色图标底座
              Row() {
                if (row.harmony) {
                  HarmonyMark({ markColor: row.color })
                } else {
                  SymbolGlyph(row.icon)
                    .fontSize(21)
                    .fontColor([row.color])
                }
              }
              .width(44)
              .height(44)
              .borderRadius(14)
              .backgroundColor('#1F' + row.color.substring(1))
              .justifyContent(FlexAlign.Center)
              .margin({ right: 12 })

              Column() {
                Text(row.alias)
                  .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(row.name)
                  .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 4 })
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)

              Row() {
                Circle({ width: 5, height: 5 })
                  .fill(row.isOnline ? '#10B981' : '#94A3B8')
                Text(row.isOnline ? ' 在线' : ' 离线')
                  .fontSize(9).fontColor(row.isOnline ? '#10B981' : '#94A3B8')
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor(row.isOnline ? 'rgba(16,185,129,0.10)' : 'rgba(148,163,184,0.12)')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .borderRadius(18)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }, (row: AliasRow): string => row.name)

          if (this.rows.length === 0 && !this.loading) {
            Column() {
              SymbolGlyph($r('sys.symbol.eye_slash'))
                .fontSize(32).fontColor(['#94A3B8'])
              Text('没有在线设备，外号无处安放')
                .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 10 })
            }
            .width('100%').padding({ top: 40, bottom: 40 })
            .alignItems(HorizontalAlign.Center)
          }

          // 重新洗牌
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(15).fontColor(['#FFFFFF'])
            Text(' 换一批外号')
              .fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
          }
          .width('100%').height(46).borderRadius(23)
          .linearGradient({ angle: 135, colors: [['#FB923C', 0], ['#EA580C', 1]] })
          .justifyContent(FlexAlign.Center)
          .shadow({ radius: 10, color: 'rgba(234,88,12,0.28)', offsetY: 4 })
          .margin({ top: 18 })
          .onClick(() => {
            if (this.rows.length > 0) {
              this.reroll()
            } else {
              this.load()
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
