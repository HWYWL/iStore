/**
 * 系统状态卡片组件
 * 展示 CPU 使用率、内存使用率、存储使用率等关键系统指标
 * 以进度条 + 数值标签的形式呈现，CPU 温度超过 70°C 时显示红色警告
 */
import { StyleConstants } from '../constants/StyleConstants'
import { SystemInfo } from '../../models/Models'
import { FormatUtils } from '../utils/FormatUtils'

@Component
export struct SystemStatusCard {
  /** 系统信息数据（由父组件传入） */
  @Prop systemInfo: SystemInfo = {
    hostname: '', model: '', kernel: '', firmwareVersion: '',
    localTime: '', uptime: 0, cpuUsage: 0, memoryTotal: 0, memoryUsed: 0,
    memoryCached: 0, memoryAvailable: 0, storageTotal: 0, storageUsed: 0, cpuTemp: 0
  }

  build() {
    Column() {
      // 标题栏：左侧标题 + 右侧运行状态指示灯
      Row() {
        Text('系统状态')
          .fontSize(StyleConstants.FONT_LG)
          .fontColor(StyleConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)

        Blank()

        Row() {
          // 绿色圆点指示灯（带发光效果）
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

      // CPU 使用率进度条
      this.StatusItem('CPU 使用率', this.systemInfo.cpuUsage, StyleConstants.PRIMARY,
        FormatUtils.formatPercent(this.systemInfo.cpuUsage))

      // 内存使用率进度条（含已用/总量数值）
      this.StatusItem('内存使用率',
        this.systemInfo.memoryTotal > 0 ? (this.systemInfo.memoryUsed / this.systemInfo.memoryTotal) * 100 : 0,
        StyleConstants.SECONDARY,
        `${FormatUtils.formatBytes(this.systemInfo.memoryUsed)} / ${FormatUtils.formatBytes(this.systemInfo.memoryTotal)}`)

      // 存储使用率进度条（含已用/总量数值）
      this.StatusItem('存储使用率',
        this.systemInfo.storageTotal > 0 ? (this.systemInfo.storageUsed / this.systemInfo.storageTotal) * 100 : 0,
        StyleConstants.WARNING,
        `${FormatUtils.formatBytes(this.systemInfo.storageUsed)} / ${FormatUtils.formatBytes(this.systemInfo.storageTotal)}`)

      // CPU 温度：仅在有数据时显示，超过 70°C 标红
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

  /**
   * 进度条条目构建器
   * @param label 指标名称
   * @param percent 百分比数值
   * @param color 进度条主色调
   * @param detail 右侧数值详情文本
   */
  @Builder StatusItem(label: string, percent: number, color: string, detail: string) {
    Column() {
      // 标签行：名称 + 数值
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

      // 进度条：底层灰色背景 + 上层渐变色填充 + 高光条
      Stack() {
        // 底层：灰色背景轨道
        Row()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor('rgba(255, 255, 255, 0.08)')

        // 中层：渐变色填充（动画过渡）
        Row()
          .width(`${Math.max(0, Math.min(100, percent))}%`)
          .height(6)
          .borderRadius(3)
          .linearGradient({
            angle: 90,
            colors: [[color, 0], [color + '88', 1]]  // 左实右透渐变
          })
          .animation({ duration: 500, curve: Curve.EaseOut })

        // 上层：高光条（增强立体感）
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
