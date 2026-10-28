/**
 * 数据模型定义
 * 包含与路由器 API 通信时使用的所有数据结构接口
 */

/**
 * 系统信息 - 路由器硬件与系统状态
 */
export interface SystemInfo {
  hostname: string          // 主机名
  model: string             // 设备型号
  kernel: string            // 内核版本
  firmwareVersion: string   // 固件版本
  localTime: string         // 设备本地时间
  uptime: number            // 运行时长（秒）
  cpuUsage: number          // CPU 使用率（百分比）
  memoryTotal: number       // 内存总量（字节）
  memoryUsed: number        // 已用内存（字节）
  memoryCached: number      // 缓存内存（字节）
  memoryAvailable: number   // 可用内存（字节）
  storageTotal: number      // 存储总量（字节）
  storageUsed: number       // 已用存储（字节）
  cpuTemp: number           // CPU 温度（摄氏度）
  cpuFreq: number           // CPU 当前频率（MHz，0 表示未知）
  boardName: string         // 主板名称
  cpuModel: string          // CPU 型号
  distribution: string      // 发行版名称
  releaseVersion: string    // 发布版本号
  releaseRevision: string   // 发布修订号
  releaseTarget: string     // 目标平台
}

/**
 * 网络接口信息
 */
export interface NetworkInterface {
  name: string              // 接口名称（如 eth0, wlan0）
  type: 'wan' | 'lan' | 'wifi' | 'vpn'  // 接口类型
  ipAddress: string         // IP 地址
  netmask: string           // 子网掩码
  gateway: string           // 网关地址
  macAddress: string        // MAC 地址
  mtu: number               // 最大传输单元
  status: 'up' | 'down'     // 接口状态：启用/禁用
  rxBytes: number           // 累计接收字节数
  txBytes: number           // 累计发送字节数
  rxRate: number            // 当前接收速率（字节/秒）
  txRate: number            // 当前发送速率（字节/秒）
  uptime: number            // 接口运行时长（秒）
}

/**
 * WAN 口状态 - 外网连接状态
 */
/** 智能网络体检单项结果 */
export interface NetworkCheckItem {
  key: string            // 检测项标识
  name: string           // 检测项名称
  target: string         // 检测目标
  desc: string           // 说明（如「阿里公共 DNS」）
  status: string         // pending / running / ok / warn / fail
  latencyMs: number      // 平均延迟（ms）
  lossPercent: number    // 丢包率（%）
  detail: string         // 附加说明（如网关地址/错误信息）
}

export interface WanStatus {
  interface: string         // WAN 接口名称
  uptime: number            // 连接持续时间（秒）
  ipAddress: string         // 公网 IP 地址
  netmask: string           // 子网掩码
  gateway: string           // 网关地址
  dns: string[]             // DNS 服务器列表
  rxRate: number            // 下载速率
  txRate: number            // 上传速率
  onlineTime: string        // 上线时间
  proto: string             // 连接协议（如 pppoe, dhcp）
  macAddr: string           // WAN 口 MAC 地址
}

/**
 * 已连接设备 - 局域网中的客户端设备
 */
export interface ConnectedDevice {
  mac: string               // MAC 地址
  ip: string                // IP 地址
  hostname: string          // 主机名
  vendor: string            // 设备厂商
  interface: string         // 连接的接口名称
  onlineTime: string        // 上线时间
  signalStrength: number    // 信号强度（dBm）
  rxRate: number            // 下载速率
  txRate: number            // 上传速率
  isOnline: boolean         // 是否在线
  bridgePort?: string       // 桥接端口（lan1/lan2…），用于区分直连与经交换机/AP 接入
}

/**
 * 流量历史记录 - 用于图表展示
 */
export interface TrafficHistory {
  timestamp: string         // 时间戳
  rx: number                // 接收流量（字节/秒）
  tx: number                // 发送流量（字节/秒）
}

/**
 * 连接配置 - 与路由器建立连接的配置信息
 */
export interface ConnectionConfig {
  host: string              // 路由器地址（IP 或域名）
  port: number              // 端口号
  token: string             // 认证令牌
  useHttps: boolean         // 是否使用 HTTPS
  username?: string         // 用户名（可选，用于基本认证）
  password?: string         // 密码（可选，用于基本认证）
}

