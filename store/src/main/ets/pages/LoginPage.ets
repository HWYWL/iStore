import { StyleConstants } from '../common/constants/StyleConstants'
import { ParticleBackground } from '../common/components/ParticleBackground'
import { GlassCard } from '../common/components/GlassCard'
import { ApiService } from '../api/ApiService'
import { ConnectionConfig } from '../models/Models'
import { DeviceStore, SavedDevice } from '../common/store/DeviceStore'
import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

@Entry
@Component
struct LoginPage {
  @State host: string = ''
  @State port: string = '80'
  @State username: string = 'root'
  @State password: string = ''
  @State label: string = ''
  @State useHttps: boolean = false
  @State isLoading: boolean = true
  @State isConnecting: boolean = false
  @State isSaving: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @State showPassword: boolean = false
  @State heroOpacity: number = 0
  @State formOpacity: number = 0
  @State savedDevices: SavedDevice[] = []
  @State showAddForm: boolean = false
  @State editingId: string = ''
  @State connectingId: string = ''
  @State loaded: boolean = false
  private apiService: ApiService = new ApiService()
  private store: DeviceStore = DeviceStore.getInstance()
  private connectTimerId: number = -1
  private context: common.Context | null = null

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = getContext(this) as common.Context
    this.context = ctx
    await this.store.init(ctx)
    const list: SavedDevice[] = await this.store.loadAll()
    this.savedDevices = list
    this.loaded = true
    this.isLoading = false

