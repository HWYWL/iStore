/**
 * DNS 速度擂台
 * 对多个公共 DNS 依次 ping 测延迟，出排行榜 + 推荐
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

interface DnsRow {
  name: string
  ip: string
  avg: number
  ok: boolean
  rank: number
}

const DNS_LIST: string[][] = [
  ['阿里', '223.5.5.5'],
  ['腾讯', '119.29.29.29'],
  ['114 网络', '114.114.114.114'],
  ['百度', '180.76.76.76']
]

@Entry
@Component
export struct DnsBattlePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State rows: DnsRow[] = []
  @State testing: boolean = false
  @State recommend: string = ''
  @State curName: string = ''
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
  }

  async runBattle(): Promise<void> {
    if (this.testing) return
    this.testing = true
    this.recommend = ''
    const list: DnsRow[] = []
    for (let i = 0; i < DNS_LIST.length; i++) {
      const name: string = DNS_LIST[i][0]
      const ip: string = DNS_LIST[i][1]
      this.curName = name
      const avg: number = await this.pingAvg(ip)
      list.push({ name: name, ip: ip, avg: avg, ok: avg > 0, rank: 0 })
    }
    // 排序出排名
    const sorted: DnsRow[] = list.slice()
    sorted.sort((a: DnsRow, b: DnsRow): number => {
      if (!a.ok) return 1
      if (!b.ok) return -1
      return a.avg - b.avg
    })
    for (let i = 0; i < sorted.length; i++) {
      sorted[i].rank = i + 1
    }
    this.rows = sorted
    // 推荐
    const best = sorted[0]
    if (best && best.ok) {
      this.recommend = `建议使用 ${best.name}（${best.ip}），当前最快 ${best.avg} ms`
    } else {
      this.recommend = '全部 DNS 均不可达，请检查外网连接'
    }
    this.curName = ''
    this.testing = false
  }

  private async pingAvg(ip: string): Promise<number> {
    try {
      const out: string = await this.api.execCommand('/bin/ping', ['-c', '3', '-W', '1', ip])
      if (out) {
        const m: RegExpMatchArray | null = out.match(/round-trip min\/avg\/max = [\d.]+\/([\d.]+)\//) ||
          out.match(/min\/avg\/max\s*=\s*[\d.]+\/([\d.]+)\//)
        if (m && m[1]) {
          return Number(m[1])
        }
      }
    } catch (e) {
      hilog.error(0x0001, 'DnsBattle', `ping ${ip} err`)
    }
    return 0
  }

  private rankIcon(r: number): Resource {
    if (r === 1) return $r('sys.symbol.star_trophy')
    if (r === 2) return $r('sys.symbol.medal')
    if (r === 3) return $r('sys.symbol.medal')
    return $r('sys.symbol.medal')
  }

  private rankColor(r: number): string {
    if (r === 1) return '#F59E0B'
    if (r === 2) return '#94A3B8'
    if (r === 3) return '#B45309'
    return '#64748B'
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('DNS 速度擂台')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
        }
        .padding({ left: 4, right: 16, top: 6, bottom: 6 })
        .borderRadius(100)
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { AppNav.getInstance().back() })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          if (this.curName) {
            Row() {
              LoadingProgress().width(18).height(18).color('#FF8A3D')
              Text(`  正在挑战 ${this.curName} DNS...`)
                .fontSize(12).fontColor(this.theme.textSecondary)
            }
            .width('100%').justifyContent(FlexAlign.Center).margin({ top: 14 })
          }

          // 排行榜
          ForEach(this.rows, (row: DnsRow) => {
            Row() {
              SymbolGlyph(this.rankIcon(row.rank)).fontSize(22).fontColor([this.rankColor(row.rank)]).width(36)
              Column() {
                Text(row.name)
                  .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                Text(row.ip)
                  .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)
              .margin({ left: 8 })
              if (row.ok) {
                Text(`${row.avg.toFixed(1)} ms`)
                  .fontSize(13).fontColor(row.rank === 1 ? '#00C853' : this.theme.textPrimary)
                  .fontFamily('monospace').fontWeight(row.rank === 1 ? FontWeight.Bold : FontWeight.Normal)
              } else {
                Text('不可达')
                  .fontSize(11).fontColor('#FF5252')
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .borderRadius(16)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
          }, (row: DnsRow): string => row.name)

          if (this.recommend) {
            Column() {
              Row() {
                SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(13).fontColor(['#F59E0B'])
                Text(' ' + this.recommend)
                  .fontSize(12).fontColor(this.theme.textPrimary).lineHeight(19)
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
            }
            .width('100%').padding(14).borderRadius(14)
            .border({ width: 0.5, color: 'rgba(255,138,61,0.4)' })
            .margin({ top: 14 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Start)
          }

          Row() {
            Text(this.testing ? '比拼中...' : '开始比拼')
              .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
          .width('100%').height(48).borderRadius(24)
          .backgroundColor(this.testing ? '#C9A98A' : '#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })
          .onClick(() => { this.runBattle() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })
  }
}
