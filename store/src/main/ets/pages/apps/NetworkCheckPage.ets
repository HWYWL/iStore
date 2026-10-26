/**
 * 智能网络体检页面
 * 一键检测：网关连通性 / 外网连通 / 公网延迟 / DNS 解析
 * 逐项展示状态（优秀/正常/警告/不可达）+ 延迟 + 丢包，并给出总评分
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { NetworkCheckItem } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { FunStore } from '../../common/store/FunStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
export struct NetworkCheckPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State items: NetworkCheckItem[] = []
  @State checking: boolean = false
  @State checked: boolean = false
  @State pulseTick: number = 0     // 脉动动画节拍（每 50ms +1，数字变化必触发刷新）
  @State curKey: string = ''        // 当前正在体检的项
  private animTimer: number = -1    // 动画驱动定时器
  @State score: number = 0
  @State scoreText: string = ''
  @State errorText: string = ''
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    // 初始化检测项为待检测
    this.items = [
      { key: 'gateway', name: '网关连通性', target: '', desc: '内网网关延迟', status: 'pending', latencyMs: 0, lossPercent: 0, detail: '' },
      { key: 'wan_ali', name: '外网连通性', target: '223.5.5.5', desc: '阿里公共 DNS', status: 'pending', latencyMs: 0, lossPercent: 0, detail: '' },
      { key: 'wan_tx', name: '公网延迟', target: '119.29.29.29', desc: '腾讯公共 DNS', status: 'pending', latencyMs: 0, lossPercent: 0, detail: '' },
      { key: 'dns', name: 'DNS 解析', target: 'baidu.com', desc: '域名解析能力', status: 'pending', latencyMs: 0, lossPercent: 0, detail: '' }
    ]
  }

  /** 开始体检：逐项检测，实时更新状态 */
  async startCheck(): Promise<void> {
    if (this.checking) {
      return
    }
    this.checking = true
    this.checked = false
    this.errorText = ''
    // 启动体检动画节拍：每 50ms 更新数字状态，opacity/省略号直接由它计算（保证可见动画）
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer)
    }
    this.pulseTick = 0
    this.animTimer = setInterval(() => {
      this.pulseTick = this.pulseTick + 1
      if (this.pulseTick > 10000) {
        this.pulseTick = 0
      }
    }, 50)
    // 重置为待检测（整体替换数组元素，V1 @State 需要新对象才触发刷新）
    const resetItems: NetworkCheckItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      resetItems.push({
        key: this.items[i].key, name: this.items[i].name, target: this.items[i].target,
        desc: this.items[i].desc, status: 'pending', latencyMs: 0, lossPercent: 0, detail: ''
      })
    }
    this.items = resetItems
    try {
      // 先识别网关地址，填充第一项目标
      try {
        const gwOut: string = await this.api.execCommand('/sbin/ip', ['route', 'show', 'default'])
        const gwMatch: RegExpMatchArray | null = gwOut.match(/default via ([\d.]+)/)
        if (gwMatch && gwMatch[1]) {
          this.items[0].target = gwMatch[1]
        } else {
          this.items[0].target = '192.168.1.1'
          this.items[0].detail = '未识别网关，使用默认 192.168.1.1'
        }
      } catch (e) {
        this.items[0].target = '192.168.1.1'
      }
      // 逐项执行（保持界面实时反馈）
      for (let i = 0; i < this.items.length; i++) {
        // 整体重建数组触发 ForEach 刷新（V1 对元素级赋值不响应——这是动画不显示的根本原因）
        const cur: NetworkCheckItem = this.items[i]
        this.items = this.items.map((it: NetworkCheckItem, idx: number): NetworkCheckItem => {
          return idx === i ? this.makeItem(it, 'running', 0, 0, '') : it
        })
        this.curKey = cur.key
        const r: NetworkCheckItem = await this.pingOne(cur)
        this.items = this.items.map((it: NetworkCheckItem, idx: number): NetworkCheckItem => {
          return idx === i ? r : it
        })
      }
      this.curKey = ''
      this.computeScore()
      this.checked = true
      // 达成「体检卫士」成就
      try {
        const hostCtx = this.getUIContext().getHostContext()
        if (hostCtx) {
          const fun = FunStore.getInstance()
          await fun.init(hostCtx as Context)
          fun.setAchieved('health')
        }
      } catch (e) {}
    } catch (e) {
      hilog.error(0x0001, 'NetworkCheck', `startCheck err: ${String(e)}`)
      this.errorText = '体检失败，请检查设备连接'
    }
    this.checking = false
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer)
      this.animTimer = -1
    }
    this.curKey = ''
  }

  /** 动态省略号：. .. ... 循环（由 pulseTick 驱动） */
  private dotsText(): string {
    const c: number = (this.pulseTick % 3) + 1
    let d: string = ''
    for (let i = 0; i < c; i++) {
      d = d + '.'
    }
    return d
  }

  /** 构造新检测项对象（显式字段，ArkTS 不支持 spread） */
  private makeItem(it: NetworkCheckItem, status: string, latency: number, loss: number, detail: string): NetworkCheckItem {
    return {
      key: it.key, name: it.name, target: it.target, desc: it.desc,
      status: status, latencyMs: latency, lossPercent: loss, detail: detail
    }
  }

  /** 单项 ping 检测 */
  private async pingOne(item: NetworkCheckItem): Promise<NetworkCheckItem> {
    const r: NetworkCheckItem = {
      key: item.key, name: item.name, target: item.target, desc: item.desc,
      status: 'fail', latencyMs: 0, lossPercent: 100, detail: item.detail || ''
    }
    try {
      const out: string = await this.api.execCommand('/bin/ping', ['-c', '3', '-W', '1', item.target])
      if (out) {
        const lossMatch: RegExpMatchArray | null = out.match(/(\d+)% packet loss/i)
        const loss: number = lossMatch ? parseInt(lossMatch[1]) : 100
        const avgMatch: RegExpMatchArray | null = out.match(/round-trip min\/avg\/max = [\d.]+\/([\d.]+)\//) ||
          out.match(/min\/avg\/max\s*=\s*[\d.]+\/([\d.]+)\//)
        const latency: number = avgMatch ? parseFloat(avgMatch[1]) : 0
        r.lossPercent = loss
        r.latencyMs = Math.round(latency)
        if (loss >= 100) {
          r.status = 'fail'
          r.detail = r.detail || '目标不可达'
        } else if (loss > 0) {
          r.status = 'warn'
          r.detail = r.detail || `${loss}% 丢包`
        } else if (latency > 0 && latency < 50) {
          r.status = 'ok'
          r.detail = '网络优秀'
        } else if (latency >= 50 && latency < 150) {
          r.status = 'ok'
          r.detail = '网络正常'
        } else if (latency >= 150) {
          r.status = 'warn'
          r.detail = '延迟偏高'
        } else {
          r.status = 'ok'
          r.detail = r.detail || '连通正常'
        }
      } else {
        r.detail = r.detail || '无响应（可能无 ping 权限）'
      }
    } catch (e) {
      r.detail = r.detail || '检测异常'
    }
    return r
  }

  /** 综合评分：ok=25 分/项，warn=10，fail=0 */
  private computeScore(): void {
    let total: number = 0
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].status === 'ok') {
        total += 25
      } else if (this.items[i].status === 'warn') {
        total += 10
      }
    }
    this.score = total
    if (total === 100) {
      this.scoreText = '网络状态优秀 ✨'
    } else if (total >= 70) {
      this.scoreText = '网络状态良好'
    } else if (total >= 40) {
      this.scoreText = '存在网络问题，建议排查'
    } else {
      this.scoreText = '网络异常，请检查路由器'
    }
  }

  /** 单项状态图标与颜色 */
  statusIcon(status: string): Resource {
    if (status === 'ok') return $r('sys.symbol.checkmark_circle')
    if (status === 'warn') return $r('sys.symbol.warning')
    if (status === 'fail') return $r('sys.symbol.xmark_circle')
    if (status === 'running') return $r('sys.symbol.clock')
    return $r('sys.symbol.info_circle')
  }

  statusColor(status: string): string {
    if (status === 'ok') return '#00C853'
    if (status === 'warn') return '#E6A800'
    if (status === 'fail') return '#FF5252'
    if (status === 'running') return '#FF8A3D'
    return '#B0A99A'
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('智能网络体检')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
        if (this.checked) {
          Text(`${this.score} 分`)
            .fontSize(13).fontColor(this.score >= 70 ? '#00C853' : '#E6A800')
            .fontWeight(FontWeight.Bold)
            .margin({ right: 16 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          // 开始按钮 / 结论卡
          if (this.checked) {
            Column() {
              Text(this.scoreText)
                .fontSize(18).fontColor(this.score >= 70 ? '#00C853' : '#E6A800')
                .fontWeight(FontWeight.Bold)
              Text(`综合评分 ${this.score} / 100`)
                .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 4 })
            }
            .width('100%').padding(20).borderRadius(20).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
          } else {
            Column() {
              Image($r('app.media.app_health'))
                .width(56).height(56)
              Text('一键检测网络健康状况')
                .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                .margin({ top: 8 })
              Text('网关连通 · 外网连通 · 公网延迟 · DNS 解析')
                .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 4 })
            }
            .width('100%').padding(24).borderRadius(20).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
          }

          if (this.errorText) {
            Text(this.errorText)
              .fontSize(12).fontColor('#FF5252').margin({ top: 12 })
          }

          // 检测项列表
          Column() {
            ForEach(this.items, (item: NetworkCheckItem) => {
              Row() {
                if (item.status === 'running') {
                  // 体检中：转圈动画
                  LoadingProgress().width(22).height(22).color(this.theme.primary)
                } else if (item.status === 'ok') {
                  // 通过：鸿蒙原生 checkmark_circle 分层绿色
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(22)
                    .fontColor(['#00C853', '#7CE495'])
                    .width(22)
                    .transition(TransitionEffect.opacity(0.2).combine(
                      TransitionEffect.scale({ x: 0.6, y: 0.6 }).animation({ duration: 200, curve: Curve.EaseOut })))
                } else if (item.status === 'warn' || item.status === 'fail') {
                  // 完成：⚠/✗ 淡入缩放
                  SymbolGlyph(this.statusIcon(item.status))
                    .fontSize(20)
                    .fontColor([this.statusColor(item.status)])
                    .fontWeight(FontWeight.Bold)
                    .width(22)
                    .transition(TransitionEffect.opacity(0.2).combine(
                      TransitionEffect.scale({ x: 0.6, y: 0.6 }).animation({ duration: 200, curve: Curve.EaseOut })))
                } else {
                  Text('·')
                    .fontSize(20).fontColor('#B0A99A').width(22)
                }
                Column() {
                  Row() {
                    Text(item.name)
                      .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                    if (item.status === 'running') {
                      Text('  体检中')
                        .fontSize(11)
                        .fontColor(this.theme.primary)
                        .opacity(0.35 + 0.65 * Math.abs(Math.sin(this.pulseTick * 0.5)))
                    } else {
                      Text(`  ${item.target}`)
                        .fontSize(10).fontColor(this.theme.textTertiary)
                    }
                  }
                  .width('100%')
                  Text(item.status === 'running' ? '正在检测，请稍候...' :
                    `${item.desc}${item.detail ? ' · ' + item.detail : ''}`)
                    .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 2 })
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                .margin({ left: 10 })

                if (item.status === 'running') {
                  Column() {
                    Text(this.dotsText())
                      .fontSize(13).fontColor(this.theme.primary)
                  }
                  .alignItems(HorizontalAlign.End)
                } else if (item.status === 'ok' || item.status === 'warn' || item.status === 'fail') {
                  Column() {
                    Text(item.latencyMs > 0 ? `${item.latencyMs} ms` : '--')
                      .fontSize(13).fontColor(this.theme.textPrimary).fontFamily('monospace')
                    if (item.lossPercent > 0) {
                      Text(`丢包 ${item.lossPercent}%`)
                        .fontSize(9).fontColor('#E6A800').margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.End)
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(16)
              .margin({ top: 10 })
              .backgroundColor(this.theme.bgCard)
              .border({
                width: item.status === 'running' ? 1.2 : 0,
                color: item.status === 'running' ? this.theme.primary : '#00000000'
              })
              .animation({ duration: 300, curve: Curve.EaseOut })
            }, (item: NetworkCheckItem): string => item.key + '_' + item.status + '_' + item.latencyMs)
          }
          .width('100%')

          // 重新体检
          Row() {
            Text(this.checking ? '体检中...' : (this.checked ? '重新体检' : '开始体检'))
              .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
          .width('100%').height(48).borderRadius(24)
          .backgroundColor(this.checking ? '#C9A98A' : '#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 20 })
          .onClick(() => { this.startCheck() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
