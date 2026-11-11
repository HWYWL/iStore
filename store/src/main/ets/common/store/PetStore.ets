/**
 * PetStore — 小管家宠物状态存储
 * 饱食度/能量/心情/等级/XP/装扮 持久化；每日递减模拟饥饿
 */
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'PetStore'
const STORE_NAME = 'pet_store'

/** 任务对应的页面路线（顺序与 PetPage QUESTS 一致）：实际打开即视为完成 */
const TASK_ROUTES: string[] = [
  'pages/apps/NetworkCheckPage',
  'pages/apps/NetworkHelperPage',
  'pages/apps/TrafficReportPage',
  'pages/apps/DeviceActivityPage',
  'pages/security/SecurityHubPage'
]

/** 任务奖励能量（顺序与 TASK_ROUTES 一致） */
const TASK_ENERGY: number[] = [20, 15, 10, 10, 15]

/** 任务数据结构版本：升级时清掉旧版写死/测试污染的勾选 */
const TASK_SCHEMA = '3'

export interface PetState {
  level: number        // 等级（1-99）
  xp: number           // 当前等级经验（0-100）
  full: number         // 饱食度 0-100
  energy: number       // 能量 0-100
  mood: number         // 心情 0-100
  dress: boolean       // 深海蓝装扮开关（持久化）
  lastDay: string      // 上次更新日期（每日递减用）
}

export class PetStore {
  private static instance: PetStore
  private prefs: preferences.Preferences | null = null

