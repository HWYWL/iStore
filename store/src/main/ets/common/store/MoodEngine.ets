/**
 * MoodEngine — 小管家「心情小话」文案引擎
 *
 * 按路由器实时状态（温度 / 负载 / 内存 / 网速 / 运行天数）和养成状态（心情值 / 等级）
 * 生成状态相关文案，再叠加一批日常闲聊，共 20 条上下；
 * 每次轮播优先（65%）从状态相关文案里挑，避开上一条，所以既贴合实际又不会重复。
 *
 * 文案长度统一控制在 14 字以内（气泡单行显示，前缀「☀ 心情 · 」占 6 字）。
 */
import { FormatUtils } from '../utils/FormatUtils'

/** 生成心情文案所需的上下文 */
export interface MoodState {
  /** 是否已连上路由器 */
  connected: boolean
  /** CPU 使用率 % */
  cpu: number
  /** 内存占用 % */
  memPct: number
  /** CPU 温度 ℃（0 = 未知） */
  temp: number
  /** 连续运行天数 */
  uptimeDays: number
  /** 实时下载 B/s */
  rxRate: number
  /** 实时上传 B/s */
  txRate: number
  /** 小管家心情值 0-100 */
  petMood: number
  /** 小管家等级 */
  level: number
}

/** 与状态无关的日常闲聊（保证文案池始终有十几条） */
const CHITCHAT: string[] = [
  '每个数据包我都盯着，一个不丢',
  '刚有个包路过，我数了一下',
  '想喝口水…不对，我是路由器',
  '夜里我也不睡，就守着你的 WiFi',
  '今天也请多指教，小管在线',
  '别关我电源，我还没玩够',
  '你上次摸我头，我记着呢',
  '偷看了你的流量报表，挺能刷',
  '你每次刷新，我都在偷看',
  '别把我和微波炉放一起，胆小',
  '我最大的愿望就是不断网',
  '我也会累，只是我不说'
]

/** 按当前状态生成「有话说」的文案（不含闲聊） */
function statePool(s: MoodState): string[] {
  const pool: string[] = []

  if (!s.connected) {
    pool.push('连不上路由器，我有点慌…')
    pool.push('小管失联中，检查下网络？')
    return pool
  }

  const cpu: number = Math.round(s.cpu)
  const mem: number = Math.round(s.memPct)
  const temp: number = Math.round(s.temp)
  const totalRate: number = s.rxRate + s.txRate
  const rateText: string = FormatUtils.formatSpeed(totalRate)

  // ---- 温度 ----
  if (temp >= 68) {
    pool.push(`${temp}℃ 了，快给我吹吹风`)
    pool.push('烫手…小管快融化了')
  } else if (temp >= 58) {
    pool.push(`有点热，${temp}℃，还能扛`)
  } else if (temp > 0 && temp <= 38) {
    pool.push(`体温 ${temp}℃，凉凉爽爽`)
  }

  // ---- CPU ----
  if (cpu >= 85) {
    pool.push(`CPU ${cpu}%，我在拼命算包`)
    pool.push('脑子转冒烟了，让我缓缓')
  } else if (cpu >= 60) {
    pool.push(`有点忙，负载 ${cpu}%，先别催`)
  } else if (cpu <= 15) {
    pool.push(`闲得慌，负载才 ${cpu}%`)
  }

  // ---- 内存 ----
  if (mem >= 85) {
    pool.push(`内存 ${mem}% 了，清下缓存？`)
  } else if (mem >= 70) {
    pool.push(`内存占着 ${mem}%，还算宽敞`)
  } else if (mem > 0 && mem <= 35) {
    pool.push(`内存只用了 ${mem}%，空得很`)
  }

  // ---- 网速 ----
  if (totalRate >= 2097152) {
    pool.push('网速起飞，我鞋都跑掉了')
  } else if (totalRate >= 10240) {
    pool.push(`网速 ${rateText}，稳`)
  } else {
    pool.push('网络静悄悄，我在打盹…')
  }

  // ---- 运行天数 ----
  if (s.uptimeDays >= 30) {
    pool.push(`连续跑了 ${s.uptimeDays} 天，稳如磐石`)
  } else if (s.uptimeDays >= 7) {
    pool.push(`连轴转了 ${s.uptimeDays} 天，我不累`)
  }

  // ---- 养成情绪 ----
  if (s.petMood >= 95) {
    pool.push('幸福爆棚，尾巴都摇起来了')
  } else if (s.petMood < 40) {
    pool.push('有点委屈…我哪里没做好')
  } else if (s.petMood < 70) {
    pool.push('心情一般，要摸摸头吗')
  }

  // ---- 等级 ----
  if (s.level >= 3) {
    pool.push(`Lv.${s.level} 的我，算老手了`)
  }

  return pool
}

/** 完整文案池：状态相关 + 日常闲聊 */
function buildPool(s: MoodState): string[] {
  const pool: string[] = statePool(s)
  for (let i = 0; i < CHITCHAT.length; i++) {
    pool.push(CHITCHAT[i])
  }
  return pool
}

/** 随机取一条心情文案：优先贴合当前状态，且不与上一条重复 */
export function pickMood(s: MoodState, avoid: string): string {
  const state: string[] = statePool(s)
  const pool: string[] = (state.length > 0 && Math.random() < 0.65) ? state : buildPool(s)
  if (pool.length === 0) {
    return avoid
  }
  for (let i = 0; i < 8; i++) {
    const text: string = pool[Math.floor(Math.random() * pool.length)]
    if (text !== avoid) {
      return text
    }
  }
  return pool[0]
}

/** 当前状态下可用的文案条数（自检用） */
export function moodPoolSize(s: MoodState): number {
  return buildPool(s).length
}
