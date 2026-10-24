/**
 * AiHelper - 网络助手（本地规则引擎）
 * 关键词匹配 → 拉取路由器实时数据 → 生成自然语言回答
 */
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice, SystemInfo, WanStatus, ConntrackInfo } from '../../models/Models'
import { FormatUtils } from '../utils/FormatUtils'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'AiHelper'

/** 聊天消息 */
export interface ChatMsg {
  role: string   // 'user' | 'ai'
  text: string
}

export class AiHelper {
  private static api: ApiService = new ApiService()

  /** 处理用户提问，返回 AI 回答 */
  static async ask(question: string): Promise<string> {
    const q: string = question.trim().toLowerCase()
    try {
      // —— 谁在占带宽 / 流量排行 ——
      if (AiHelper.matchAny(q, ['谁在占', '占带宽', '占网速', '谁在下载', '流量大', '下载最多', '谁在用网', '流量排行', '谁跑流量'])) {
        return await AiHelper.answerTopTraffic()
      }
      // —— 设备数量 ——
      if (AiHelper.matchAny(q, ['多少设备', '几个设备', '多少台', '设备数量', '在线设备', '几台设备', '有多少设备', '设备列表'])) {
        return await AiHelper.answerDevices()
      }
      // —— 网络卡 / 慢 ——
      if (AiHelper.matchAny(q, ['网络卡', '网速慢', '为什么慢', '卡顿', '延迟高', '网不好', '断网', '老掉线', '不稳定'])) {
        return await AiHelper.answerSlow()
      }
      // —— 安全 / 陌生设备 ——
      if (AiHelper.matchAny(q, ['陌生', '安全', '新设备', '风险', '入侵', '被蹭网', '不认识', '可疑', '黑客'])) {
        return await AiHelper.answerSecurity()
      }
      // —— 温度 ——
      if (AiHelper.matchAny(q, ['温度', '发烫', '热不热', 'cpu温度', '多少度'])) {
        return await AiHelper.answerTemp()
      }
      // —— 实时速度 ——
      if (AiHelper.matchAny(q, ['速度', '下载速度', '上传速度', '多少兆', '跑多快', '带宽'])) {
        return await AiHelper.answerSpeed()
      }
      // —— 帮助 ——
      if (AiHelper.matchAny(q, ['你是谁', '能做什么', '帮助', '怎么用', '功能', 'hello', 'hi', '你好', '在吗'])) {
        return AiHelper.answerHelp()
      }
      // —— 默认：引导用户使用支持的问法 ——
      return AiHelper.answerDefault()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ask err: ${JSON.stringify(e)}`)
      return '抱歉，查询数据时出错了，请检查设备是否已连接。'
    }
  }

  /** 关键词匹配（任一命中） */
  private static matchAny(q: string, keywords: string[]): boolean {
    for (let i = 0; i < keywords.length; i++) {
      if (q.indexOf(keywords[i]) >= 0) {
        return true
      }
    }
    return false
  }

  /** 谁在占带宽 */
  private static async answerTopTraffic(): Promise<string> {
    const devices: ConnectedDevice[] = await AiHelper.api.fetchConnectedDevices()
    const online: ConnectedDevice[] = devices.filter((d: ConnectedDevice) => d.isOnline)
    if (online.length === 0) {
      return '当前没有在线设备，看起来大家都在休息 😴'
    }
    const sorted: ConnectedDevice[] = [...online].sort((a: ConnectedDevice, b: ConnectedDevice) => {
      return (b.rxRate + b.txRate) - (a.rxRate + a.txRate)
    })
    const top: ConnectedDevice[] = sorted.slice(0, 5)
    let text: string = `当前 ${online.length} 台设备在线，流量消耗 TOP ${top.length}：\n`
    for (let i = 0; i < top.length; i++) {
      const d: ConnectedDevice = top[i]
      const name: string = AiHelper.devName(d)
      const total: number = d.rxRate + d.txRate
      if (total <= 0) {
        text += `${i + 1}. ${name}：空闲\n`
      } else {
        text += `${i + 1}. ${name}：↓${FormatUtils.formatSpeed(d.rxRate)} ↑${FormatUtils.formatSpeed(d.txRate)}\n`
      }
    }
    const totalRate: number = online.reduce((s: number, d: ConnectedDevice) => s + d.rxRate + d.txRate, 0)
    text += `全网实时速率约 ${FormatUtils.formatSpeed(totalRate)}`
    return text
  }

  /** 设备数量 */
  private static async answerDevices(): Promise<string> {
    const devices: ConnectedDevice[] = await AiHelper.api.fetchConnectedDevices()
    const online: ConnectedDevice[] = devices.filter((d: ConnectedDevice) => d.isOnline)
    const wifi: ConnectedDevice[] = online.filter((d: ConnectedDevice) => AiHelper.isWireless(d))
    const wired: ConnectedDevice[] = online.filter((d: ConnectedDevice) => !AiHelper.isWireless(d))
    let text: string = `共发现 ${devices.length} 台设备，其中在线 ${online.length} 台：\n`
    text += `📶 无线 ${wifi.length} 台 · 🔌 有线 ${wired.length} 台\n`
    if (online.length > 0) {
      const names: string[] = online.slice(0, 8).map((d: ConnectedDevice) => AiHelper.devName(d))
      text += `在线设备：${names.join('、')}${online.length > 8 ? ' 等' : ''}`
    }
    return text
  }

  /** 网络卡顿分析 */
  private static async answerSlow(): Promise<string> {
    try {
      const sysP: Promise<SystemInfo> = AiHelper.api.fetchSystemInfo()
      const connP: Promise<ConntrackInfo> = AiHelper.api.fetchConntrackInfo()
      const devP: Promise<ConnectedDevice[]> = AiHelper.api.fetchConnectedDevices()
      const sys: SystemInfo = await sysP
      const conntrack: ConntrackInfo = await connP
      const devices: ConnectedDevice[] = await devP
      const online: ConnectedDevice[] = devices.filter((d: ConnectedDevice) => d.isOnline)
      const totalRate: number = online.reduce((s: number, d: ConnectedDevice) => s + d.rxRate + d.txRate, 0)
      let text: string = '我帮你检查了路由器状态：\n'
      text += `CPU 使用率 ${sys.cpuUsage.toFixed(1)}%，内存 ${AiHelper.memPct(sys)}%`
      if (sys.cpuTemp > 0) {
        text += `，温度 ${sys.cpuTemp.toFixed(0)}°C`
      }
      text += `\n连接数 ${conntrack.current}（上限 ${conntrack.max}）`
      text += `，全网当前速率 ${FormatUtils.formatSpeed(totalRate)}\n`
      const busy: ConnectedDevice[] = [...online].sort((a: ConnectedDevice, b: ConnectedDevice) =>
        (b.rxRate + b.txRate) - (a.rxRate + a.txRate)).filter((d: ConnectedDevice) => d.rxRate + d.txRate > 500 * 1024)
      if (sys.cpuUsage > 80) {
        text += '⚠️ CPU 负载较高，可能成为瓶颈'
      } else if (conntrack.percent > 80) {
        text += '⚠️ 连接数接近上限，建议重启路由器'
      } else if (busy.length > 0) {
        text += `当前流量大户：${busy.slice(0, 3).map((d: ConnectedDevice) =>
          `${AiHelper.devName(d)}(${FormatUtils.formatSpeed(d.rxRate + d.txRate)})`).join('、')}`
      } else {
        text += '路由器自身状态良好，建议检查宽带线路或运营商侧问题'
      }
      return text
    } catch (e) {
      return '检查网络状态失败，请确认设备已连接。'
    }
  }

  /** 安全 / 陌生设备 */
  private static async answerSecurity(): Promise<string> {
    const devices: ConnectedDevice[] = await AiHelper.api.fetchConnectedDevices()
    const online: ConnectedDevice[] = devices.filter((d: ConnectedDevice) => d.isOnline)
    if (online.length === 0) {
      return '当前没有在线设备，网络安全状态良好 ✅'
    }
    // 陌生设备：无主机名且接口为无线（可能是蹭网设备）
    const suspicious: ConnectedDevice[] = online.filter((d: ConnectedDevice) =>
      (!d.hostname || d.hostname === '') && AiHelper.isWireless(d))
    let text: string = `当前在线 ${online.length} 台设备。`
    if (suspicious.length > 0) {
      text += `\n⚠️ 发现 ${suspicious.length} 台未识别名称的无线设备，可能是陌生设备：\n`
      for (let i = 0; i < suspicious.length; i++) {
        text += `${i + 1}. ${suspicious[i].mac}（${suspicious[i].vendor || '未知厂商'}）\n`
      }
      text += '建议到"设备"页检查，必要时可禁用其联网或踢下线'
    } else {
      text += '\n所有在线设备都有可识别的主机名，暂未发现明显异常 ✅'
      text += '\n（提示：安全判断基于设备名称，建议定期检查）'
    }
    return text
  }

  /** 温度 */
  private static async answerTemp(): Promise<string> {
    const sys: SystemInfo = await AiHelper.api.fetchSystemInfo()
    if (sys.cpuTemp <= 0) {
      return '当前设备未提供温度传感器数据，无法显示。'
    }
    const t: number = sys.cpuTemp
    let status: string = ''
    if (t < 50) status = '非常凉爽，状态健康 ✅'
    else if (t < 70) status = '正常温度，运行稳定 👍'
    else if (t < 85) status = '偏高，注意通风散热 ⚠️'
    else status = '过热！建议检查散热或降低负载 🔥'
    return `当前路由器温度 ${t.toFixed(0)}°C，${status}`
  }

  /** 实时速度 */
  private static async answerSpeed(): Promise<string> {
    const lan: WanStatus = await AiHelper.api.fetchLanStatus()
    const down: number = lan.rxRate
    const up: number = lan.txRate
    return `当前实时速率：\n↓ 下载 ${FormatUtils.formatSpeed(down)}\n↑ 上传 ${FormatUtils.formatSpeed(up)}\n（数据每 5 秒刷新）`
  }

  /** 帮助 */
  private static answerHelp(): string {
    return '我是 iStore 网络助手 🤖\n你可以问我：\n' +
      '📊 "谁在占带宽？" —— 查看流量消耗排行\n' +
      '📶 "有多少设备？" —— 在线设备统计\n' +
      '🐌 "网络为什么卡？" —— 路由器状态诊断\n' +
      '🛡 "有没有陌生设备？" —— 安全检查\n' +
      '🌡 "路由器温度多少？" —— 温度监控\n' +
      '⚡ "下载速度多少？" —— 实时速率'
  }

  /** 默认回答（未命中关键词时引导） */
  private static answerDefault(): string {
    return '这个问题我还不太会 😅 你可以试试问我：\n' +
      '"谁在占带宽" / "多少设备" / "网络为什么卡" / "有没有陌生设备" / "温度多少" / "下载速度"'
  }

  /** 设备显示名 */
  private static devName(d: ConnectedDevice): string {
    return d.hostname || d.vendor || d.mac
  }

  /** 是否无线设备 */
  private static isWireless(d: ConnectedDevice): boolean {
    const ifLower: string = (d.interface || '').toLowerCase()
    return ifLower.startsWith('wlan') || ifLower.startsWith('phy') ||
      ifLower.startsWith('radio') || ifLower.startsWith('wl')
  }

  /** 内存占用率 */
  private static memPct(sys: SystemInfo): number {
    if (sys.memoryTotal <= 0) return 0
    return Math.round(sys.memoryUsed / sys.memoryTotal * 100)
  }
}
