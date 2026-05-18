import { StyleConstants } from '../constants/StyleConstants'
import { SystemInfo } from '../../models/Models'
import { FormatUtils } from '../utils/FormatUtils'

@Component
export struct SystemStatusCard {
  @Prop systemInfo: SystemInfo = {
    hostname: '', model: '', kernel: '', firmwareVersion: '',
    localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
    memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0
  }

  build() {
    Column() {
      Row() {
        Text('系统状态')
          .fontSize(StyleConstants.FONT_LG)
          .fontColor(StyleConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)

        Blank()

        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(StyleConstants.SUCCESS)
            .shadow({
              radius: 4,
              color: 'rgba(0, 230, 118, 0.5)',
              offsetX: 0,
              offsetY: 0
            })

          Text('运行中')
            .fontSize(StyleConstants.FONT_SM)
            .fontColor(StyleConstants.SUCCESS)
            .margin({ left: 4 })
        }
      }
      .width('100%')

      this.StatusItem('CPU 使用率', this.systemInfo.cpuUsage, StyleConstants.PRIMARY,
        FormatUtils.formatPercent(this.systemInfo.cpuUsage))

      this.StatusItem('内存使用率',
        this.systemInfo.memoryTotal > 0 ? (this.systemInfo.memoryUsed / this.systemInfo.memoryTotal) * 100 : 0,
        StyleConstants.SECONDARY,
        `${FormatUtils.formatBytes(this.systemInfo.memoryUsed)} / ${FormatUtils.formatBytes(this.systemInfo.memoryTotal)}`)

      this.StatusItem('存储使用率',
        this.systemInfo.storageTotal > 0 ? (this.systemInfo.storageUsed / this.systemInfo.storageTotal) * 100 : 0,
        StyleConstants.WARNING,
        `${FormatUtils.formatBytes(this.systemInfo.storageUsed)} / ${FormatUtils.formatBytes(this.systemInfo.storageTotal)}`)

      if (this.systemInfo.cpuTemp > 0) {
        Row() {
          Text('CPU 温度').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY)
          Blank()
          Text(FormatUtils.formatTemperature(this.systemInfo.cpuTemp))
            .fontSize(StyleConstants.FONT_SM)
            .fontColor(this.systemInfo.cpuTemp > 70 ? StyleConstants.DANGER : StyleConstants.SUCCESS)
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
  }

  @Builder StatusItem(label: string, percent: number, color: string, detail: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(StyleConstants.FONT_SM)
          .fontColor(StyleConstants.TEXT_SECONDARY)
        Blank()
        Text(detail)
          .fontSize(StyleConstants.FONT_SM)
          .fontColor(StyleConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: 4 })

      Stack() {
        Row()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor('rgba(255, 255, 255, 0.08)')

        Row()
          .width(`${Math.max(0, Math.min(100, percent))}%`)
          .height(6)
          .borderRadius(3)
          .linearGradient({
            angle: 90,
            colors: [[color, 0], [color + '88', 1]]
          })
          .animation({ duration: 500, curve: Curve.EaseOut })

        Row()
          .width(`${Math.max(0, Math.min(100, percent))}%`)
          .height(3)
          .borderRadius(3)
          .margin({ top: 1.5 })
          .linearGradient({
            angle: 90,
            colors: [['rgba(255,255,255,0.3)', 0], ['rgba(255,255,255,0)', 1]]
          })
      }
    }
    .width('100%')
    .margin({ top: 12 })
  }
}