  static getInstance(): PetStore {
    if (!PetStore.instance) {
      PetStore.instance = new PetStore()
    }
    return PetStore.instance
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs) return
    try {
      this.prefs = await preferences.getPreferences(ctx, STORE_NAME)
      this.resetTaskSchemaIfNeeded()
      this.applyDailyDecay()
      this.persistVisits()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `init err: ${String(e)}`)
    }
  }

  /** 任务数据升级：旧版勾选是写死/测试污染的，一次性清空 */
  private resetTaskSchemaIfNeeded(): void {
    if (!this.prefs) return
    try {
      const v: string = (this.prefs.getSync('task_schema', '') as string) || ''
      if (v !== TASK_SCHEMA) {
        this.prefs.putSync('task_flags', '[]')
        this.prefs.putSync('task_day', '')
        this.prefs.putSync('task_rewarded', '[]')
        this.prefs.putSync('task_rewarded_day', '')
        this.prefs.putSync('task_schema', TASK_SCHEMA)
        this.prefs.flush()
      }
    } catch (e) {}
  }

  /** 默认状态 */
  private defaultState(): PetState {
    return {
      level: 1, xp: 0, full: 80, energy: 50, mood: 85,
      dress: false, lastDay: this.today()
    }
  }

  getState(): PetState {
    if (!this.prefs) return this.defaultState()
    try {
      const raw: string = (this.prefs.getSync('state', '') as string) || ''
      if (!raw) {
        const s: PetState = this.defaultState()
        this.saveState(s)
        return s
      }
      const obj: PetState = JSON.parse(raw) as PetState
      if (obj.dress === undefined) {
        obj.dress = false
      }
      return obj
    } catch (e) {
      return this.defaultState()
    }
  }

  saveState(s: PetState): void {
    if (!this.prefs) return
    try {
      this.prefs.putSync('state', JSON.stringify(s))
      this.prefs.flush()
    } catch (e) {}
  }

  private today(): string {
    const d: Date = new Date()
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
  }

  /** 每日衰减：饱食 -15、心情 -8（未登录也会饿） */
  private applyDailyDecay(): void {
    if (!this.prefs) return
    try {
      const s: PetState = this.getState()
      if (s.lastDay === this.today()) return
      s.full = Math.max(0, s.full - 15)
      s.mood = Math.max(0, s.mood - 8)
      s.lastDay = this.today()
      this.saveState(s)
    } catch (e) {}
  }

  /** 喂数据：饱食 +15、XP +5 */
  feed(): PetState {
    const s: PetState = this.getState()
    s.full = Math.min(100, s.full + 15)
    this.addXp(s, 5)
    this.saveState(s)
    return s
  }

  /** 摸摸头：心情 +10、XP +3 */
  pat(): PetState {
    const s: PetState = this.getState()
    s.mood = Math.min(100, s.mood + 10)
    this.addXp(s, 3)
    this.saveState(s)
    return s
  }

  /** 深海蓝装扮开关（持久化，重启后保留；换装扮也给成长 XP） */
  setDress(on: boolean): PetState {
    const s: PetState = this.getState()
    s.dress = on
    this.addXp(s, 3)
    this.saveState(s)
    return s
  }

  /** 任务完成：能量 +n、XP +3 */
  completeTask(energy: number): PetState {
    const s: PetState = this.getState()
    s.energy = Math.min(100, s.energy + energy)
    this.addXp(s, 3)
    this.saveState(s)
    return s
  }

  // ========== 每日任务完成状态（持久化，每日重置） ==========
  /** 今日已完成任务索引数组（隔天自动归零） */
  getDoneTasks(): boolean[] {
    const done: boolean[] = [false, false, false, false, false]
    if (!this.prefs) return done
    try {
      const day: string = (this.prefs.getSync('task_day', '') as string) || ''
      if (day !== this.today()) return done
      const raw: string = (this.prefs.getSync('task_flags', '') as string) || ''
      if (raw) {
        const arr: boolean[] = JSON.parse(raw) as boolean[]
        for (let i = 0; i < arr.length && i < 5; i++) {
          done[i] = arr[i]
        }
      }
    } catch (e) {}
    return done
  }

  markTaskDone(idx: number): void {
    if (!this.prefs) return
    try {
      const done: boolean[] = this.getDoneTasks()
      if (idx >= 0 && idx < 5) {
        done[idx] = true
      }
      this.prefs.putSync('task_day', this.today())
      this.prefs.putSync('task_flags', JSON.stringify(done))
      this.prefs.flush()
    } catch (e) {}
  }

  // ========== 真实完成埋点：页面被实际打开才算完成 ==========
  /** 内存暂存访问记录（prefs 尚未就绪时也不会丢） */
  private routeVisits: string[] = []

  /** 页面访问埋点（由 AppNav 在真正跳转时调用） */
  markTaskByRoute(route: string): void {
    if (this.routeVisits.indexOf(route) < 0) {
      this.routeVisits.push(route)
    }
    this.persistVisits()
  }

  /**
   * 结算新完成任务的奖励（幂等）：同一任务只发一次能量与 XP，
   * 多个页面实例重复调用也不会重复加。
   * @returns 本次实际发放的能量值（0 表示无新奖励）
   */
  settleTasks(): number {
    if (!this.prefs) return 0
    try {
      if (((this.prefs.getSync('task_rewarded_day', '') as string) || '') !== this.today()) {
        this.prefs.putSync('task_rewarded_day', this.today())
        this.prefs.putSync('task_rewarded', '[]')
      }
      const done: boolean[] = this.getDoneTasks()
      const raw: string = (this.prefs.getSync('task_rewarded', '') as string) || ''
      const rewarded: boolean[] = [false, false, false, false, false]
      if (raw) {
        const arr: boolean[] = JSON.parse(raw) as boolean[]
        for (let i = 0; i < 5 && i < arr.length; i++) {
          rewarded[i] = arr[i] === true
        }
      }
      let gained: number = 0
      for (let i = 0; i < 5; i++) {
        if (done[i] && rewarded[i] !== true) {
          gained += TASK_ENERGY[i]
          rewarded[i] = true
        }
      }
      if (gained > 0) {
        const s: PetState = this.getState()
        s.energy = Math.min(100, s.energy + gained)
        this.addXp(s, 3)
        this.saveState(s)
        this.prefs.putSync('task_rewarded', JSON.stringify(rewarded))
        this.prefs.flush()
      }
      return gained
    } catch (e) {
      return 0
    }
  }

  /** 把暂存访问写入持久化任务状态 */
  persistVisits(): void {
    if (!this.prefs || this.routeVisits.length === 0) return
    for (let i = 0; i < TASK_ROUTES.length; i++) {
      if (this.routeVisits.indexOf(TASK_ROUTES[i]) >= 0) {
        this.markTaskDone(i)
      }
    }
  }

  /** 加经验（升级逻辑） */
  private addXp(s: PetState, n: number): void {
    s.xp += n
    while (s.xp >= 100) {
      s.xp -= 100
      s.level++
    }
  }
}
