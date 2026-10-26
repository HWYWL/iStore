/**
 * NotificationWatcher - 智能通知与定时任务检测器（单例）
 * 由 MainPage 在前台时启停（start/stop），间隔 60 秒检测：
 * 1. 断网告警：路由器离线/恢复时发本地通知
 * 2. 新设备提醒：设备列表出现新 MAC 时发本地通知
 * 3. AI 健康告警：温度/内存/CPU/流量超阈值时发本地通知
 * 4. 定时任务：到点执行定时重启 / 定时开关 WiFi（App 运行期间有效）
 */
import { notificationManager } from '@kit.NotificationKit'
import { ApiService } from '../../api/ApiService'
import { NotifyStore } from './NotifyStore'
import { ScheduleStore, ScheduleTask } from './ScheduleStore'
import { AiHealthChecker } from './AiHealthChecker'
import { AppState } from './AppState'
import { ConnectedDevice } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'NotifyWatcher'
const DOMAIN = 0x0001
const CHECK_INTERVAL = 60 * 1000  // 60 秒

export class NotificationWatcher {
  private static instance: NotificationWatcher
  private timer: number = -1
  private detecting: boolean = false
  private api: ApiService = new ApiService()
  private notifyStore: NotifyStore = NotifyStore.getInstance()
  private scheduleStore: ScheduleStore = ScheduleStore.getInstance()

  static getInstance(): NotificationWatcher {
    if (!NotificationWatcher.instance) {
      NotificationWatcher.instance = new NotificationWatcher()
    }
    return NotificationWatcher.instance
  }

  /** 启动检测（App 前台时调用） */
  start(): void {
    if (this.timer !== -1) return
    this.timer = setInterval(() => {
      this.tick()
    }, CHECK_INTERVAL)
    // 启动后立即执行一次
    this.tick()
  }

  /** 停止检测（App 退后台/页面销毁时调用） */
  stop(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  isRunning(): boolean {
    return this.timer !== -1
  }

  private async tick(): Promise<void> {
    if (this.detecting) return
    this.detecting = true
    try {
      // 无活跃设备时跳过（需已连接路由器）
      if (!AppState.getInstance().getActiveDeviceId()) {
        return
      }
      await this.checkNotify()
      await this.checkHealth()
      await this.checkSchedule()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `tick err: ${JSON.stringify(e)}`)
    } finally {
      this.detecting = false
    }
  }

  // ========== 智能通知检测 ==========

  private async checkNotify(): Promise<void> {
    if (!this.notifyStore.isEnabled()) return
    // 在线检测
    const online: boolean = await this.api.isRouterOnline()
    const last: boolean | null = this.notifyStore.getLastOnline()

    if (this.notifyStore.isOfflineAlertOn()) {
      // 断网/恢复属于关键告警，不受免打扰限制
      if (last === true && !online) {
        // 上次在线 → 现在离线：断网告警
        this.publish('offline', '⚠️ 路由器离线', '检测到路由器连接中断，请检查网络或电源', true)
      } else if (last === false && online) {
        // 上次离线 → 现在在线：恢复通知
        this.publish('recover', '✅ 路由器已恢复', '路由器重新上线，网络已恢复正常', true)
      }
    }
    this.notifyStore.setLastOnline(online)

    // 新设备检测（仅在线时）
    if (online && this.notifyStore.isNewDeviceAlertOn()) {
      await this.checkNewDevices()
    }
  }

  private async checkNewDevices(): Promise<void> {
    try {
      const devices: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      if (devices.length === 0) return
      const known: string[] = this.notifyStore.getLastMacs()
      const knownSet: Set<string> = new Set()
      for (let i = 0; i < known.length; i++) {
        knownSet.add(known[i].toUpperCase())
      }
      const current: string[] = []
      const news: ConnectedDevice[] = []
      for (let i = 0; i < devices.length; i++) {
        const mac: string = devices[i].mac.toUpperCase()
        if (!mac) continue
        current.push(mac)
        if (!knownSet.has(mac)) {
          news.push(devices[i])
        }
      }
      // 有已知设备时才报警（首次建立基线不打扰）
      if (known.length > 0 && news.length > 0) {
        for (let i = 0; i < news.length; i++) {
          const dev: ConnectedDevice = news[i]
          const name: string = dev.hostname || dev.mac
          this.publish('newDevice', '🆕 新设备接入', `${name}（${dev.mac}）已连接到网络`, false)
        }
      }
      // 更新已知集合（保留最近 50 个，避免无限增长）
      const merged: string[] = current.slice(0, 50)
      this.notifyStore.setLastMacs(merged)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `checkNewDevices err: ${JSON.stringify(e)}`)
    }
  }

  // ========== AI 健康告警检测 ==========

  private async checkHealth(): Promise<void> {
    try {
      await AiHealthChecker.getInstance().checkHealth()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `checkHealth err: ${JSON.stringify(e)}`)
    }
  }

  // ========== 定时任务检测 ==========

  private async checkSchedule(): Promise<void> {
    const now: Date = new Date()
    const hhmm: string = `${this.pad(now.getHours())}:${this.pad(now.getMinutes())}`
    const today: string = this.yyyymmdd(now)
    // 0=周一 ... 6=周日
    const weekday: number = (now.getDay() + 6) % 7

    // 定时重启
    const reboot = this.scheduleStore.getRebootTask()
    if (reboot.enabled && this.matchTime(reboot, hhmm, weekday)) {
      if (this.scheduleStore.getLastExec('reboot') !== today) {
        this.scheduleStore.setLastExec('reboot', today)
        hilog.info(DOMAIN, TAG, 'schedule: reboot triggered')
        this.api.rebootDevice()
      }
    }

    // 定时关 WiFi
    const wifiOff = this.scheduleStore.getWifiOffTask()
    if (wifiOff.enabled && this.matchTime(wifiOff, hhmm, weekday)) {
      if (this.scheduleStore.getLastExec('wifiOff') !== today) {
        this.scheduleStore.setLastExec('wifiOff', today)
        hilog.info(DOMAIN, TAG, 'schedule: wifi off triggered')
        this.api.setAllWifiEnabled(false)
      }
    }

    // 定时开 WiFi
    const wifiOn = this.scheduleStore.getWifiOnTask()
    if (wifiOn.enabled && this.matchTime(wifiOn, hhmm, weekday)) {
      if (this.scheduleStore.getLastExec('wifiOn') !== today) {
        this.scheduleStore.setLastExec('wifiOn', today)
        hilog.info(DOMAIN, TAG, 'schedule: wifi on triggered')
        this.api.setAllWifiEnabled(true)
      }
    }
  }

  /** 时间与星期是否匹配 */
  private matchTime(task: ScheduleTask, hhmm: string, weekday: number): boolean {
    if (task.time !== hhmm) return false
    if (task.weekdays.length === 0) return true  // 每天
    return task.weekdays.indexOf(weekday) >= 0
  }

  // ========== 通知发布 ==========

  /**
   * 发布通知并记录到告警历史
   * @param bypassQuiet 关键告警（断网/恢复）不受免打扰限制
   */
  private async publish(type: string, title: string, text: string, bypassQuiet: boolean): Promise<void> {
    // 先入历史（免打扰期间也留痕，方便用户回看）
    this.notifyStore.addHistory(type, title, text)
    if (!bypassQuiet && this.notifyStore.isInQuietHours()) {
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

  private pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  private yyyymmdd(d: Date): string {
    return `${d.getFullYear()}-${this.pad(d.getMonth() + 1)}-${this.pad(d.getDate())}`
  }
}
