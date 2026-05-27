/**
 * 流量柱状图组件
 * 以双柱（下载/上传）的形式展示网络流量历史记录
 * 支持图例、时间标签、网格线背景
 */
import { StyleConstants } from '../constants/StyleConstants'
import { TrafficHistory } from '../../models/Models'
import { FormatUtils } from '../utils/FormatUtils'

@Component
export struct TrafficLineChart {
  /** 流量历史数据（由父组件传入） */
  @Prop data: TrafficHistory[] = []
  /** 是否显示图例（下载/上传颜色标识） */
  @Prop showLegend: boolean = true

  /**
   * 获取数据中的最大值，用于归一化计算柱状图高度
   * 至少返回 1 以避免除零
   */
  private getMaxVal(): number {
    if (this.data.length === 0) return 1
    let max = 1
    for (const d of this.data) {
      if (d.rx > max) max = d.rx
      if (d.tx > max) max = d.tx
    }
    return max
  }

  build() {
    Column() {
      // 图例区域：显示下载（青蓝）和上传（紫罗兰）颜色标识
      if (this.showLegend) {
        Row() {
          Row() {
            Circle().width(6).height(6).fill(StyleConstants.PRIMARY).margin({ right: 4 })
            Text('下载').fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY)
          }
          .margin({ right: 14 })

          Row() {
            Circle().width(6).height(6).fill(StyleConstants.SECONDARY).margin({ right: 4 })
            Text('上传').fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY)
          }
        }
        .width('100%')
        .margin({ bottom: 6 })
      }

      // X 轴时间标签：平均取 4 个时间点
      Row() {
        ForEach(this.getLabels(), (label: string, index: number) => {
          Text(label)
            .fontSize(9)
            .fontColor(StyleConstants.TEXT_TERTIARY)
            .width('25%')
            .textAlign(TextAlign.Center)
        }, (label: string, index: number) => index.toString())
      }
      .width('100%')
      .margin({ bottom: 2 })

      // 图表区域：网格线 + 柱状图叠加
      Stack() {
        // 背景网格线（4 条水平分割线）
        Column() {
          ForEach(this.getGridLines(), (_: number, index: number) => {
            Divider()
              .strokeWidth(0.3)
              .color('rgba(255, 255, 255, 0.04)')
              .margin({ top: 4, bottom: 4 })
          }, (_: number, index: number) => index.toString())
        }
        .width('100%')
        .height(120)

        // 柱状图主体：每个数据点显示一对（下载 + 上传）柱子
        Column() {
          ForEach(this.data, (item: TrafficHistory, idx: number) => {
            Row() {
              // 下载柱（青蓝色）
              Column() {
                this.BarItem(item.rx, this.getMaxVal(), StyleConstants.PRIMARY)
              }
              .width(`${100 / this.data.length}%`)
              .padding({ left: 1, right: 1 })

              // 上传柱（紫罗兰色）
              Column() {
                this.BarItem(item.tx, this.getMaxVal(), StyleConstants.SECONDARY)
              }
              .width(`${100 / this.data.length}%`)
              .padding({ left: 1, right: 1 })
            }
            .width('100%')
          }, (item: TrafficHistory, idx: number) => idx.toString())
        }
        .width('100%')
        .height(120)
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 单根柱状条构建器
   * @param value 当前值
   * @param max 最大值（用于归一化）
   * @param color 柱子渐变色
   */
  @Builder BarItem(value: number, max: number, color: string) {
    Column() {
      // 上方留白（柱子从底部向上生长）
      Blank()
      // 柱子主体：高度按 value/max 比例计算
      Column()
        .width('100%')
        .height(`${Math.max(0.5, (value / max) * 100)}%`)
        .borderRadius(1.5)
        .linearGradient({
          angle: 180,  // 从上到下渐变
          colors: [[color + 'CC', 0], [color + '22', 1]]  // 上实下透
        })
        .animation({ duration: 400, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)  // 底部对齐
  }

  /**
   * 生成 X 轴时间标签（取 4 个均匀分布的时间点）
   */
  private getLabels(): string[] {
    if (this.data.length === 0) return ['--', '--', '--', '--']
    const labels: string[] = []
    const step = Math.max(1, Math.floor(this.data.length / 4))
    for (let i = 0; i < 4 && i * step < this.data.length; i++) {
      const ts = this.data[i * step].timestamp
      labels.push(this.formatTimeLabel(ts))
    }
    return labels
  }

  /** 网格线数量（4 条） */
  private getGridLines(): number[] {
    return [1, 2, 3, 4]
  }

  /**
   * 时间戳格式化为 HH:MM 格式
   */
  private formatTimeLabel(timestamp: string): string {
    if (!timestamp) return '--'
    const date = new Date(timestamp)
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }
}
