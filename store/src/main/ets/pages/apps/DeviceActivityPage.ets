/**
 * 设备作息热力图
 * 打开本页即采样在线设备，记录 24h 活跃，色块深浅展示
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { FunStore } from '../../common/store/FunStore'
import { ApiService } from '../../api/ApiService'
import { ConnectedDevice } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

interface ActRow {
  name: string
  mac: string
  hours: boolean[]
  isOnline: boolean
}

@Entry
@Component
export struct DeviceActivityPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State rows: ActRow[] = []
  @State sampled: boolean = false
  @State nowHour: number = -1
  private api: ApiService = new ApiService()
  private fun: FunStore = FunStore.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.nowHour = new Date().getHours()
    this.load()
  }

  async load(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        await this.fun.init(hostCtx as Context)
      }
      // 1. 采样：当前在线设备 → 记录当前小时活跃
      const devs: ConnectedDevice[] = await this.api.fetchConnectedDevices()
      const macs: string[] = []
      for (let i = 0; i < devs.length; i++) {
        if (devs[i].mac) {
          macs.push(devs[i].mac)
        }
      }
      this.fun.addActivity(macs)
      this.sampled = true
      // 2. 读今日活跃数据
      const data: Record<string, string[]> = this.fun.getTodayActivity()
      // 3. 组装行：在线设备优先（有名字），再补历史活跃的离线设备
      const macToDev: Record<string, ConnectedDevice> = {}
      for (let i = 0; i < devs.length; i++) {
        macToDev[devs[i].mac] = devs[i]
      }
      const list: ActRow[] = []
      const added: Record<string, boolean> = {}
      // 先在线设备
      for (let i = 0; i < devs.length; i++) {
        const d: ConnectedDevice = devs[i]
        const hours: string[] = data[d.mac]
        const hb: boolean[] = []
        for (let h = 0; h < 24; h++) {
          hb.push(hours ? hours[h] === '1' : false)
        }
        list.push({
          name: d.hostname || d.vendor || d.ip,
          mac: d.mac,
          hours: hb,
          isOnline: true
        })
        added[d.mac] = true
      }
      // 再历史活跃但当前离线的设备
      const macKeys: string[] = Object.keys(data)
      for (let i = 0; i < macKeys.length; i++) {
        const mac: string = macKeys[i]
        if (!added[mac]) {
          const hours: string[] = data[mac]
          const hb: boolean[] = []
          for (let h = 0; h < 24; h++) {
            hb.push(hours ? hours[h] === '1' : false)
          }
          list.push({
            name: `设备 ${mac.length >= 17 ? mac.substring(mac.length - 5) : mac}`,
            mac: mac,
            hours: hb,
            isOnline: false
          })
        }
      }
      this.rows = list
    } catch (e) {
      hilog.error(0x0001, 'Activity', `load err: ${String(e)}`)
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('设备作息热力图')
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

      // 说明卡
      Row() {
        Text(this.sampled ? '✅ 已采样本时段活跃' : '⏳ 正在采样在线设备...')
          .fontSize(11).fontColor(this.theme.textTertiary)
        Blank()
        if (this.nowHour >= 0) {
          Text(`当前 ${this.nowHour}:00`)
            .fontSize(11).fontColor(this.theme.primary)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 2 })

      Scroll() {
        Column() {
          ForEach(this.rows, (row: ActRow) => {
            Column() {
              Row() {
                Circle({ width: 6, height: 6 })
                  .fill(row.isOnline ? '#00C853' : '#C9C4B8')
                Text(row.name)
                  .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 6 }).layoutWeight(1)
                Text(row.isOnline ? '在线' : '离线')
                  .fontSize(9).fontColor(row.isOnline ? '#00C853' : '#B0A99A')
              }
              .width('100%')

              // 24 小时色块
              Row() {
                ForEach(row.hours, (active: boolean, h: number) => {
                  Column() {
                    Text('')
                      .width('100%')
                      .aspectRatio(1)
                  }
                  .layoutWeight(1)
                  .margin({ right: h < 23 ? 2 : 0 })
                  .borderRadius(3)
                  .backgroundColor(active ? '#FF8A3D' : (h === this.nowHour ? '#FFD9BC' : '#F0EBE0'))
                }, (active: boolean, h: number): string => `${row.mac}_${h}_${active}`)
              }
              .width('100%')
              .margin({ top: 8 })

              // 小时刻度
              Row() {
                Text('0').fontSize(8).fontColor(this.theme.textTertiary)
                Blank()
                Text('6').fontSize(8).fontColor(this.theme.textTertiary)
                Blank()
                Text('12').fontSize(8).fontColor(this.theme.textTertiary)
                Blank()
                Text('18').fontSize(8).fontColor(this.theme.textTertiary)
                Blank()
                Text('23').fontSize(8).fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .margin({ top: 2 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 10 })
            .borderRadius(16)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
          }, (row: ActRow): string => row.mac)

          if (this.rows.length === 0) {
            Text('还没有活跃记录，多打开几次本页就会累积')
              .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 30 })
          }

          Row() {
            Text('↻ 刷新采样')
              .fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
          }
          .width('100%').height(44).borderRadius(22)
          .backgroundColor('#FF8A3D')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })
          .onClick(() => { this.load() })
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
