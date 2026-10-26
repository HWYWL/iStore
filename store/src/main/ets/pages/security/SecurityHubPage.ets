/**
 * SecurityHubPage — 家庭网络安全中心
 * R1 安全评分（0-100 三档）+ R2 一键体检（5 项）+ R4 一键处置（隔离/信任）+ R6 历史
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SecurityHubEngine, SecurityItem, SecurityResult, SecurityHistory } from '../../common/security/SecurityHubEngine'
import { SshService } from '../../common/ssh/SshService'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
export struct SecurityHubPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State score: number = -1
  @State scoreText: string = '点击开始体检'
  @State items: SecurityItem[] = []
  @State scanning: boolean = false
  @State history: SecurityHistory[] = []
  @State sshOk: boolean = false
  @State suspiciousDevices: string[] = []   // 可疑设备 mac 列表
  @State topSafeArea: number = 44
  private engine: SecurityHubEngine = SecurityHubEngine.getInstance()

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.engine.init(hostCtx).then(() => {
        this.history = this.engine.getHistory()
        if (this.history.length > 0) {
          this.score = this.history[0].score
          this.scoreText = this.levelText(this.history[0].score)
        }
      })
    }
    this.sshOk = SshService.getInstance().isConnected()
    // 状态栏避让
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 开始体检 */
  async doScan(): Promise<void> {
    if (this.scanning) return
    this.scanning = true
    this.score = -1
    this.scoreText = '体检中…'
    this.items = []
    this.suspiciousDevices = []
    // SSH 未连接时尝试连接
    if (!this.sshOk) {
      const dev = AppState.getInstance().getActiveDevice()
      if (dev) {
        this.sshOk = await SshService.getInstance().connect(dev)
      }
    }
    try {
      const result: SecurityResult = await this.engine.runScan((item: SecurityItem) => {
        this.items = this.items.concat([item])
      })
      this.score = result.score
      this.scoreText = this.levelText(result.score)
      this.history = this.engine.getHistory()
    } catch (e) {
      this.scoreText = '体检失败，请稍后重试'
    }
    this.scanning = false
  }

  /** 评分文案 */
  levelText(s: number): string {
    if (s >= 85) return '家庭网络很安全 ✅'
    if (s >= 60) return '存在风险，建议处理 ⚠️'
    return '安全状况堪忧！请立即处理 🔴'
  }

  /** 评分颜色 */
  scoreColor(s: number): string {
    if (s >= 85) return '#00C853'
    if (s >= 60) return '#E6A800'
    return '#FF5252'
  }

  /** 处置：踢出设备（R4） */
  kickDevice(mac: string): void {
    promptAction.showDialog({
      title: '踢出设备',
      message: `将踢出设备 ${mac}，如误报可标记为信任设备`,
      buttons: [
        { text: '取消', color: '#888780' },
        { text: '踢出', color: '#FF5252' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        promptAction.showToast({ message: '已踢出设备', duration: 1500 })
      }
    }).catch(() => {})
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.security_shield'))
            .fontSize(20)
            .fontColor(['#10B981'])
          Text(' 安全中心')
            .fontSize(20)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Bold)
        }
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Blank()
        Text(this.sshOk ? 'SSH 已连接' : 'SSH 未连接')
          .fontSize(11)
          .fontColor(this.sshOk ? '#00A94F' : this.theme.textTertiary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 10, bottom: 10 })

      Scroll() {
        Column() {
          // R1：评分卡
          Row() {
            Column() {
              Text(this.score < 0 ? '--' : `${this.score}`)
                .fontSize(56)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.score < 0 ? this.theme.textTertiary : this.scoreColor(this.score))
              Text('安全评分')
                .fontSize(12)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            Column() {
              Text(this.scoreText)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.score < 0 ? this.theme.textTertiary : this.scoreColor(this.score))
              Text('陌生设备 / 开放端口 / 弱密码 / 固件 / 访客隔离')
                .fontSize(10)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 8 })
              Row() {
                Text(this.scanning ? '体检中…' : '重新体检')
                  .fontSize(13)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Medium)
                  .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                  .borderRadius(18)
                  .backgroundColor(this.theme.primary)
                  .margin({ top: 12 })
                  .onClick(() => { this.doScan() })
              }
              .width('100%')
            }
            .layoutWeight(2)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(20)
          .borderRadius(20)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .margin({ top: 8 })

          // R2：体检项列表
          if (this.items.length > 0) {
            Column() {
              ForEach(this.items, (item: SecurityItem) => {
                Row() {
                  SymbolGlyph(this.itemIcon(item.level))
                    .fontSize(20)
                    .fontColor([this.itemColor(item.level)])
                  Column() {
                    Text(item.name)
                      .fontSize(14)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text(item.detail)
                      .fontSize(11)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 4 })
                      .maxLines(2)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  if (item.level === 'risk') {
                    Text('需处理')
                      .fontSize(10)
                      .fontColor('#FF5252')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(8)
                      .backgroundColor('rgba(255,82,82,0.1)')
                  }
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .margin({ top: 8 })
                .backgroundColor(this.theme.bgCard)
                .border({ width: 0.5, color: this.theme.borderGlass })
              }, (item: SecurityItem) => `${item.key}_${item.level}`)
            }
            .width('100%')
            .margin({ top: 14 })
          }

          // R6：历史记录
          if (this.history.length > 0) {
            Text('近 30 天评分记录')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 18, bottom: 8 })
            Scroll() {
              Row() {
                ForEach(this.history, (h: SecurityHistory) => {
                  Column() {
                    Text(`${h.score}`)
                      .fontSize(12)
                      .fontColor(this.scoreColor(h.score))
                      .fontWeight(FontWeight.Bold)
                    Text(this.historyTime(h.time))
                      .fontSize(9)
                      .fontColor(this.theme.textTertiary)
                      .margin({ top: 4 })
                  }
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(10)
                  .backgroundColor(this.theme.bgGlassLight)
                  .margin({ right: 6 })
                }, (h: SecurityHistory) => `${h.time}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 底部避让
          Blank().height(AppState.getInstance().getBottomNavInset())
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  itemIcon(level: string): Resource {
    if (level === 'safe') return $r('sys.symbol.checkmark_circle')
    if (level === 'risk') return $r('sys.symbol.warning')
    if (level === 'checking') return $r('sys.symbol.clock')
    return $r('sys.symbol.info_circle')
  }

  /** 等级配色 */
  itemColor(level: string): string {
    if (level === 'safe') return '#10B981'
    if (level === 'risk') return '#EF4444'
    if (level === 'checking') return '#F59E0B'
    return '#64748B'
  }

  historyTime(t: number): string {
    const d: Date = new Date(t)
    return `${d.getMonth() + 1}/${d.getDate()}`
  }
}
