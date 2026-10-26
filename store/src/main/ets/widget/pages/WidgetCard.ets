/**
 * WidgetCard - 桌面小组件（网络状态卡片）
 * 布局自适应：无论尺寸判断是否成功，均展示速率 + CPU/内存；
 * 2*4 额外展示路由器 IP 与更宽松的排版
 * 点击直达 App 首页；数据来自 FormBindingData（App 后台写入 Preferences，Extension 定期推送）
 * 注：postCardAction 为卡片全局内置函数，无需 import
 */
let storage = new LocalStorage()

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('rxRate') rxRate: number = 0
  @LocalStorageProp('txRate') txRate: number = 0
  @LocalStorageProp('deviceCount') deviceCount: number = 0
  @LocalStorageProp('online') online: boolean = false
  @LocalStorageProp('deviceName') deviceName: string = 'iStore 路由管家'
  @LocalStorageProp('cpuUsage') cpuUsage: number = 0
  @LocalStorageProp('memPercent') memPercent: number = 0
  @LocalStorageProp('ip') ip: string = ''
  @LocalStorageProp('todayTraffic') todayTraffic: number = 0
  @LocalStorageProp('metric') metric: string = 'speed'
  @LocalStorageProp('widgetSize') widgetSize: string = '2*2'
  // 系统自动注入的卡片尺寸（权威来源），如 '2*2' / '2*4' / '4*4'
  @LocalStorageProp('formDimension') formDimension: string = '2*2'

  /** 是否大尺寸卡片（2*4 / 4*4） */
  isLarge(): boolean {
    return this.formDimension === '2*4' || this.formDimension === '4*4'
      || this.widgetSize === '2*4' || this.widgetSize === '4*4'
  }

  /** 格式化速率 */
  fmtSpeed(v: number): string {
    if (v >= 1048576) return `${(v / 1048576).toFixed(1)} MB/s`
    if (v >= 1024) return `${(v / 1024).toFixed(0)} KB/s`
    return `${v} B/s`
  }

  /** CPU/内存颜色 */
  gaugeColor(v: number): string {
    if (v >= 90) return '#FF5252'
    if (v >= 70) return '#FFB300'
    return '#00C853'
  }

  /** 字节格式化（今日流量） */
  fmtBytes(v: number): string {
    if (v >= 1073741824) return `${(v / 1073741824).toFixed(1)} GB`
    if (v >= 1048576) return `${(v / 1048576).toFixed(0)} MB`
    if (v >= 1024) return `${(v / 1024).toFixed(0)} KB`
    return `${v} B`
  }

  /** 主指标图标（线稿风格，与 App 内图标同源） */
  metricIconSrc(): Resource {
    if (this.metric === 'traffic') return $r('app.media.w_metric_traffic')
    if (this.metric === 'cpu') return $r('app.media.w_metric_cpu')
    if (this.metric === 'devices') return $r('app.media.w_metric_devices')
    return $r('app.media.w_metric_speed')
  }

  /** 主指标图示底色（与图标同色系的浅色底） */
  metricTint(): string {
    if (this.metric === 'traffic') return 'rgba(124,58,237,0.12)'
    if (this.metric === 'cpu') return 'rgba(245,158,11,0.14)'
    if (this.metric === 'devices') return 'rgba(16,185,129,0.14)'
    return 'rgba(37,99,235,0.12)'
  }

  /** 主指标文本（由 App 内「小组件设置」决定） */
  metricText(): string {
    if (this.metric === 'traffic') return `今日 ${this.fmtBytes(this.todayTraffic)}`
    if (this.metric === 'cpu') return `CPU ${this.cpuUsage.toFixed(0)}% · 内存 ${this.memPercent.toFixed(0)}%`
    if (this.metric === 'devices') return `${this.deviceCount} 台设备在线`
    return this.fmtSpeed(this.rxRate)
  }

  build() {
    Column() {
      // 顶部：名称 + 状态
      Row() {
        Text(this.deviceName)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0A0E27')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Row() {
          Circle({ width: 5, height: 5 })
            .fill(this.online ? '#00C853' : '#FF5252')
          Text(this.online ? '在线' : '离线')
            .fontSize(10)
            .fontColor(this.online ? '#00A94F' : '#FF5252')
            .margin({ left: 4 })
        }
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(9)
        .backgroundColor(this.online ? 'rgba(0,200,83,0.12)' : 'rgba(255,82,82,0.12)')
      }
      .width('100%')

      // 中部：主指标（由 App 内「小组件设置」决定，默认实时速率）
      Row() {
        Row() {
          Image(this.metricIconSrc())
            .width(this.isLarge() ? 16 : 14)
            .height(this.isLarge() ? 16 : 14)
            .objectFit(ImageFit.Contain)
        }
        .width(this.isLarge() ? 30 : 26)
        .height(this.isLarge() ? 30 : 26)
        .borderRadius(this.isLarge() ? 9 : 8)
        .backgroundColor(this.metricTint())
        .justifyContent(FlexAlign.Center)
        Text(this.metricText())
          .fontSize(this.isLarge() ? 22 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0A0E27')
          .margin({ left: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 10 })

      // 副行：主指标非速率时补充 下行 / 上行 实时速率
      if (this.metric !== 'speed') {
        Row() {
          Image($r('app.media.w_rate_down'))
            .width(11)
            .height(11)
            .objectFit(ImageFit.Contain)
          Text(this.fmtSpeed(this.rxRate))
            .fontSize(11)
            .fontColor('#5F6B8A')
            .margin({ left: 3 })
            .maxLines(1)
          Image($r('app.media.w_rate_up'))
            .width(11)
            .height(11)
            .objectFit(ImageFit.Contain)
            .margin({ left: 10 })
          Text(this.fmtSpeed(this.txRate))
            .fontSize(11)
            .fontColor('#5F6B8A')
            .margin({ left: 3 })
            .maxLines(1)
        }
        .width('100%')
        .padding({ top: 4 })
      }

      // 系统状态行：CPU / 内存 / IP（2*4 时 IP 独立一列；主指标为 CPU 时避免重复）
      if (this.isLarge() && this.metric !== 'cpu') {
        Row() {
          Column() {
            Row() {
              Circle({ width: 6, height: 6 })
                .fill(this.gaugeColor(this.cpuUsage))
              Text(' CPU')
                .fontSize(10)
                .fontColor('#5F6B8A')
            }
            Text(`${this.cpuUsage.toFixed(0)}%`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0A0E27')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Row() {
              Circle({ width: 6, height: 6 })
                .fill(this.gaugeColor(this.memPercent))
              Text(' 内存')
                .fontSize(10)
                .fontColor('#5F6B8A')
            }
            Text(`${this.memPercent.toFixed(0)}%`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0A0E27')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Text('IP')
              .fontSize(10)
              .fontColor('#5F6B8A')
            Text(this.ip || '--')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0A0E27')
              .margin({ top: 2 })
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 8 })
        .border({ width: { top: 0.5 }, color: 'rgba(0,0,0,0.06)' })
        .padding({ top: 6 })
      }

      // 底部：辅助信息 + 查看详情（主指标已占用时不重复展示）
      Row() {
        if (this.isLarge()) {
          Row() {
            if (this.metric === 'devices') {
              Text(`今日 ${this.fmtBytes(this.todayTraffic)}`)
                .fontSize(11)
                .fontColor('#5F6B8A')
                .maxLines(1)
            } else {
              Image($r('app.media.w_host'))
                .width(12)
                .height(12)
                .objectFit(ImageFit.Contain)
              Text(` 在线设备 ${this.deviceCount} 台`)
                .fontSize(11)
                .fontColor('#5F6B8A')
                .maxLines(1)
            }
          }
          Blank()
          Text('查看详情 ›')
            .fontSize(10)
            .fontColor('#185FA5')
        } else if (this.metric === 'cpu') {
          Text(`今日 ${this.fmtBytes(this.todayTraffic)}`)
            .fontSize(10)
            .fontColor('#5F6B8A')
            .maxLines(1)
          Blank()
          Row() {
            Image($r('app.media.w_host'))
              .width(11)
              .height(11)
              .objectFit(ImageFit.Contain)
            Text(` ${this.deviceCount}`)
              .fontSize(10)
              .fontColor('#5F6B8A')
          }
        } else {
          Row() {
            Circle({ width: 5, height: 5 })
              .fill(this.gaugeColor(this.cpuUsage))
            Text(` CPU ${this.cpuUsage.toFixed(0)}%`)
              .fontSize(10)
              .fontColor('#5F6B8A')
          }
          Row() {
            Circle({ width: 5, height: 5 })
              .fill(this.gaugeColor(this.memPercent))
            Text(` 内存 ${this.memPercent.toFixed(0)}%`)
              .fontSize(10)
              .fontColor('#5F6B8A')
          }
          .margin({ left: 10 })
          Blank()
          if (this.metric !== 'devices') {
            Row() {
              Image($r('app.media.w_host'))
                .width(11)
                .height(11)
                .objectFit(ImageFit.Contain)
              Text(` ${this.deviceCount}`)
                .fontSize(10)
                .fontColor('#5F6B8A')
            }
          }
        }
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .borderRadius(18)
    .linearGradient({
      angle: 135,
      colors: [['#FFFFFF', 0], ['#E8F1FB', 1]]
    })
    .onClick(() => {
      // 卡片点击：拉起 App 首页（卡片专用交互）
      postCardAction(this, {
        action: 'router',
        abilityName: 'StoreAbility',
        params: { targetPage: 'pages/dashboard/MainPage' }
      })
    })
  }
}
