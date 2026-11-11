/**
 * PageRegistry — 全应用功能页的统一注册表
 *
 * 单一数据源：应用中心的磁贴分组、全局搜索（标题 / 拼音首字母 / 最近使用）
 * 都从这里取数据，新增页面时只改这一个文件。
 *
 * 新增页面步骤：
 *   1. 在 PAGE_REGISTRY 里追加一条（route 与 main_pages.json 一致）
 *   2. py 填标题的拼音首字母（小写，不含空格），如「安全中心」→ aqzx
 */

/** 单个功能页定义 */
export interface PageEntry {
  /** 路由路径（与 main_pages.json 一致） */
  route: string
  /** 中文标题（磁贴名称 / 搜索结果主标题） */
  title: string
  /** 一句话描述 */
  desc: string
  /** 图标名（AppIcon 的 name，走统一图标包） */
  icon: string
  /** 所属分组（'我的' / '网络' / '多媒体' / '趣味' / '管理' / '系统'） */
  group: string
  /** 标题拼音首字母（小写），用于键盘快捷检索，如 aqzx */
  py: string
  /** 磁贴底部实时指标 key（由应用中心消费，可缺省） */
  metric?: string
}

/** 分组定义（顺序即应用中心的展示顺序） */
export interface PageGroupDef {
  title: string
  items: PageEntry[]
}

/** 分组展示顺序 */
export const PAGE_GROUP_ORDER: string[] = ['我的', '网络', '多媒体', '趣味', '管理', '系统']

