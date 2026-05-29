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
}

/**
 * 插件信息 - iStore 应用商店中的插件
 */
export interface Plugin {
  id: string                // 插件唯一标识
  name: string              // 插件名称（英文）
  displayName: string       // 显示名称（中文）
  description: string       // 插件描述
  version: string           // 版本号
  author: string            // 作者
  category: string          // 分类
  installed: boolean        // 是否已安装
  enabled: boolean          // 是否已启用
  running: boolean          // 是否正在运行
  iconUrl: string           // 图标地址
  size: string              // 包大小
}

/**
 * DHCP 租约 - 设备 IP 分配记录
 */
export interface DhcpLease {
  mac: string               // 设备 MAC 地址
  ip: string                // 分配的 IP 地址
  hostname: string          // 设备主机名
  expiresAt: string         // 租约到期时间
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
 * 通用 API 响应格式
 */
export interface ApiResponse<T> {
  code: number              // 状态码（0 表示成功）
  message: string           // 响应消息
  data: T                   // 响应数据
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
 * 日志条目
 */
export interface LogEntry {
  time: string              // 日志时间
  level: 'info' | 'warn' | 'error'  // 日志级别
  module: string            // 所属模块
  message: string           // 日志内容
}

/**
 * WiFi 设置 - 无线网络配置
 */
export interface WifiSettings {
  radio: string             // 无线频段（2G/5G）
  ssid: string              // WiFi 名称
  channel: number           // 信道号
  bandwidth: string         // 带宽（20MHz/40MHz/80MHz）
  encryption: string        // 加密方式
  password: string          // WiFi 密码
  enabled: boolean          // 是否启用
  hidden: boolean           // 是否隐藏 SSID
}

/**
 * 防火墙规则
 */
export interface FirewallRule {
  name: string              // 规则名称
  src: string               // 源地址
  dest: string              // 目标地址
  proto: string             // 协议（tcp/udp/icmp）
  port: string              // 端口号
  target: 'ACCEPT' | 'REJECT' | 'DROP'  // 动作：允许/拒绝/丢弃
  enabled: boolean          // 是否启用
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
  users: OafUser[]          // 用户列表
}

/**
 * OAF 用户 - 被管控的设备/用户
 */
export interface OafUser {
  id: string                // 用户 ID
  name: string              // 用户名称
  mac: string               // 设备 MAC 地址
  ip: string                // 设备 IP 地址
  selected: boolean         // 是否已选中（用于 UI 选择）
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
}
