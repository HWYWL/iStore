/**
 * 格式化工具类
 * 提供字节、速率、时间、温度、MAC 地址、设备类型判断等格式化方法
 * 所有方法均为静态方法，无需实例化
 */
export class FormatUtils {
  /**
   * 字节数格式化为人类可读的字符串
   * @param bytes 字节数
   * @returns 如 "1.5 GB"、"256 MB"、"0 B"
   */
  static formatBytes(bytes: number): string {
    // 特殊情况：0 或 NaN 直接返回
    if (bytes === 0 || isNaN(bytes)) return '0 B'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const base = 1024
    // 根据字节数计算应使用的单位级别
    const i = Math.floor(Math.log(bytes) / Math.log(base))
    // 超出最大单位时使用最大单位
    if (i >= units.length) return `${(bytes / Math.pow(base, units.length - 1)).toFixed(1)} ${units[units.length - 1]}`
    // B 级别不显示小数，其他保留 1 位小数
    return `${(bytes / Math.pow(base, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`
  }

  /**
   * 速率格式化（字节/秒）
   * @param bytesPerSecond 每秒字节数
   * @returns 如 "1.5 MB/s"
   */
  static formatSpeed(bytesPerSecond: number): string {
    return `${FormatUtils.formatBytes(bytesPerSecond)}/s`
  }

  /**
   * 运行时长格式化（秒 → 天/时/分/秒）
   * @param seconds 秒数
   * @returns 如 "3天 12时 5分 30秒"
   */
  static formatUptime(seconds: number): string {
    if (seconds < 60) return `${seconds}秒`
    if (seconds < 3600) return `${Math.floor(seconds / 60)}分 ${seconds % 60}秒`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}时 ${Math.floor((seconds % 3600) / 60)}分`
    // ≥ 1 天时显示完整格式
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const secs = seconds % 60
    return `${days}天 ${hours}时 ${minutes}分 ${secs}秒`
  }

  /**
   * 百分比格式化（限制 0-100 范围）
   * @param value 百分比数值（可能超出范围）
   * @returns 如 "85.5%"
   */
  static formatPercent(value: number): string {
    return `${Math.max(0, Math.min(100, value)).toFixed(1)}%`
  }

  /**
   * 温度格式化
   * @param celsius 摄氏温度
   * @returns 如 "45.2°C"
   */
  static formatTemperature(celsius: number): string {
    return `${celsius.toFixed(1)}°C`
  }

  /**
   * MAC 地址格式化：统一转大写，冒号分隔
   * @param mac 原始 MAC 地址（可能是各种格式）
   * @returns 如 "B8:27:EB:XX:XX:XX"
   */
  static formatMac(mac: string): string {
    if (!mac) return ''
    // 移除所有非十六进制字符
    const cleaned = mac.replace(/[^0-9a-fA-F]/g, '')
    // 标准 12 位 MAC 地址按每 2 位加冒号
    if (cleaned.length === 12) {
      return cleaned.match(/.{2}/g)!.join(':').toUpperCase()
    }
    // 非标准格式直接转大写返回
    return mac.toUpperCase()
  }

  /**
   * IP 地址格式化（空值兜底）
   * @param ip IP 地址
   * @returns 有效 IP 或 "--"
   */
  static formatIp(ip: string): string {
    return ip || '--'
  }

  /**
   * 字符串截断（超出长度加省略号）
   * @param str 原始字符串
   * @param maxLength 最大长度
   * @returns 截断后的字符串
   */
  static truncate(str: string, maxLength: number): string {
    if (str.length <= maxLength) return str
    return str.substring(0, maxLength - 3) + '...'
  }

  /**
   * 根据 MAC 地址前缀识别设备厂商
   * @param mac MAC 地址
   * @returns 厂商名称或 "Unknown"
   */
  static getVendorName(mac: string): string {
    if (!mac) return 'Unknown'
    // 取 MAC 地址前 6 位（OUI 厂商识别码）
    const prefix = mac.replace(/[^0-9a-fA-F]/g, '').substring(0, 6).toUpperCase()
    // 常见厂商 OUI 映射表
    const vendors: Record<string, string> = {
      'B827EB': 'Raspberry Pi',
      'DC4EDE': 'Apple',
      'A41F72': 'Apple',
      'F8FFC2': 'Apple',
      '001DD8': 'Intel',
      '3C5EC3': 'Intel',
      'C8D9D2': 'Xiaomi',
      '38DE60': 'Xiaomi',
      '70B3D5': 'Samsung',
      'D0176A': 'Samsung',
      'E45F01': 'Huawei',
      '58CB52': 'Huawei',
      '7C03AB': 'Google',
      'DC16B2': 'TP-Link',
      '14CC20': 'Asus',
      '04D4C4': 'Netgear',
      '000625': 'Linksys',
      '40B034': 'Sony',
      'B42A39': 'Microsoft',
      '00E04C': 'Realtek'
    }
    return vendors[prefix] || 'Unknown'
  }

  /**
   * 根据设备名称或 MAC 判断设备类型图标
   * @param mac 设备 MAC 地址
   * @param hostname 设备主机名
   * @returns 设备类型标识字符串（phone/laptop/tv/server/camera/printer/speaker/watch/device）
   */
  static getDeviceIcon(mac: string, hostname: string): string {
    const name = hostname.toLowerCase()
    // 根据主机名关键词判断设备类型
    if (name.includes('phone') || name.includes('iphone') || name.includes('xiaomi') || name.includes('huawei') || name.includes('samsung')) return 'phone'
    if (name.includes('laptop') || name.includes('macbook') || name.includes('notebook') || name.includes('thinkpad')) return 'laptop'
    if (name.includes('tv') || name.includes('mi tv') || name.includes('smart tv')) return 'tv'
    if (name.includes('pi') || name.includes('raspberry')) return 'server'
    if (name.includes('camera') || name.includes('cam')) return 'camera'
    if (name.includes('printer')) return 'printer'
    if (name.includes('speaker') || name.includes('echo') || name.includes('alexa')) return 'speaker'
    if (name.includes('watch') || name.includes('band')) return 'watch'
    // 无法识别时返回通用设备图标
    return 'device'
  }
}
