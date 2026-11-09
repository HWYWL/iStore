/**
 * LiveRateStore - 全局实时速率心跳
 *
 * 首页仪表盘、应用中心 Bento 主卡、小管家网络流量共用同一份上下行速率，
 * 统一按 LIVE_REFRESH_MS 刷新，避免同屏三处各拉一次导致数字错拍。
 *
 * 用法：
 *   const cb: RateListener = (rx, tx) => { ... }
 *   LiveRateStore.getInstance().subscribe(cb)     // 立即回调一次 + 启动心跳
 *   LiveRateStore.getInstance().unsubscribe(cb)   // aboutToDisappear 调用
 *   LiveRateStore.getInstance().push(rx, tx)      // 页面自己有最新值时顺手广播
 */
import { ApiService } from '../../api/ApiService'
import { WanStatus } from '../../models/Models'
import { AppState } from './AppState'
import { LIVE_REFRESH_MS } from '../utils/RefreshRate'

/** 速率监听回调（单位 B/s） */
export type RateListener = (rxRate: number, txRate: number) => void

export class LiveRateStore {
  private static instance: LiveRateStore | null = null
  private listeners: RateListener[] = []
  private rxRate: number = 0
  private txRate: number = 0
  private stamp: number = 0
  private timerId: number = -1
  private inFlight: boolean = false

  static getInstance(): LiveRateStore {
    if (LiveRateStore.instance === null) {
      LiveRateStore.instance = new LiveRateStore()
    }
    return LiveRateStore.instance
  }

  getRxRate(): number {
    return this.rxRate
  }

  getTxRate(): number {
    return this.txRate
  }

  /** 拿到最新值的页面（如首页轮询）顺手推送，立即广播给所有订阅者 */
  push(rxRate: number, txRate: number): void {
    this.rxRate = rxRate
    this.txRate = txRate
    this.stamp = Date.now()
    this.emit()
  }

  /** 订阅：立即回调一次当前值，并在有人订阅时启动 5 秒心跳 */
  subscribe(cb: RateListener): void {
    if (this.listeners.indexOf(cb) < 0) {
      this.listeners.push(cb)
    }
    cb(this.rxRate, this.txRate)
    this.start()
  }

  /** 退订：最后一个订阅者离开时停掉心跳 */
  unsubscribe(cb: RateListener): void {
    const i: number = this.listeners.indexOf(cb)
    if (i >= 0) {
      this.listeners.splice(i, 1)
    }
    if (this.listeners.length === 0) {
      this.stop()
    }
  }

  private start(): void {
    if (this.timerId !== -1) {
      return
    }
    this.tick()
    this.timerId = setInterval(() => {
      this.tick()
    }, LIVE_REFRESH_MS)
  }

  private stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  /** 心跳：5 秒内已有外部推送（首页在轮询）就直接复用，不再重复请求路由器 */
  private async tick(): Promise<void> {
    if (this.inFlight) {
      return
    }
    if (Date.now() - this.stamp < LIVE_REFRESH_MS * 0.9) {
      return
    }
    if (!AppState.getInstance().isConnected()) {
      return
    }
    this.inFlight = true
    try {
      const wan: WanStatus = await ApiService.getInstance().fetchLanStatus()
      this.rxRate = wan.rxRate
      this.txRate = wan.txRate
      this.stamp = Date.now()
      this.emit()
    } catch (e) {
    } finally {
      this.inFlight = false
    }
  }

  private emit(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](this.rxRate, this.txRate)
      } catch (e) {
      }
    }
  }
}
