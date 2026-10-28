/**
 * WiFi 访客卡片
 * SSID 自动获取 + 密码手输 → 生成扫码连接卡片，可截图分享给访客
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { WifiApInfo } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct WifiCardPageRoute {
  build() {
    Column() {
      WifiCardPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct WifiCardPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State ssid: string = ''
  @State password: string = ''
  @State qrContent: string = ''
  @State apList: string[] = []
  @State selAp: string = ''
  @State loaded: boolean = false
  private api: ApiService = new ApiService()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.load()
  }

  async load(): Promise<void> {
    try {
      const list: WifiApInfo[] = await this.api.fetchWifiApList()
      const names: string[] = []
      let first: string = ''
      for (let i = 0; i < list.length; i++) {
        if (list[i].ssid) {
          names.push(list[i].ssid)
          if (!first) first = list[i].ssid
        }
      }
      this.apList = names
      this.selAp = first
      this.ssid = first
    } catch (e) {
      hilog.error(0x0001, 'WifiCard', `load err: ${String(e)}`)
    }
    this.loaded = true
  }

  /** 生成二维码内容（WIFI 标准格式） */
  buildQr(): void {
    const pass: string = this.password.trim()
    if (!this.ssid) return
    this.qrContent = `WIFI:T:WPA;S:${this.ssid};P:${pass};;`
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('‹')
            .fontSize(22).fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 6 })
          Text('WiFi 访客卡片')
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
          // 卡片
          Column() {
            SymbolGlyph($r('sys.symbol.wifi'))
              .fontSize(38)
              .fontColor([this.theme.primary])
            Text('欢迎连我的 WiFi')
              .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              .margin({ top: 8 })
            Text(this.ssid || 'WiFi 名称')
              .fontSize(20).fontColor('#FF8A3D').fontWeight(FontWeight.Bold).fontFamily('monospace')
              .margin({ top: 6 })

            // 二维码
            if (this.qrContent) {
              Column() {
                QRCode(this.qrContent)
                  .width(160).height(160)
                  .backgroundColor('#FFFFFF')
                  .padding(8)
              }
              .borderRadius(16).padding(10).backgroundColor('#FFFFFF')
              .margin({ top: 12 })
              Text('手机相机扫码即可连接')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 8 })
            } else {
              Column() {
                Text('输入密码后生成二维码')
                  .fontSize(11).fontColor('#B0A99A')
              }
              .width(160).height(160).borderRadius(16)
              .border({ width: 1, color: '#E5DFD2', style: BorderStyle.Dashed })
              .justifyContent(FlexAlign.Center)
              .margin({ top: 12 })
            }
          }
          .width('100%').padding(22).borderRadius(24).margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .alignItems(HorizontalAlign.Center)

          // 选网络
          Column() {
            Text('选择网络（SSID）')
              .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
            Row({ space: 8 }) {
              ForEach(this.apList, (ap: string) => {
                Text(ap)
                  .fontSize(11)
                  .fontColor(this.selAp === ap ? '#FFFFFF' : this.theme.textPrimary)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor(this.selAp === ap ? '#FF8A3D' : '#F0EBE0')
                  .onClick(() => {
                    this.selAp = ap
                    this.ssid = ap
                    this.buildQr()
                  })
              }, (ap: string): string => ap)
            }
            .width('100%').margin({ top: 8 })

            Text('密码')
              .fontSize(12).fontColor(this.theme.textSecondary).width('100%').margin({ top: 12 })
            TextInput({ placeholder: '输入 WiFi 密码', text: this.password })
              .width('100%').height(42).borderRadius(10)
              .backgroundColor('#F0EBE0')
              .fontSize(13)
              .type(InputType.Password)
              .onChange((v: string) => {
                this.password = v
                this.buildQr()
              })
          }
          .width('100%').padding(16).borderRadius(18).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(13).fontColor(['#F59E0B'])
            Text(' 提示：密码只在本地生成二维码，不会上传或显示明文')
              .fontSize(10).fontColor(this.theme.textTertiary)
              .layoutWeight(1)
          }
          .margin({ top: 12 })
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
