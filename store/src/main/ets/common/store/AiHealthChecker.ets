/**
 * AiHealthChecker - AI 智能健康巡检（单例）
 * 由 NotificationWatcher 每 60 秒调用一次，采集路由器健康指标，
 * 超过阈值时推送系统通知（同类型 24h 内去重）。
 *
 * 告警维度（阈值均可在「智能通知」页调整）：
 *  1. temp      CPU 温度过高（默认 >75°C）
 *  2. memory    内存占用过高（默认 >85%）
 *  3. cpu       CPU 使用率持续过高（默认 >90%）
 *  4. traffic   突发流量（下行速率 > 50Mbps）
 */
import { notificationManager } from '@kit.NotificationKit'
import { ApiService } from '../../api/ApiService'
import { NotifyStore } from './NotifyStore'
import { AppState } from './AppState'
import { SystemInfo } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'AiHealth'
const DOMAIN = 0x0001

// 固定阈值（温度/内存/CPU 阈值改为用户在「智能通知」里配置，见 NotifyStore）
const TRAFFIC_MBPS_WARN = 50 // 突发下行 Mbps

export class AiHealthChecker {
  private static instance: AiHealthChecker
  private api: ApiService = new ApiService()
  private notifyStore: NotifyStore = NotifyStore.getInstance()

  static getInstance(): AiHealthChecker {
    if (!AiHealthChecker.instance) {
      AiHealthChecker.instance = new AiHealthChecker()
    }
    return AiHealthChecker.instance
  }

  // ========== 智能告警 ==========

  /** 主入口：检查健康指标并推送异常通知（由 NotificationWatcher 周期调用） */
  async checkHealth(): Promise<void> {
    // 开关控制：总开关 + AI 健康告警开关
    if (!this.notifyStore.isEnabled() || !this.notifyStore.isAiHealthAlertOn()) return
    if (!AppState.getInstance().getActiveDeviceId()) return
    try {
      const sys: SystemInfo = await this.api.fetchSystemInfo()
      const today: string = this.today()
      const last: Record<string, string> = this.notifyStore.getLastAiAlerts()
      // ArkTS 不支持对象 spread，逐字段复制
      const fired: Record<string, string> = {}
      const keys: string[] = Object.keys(last)
      for (let i = 0; i < keys.length; i++) {
        fired[keys[i]] = last[keys[i]]
      }

      // 阈值来自用户配置（通知设置里可调）
      const tempWarn: number = this.notifyStore.getTempThreshold()
      const memWarn: number = this.notifyStore.getMemThreshold()
      const cpuWarn: number = this.notifyStore.getCpuThreshold()

      // —— 1. CPU 温度 ——
      if (sys.cpuTemp > tempWarn && last['temp'] !== today) {
        this.publish('temp', '🌡️ 路由器温度过高', `今天有点烫手：${sys.cpuTemp.toFixed(0)}°C（阈值 ${tempWarn}°C），建议给我透透气 🥵`)
        fired['temp'] = today
      }

      // —— 2. 内存占用 ——
      const memPct: number = sys.memoryTotal > 0 ? (sys.memoryUsed / sys.memoryTotal) * 100 : 0
      if (memPct > memWarn && last['memory'] !== today) {
        this.publish('memory', '💾 内存占用过高', `脑子快满了：已用 ${memPct.toFixed(0)}%（阈值 ${memWarn}%），重启一下我会舒服很多 💭`)
        fired['memory'] = today
      }

      // —— 3. CPU 使用率 ——
      if (sys.cpuUsage > cpuWarn && last['cpu'] !== today) {
        this.publish('cpu', '⚙️ CPU 高负载', `有点忙不过来：CPU ${sys.cpuUsage.toFixed(0)}%（阈值 ${cpuWarn}%），看看谁在跑任务吧 ⚙️`)
        fired['cpu'] = today
      }

      // —— 4. 突发流量 ——
      const mbps: number = await this.downMbps()
      if (mbps >= TRAFFIC_MBPS_WARN && last['traffic'] !== today) {
        this.publish('traffic', '🚀 突发大流量', `有人在下大东西：下行 ${mbps.toFixed(1)} Mbps，去看看谁在占带宽 🚀`)
        fired['traffic'] = today
      }

      this.notifyStore.setLastAiAlerts(fired)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `checkHealth err: ${JSON.stringify(e)}`)
    }
  }

  /** 当前下行速率（Mbps） */
  private async downMbps(): Promise<number> {
    try {
      const bytes: number[] = await this.api.fetchWanTrafficBytes()
      // 返回值约定：两次采样差 → 速率，此处复用 ApiService 内部实现
      if (bytes.length >= 2 && bytes[1] > 0) {
        return bytes[0] / 1024 / 1024  // 由调用侧换算
      }
      return 0
    } catch (e) {
      return 0
    }
  }

  // ========== 通知发布 ==========

  private async publish(type: string, title: string, text: string): Promise<void> {
    // 历史留痕（免打扰期间也记录）
    this.notifyStore.addHistory(type, title, text)
    // 免打扰时段内不弹系统通知
    if (this.notifyStore.isInQuietHours()) {
      hilog.info(DOMAIN, TAG, `quiet hours, suppressed: ${title}`)
      return
    }
    try {
      const req: notificationManager.NotificationRequest = {
        id: Math.floor(Date.now() % 90000) + 10000,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text
          }
        }
      }
      await notificationManager.publish(req)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `publish err: ${JSON.stringify(e)}`)
    }
  }

  private today(): string {
    const d: Date = new Date()
    return `${d.getFullYear()}-${this.pad(d.getMonth() + 1)}-${this.pad(d.getDate())}`
  }

  private pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }
}
