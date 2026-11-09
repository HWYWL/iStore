/**
 * RefreshRate - 全局实时数据刷新节奏
 *
 * 首页仪表盘、应用中心速率卡、小管家网络流量共用同一个间隔，
 * 避免同一份实时速率在不同页面刷新快慢不一致（数字来回跳）。
 */
export const LIVE_REFRESH_MS: number = 5000