/**
 * 挂载点信息 - 磁盘分区挂载情况
 */
export interface MountPoint {
  device: string            // 设备路径
  mountPoint: string        // 挂载点路径
  filesystem: string        // 文件系统类型
  size: number              // 分区总大小（字节）
  used: number              // 已用空间（字节）
  available: number         // 可用空间（字节）
  usedPercent: number       // 使用率（百分比）
}

/**
 * 连接跟踪信息 - NAT 连接数统计
 */
export interface ConntrackInfo {
  current: number           // 当前连接数
  max: number               // 最大连接数
  percent: number           // 使用率（百分比）
}

/**
 * 进程信息 - 系统进程列表项
 */
export interface ProcessInfo {
  pid: number               // 进程 ID
  ppid: number              // 父进程 ID
  name: string              // 进程名称
  cpu: number               // CPU 使用率
  mem: number               // 内存使用量（字节）
  memPercent: number        // 内存使用率（百分比）
  status: string            // 进程状态
  user: string              // 所属用户
  command: string           // 完整命令行
}

/**
 * 启动项 - 系统启动时自动运行的服务
 */
export interface StartupItem {
  name: string              // 服务名称
  priority: number          // 启动优先级
  enabled: boolean          // 是否启用
  running: boolean          // 是否正在运行
}

/**
 * 路由表条目
 */
export interface RouteEntry {
  destination: string       // 目标地址
  gateway: string           // 网关地址
  device: string            // 出口设备
  source: string            // 源地址
  scope: string             // 路由范围
  table: string             // 路由表 ID
  flags: string             // 路由标志
}

/**
 * 无线客户端 - WiFi 连接的终端设备
 */
export interface WirelessClient {
  mac: string               // MAC 地址
  hostname: string          // 主机名
  interface: string         // 无线接口名称
  signal: number            // 信号强度（dBm）
  signalNoise: number       // 信噪比（dBm）
  rxRate: number            // 接收速率
  txRate: number            // 发送速率
  connectedTime: number     // 连接时间（秒）
  inactiveTime: number      // 不活跃时间（秒）
  isMesh: boolean           // 是否为 Mesh 节点
}

/**
 * 无线设备 - 物理无线网卡/AP 信息
 */
export interface WirelessDevice {
  name: string              // 设备名称（如 radio0）
  bssid: string             // BSSID（AP 的 MAC 地址）
  ssid: string              // 网络名称
  channel: number           // 信道
  frequency: number         // 频率（MHz）
  bandwidth: string         // 带宽
  encryption: string        // 加密方式
  signal: number            // 信号强度
  quality: number           // 信号质量（百分比）
  mode: string              // 工作模式（ap/client）
  up: boolean               // 是否启用
  hwmode: string            // 硬件模式（11g/11n/11ac）
  protocol: string          // 协议
}

/**
 * WiFi 接入点完整信息（管理页展示 + 编辑用）
 */
export interface WifiApInfo {
  device: string            // 无线设备名（radio0/radio1）
  ssid: string              // 网络名称
  channel: number           // 当前信道
  frequency: number         // 频率（MHz）
  txpower: number           // 发射功率（dBm）
  encryption: string        // 加密方式（如 WPA2-PSK/WPA3）
  quality: number           // 信号质量（%）
  hwmode: string            // 硬件模式（11g/11n/11ac/11ax）
  mode: string              // 工作模式（ap）
  up: boolean               // 是否启用
  clientCount: number       // 已连接客户端数
  bandwidth: string         // 带宽（HT20/HT40/VHT80 等）
  disabled: boolean         // 配置中是否禁用
}

/**
 * WiFi 客户端详细信息（管理页客户端列表）
 */
export interface WifiClientDetail {
  mac: string               // MAC 地址
  hostname: string          // 主机名
  device: string            // 所属无线设备（radio0 等）
  signal: number            // 信号（dBm）
  noise: number             // 噪声（dBm）
  rxRate: number            // 接收速率（Mbps）
  txRate: number            // 发送速率（Mbps）
  connectedTime: number     // 连接时长（秒）
  inactiveTime: number      // 空闲时间（秒）
}