    setTimeout(() => { this.heroOpacity = 1 }, 100)
    setTimeout(() => { this.formOpacity = 1 }, 300)
  }

  getConfig(): ConnectionConfig {
    const host: string = this.host.trim()
    const port: string = this.port || '80'
    const username: string = this.username.trim() || 'root'
    return {
      host: host,
      port: Number(port) || 80,
      username: username,
      password: this.password,
      useHttps: this.useHttps
    }
  }

  async doSave(): Promise<void> {
    const host: string = this.host.trim()
    if (!host) {
      this.errorMessage = '请输入设备地址'
      return
    }

    this.isSaving = true
    this.errorMessage = ''
    this.successMessage = ''

    const config: ConnectionConfig = this.getConfig()
    const deviceLabel: string = this.label.trim() || config.host

    try {
      let device: SavedDevice
      if (this.editingId) {
        device = {
          id: this.editingId,
          label: deviceLabel,
          host: config.host,
          port: String(config.port),
          username: config.username,
          password: config.password,
          useHttps: config.useHttps,
          lastConnected: Date.now()
        }
        this.editingId = ''
      } else {
        device = this.store.createDevice(deviceLabel, config)
      }

      await this.store.save(device)
      await this.reloadDeviceList()
      this.successMessage = '设备已保存'
      this.isSaving = false
      this.resetForm()

      setTimeout(() => { this.successMessage = '' }, 2000)
    } catch (e) {
      this.isSaving = false
      this.errorMessage = '保存失败'
    }
  }

  async connectAndEnter(savedDevice?: SavedDevice): Promise<void> {
    const host: string = savedDevice ? savedDevice.host : this.host.trim()
    const port: string = savedDevice ? savedDevice.port : this.port
    const username: string = savedDevice ? savedDevice.username : (this.username.trim() || 'root')
    const password: string = savedDevice ? savedDevice.password : this.password
    const useHttps: boolean = savedDevice ? savedDevice.useHttps : this.useHttps
    const config: ConnectionConfig = { host, port: Number(port) || 80, username, password, useHttps }

    if (!host) {
      this.errorMessage = '请输入 iStoreOS 设备地址'
      this.shakeError()
      return
    }

    this.isConnecting = true
    this.errorMessage = ''
    this.connectingId = savedDevice ? savedDevice.id : ''
    let timedOut: boolean = false

    this.connectTimerId = setTimeout(() => {
      if (this.isConnecting) {
        timedOut = true
        this.isConnecting = false
        this.connectingId = ''
        this.errorMessage = '连接超时，请检查设备地址和网络'
        this.shakeError()
      }
    }, 1500)

    try {
      this.apiService.configureConnection(config)
      const connected: boolean = await this.apiService.connect()

      if (timedOut) return
      if (this.connectTimerId !== -1) {
        clearTimeout(this.connectTimerId)
        this.connectTimerId = -1
      }

      if (connected) {
        if (savedDevice) {
          this.store.recordConnect(savedDevice.id)
        } else {
          const device: SavedDevice = this.store.createDevice(config.host, config)
          this.store.save(device)
          this.store.recordConnect(device.id)
        }
        this.isConnecting = false
        this.connectingId = ''
        router.pushUrl({ url: 'pages/DashboardPage', params: { host: config.host } })
      } else {
        this.isConnecting = false
        this.connectingId = ''
        const apiErr: string = this.apiService.getLastError()
        this.errorMessage = apiErr ? `连接失败: ${apiErr}` : '连接失败，请检查地址和凭据'
        this.shakeError()
      }
    } catch (netErr) {
      if (timedOut) return
      if (this.connectTimerId !== -1) {
        clearTimeout(this.connectTimerId)
        this.connectTimerId = -1
      }
      this.isConnecting = false
      this.connectingId = ''
      this.errorMessage = '网络错误，请检查设备地址和网络连接'
      this.shakeError()
    }
  }

  resetForm(): void {
    this.host = ''
    this.port = '80'
    this.username = 'root'
    this.password = ''
    this.label = ''
    this.editingId = ''
    this.errorMessage = ''
  }

  fillForm(device: SavedDevice): void {
    this.host = device.host
    this.port = device.port
    this.username = device.username
    this.password = device.password
    this.label = device.label
    this.editingId = device.id
    this.showAddForm = true
    this.errorMessage = ''
  }

  async deleteDevice(id: string): Promise<void> {
    await this.store.remove(id)
    this.reloadDeviceList()
  }

  async reloadDeviceList(): Promise<void> {
    const list: SavedDevice[] = await this.store.loadAll()
    this.savedDevices = list
  }

  shakeError(): void {
    setTimeout(() => { this.errorMessage = '' }, 4000)
  }

  toggleAddForm(): void {
    this.showAddForm = !this.showAddForm
    if (this.showAddForm) {
      this.resetForm()
      this.errorMessage = ''
    }
  }

  build() {
    Stack() {
      ParticleBackground()

      Column() {
        Column() {
          Image($r('app.media.device_icon'))
            .width(80).height(80).borderRadius(20)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 30, color: 'rgba(0, 212, 255, 0.3)', offsetX: 0, offsetY: 0 })
            .opacity(this.heroOpacity)
            .animation({ duration: 800, curve: Curve.FastOutSlowIn })

          Text('iStore')
            .fontSize(StyleConstants.FONT_HERO)
            .fontColor(StyleConstants.TEXT_PRIMARY)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 16 })
            .animation({ duration: 600, curve: Curve.EaseOut })

          Text('iStoreOS 设备管理')
            .fontSize(StyleConstants.FONT_MD)
            .fontColor(StyleConstants.TEXT_SECONDARY)
            .margin({ top: 4 })
            .animation({ duration: 600, curve: Curve.EaseOut })
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 48, bottom: 16 })

        Scroll() {
          Column() {
            if (this.savedDevices.length > 0) {
              Text('我的设备')
                .fontSize(StyleConstants.FONT_SM)
                .fontColor(StyleConstants.TEXT_TERTIARY)
                .width('100%')
                .padding({ left: 4, bottom: 8 })

              ForEach(this.savedDevices, (device: SavedDevice, index: number) => {
                GlassCard({ cardWidth: '100%', cardPadding: 12, marginTop: 6, bgOpacity: this.connectingId === device.id ? 0.16 : 0.08 }) {
                  Row() {
                    Stack() {
                      Image($r('app.media.device_icon'))
                        .width(40).height(40).borderRadius(10)
                        .objectFit(ImageFit.Cover)
                        .opacity(this.connectingId === device.id ? 0.4 : 1)

                      if (this.connectingId === device.id) {
                        LoadingProgress()
                          .width(22).height(22)
                          .color(StyleConstants.PRIMARY)
                      }
                    }
                    .width(40).height(40)

                    Column() {
                      Text(device.label || device.host)
                        .fontSize(StyleConstants.FONT_MD)
                        .fontColor(StyleConstants.TEXT_PRIMARY)
                        .fontWeight(FontWeight.Medium)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        Text(device.host)
                          .fontSize(StyleConstants.FONT_XS)
                          .fontColor(StyleConstants.TEXT_TERTIARY)
                          .margin({ right: 6 })
                        Text(`:${device.port}`)
                          .fontSize(StyleConstants.FONT_XS)
                          .fontColor(StyleConstants.TEXT_TERTIARY)
                        if (this.connectingId === device.id) {
                          Text(' · 连接中...')
                            .fontSize(StyleConstants.FONT_XS)
                            .fontColor(StyleConstants.PRIMARY)
                        }
                      }
                    }
                    .margin({ left: 10 })
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text('✏️')
                      .fontSize(16).fontColor(StyleConstants.TEXT_TERTIARY)
                      .padding(8)
                      .onClick(() => { this.fillForm(device) })

                    Text('🗑')
                      .fontSize(16).fontColor(StyleConstants.TEXT_TERTIARY)
                      .padding(8)
                      .onClick(() => { this.deleteDevice(device.id) })
                  }
                  .width('100%')
                  .onClick(() => { this.connectAndEnter(device) })
                }
              }, (item: SavedDevice): string => item.id)
            }

            Row() {
              Text(this.showAddForm ? '收起 ▲' : '+ 添加新设备')
                .fontSize(StyleConstants.FONT_SM)
                .fontColor(StyleConstants.TEXT_SECONDARY)
                .padding({ top: 8, bottom: 8 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.toggleAddForm() })
            .margin({ top: this.savedDevices.length > 0 ? 8 : 0 })

            if (this.showAddForm) {
              Column() {
                Row() {
                  Text('名称').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(64)
                  TextInput({ placeholder: '例如: 家用路由', text: this.label })
                    .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.label = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(StyleConstants.RADIUS_MD)
                .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
                .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                Row() {
                  Text('地址').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(64)
                  TextInput({ placeholder: '192.168.1.1', text: this.host })
                    .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.host = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(StyleConstants.RADIUS_MD)
                .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
                .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                Row() {
                  Text('端口').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(64)
                  TextInput({ placeholder: '80', text: this.port })
                    .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.port = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(StyleConstants.RADIUS_MD)
                .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
                .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                Row() {
                  Text('用户').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).width(64)
                  TextInput({ placeholder: 'root', text: this.username })
                    .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.username = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(StyleConstants.RADIUS_MD)
                .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
                .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                Row() {
                  TextInput({ placeholder: '密码', text: this.password })
                    .type(this.showPassword ? InputType.Normal : InputType.Password)
                    .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.password = v })
                    .layoutWeight(1).height(48)
                  Text(this.showPassword ? '◉' : '◎')
                    .fontSize(18).fontColor(StyleConstants.TEXT_SECONDARY)
                    .padding(8)
                    .onClick(() => { this.showPassword = !this.showPassword })
                }
                .width('100%').height(48).borderRadius(StyleConstants.RADIUS_MD)
                .backgroundColor(StyleConstants.BG_CARD)
                .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
                .padding({ left: 14, right: 8 }).margin({ bottom: 16 })

                Row() {
                  Button() {
                    Text('保存设备')
                      .fontSize(StyleConstants.FONT_MD)
                      .fontColor(StyleConstants.TEXT_PRIMARY)
                  }
                  .width('48%').height(44)
                  .borderRadius(StyleConstants.RADIUS_FULL)
                  .backgroundColor('rgba(255,255,255,0.1)')
                  .border({ width: 1, color: StyleConstants.BORDER_GLASS })
                  .enabled(!this.isSaving)
                  .onClick(() => { this.doSave() })

                  Button() {
                    Text('连接并进入')
                      .fontSize(StyleConstants.FONT_MD)
                      .fontColor(StyleConstants.TEXT_PRIMARY)
                      .fontWeight(FontWeight.Medium)
                  }
                  .width('48%').height(44)
                  .borderRadius(StyleConstants.RADIUS_FULL)
                  .linearGradient({
                    angle: 135,
                    colors: [[StyleConstants.PRIMARY, 0], [StyleConstants.SECONDARY, 1]]
                  })
                  .shadow({ radius: 12, color: 'rgba(0, 212, 255, 0.35)', offsetX: 0, offsetY: 3 })
                  .enabled(!this.isConnecting && !this.isSaving)
                  .onClick(() => { this.connectAndEnter() })
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
              .animation({ duration: 300, curve: Curve.FastOutSlowIn })
            }

            if (this.errorMessage) {
              Text(this.errorMessage)
                .fontSize(StyleConstants.FONT_SM)
                .fontColor(StyleConstants.DANGER)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 12, bottom: 4 })
                .animation({ duration: 300 })
            }

            if (this.successMessage) {
              Text(this.successMessage)
                .fontSize(StyleConstants.FONT_SM)
                .fontColor(StyleConstants.SUCCESS)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 12, bottom: 4 })
                .animation({ duration: 300 })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .opacity(this.formOpacity)
        .animation({ duration: 600, curve: Curve.FastOutSlowIn })
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]]
    })
  }
}
