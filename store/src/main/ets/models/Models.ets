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