/**
 * OAF（应用过滤引擎）运行状态
 */
export interface OafStatus {
  pluginVersion: string     // 插件版本
  engineVersion: string     // 引擎版本
  kernelVersion: string     // 内核模块版本
  configStatus: string      // 配置状态
  filterStatus: string      // 过滤状态
  engineStatus: string      // 引擎状态
  versionTooHigh: boolean   // 版本是否过高（可能导致兼容性问题）
}

/**
 * 应用过滤基础配置
 */
export interface AppFilterBase {
  appFilterEnabled: boolean // 应用过滤总开关
  appLogEnabled: boolean    // 应用日志开关
  workMode: 'gateway' | 'bypass'  // 工作模式：网关模式/旁路模式
}

/**
 * 应用分类 - 家长控制中的应用分组
 */
export interface AppClass {
  id: number                // 分类 ID
  name: string              // 分类名称（如"视频"、"游戏"）
  apps: AppItem[]           // 该分类下的应用列表
}

/**
 * 应用项 - 单个可管控的应用
 */
export interface AppItem {
  id: number                // 应用 ID
  name: string              // 应用名称
  enabled: boolean          // 是否已启用管控
}

/**
 * 应用过滤时间段配置
 */
export interface AppFilterTime {
  fixedTimes: TimeSlot[]    // 固定时间段列表
  dynamicMinutes: number    // 动态时长（分钟）
  dynamicStartHour: number  // 动态开始小时
  dynamicStartMin: number   // 动态开始分钟
  dynamicEndHour: number    // 动态结束小时
  dynamicEndMin: number     // 动态结束分钟
  weekdays: number[]        // 生效星期（0-6，0 为周日）
}

/**
 * 时间段
 */
export interface TimeSlot {
  startHour: number         // 开始小时
  startMin: number          // 开始分钟
  endHour: number           // 结束小时
  endMin: number            // 结束分钟
}

/**
 * 应用过滤用户配置 - 受管控的用户列表
 */
export interface AppFilterUser {
  mode: 'auto' | 'manual'   // 模式：自动/手动
  users: Object[]           // 用户列表
}

/**
 * 设备访问时间统计 - 某设备使用各应用的时长
 */
export interface DeviceVisitTime {
  appId: number             // 应用 ID
  appName: string           // 应用名称
  totalSeconds: number      // 总使用时长（秒）
  percent: number           // 占比（百分比）
}

/**
 * 设备访问记录 - 某设备访问应用的详细记录
 */
export interface DeviceVisitRecord {
  appId: number             // 应用 ID
  appName: string           // 应用名称
  startTime: string         // 开始时间
  duration: number          // 持续时长（秒）
}

/**
 * 用户列表项 - 家长控制用户概览
 */
export interface UserListItem {
  hostname: string          // 主机名
  mac: string               // MAC 地址
  ip: string                // IP 地址
  currentApp: string        // 当前正在使用的应用
  currentUrl: string        // 当前访问的 URL
  commonApps: number[]      // 常用应用 ID 列表
}

export interface IStoreApp {
  name: string
  title: string
  version: string
  icon: string
  link: string
  iconBase64: string
  category: string   // 应用分类（无分类时为空）
}

export interface DockerOverview {
  dockerVersion: string
  daemonStatus: string
  containersTotal: number
  containersRunning: number
  imagesTotal: number
  diskUsed: string
  memUsedMb: string
}

export interface DockerContainer {
  id: string
  name: string
  status: string
  image: string
  running: boolean
}

export interface DockerStats {
  id: string
  name: string
  cpuPercent: number
  memUsage: string
  memPercent: number
}

/** DHCP 静态绑定（host section） */
export interface DhcpBindingInfo {
  section: string
  mac: string
  ip: string
  name: string
}

/** WiFi 访客网络配置信息 */
export interface GuestWifiInfo {
  enabled: boolean
  ssid: string
  password: string
  network: string
  device: string
  section: string
}

/** Docker 镜像信息 */
export interface DockerImage {
  id: string
  repoTag: string   // 仓库名:标签
  size: number      // 大小（字节）
  created: number   // 创建时间戳
}

/** Docker 网络信息 */
export interface DockerNetwork {
  id: string
  name: string
  driver: string
  scope: string
}
