/**
 * RollingNumber —— 数字滚动组件
 *
 * 值变化时用定时器插值（约 420ms），让速率/百分比/计数看起来是"滚上去"的，
 * 而不是瞬间跳变。刻意不使用 `Text.contentTransition(NumericTextTransition)`：
 * 那个 API 在真机上会直接让应用退出（编译期无告警），且只支持正整数。
 *
 * 用法：RollingNumber({ value: this.cpuPct, suffix: '%', fontSize: 9.5 })
 */
@Component
export struct RollingNumber {
  /** 目标值 */
  @Prop @Watch('onTargetChange') value: number = 0
  /** 小数位 */
  @Prop decimals: number = 0
  /** 后缀（%，台，KB/s 等），不做插值 */
  @Prop suffix: string = ''
  @Prop fontSize: number = 12
  @Prop fontWeight: FontWeight = FontWeight.Bold
  @Prop color: ResourceColor = '#000000'

  /** 当前显示值 */
  @State private shown: number = 0
  private timerId: number = -1

  aboutToAppear(): void {
    this.shown = this.value
  }

  aboutToDisappear(): void {
    this.stop()
  }

  onTargetChange(): void {
    this.animateTo(this.value)
  }

  private stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  /** 从当前显示值插值到目标值（16ms 一步，缓出曲线） */
  private animateTo(target: number): void {
    this.stop()
    const from: number = this.shown
    const delta: number = target - from
    if (Math.abs(delta) < 0.001) {
      this.shown = target
      return
    }
    const durationMs: number = 420
    const stepMs: number = 16
    let elapsed: number = 0
    this.timerId = setInterval(() => {
      elapsed += stepMs
      if (elapsed >= durationMs) {
        this.shown = target
        this.stop()
        return
      }
      const t: number = elapsed / durationMs
      const eased: number = 1 - (1 - t) * (1 - t)  // easeOutQuad
      this.shown = from + delta * eased
    }, stepMs)
  }

  private text(): string {
    return this.shown.toFixed(this.decimals) + this.suffix
  }

  build() {
    Text(this.text())
      .fontSize(this.fontSize)
      .fontWeight(this.fontWeight)
      .fontColor(this.color)
  }
}
