import { StyleConstants } from '../constants/StyleConstants'
import { TrafficHistory } from '../../models/Models'
import { FormatUtils } from '../utils/FormatUtils'

@Component
export struct TrafficLineChart {
  @Prop data: TrafficHistory[] = []
  @Prop showLegend: boolean = true

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

      Stack() {
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

        Column() {
          ForEach(this.data, (item: TrafficHistory, idx: number) => {
            Row() {
              Column() {
                this.BarItem(item.rx, this.getMaxVal(), StyleConstants.PRIMARY)
              }
              .width(`${100 / this.data.length}%`)
              .padding({ left: 1, right: 1 })

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

  @Builder BarItem(value: number, max: number, color: string) {
    Column() {
      Blank()
      Column()
        .width('100%')
        .height(`${Math.max(0.5, (value / max) * 100)}%`)
        .borderRadius(1.5)
        .linearGradient({
          angle: 180,
          colors: [[color + 'CC', 0], [color + '22', 1]]
        })
        .animation({ duration: 400, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }

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

  private getGridLines(): number[] {
    return [1, 2, 3, 4]
  }

  private formatTimeLabel(timestamp: string): string {
    if (!timestamp) return '--'
    const date = new Date(timestamp)
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }
}