/** 全部功能页（顺序即分组内展示顺序） */
export const PAGE_REGISTRY: PageEntry[] = [
  // ===== 我的 =====
  { route: 'pages/pet/PetPage', title: '小管家', desc: '养成式网络管家 · 每日任务',
    icon: 'heart', group: '我的', py: 'xgj', metric: 'pet' },
  { route: 'pages/apps/StorePage', title: 'iStore 商店', desc: '浏览与安装路由器插件',
    icon: 'bag', group: '我的', py: 'istore', metric: 'store' },
  { route: 'pages/apps/DockerPage', title: 'Docker', desc: '容器、镜像与网络管理',
    icon: 'square_stack_3d', group: '我的', py: 'docker', metric: 'docker' },
  { route: 'pages/apps/WebViewPage', title: 'OpenWRT 首页', desc: '打开路由器管理后台',
    icon: 'wifi_router', group: '我的', py: 'openwrt', metric: 'ip' },

  // ===== 网络 =====
  { route: 'pages/security/SecurityHubPage', title: '安全中心', desc: '安全评分 / 陌生设备 / 危险端口',
    icon: 'security_shield', group: '网络', py: 'aqzx', metric: 'security' },
  { route: 'pages/apps/WifiPage', title: 'WiFi 管理', desc: '无线网络状态与配置管理',
    icon: 'wifi', group: '网络', py: 'wifigl', metric: 'wifi' },
  { route: 'pages/apps/NetworkPage', title: '网络管理', desc: '接口状态与网络信息',
    icon: 'globe_badge_message', group: '网络', py: 'wlgl', metric: 'network' },
  { route: 'pages/apps/TrafficRankPage', title: '流量排行', desc: '按速率排名的客户端活跃度',
    icon: 'arrow_up_right', group: '网络', py: 'llpx', metric: 'trafficRank' },
  { route: 'pages/apps/ConntrackRankPage', title: '连接排行', desc: '发现 NAT 连接数最多的设备',
    icon: 'link', group: '网络', py: 'ljpx', metric: 'conntrack' },
  { route: 'pages/apps/PortTrafficPage', title: '网口流量', desc: '各接口实时速率与累计统计',
    icon: 'arrow_up_and_down_square_portrait', group: '网络', py: 'wkll', metric: 'portTraffic' },
  { route: 'pages/apps/EthPortPage', title: '物理网口', desc: '查看物理端口连接状态与速率',
    icon: 'square_grid_3x1_below_line_grid_1x2', group: '网络', py: 'wlwk', metric: 'ethPort' },
  { route: 'pages/apps/TrafficReportPage', title: '流量统计', desc: '近 7/30 天每日流量趋势',
    icon: 'list_square_bill', group: '网络', py: 'lltj', metric: 'trafficReport' },
  { route: 'pages/apps/NetworkCheckPage', title: '智能体检', desc: '一键检测网络连通与延迟',
    icon: 'staroflife', group: '网络', py: 'zntj', metric: 'netCheck' },
  { route: 'pages/apps/TopologyPage', title: '网络拓扑', desc: '可视化设备连接关系图',
    icon: 'circle_grid_2x2', group: '网络', py: 'wltp', metric: 'topology' },

  // ===== 多媒体 =====
  { route: 'pages/apps/AlbumPage', title: '相册', desc: 'Immich 照片与视频管理',
    icon: 'ohos_photo', group: '多媒体', py: 'xc', metric: 'album' },
  { route: 'pages/apps/JellyfinPage', title: 'Jellyfin', desc: '电影、剧集与音乐媒体中心',
    icon: 'movie', group: '多媒体', py: 'jellyfin', metric: 'jellyfin' },

  // ===== 趣味 =====
  { route: 'pages/apps/SmartHubPage', title: '智能管家', desc: '预知·侦探·值班·一句话·周报',
    icon: 'lightbulb', group: '趣味', py: 'zngj', metric: 'smart' },
  { route: 'pages/apps/MileStonePage', title: '运行里程碑', desc: '连续运行天数与纪念日',
    icon: 'flag', group: '趣味', py: 'yxlcb', metric: 'milestone' },
  { route: 'pages/apps/AchievementPage', title: '网络成就', desc: '收集你的网络徽章',
    icon: 'medal', group: '趣味', py: 'wlcj', metric: 'achievement' },
  { route: 'pages/apps/DeviceActivityPage', title: '设备作息', desc: '设备 24h 活跃热力图',
    icon: 'clock', group: '趣味', py: 'sbzx', metric: 'activity' },
  { route: 'pages/apps/DiaryPage', title: '网络日记', desc: '每日网络事件时间线',
    icon: 'book', group: '趣味', py: 'wlrj', metric: 'diary' },
  { route: 'pages/apps/NetworkReportPage', title: 'AI 周报', desc: '7 天流量汇总与点评',
    icon: 'doc_text', group: '趣味', py: 'aizb', metric: 'report' },
  { route: 'pages/apps/FortunePage', title: '今日运势', desc: '每天一次网络占卜',
    icon: 'wand_and_stars', group: '趣味', py: 'jrys', metric: 'fortune' },
  { route: 'pages/apps/RouterMoodPage', title: '路由器心情', desc: '今天路由器心情如何',
    icon: 'face_smiling', group: '趣味', py: 'lyqxq', metric: 'mood' },
  { route: 'pages/apps/WifiCardPage', title: 'WiFi 访客卡', desc: '扫码连接 WiFi 卡片',
    icon: 'qrcode', group: '趣味', py: 'wififkk', metric: 'wifiCard' },
  { route: 'pages/apps/NetEcgPage', title: '网络心电图', desc: '实时延迟波形监测',
    icon: 'waveform', group: '趣味', py: 'wlxdt', metric: 'ecg' },
  { route: 'pages/apps/SpeedTestPage', title: '网速排位赛', desc: '测速看全国排名',
    icon: 'gauge_with_dots_needle_33percent', group: '趣味', py: 'wspws', metric: 'speedTest' },
  { route: 'pages/apps/DeviceAliasPage', title: '设备外号', desc: '给设备起社交外号',
    icon: 'label', group: '趣味', py: 'sbwh', metric: 'alias' },
  { route: 'pages/apps/DnsBattlePage', title: 'DNS 擂台', desc: '各家 DNS 谁最快',
    icon: 'arrow_left_arrow_right', group: '趣味', py: 'dnslt', metric: 'dns' },
  { route: 'pages/apps/WolPage', title: '远程开机', desc: 'WOL 一键唤醒设备',
    icon: 'bolt', group: '趣味', py: 'yckj', metric: 'wol' },
  { route: 'pages/apps/ShareCardPage', title: '装 B 分享卡', desc: '网络状态生成分享图',
    icon: 'share', group: '趣味', py: 'zbfxk', metric: 'shareCard' },
  { route: 'pages/apps/RouterLevelPage', title: '路由器等级', desc: 'Lv.1 到网络之神',
    icon: 'crown', group: '趣味', py: 'lyqdj', metric: 'level' },
  { route: 'pages/apps/TrafficBillPage', title: '流量月账单', desc: '运营商账单风统计',
    icon: 'yuansign_moneybag', group: '趣味', py: 'llyzd', metric: 'bill' },

  // ===== 管理 =====
  { route: 'pages/apps/DeviceManagePage', title: '设备管理', desc: '设备列表与备注管理',
    icon: 'rectangle_stack', group: '管理', py: 'sbgl', metric: 'deviceManage' },
  { route: 'pages/apps/NetworkHelperPage', title: '设备辅助AI', desc: '快捷问答 · 实时诊断网络',
    icon: 'AI_help_write', group: '管理', py: 'sbfzai', metric: 'aiHelper' },
  { route: 'pages/apps/OafPage', title: '家长控制', desc: 'OAF 应用过滤引擎配置',
    icon: 'person_shield', group: '管理', py: 'jzkz', metric: 'oaf' },
  { route: 'pages/process/ProcessListPage', title: '系统进程', desc: '查看和管理运行中的进程',
    icon: 'gearshape', group: '管理', py: 'xtjc', metric: 'process' },
  { route: 'pages/process/StartupPage', title: '启动项', desc: '管理开机自启服务',
    icon: 'play_circle', group: '管理', py: 'qdx', metric: 'startup' },
  { route: 'pages/apps/NotifySettingsPage', title: '智能通知', desc: '断网告警与新设备接入提醒',
    icon: 'bell', group: '管理', py: 'zntz', metric: 'notify' },
  { route: 'pages/apps/SchedulePage', title: '定时任务', desc: '定时重启与定时开关 WiFi',
    icon: 'calendar', group: '管理', py: 'dsrw', metric: 'schedule' },
  { route: 'pages/apps/SkinManagePage', title: '主题', desc: '色板与材质（含液态玻璃）',
    icon: 'paintbrush', group: '管理', py: 'pfgl', metric: 'skin' },
  { route: 'pages/apps/SshTerminalPage', title: 'SSH 终端', desc: '命令行管理路由器',
    icon: 'code_square', group: '管理', py: 'sshzd', metric: 'ssh' },
  { route: 'pages/apps/FileManagerPage', title: '文件管理', desc: '浏览管理 OpenWrt 文件',
    icon: 'folder', group: '管理', py: 'wjgl', metric: 'files' },

  // ===== 系统 =====
  { route: 'pages/system/NetworkRestartPage', title: '网络重启', desc: '只重启网络服务不动整机',
    icon: 'arrow_clockwise', group: '系统', py: 'wlcz', metric: 'netRestart' },
  { route: 'pages/system/PackageManagerPage', title: '软件包管理', desc: 'opkg/apk 安装卸载软件',
    icon: 'card_package', group: '系统', py: 'rjbgl', metric: 'packages' },
  { route: 'pages/system/SystemLogPage', title: '系统日志', desc: '实时查看路由器日志',
    icon: 'doc_plaintext', group: '系统', py: 'xtrz', metric: 'syslog' },
  { route: 'pages/system/ConfigBackupPage', title: '配置备份', desc: '备份与恢复全部配置',
    icon: 'externaldrive', group: '系统', py: 'pzbf', metric: 'backup' },
  { route: 'pages/system/RebootPage', title: '重启', desc: '重启路由器设备',
    icon: 'power', group: '系统', py: 'cz', metric: 'reboot' },
  { route: 'pages/system/FactoryResetPage', title: '恢复出厂', desc: '恢复设备到出厂设置',
    icon: 'arrow_counterclockwise', group: '系统', py: 'hfcc', metric: 'factory' },
  { route: 'pages/apps/WidgetSettingsPage', title: '小组件设置', desc: '选择桌面卡片显示的主指标',
    icon: 'square_grid_2x2', group: '系统', py: 'xjsz', metric: 'widget' },
  { route: 'pages/other/AboutPage', title: '关于', desc: '版本信息与更新检查',
    icon: 'info_circle', group: '系统', py: 'gy', metric: 'about' },
]

