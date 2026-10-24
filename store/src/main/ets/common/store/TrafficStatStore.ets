/**
 * TrafficStatStore - 每日流量统计存储（单例）
 * 按天累计下载/上传字节数，保留最近 60 天
 * 由 DashboardTab 轮询时通过累计字节差值增量累加
 */
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'TrafficStatStore'
const DOMAIN = 0x0001
const STORE_NAME = 'iStore_traffic'
const MAX_DAYS = 60

export interface DayTraffic {
  date: string       // YYYY-MM-DD
  rx: number         // 下载字节
  tx: number         // 上传字节
}

export class TrafficStatStore {
  private static instance: TrafficStatStore
  private prefs: preferences.Preferences | null = null

  static getInstance(): TrafficStatStore {
    if (!TrafficStatStore.instance) {
      TrafficStatStore.instance = new TrafficStatStore()
    }
    return TrafficStatStore.instance
  }

  async init(context: Context): Promise<void> {
    if (this.prefs) return
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Init failed: ${JSON.stringify(e)}`)
    }
  }

  /** 当天累计增加流量（字节） */
  addToday(rx: number, tx: number): void {
    if (!this.prefs) return
    if (rx < 0) rx = 0
    if (tx < 0) tx = 0
    try {
      const date: string = this.today()
      const key: string = `day_${date}`
      const cur: DayTraffic = this.getDay(date)
      const rec: DayTraffic = {
        date: date,
        rx: cur.rx + rx,
        tx: cur.tx + tx
      }
      this.prefs.putSync(key, JSON.stringify(rec))
      // 清理过期数据（保留最近 MAX_DAYS 天）
      this.cleanup()
      this.prefs.flush()
      hilog.info(DOMAIN, TAG, `addToday +${rx}/+${tx} => ${date} total=${rec.rx}/${rec.tx}`)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `addToday err: ${JSON.stringify(e)}`)
    }
  }

  /** 获取指定日期流量 */
  getDay(date: string): DayTraffic {
    if (!this.prefs) return { date: date, rx: 0, tx: 0 }
    try {
      const key: string = `day_${date}`
      const v: string = this.prefs.getSync(key, '') as string
      if (!v) return { date: date, rx: 0, tx: 0 }
      const rec = JSON.parse(v) as Record<string, Object>
      return {
        date: date,
        rx: (rec['rx'] as number) || 0,
        tx: (rec['tx'] as number) || 0
      }
    } catch (e) {
      return { date: date, rx: 0, tx: 0 }
    }
  }

  /** 获取最近 N 天流量（含今天，按日期升序） */
  getDays(count: number): DayTraffic[] {
    const result: DayTraffic[] = []
    const today: Date = new Date()
    for (let i = count - 1; i >= 0; i--) {
      const d: Date = new Date(today.getTime() - i * 86400000)
      result.push(this.getDay(this.dateKey(d)))
    }
    return result
  }

  /** 清理超出保留天数的旧数据 */
  private cleanup(): void {
    if (!this.prefs) return
    try {
      const cutoff: Date = new Date(Date.now() - MAX_DAYS * 86400000)
      const cutoffKey: string = `day_${this.dateKey(cutoff)}`
      const allKeys: string[] = this.prefs.getAllSync() ? Object.keys(this.prefs.getAllSync() as Object) : []
      for (let i = 0; i < allKeys.length; i++) {
        const k: string = allKeys[i]
        if (k.startsWith('day_') && k < cutoffKey) {
          this.prefs.deleteSync(k)
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `cleanup err: ${JSON.stringify(e)}`)
    }
  }

  private today(): string {
    return this.dateKey(new Date())
  }

  private dateKey(d: Date): string {
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
  }
}
