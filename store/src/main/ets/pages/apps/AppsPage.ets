import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getAppVersionText } from '../../common/utils/AppVersion'
import { ApiService } from '../../api/ApiService'
import { SystemInfo } from '../../models/Models'
import { AppNav } from '../../common/utils/AppNav'


interface ToolEntry {
  icon: Resource      // 系统符号图标（sys.symbol.*），全局统一线稿风格
  name: string
  desc: string
  route: string
}

/** 分类分组 */
interface ToolGroup {
  title: string
  items: ToolEntry[]
}

/** 图标底色渐变 */
interface IconGradient {
  angle: number
  colors: Array<[ResourceColor, number]>
}

@Entry
@Component
struct AppsPageRoute {
  build() {
    Column() {
      AppsPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct AppsPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State itemSlides: number[] = []
  @State deviceName: string = '未连接设备'
  @State deviceHost: string = ''
  @State deviceConnected: boolean = false
  @State versionText: string = getAppVersionText()
  @State savedCount: number = 0
  @State upText: string = '--'       // 运行时长（保持卡片样式不变，仅新增数据）
  private api: ApiService = new ApiService()
  // 皮肤切换监听：应用中心是嵌在主页面里的常驻 Panel，不订阅的话换肤后背景/卡片会停留在旧配色
  private themeListener: (() => void) | null = null

  private groups: ToolGroup[] = [
    {
      title: '我的',
      items: [
        { icon: $r('sys.symbol.heart'), name: '小管家', desc: '养成式网络管家 · 每日任务', route: 'pages/pet/PetPage' },
        { icon: $r('sys.symbol.bag'), name: 'iStore 商店', desc: '浏览与安装路由器插件', route: 'pages/apps/StorePage' },
        { icon: $r('sys.symbol.square_stack_3d'), name: 'Docker', desc: '容器、镜像与网络管理', route: 'pages/apps/DockerPage' },
      ]
    },
    {
      title: '网络',
      items: [
        { icon: $r('sys.symbol.security_shield'), name: '安全中心', desc: '安全评分 / 陌生设备 / 危险端口', route: 'pages/security/SecurityHubPage' },
        { icon: $r('sys.symbol.wifi'), name: 'WiFi 管理', desc: '无线网络状态与配置管理', route: 'pages/apps/WifiPage' },
        { icon: $r('sys.symbol.globe_badge_message'), name: '网络管理', desc: '接口状态与网络信息', route: 'pages/apps/NetworkPage' },
        { icon: $r('sys.symbol.arrow_up_right'), name: '流量排行',  desc: '按速率排名的客户端活跃度', route: 'pages/apps/TrafficRankPage' },
        { icon: $r('sys.symbol.link'), name: '连接排行',  desc: '发现 NAT 连接数最多的设备', route: 'pages/apps/ConntrackRankPage' },
        { icon: $r('sys.symbol.arrow_up_and_down_square_portrait'), name: '网口流量',  desc: '各接口实时速率与累计统计', route: 'pages/apps/PortTrafficPage' },
        { icon: $r('sys.symbol.square_grid_3x1_below_line_grid_1x2'), name: '物理网口',  desc: '查看物理端口连接状态与速率', route: 'pages/apps/EthPortPage' },
        { icon: $r('sys.symbol.list_square_bill'), name: '流量统计',  desc: '近 7/30 天每日流量趋势', route: 'pages/apps/TrafficReportPage' },
        { icon: $r('sys.symbol.staroflife'), name: '智能体检',  desc: '一键检测网络连通与延迟', route: 'pages/apps/NetworkCheckPage' },
        { icon: $r('sys.symbol.circle_grid_2x2'), name: '网络拓扑',  desc: '可视化设备连接关系图', route: 'pages/apps/TopologyPage' },
      ]
    },
    {
      title: '多媒体',
      items: [
        { icon: $r('sys.symbol.ohos_photo'), name: '相册', desc: 'Immich 照片与视频管理', route: 'pages/apps/AlbumPage' },
        { icon: $r('sys.symbol.movie'), name: 'Jellyfin', desc: '电影、剧集与音乐媒体中心', route: 'pages/apps/JellyfinPage' },
      ]
    },
    {
      title: '趣味',
      items: [
        { icon: $r('sys.symbol.lightbulb'), name: '智能管家', desc: '预知·侦探·值班·一句话·周报', route: 'pages/apps/SmartHubPage' },
        { icon: $r('sys.symbol.flag'), name: '运行里程碑', desc: '连续运行天数与纪念日', route: 'pages/apps/MileStonePage' },
        { icon: $r('sys.symbol.medal'), name: '网络成就',  desc: '收集你的网络徽章', route: 'pages/apps/AchievementPage' },
        { icon: $r('sys.symbol.clock'), name: '设备作息',  desc: '设备 24h 活跃热力图', route: 'pages/apps/DeviceActivityPage' },
        { icon: $r('sys.symbol.book'), name: '网络日记',  desc: '每日网络事件时间线', route: 'pages/apps/DiaryPage' },
        { icon: $r('sys.symbol.doc_text'), name: 'AI 周报',  desc: '7 天流量汇总与点评', route: 'pages/apps/NetworkReportPage' },
        { icon: $r('sys.symbol.wand_and_stars'), name: '今日运势',  desc: '每天一次网络占卜', route: 'pages/apps/FortunePage' },
        { icon: $r('sys.symbol.face_smiling'), name: '路由器心情', desc: '今天路由器心情如何', route: 'pages/apps/RouterMoodPage' },
        { icon: $r('sys.symbol.qrcode'), name: 'WiFi 访客卡', desc: '扫码连接 WiFi 卡片', route: 'pages/apps/WifiCardPage' },
        { icon: $r('sys.symbol.waveform'), name: '网络心电图', desc: '实时延迟波形监测', route: 'pages/apps/NetEcgPage' },
        { icon: $r('sys.symbol.gauge_with_dots_needle_33percent'), name: '网速排位赛', desc: '测速看全国排名', route: 'pages/apps/SpeedTestPage' },
        { icon: $r('sys.symbol.label'), name: '设备外号', desc: '给设备起社交外号', route: 'pages/apps/DeviceAliasPage' },
        { icon: $r('sys.symbol.arrow_left_arrow_right'), name: 'DNS 擂台', desc: '各家 DNS 谁最快', route: 'pages/apps/DnsBattlePage' },
        { icon: $r('sys.symbol.bolt'), name: '远程开机', desc: 'WOL 一键唤醒设备', route: 'pages/apps/WolPage' },
        { icon: $r('sys.symbol.share'), name: '装 B 分享卡', desc: '网络状态生成分享图', route: 'pages/apps/ShareCardPage' },
        { icon: $r('sys.symbol.crown'), name: '路由器等级', desc: 'Lv.1 到网络之神', route: 'pages/apps/RouterLevelPage' },
        { icon: $r('sys.symbol.yuansign_moneybag'), name: '流量月账单', desc: '运营商账单风统计', route: 'pages/apps/TrafficBillPage' },
      ]
    },
    {
      title: '管理',
      items: [
        { icon: $r('sys.symbol.rectangle_stack'), name: '设备管理',  desc: '设备列表与备注管理', route: 'pages/apps/DeviceManagePage' },
        { icon: $r('sys.symbol.AI_help_write'), name: '设备辅助AI',  desc: '快捷问答 · 实时诊断网络', route: 'pages/apps/NetworkHelperPage' },
        { icon: $r('sys.symbol.person_shield'), name: '家长控制',  desc: 'OAF 应用过滤引擎配置', route: 'pages/apps/OafPage' },
        { icon: $r('sys.symbol.gearshape'), name: '系统进程',  desc: '查看和管理运行中的进程', route: 'pages/process/ProcessListPage' },
        { icon: $r('sys.symbol.play_circle'), name: '启动项',   desc: '管理开机自启服务', route: 'pages/process/StartupPage' },
        { icon: $r('sys.symbol.bell'), name: '智能通知',  desc: '断网告警与新设备接入提醒', route: 'pages/apps/NotifySettingsPage' },
        { icon: $r('sys.symbol.calendar'), name: '定时任务',  desc: '定时重启与定时开关 WiFi', route: 'pages/apps/SchedulePage' },
        { icon: $r('sys.symbol.paintbrush'), name: '皮肤管理',  desc: '更换应用主题皮肤', route: 'pages/apps/SkinManagePage' },
        { icon: $r('sys.symbol.code_square'), name: 'SSH 终端',   desc: '命令行管理路由器', route: 'pages/apps/SshTerminalPage' },
        { icon: $r('sys.symbol.folder'), name: '文件管理',   desc: '浏览管理 OpenWrt 文件', route: 'pages/apps/FileManagerPage' },
      ]
    },
    {
      title: '系统',
      items: [
        { icon: $r('sys.symbol.wifi_router'), name: 'OpenWRT 首页', desc: '打开路由器管理后台', route: 'pages/apps/WebViewPage' },
        { icon: $r('sys.symbol.arrow_clockwise'), name: '网络重启',  desc: '只重启网络服务不动整机', route: 'pages/system/NetworkRestartPage' },
        { icon: $r('sys.symbol.card_package'), name: '软件包管理', desc: 'opkg/apk 安装卸载软件', route: 'pages/system/PackageManagerPage' },
        { icon: $r('sys.symbol.doc_plaintext'), name: '系统日志',  desc: '实时查看路由器日志', route: 'pages/system/SystemLogPage' },
        { icon: $r('sys.symbol.externaldrive'), name: '配置备份',  desc: '备份与恢复全部配置', route: 'pages/system/ConfigBackupPage' },
        { icon: $r('sys.symbol.power'), name: '重启',     desc: '重启路由器设备', route: 'pages/system/RebootPage' },
        { icon: $r('sys.symbol.arrow_counterclockwise'), name: '恢复出厂', desc: '恢复设备到出厂设置', route: 'pages/system/FactoryResetPage' },
        { icon: $r('sys.symbol.square_grid_2x2'), name: '小组件设置', desc: '选择桌面卡片显示的主指标', route: 'pages/apps/WidgetSettingsPage' },
        { icon: $r('sys.symbol.info_circle'), name: '关于',     desc: '版本信息与更新检查', route: '__about__' },
      ]
    },
  ]

  /** 扁平化获取总数量用于动画 */
  private flatTools(): ToolEntry[] {
    const arr: ToolEntry[] = []
    for (const g of this.groups) {
      for (const t of g.items) arr.push(t)
    }
    return arr
  }

  /** 拉取远程最新版本并跳转关于页（version.json 发布信息） */
  /** 获取运行时长（只读 uptime，不改变卡片样式） */
  async loadUptime(): Promise<void> {
    if (!this.deviceConnected) return
    try {
      const sys: SystemInfo = await this.api.fetchSystemInfo()
      const u: number = sys.uptime
      if (u > 0) {
        const days: number = Math.floor(u / 86400)
        const hrs: number = Math.floor((u % 86400) / 3600)
        const mins: number = Math.floor((u % 3600) / 60)
        if (days > 0) {
          this.upText = `${days}天`
        } else if (hrs > 0) {
          this.upText = `${hrs}时`
        } else {
          this.upText = `${mins}分`
        }
      }
    } catch (e) {}
  }

  handleClick(tool: ToolEntry): void {
    // 关于页：直接进入，版本检查由页面内「检查更新」按钮触发（不再阻塞进入）
    if (tool.route === '__about__') {
      try {
        AppNav.getInstance().open('pages/other/AboutPage')
      } catch (e) {
        hilog.error(0x0001, 'AppsPage', `pushUrl failed: ${e}`)
      }
    } else {
      try {
        AppNav.getInstance().open(tool.route)
      } catch (e) {
        hilog.error(0x0001, 'AppsPage', `pushUrl failed: ${e}`)
      }
    }
  }

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
    // 跟随皮肤切换实时刷新配色
    this.themeListener = () => {
      this.theme = AppState.getInstance().getTheme()
    }
    AppState.getInstance().onThemeChange(this.themeListener)
    
    // 填充设备信息（仿应用商店「我的」个人卡片）
    const active = AppState.getInstance().getActiveDevice()
    this.deviceConnected = AppState.getInstance().isConnected()
    if (active) {
      this.deviceName = active.label || active.host || '路由器'
      this.deviceHost = active.host ? `${active.host}${active.port && active.port !== '80' ? ':' + active.port : ''}` : ''
    }
    this.savedCount = AppState.getInstance().devices.length
    this.loadUptime()

    const tools: ToolEntry[] = this.flatTools()
    const slides: number[] = []
    for (let i = 0; i < tools.length; i++) slides.push(300)
    this.itemSlides = slides

    for (let i = 0; i < tools.length; i++) {
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseOut }, () => {
          const arr: number[] = [...this.itemSlides]
          arr[i] = 0
          this.itemSlides = arr
        })
      }, 50 * i)
    }
  }

  aboutToDisappear(): void {
    if (this.themeListener) {
      AppState.getInstance().offThemeChange(this.themeListener)
      this.themeListener = null
    }
  }

  /** 切换设备：回到设备列表（连接状态保留在存储里，可随时切回） */
  switchDevice(): void {
    AppState.getInstance().requestSwitchDevice()
    try {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/entry/LoginPage' })
    } catch (e) {
      hilog.error(0x0001, 'AppsPage', `switchDevice nav err: ${String(e)}`)
    }
  }

  /** 获取全局动画索引 */
  getSlideIndex(groupIdx: number, itemIdx: number): number {
    let idx = 0
    for (let g = 0; g < groupIdx; g++) idx += this.groups[g].items.length
    return idx + itemIdx
  }

  /** 分组内双列分组（每行 2 个） */
  groupRows(items: ToolEntry[]): ToolEntry[][] {
    const rows: ToolEntry[][] = []
    for (let i = 0; i < items.length; i += 2) {
      rows.push(items.slice(i, i + 2))
    }
    return rows
  }

  /** 图标多彩底色（按序号循环，同一套形状规范，颜色丰富） */
  private iconPalette: string[][] = [
    ['#60A5FA', '#2563EB'],
    ['#A78BFA', '#7C3AED'],
    ['#F472B6', '#DB2777'],
    ['#FBBF24', '#F59E0B'],
    ['#34D399', '#059669'],
    ['#22D3EE', '#0891B2'],
    ['#FB923C', '#EA580C'],
    ['#818CF8', '#4F46E5']
  ]

  private iconGradient(idx: number): IconGradient {
    const c: string[] = this.iconPalette[Math.abs(idx) % this.iconPalette.length]
    return { angle: 135, colors: [[c[0], 0], [c[1], 1]] }
  }

  /** 双列功能方块（彩色图标底座 + 名称，紧凑应用商店风格） */
  @Builder
  toolCard(tool: ToolEntry, slideIdx: number) {
    Column() {
      // 统一图标：同一形状规范的渐变底座 + 白色系统符号
      Row() {
        SymbolGlyph(tool.icon)
          .fontSize(19)
          .fontColor(['#FFFFFF'])
      }
      .width(36)
      .height(36)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .linearGradient(this.iconGradient(slideIdx))
      .shadow({ radius: 6, color: 'rgba(37,99,235,0.18)', offsetY: 2 })

      Text(tool.name)
        .fontSize(11)
        .fontColor(this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.theme.bgCard)
    .backdropBlur(20)
    .border({ width: 0.5, color: this.theme.borderGlass })
    .alignItems(HorizontalAlign.Center)
    .opacity(this.itemSlides.length > slideIdx && this.itemSlides[slideIdx] === 0 ? 1 : 0)
    .translate({ x: this.itemSlides.length > slideIdx ? this.itemSlides[slideIdx] : 300 })
    .onClick(() => this.handleClick(tool))
  }

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        // 顶栏
        Row() {
          Row() {
            Text(' 应用中心').fontSize(16).fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100).backgroundColor('transparent')
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try { AppNav.getInstance().back() }
            catch (e) { hilog.error(0x0001, 'AppsPage', `router.back failed: ${e}`) }
          })

          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 12 })

        // 内容列表（仿鸿蒙应用商店「我的」排版）
        Scroll() {
          Column() {
            // ===== 顶部个人信息卡片 =====
            Row() {
              // 圆形设备头像
              Row() {
                Image($r('app.media.app_center'))
                  .width(32).height(32)
              }
              .width(64).height(64).borderRadius(32)
              .backgroundColor(this.deviceConnected ? 'rgba(68,138,255,0.15)' : 'rgba(255,82,82,0.12)')
              .justifyContent(FlexAlign.Center)

              // 名称 + 地址
              Column() {
                Row() {
                  Text(this.deviceName)
                    .fontSize(18).fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Bold)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.deviceConnected ? '●' : '○')
                    .fontSize(14).fontColor(this.deviceConnected ? '#00E676' : '#FF5252')
                    .margin({ left: 6 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (this.deviceHost) {
                  Text(this.deviceHost)
                    .fontSize(12).fontColor(this.theme.textTertiary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 3 })
                } else {
                  Text('未连接设备，请先登录路由器')
                    .fontSize(12).fontColor(this.theme.textTertiary)
                    .margin({ top: 3 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 14 })

              // 已保存设备数 + 运行时长（同款样式并排）
              Row({ space: 12 }) {
                Column() {
                  Text(String(this.savedCount))
                    .fontSize(20).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
                  Text('已保存设备')
                    .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(this.upText)
                    .fontSize(20).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
                  Text('运行时长')
                    .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Center)
              }
              .alignItems(VerticalAlign.Center)
              .padding({ left: 12, right: 4 })

              // 切换设备入口（点整张卡片也可）
              Text('›')
                .fontSize(20).fontColor(this.theme.textTertiary)
                .margin({ left: 8 })
            }
            .width('calc(100% - 56px)')
            .padding(18)
            .borderRadius(20)
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .margin({ left: 28, right: 28, top: 8 })
            .onClick(() => { this.switchDevice() })

            // ===== 分组（横线式标题 + 双列方块，无大卡片框）=====
            ForEach(this.groups, (group: ToolGroup, gIdx: number) => {
              Column() {
                // 横线式分类标题：———— 网络 ————
                Row() {
                  Row()
                    .layoutWeight(1)
                    .height(0.5)
                    .backgroundColor(this.theme.borderGlass)
                  Text(group.title)
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .margin({ left: 12, right: 12 })
                  Row()
                    .layoutWeight(1)
                    .height(0.5)
                    .backgroundColor(this.theme.borderGlass)
                }
                .width('100%')
                .padding({ left: 18, right: 18, top: 20, bottom: 6 })

                // 双列方块网格（无卡片容器，直接浮在背景上）
                ForEach(this.groupRows(group.items), (row: ToolEntry[], rowIdx: number) => {
                  Row() {
                    ForEach(row, (tool: ToolEntry, colIdx: number) => {
                      this.toolCard(tool, this.getSlideIndex(gIdx, rowIdx * 2 + colIdx))
                    }, (tool: ToolEntry): string => tool.name + tool.desc)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 8 })
                }, (row: ToolEntry[], rowIdx: number): string => `row_${rowIdx}`)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            })

            // 底部版本信息
            Column() {
              Text('iStore 路由管家')
                .fontSize(12).fontColor(this.theme.textTertiary)
              Text(`${this.versionText} · 开源 · HarmonyOS`)
                .fontSize(10).fontColor(this.theme.textTertiary).opacity(0.7)
                .margin({ top: 3 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 28, bottom: 40 })
          }
          .width('100%')
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ top: 4 })
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
