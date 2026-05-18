export class FormatUtils {
  static formatBytes(bytes: number): string {
    if (bytes === 0 || isNaN(bytes)) return '0 B'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const base = 1024
    const i = Math.floor(Math.log(bytes) / Math.log(base))
    if (i >= units.length) return `${(bytes / Math.pow(base, units.length - 1)).toFixed(1)} ${units[units.length - 1]}`
    return `${(bytes / Math.pow(base, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`
  }

  static formatSpeed(bytesPerSecond: number): string {
    return `${FormatUtils.formatBytes(bytesPerSecond)}/s`
  }

  static formatUptime(seconds: number): string {
    if (seconds < 60) return `${seconds}s`
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    return `${days}d ${hours}h`
  }

  static formatPercent(value: number): string {
    return `${Math.max(0, Math.min(100, value)).toFixed(1)}%`
  }

  static formatTemperature(celsius: number): string {
    return `${celsius.toFixed(1)}°C`
  }

  static formatMac(mac: string): string {
    if (!mac) return ''
    const cleaned = mac.replace(/[^0-9a-fA-F]/g, '')
    if (cleaned.length === 12) {
      return cleaned.match(/.{2}/g)!.join(':').toUpperCase()
    }
    return mac.toUpperCase()
  }

  static formatIp(ip: string): string {
    return ip || '--'
  }

  static truncate(str: string, maxLength: number): string {
    if (str.length <= maxLength) return str
    return str.substring(0, maxLength - 3) + '...'
  }

  static getVendorName(mac: string): string {
    if (!mac) return 'Unknown'
    const prefix = mac.replace(/[^0-9a-fA-F]/g, '').substring(0, 6).toUpperCase()
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

  static getDeviceIcon(mac: string, hostname: string): string {
    const name = hostname.toLowerCase()
    if (name.includes('phone') || name.includes('iphone') || name.includes('xiaomi') || name.includes('huawei') || name.includes('samsung')) return 'phone'
    if (name.includes('laptop') || name.includes('macbook') || name.includes('notebook') || name.includes('thinkpad')) return 'laptop'
    if (name.includes('tv') || name.includes('mi tv') || name.includes('smart tv')) return 'tv'
    if (name.includes('pi') || name.includes('raspberry')) return 'server'
    if (name.includes('camera') || name.includes('cam')) return 'camera'
    if (name.includes('printer')) return 'printer'
    if (name.includes('speaker') || name.includes('echo') || name.includes('alexa')) return 'speaker'
    if (name.includes('watch') || name.includes('band')) return 'watch'
    return 'device'
  }
}
