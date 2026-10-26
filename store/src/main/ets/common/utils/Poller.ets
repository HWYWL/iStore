/**
 * Poller - 统一轮询器
 *
 * 解决页面各自 setInterval 带来的三个问题：
 * 1. 可见性门控：visible 回调返回 false 时跳过本次轮询（省电、后台不偷跑请求）
 * 2. 请求叠加：上一次任务未结束时跳过本次触发（弱网下不会越堆越多）
 * 3. 生命周期：dispose() 一次性清理，避免忘记 clearInterval 造成内存泄漏
 *
 * 用法：
 *   this.poller = new Poller(() => this.refresh(), 5000)
 *   this.poller.start()            // 启动定时器
 *   this.poller.start(true)        // 启动并立即执行一次
 *   this.poller.trigger()          // 手动立即刷新（同样受可见性与进行中锁约束）
 *   this.poller.dispose()          // aboutToDisappear 中调用
 */
export class Poller {
  private task: () => void | Promise<void>
  private intervalMs: number
  private visible: (() => boolean) | null
  private timerId: number = -1
  private inFlight: boolean = false
  private disposed: boolean = false

  constructor(task: () => void | Promise<void>, intervalMs: number, visible?: () => boolean) {
    this.task = task
    this.intervalMs = intervalMs > 0 ? intervalMs : 1000
    this.visible = visible !== undefined ? visible : null
  }

  /** 启动定时轮询（幂等，重复调用不会叠加定时器） */
  start(immediate: boolean = false): void {
    if (this.disposed) {
      return
    }
    if (immediate) {
      this.trigger()
    }
    if (this.timerId !== -1) {
      return
    }
    this.timerId = setInterval(() => {
      this.trigger()
    }, this.intervalMs)
  }

  /** 暂停定时轮询（保留实例，可再次 start） */
  stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  /** 彻底释放（aboutToDisappear 调用，释放后不可再用） */
  dispose(): void {
    this.stop()
    this.disposed = true
    this.visible = null
  }

  isRunning(): boolean {
    return this.timerId !== -1
  }

  isBusy(): boolean {
    return this.inFlight
  }

  /** 立即执行一次：可见性不通过或上一次仍在执行时直接跳过 */
  async trigger(): Promise<void> {
    if (this.disposed || this.inFlight || !this.checkVisible()) {
      return
    }
    this.inFlight = true
    try {
      await this.task()
    } finally {
      this.inFlight = false
    }
  }

  private checkVisible(): boolean {
    if (this.visible === null) {
      return true
    }
    try {
      return this.visible()
    } catch (e) {
      return true
    }
  }
}
