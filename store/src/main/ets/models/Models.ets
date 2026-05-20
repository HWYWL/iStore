export interface SystemInfo {
  hostname: string
  model: string
  kernel: string
  firmwareVersion: string
  localTime: string
  uptime: number
  cpuUsage: number
  memoryTotal: number
  memoryUsed: number
  memoryCached: number
  memoryAvailable: number
  storageTotal: number
  storageUsed: number
  cpuTemp: number
  boardName: string
  cpuModel: string
  distribution: string
  releaseVersion: string
  releaseRevision: string
  releaseTarget: string
}

export interface NetworkInterface {
  name: string
  type: 'wan' | 'lan' | 'wifi' | 'vpn'
  ipAddress: string
  netmask: string
  gateway: string
  macAddress: string
  mtu: number
  status: 'up' | 'down'
  rxBytes: number
  txBytes: number
  rxRate: number
  txRate: number
}

export interface WanStatus {
  interface: string
  uptime: number
  ipAddress: string
  gateway: string
  dns: string[]
  rxRate: number
  txRate: number
  onlineTime: string
}

export interface ConnectedDevice {
  mac: string
  ip: string
  hostname: string
  vendor: string
  interface: string
  onlineTime: string
  signalStrength: number
  rxRate: number
  txRate: number
  isOnline: boolean
}

export interface Plugin {
  id: string
  name: string
  displayName: string
  description: string
  version: string
  author: string
  category: string
  installed: boolean
  enabled: boolean
  running: boolean
  iconUrl: string
  size: string
}

export interface DhcpLease {
  mac: string
  ip: string
  hostname: string
  expiresAt: string
}

export interface TrafficHistory {
  timestamp: string
  rx: number
  tx: number
}

export interface ApiResponse<T> {
  code: number
  message: string
  data: T
}

export interface ConnectionConfig {
  host: string
  port: number
  username: string
  password: string
  useHttps: boolean
  token?: string
}

export interface LogEntry {
  time: string
  level: 'info' | 'warn' | 'error'
  module: string
  message: string
}

export interface WifiSettings {
  radio: string
  ssid: string
  channel: number
  bandwidth: string
  encryption: string
  password: string
  enabled: boolean
  hidden: boolean
}

export interface FirewallRule {
  name: string
  src: string
  dest: string
  proto: string
  port: string
  target: 'ACCEPT' | 'REJECT' | 'DROP'
  enabled: boolean
}

export interface MountPoint {
  device: string
  mountPoint: string
  filesystem: string
  size: number
  used: number
  available: number
  usedPercent: number
}

export interface ConntrackInfo {
  current: number
  max: number
  percent: number
}

export interface ProcessInfo {
  pid: number
  ppid: number
  name: string
  cpu: number
  mem: number
  memPercent: number
  status: string
  user: string
  command: string
}

export interface StartupItem {
  name: string
  priority: number
  enabled: boolean
  running: boolean
}

export interface RouteEntry {
  destination: string
  gateway: string
  device: string
  source: string
  scope: string
  table: string
  flags: string
}

export interface WirelessClient {
  mac: string
  hostname: string
  interface: string
  signal: number
  signalNoise: number
  rxRate: number
  txRate: number
  connectedTime: number
  inactiveTime: number
  isMesh: boolean
}

export interface WirelessDevice {
  name: string
  bssid: string
  ssid: string
  channel: number
  frequency: number
  bandwidth: string
  encryption: string
  signal: number
  quality: number
  mode: string
  up: boolean
  hwmode: string
  protocol: string
}

export interface RealtimeBandwidth {
  interface: string
  rx: RealtimeDataPoint[]
  tx: RealtimeDataPoint[]
}

export interface RealtimeLoad {
  load1: RealtimeDataPoint[]
  load5: RealtimeDataPoint[]
  load15: RealtimeDataPoint[]
}

export interface RealtimeDataPoint {
  time: string
  value: number
}

export interface OafStatus {
  pluginVersion: string
  engineVersion: string
  kernelVersion: string
  configStatus: string
  filterStatus: string
  engineStatus: string
  versionTooHigh: boolean
}

export interface AppFilterBase {
  appFilterEnabled: boolean
  appLogEnabled: boolean
  workMode: 'gateway' | 'bypass'
}

export interface AppClass {
  id: number
  name: string
  apps: AppItem[]
}

export interface AppItem {
  id: number
  name: string
  enabled: boolean
}

export interface AppFilterTime {
  fixedTimes: TimeSlot[]
  dynamicMinutes: number
  dynamicStartHour: number
  dynamicStartMin: number
  dynamicEndHour: number
  dynamicEndMin: number
  weekdays: number[]
}

export interface TimeSlot {
  startHour: number
  startMin: number
  endHour: number
  endMin: number
}

export interface AppFilterUser {
  mode: 'auto' | 'manual'
  users: OafUser[]
}

export interface OafUser {
  id: string
  name: string
  mac: string
  ip: string
  selected: boolean
}

export interface DeviceVisitTime {
  appId: number
  appName: string
  totalSeconds: number
  percent: number
}

export interface DeviceVisitRecord {
  appId: number
  appName: string
  startTime: string
  duration: number
}

export interface UserListItem {
  hostname: string
  mac: string
  ip: string
  currentApp: string
  currentUrl: string
  commonApps: number[]
}