/** 按分组顺序聚合（应用中心磁贴直接消费） */
export function getPageGroups(): PageGroupDef[] {
  const out: PageGroupDef[] = []
  for (let i = 0; i < PAGE_GROUP_ORDER.length; i++) {
    const items: PageEntry[] = []
    for (let j = 0; j < PAGE_REGISTRY.length; j++) {
      if (PAGE_REGISTRY[j].group === PAGE_GROUP_ORDER[i]) {
        items.push(PAGE_REGISTRY[j])
      }
    }
    if (items.length > 0) {
      const def: PageGroupDef = { title: PAGE_GROUP_ORDER[i], items: items }
      out.push(def)
    }
  }
  return out
}

/** 按路由查页面定义（最近使用回填标题 / 图标） */
export function findPage(route: string): PageEntry | null {
  for (let i = 0; i < PAGE_REGISTRY.length; i++) {
    if (PAGE_REGISTRY[i].route === route) {
      return PAGE_REGISTRY[i]
    }
  }
  return null
}

/** 命中评分：标题 > 拼音首字母 > 描述 > 路由；0 表示不命中 */
function scoreOf(entry: PageEntry, kw: string): number {
  const title: string = entry.title.toLowerCase()
  if (title === kw) return 100
  if (title.indexOf(kw) === 0) return 92
  if (title.indexOf(kw) > 0) return 84
  const py: string = entry.py.toLowerCase()
  if (py === kw) return 78
  if (py.indexOf(kw) === 0) return 70
  if (py.indexOf(kw) > 0) return 62
  if (entry.desc.toLowerCase().indexOf(kw) >= 0) return 40
  if (entry.route.toLowerCase().indexOf(kw) >= 0) return 30
  return 0
}

/** 搜索结果（按命中优先级排序，最多 limit 条） */
export function searchPages(keyword: string, limit: number = 8): PageEntry[] {
  const kw: string = keyword.trim().toLowerCase()
  const hits: PageEntry[] = []
  const scores: number[] = []
  if (kw.length === 0) {
    return hits
  }
  for (let i = 0; i < PAGE_REGISTRY.length; i++) {
    const s: number = scoreOf(PAGE_REGISTRY[i], kw)
    if (s <= 0) continue
    // 插入排序：分数高的靠前，同分保持注册表顺序
    let pos: number = hits.length
    for (let j = 0; j < hits.length; j++) {
      if (s > scores[j]) {
        pos = j
        break
      }
    }
    hits.splice(pos, 0, PAGE_REGISTRY[i])
    scores.splice(pos, 0, s)
    if (hits.length > limit) {
      hits.pop()
      scores.pop()
    }
  }
  return hits
}
