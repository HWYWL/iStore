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

/** 小时粒度流量（0~23 点），用于 24 小时分布 / 历史曲线 */
export interface HourTraffic {
  hour: number       // 0~23
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

      // 同时写入小时桶（24 点分布 / 历史曲线用）
      const hour: number = new Date().getHours()
      const hours: number[][] = this.loadHourArray(date)
      const curHour: number[] = hours[hour]
      hours[hour] = [(curHour[0] || 0) + rx, (curHour[1] || 0) + tx]
      this.prefs.putSync(`hour_${date}`, JSON.stringify(hours))
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

  /** 今日累计流量（下载 + 上传，字节） */
  getTodayTotal(): number {
    const d: DayTraffic = this.getDay(this.today())
    return d.rx + d.tx
  }

  /** 读取某天的小时桶（固定 24 个 [rx,tx]，缺失补 0） */
  private loadHourArray(date: string): number[][] {
    const arr: number[][] = []
    for (let h = 0; h < 24; h++) {
      arr.push([0, 0])
    }
    if (!this.prefs) return arr
    try {
      const v: string = this.prefs.getSync(`hour_${date}`, '') as string
      if (!v) return arr
      const parsed = JSON.parse(v) as number[][]
      for (let h = 0; h < 24 && h < parsed.length; h++) {
        const pair = parsed[h]
        if (Array.isArray(pair) && pair.length >= 2) {
          arr[h] = [Number(pair[0]) || 0, Number(pair[1]) || 0]
        }
      }
    } catch (e) {
      // 解析失败按空数据处理，不影响主流程
      hilog.warn(DOMAIN, TAG, `loadHourArray err: ${JSON.stringify(e)}`)
    }
    return arr
  }

  /**
   * 获取某天 24 小时流量分布
   * @param date YYYY-MM-DD，默认今天
   */
  getHourly(date?: string): HourTraffic[] {
    const key: string = date ? date : this.today()
    const arr: number[][] = this.loadHourArray(key)
    const out: HourTraffic[] = []
    for (let h = 0; h < 24; h++) {
      out.push({ hour: h, rx: arr[h][0], tx: arr[h][1] })
    }
    return out
  }

  /** 今日 24 小时流量分布 */
  getTodayHourly(): HourTraffic[] {
    return this.getHourly(this.today())
  }

  /**
   * 区间内的分时趋势：把最近 N 天的小时桶按小时累加，得到 24 点分布
   * @param days 天数（如 7 = 近 7 天最活跃时段）
   */
  getHourlyTrend(days: number): HourTraffic[] {
    const out: HourTraffic[] = []
    for (let h = 0; h < 24; h++) {
      out.push({ hour: h, rx: 0, tx: 0 })
    }
    const list: DayTraffic[] = this.getDays(days)
    for (let i = 0; i < list.length; i++) {
      const arr: number[][] = this.loadHourArray(list[i].date)
      for (let h = 0; h < 24; h++) {
        out[h].rx += arr[h][0]
        out[h].tx += arr[h][1]
      }
    }
    return out
  }

  /** 清理超出保留天数的旧数据（天桶 + 小时桶） */
  private cleanup(): void {
    if (!this.prefs) return
    try {
      const cutoff: Date = new Date(Date.now() - MAX_DAYS * 86400000)
      const cutoffDate: string = this.dateKey(cutoff)
      const allKeys: string[] = this.prefs.getAllSync() ? Object.keys(this.prefs.getAllSync() as Object) : []
      for (let i = 0; i < allKeys.length; i++) {
        const k: string = allKeys[i]
        if (k.startsWith('day_') && k < `day_${cutoffDate}`) {
          this.prefs.deleteSync(k)
        } else if (k.startsWith('hour_') && k < `hour_${cutoffDate}`) {
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
