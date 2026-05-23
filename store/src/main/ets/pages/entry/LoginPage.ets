import { AppState } from '../../common/store/AppState'
import { SavedDevice } from '../../common/store/DeviceStore'
import { ConnectionConfig } from '../../models/Models'
import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct LoginPage {
  @State host: string = ''
  @State port: string = '80'
  @State username: string = 'root'
  @State password: string = ''
  @State label: string = ''
  @State isConnecting: boolean = false
  @State isSaving: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @State showPassword: boolean = false
  @State savedDevices: SavedDevice[] = []
  @State showAddForm: boolean = false
  @State editingId: string = ''
  @State connectingId: string = ''
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  private appState: AppState = AppState.getInstance()
  private connectTimerId: number = -1

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = getContext(this) as common.Context
    await this.appState.init(ctx)
    this.savedDevices = this.appState.devices
    this.isDark = this.appState.isDarkMode
    this.theme = this.appState.getTheme()

    this.appState.onThemeChange(() => {
      this.isDark = this.appState.isDarkMode
      this.theme = this.appState.getTheme()
    })

    // 如果已有活跃连接，直接进入主页面
    if (this.appState.getActiveDeviceId()) {
      try {
        router.replaceUrl({ url: 'pages/dashboard/MainPage' })
      } catch (e) {
        hilog.error(0x0001, 'LoginPage', `replaceUrl failed: ${e}`)
      }
    }
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
      useHttps: false
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
        const existing: SavedDevice | undefined = this.appState.getDeviceById(this.editingId)
        device = {
          id: this.editingId,
          label: deviceLabel,
          host: config.host,
          port: String(config.port),
          username: config.username,
          password: config.password,
          useHttps: false,
          lastConnected: existing ? existing.lastConnected : Date.now()
        }
        this.editingId = ''
      } else {
        const rand: string = Math.random().toString(36).substring(2, 10)
        device = {
          id: `${config.host}_${rand}`,
          label: deviceLabel,
          host: config.host,
          port: String(config.port),
          username: config.username,
          password: config.password,
          useHttps: false,
          lastConnected: Date.now()
        }
      }

      await this.appState.saveDevice(device)
      this.savedDevices = this.appState.devices
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
    const config: ConnectionConfig = { host, port: Number(port) || 80, username, password, useHttps: false }

    if (!host) {
      this.errorMessage = '请输入设备地址'
      return
    }

    this.isConnecting = true
    this.errorMessage = ''
    this.connectingId = savedDevice ? savedDevice.id : ''
    let timedOut: boolean = false

    // 超时处理
    this.connectTimerId = setTimeout(() => {
      if (this.isConnecting) {
        timedOut = true
        this.isConnecting = false
        this.connectingId = ''
        this.errorMessage = '连接超时，请检查设备地址和网络'
        setTimeout(() => { this.errorMessage = '' }, 4000)
      }
    }, 8000)

    try {
      // 如果是已保存的设备，先确保它在列表中存在
      if (!savedDevice) {
        const device: SavedDevice = {
          id: `${config.host}_${Math.random().toString(36).substring(2, 10)}`,
          label: config.host,
          host: config.host,
          port: String(config.port),
          username: config.username,
          password: config.password,
          useHttps: false,
          lastConnected: Date.now()
        }
        await this.appState.saveDevice(device)
        savedDevice = device
      }

      const connected: boolean = await this.appState.connectToDevice(savedDevice.id)

      if (timedOut) return
      if (this.connectTimerId !== -1) {
        clearTimeout(this.connectTimerId)
        this.connectTimerId = -1
      }

      if (connected) {
        this.isConnecting = false
        this.connectingId = ''
        try {
          router.pushUrl({ url: 'pages/dashboard/MainPage' })
        } catch (e) {
          hilog.error(0x0001, 'LoginPage', `pushUrl failed: ${e}`)
        }
      } else {
        this.isConnecting = false
        this.connectingId = ''
        // 显示 ApiClient 中的详细错误信息
        const lastErr: string = this.appState.getLastError()
        if (lastErr) {
          this.errorMessage = lastErr
        } else {
          this.errorMessage = '连接失败，请检查地址和凭据'
        }
        setTimeout(() => { this.errorMessage = '' }, 5000)
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
      setTimeout(() => { this.errorMessage = '' }, 4000)
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
    await this.appState.removeDevice(id)
    this.savedDevices = this.appState.devices
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
      Column() {
        // 顶部：Logo + 主题切换
        Row() {
          Blank()
          Row() {
            Text(this.isDark ? '☀️' : '🌙').fontSize(20)
          }
          .width(40).height(40).borderRadius(20)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.appState.toggleTheme()
          })
          .margin({ right: 16, top: 8 })
        }
        .width('100%')

        Column() {
          Image($r('app.media.logo'))
            .width(80).height(80).borderRadius(20)
            .objectFit(ImageFit.Cover)
            .margin({ top: 24 })

          Text('iStore')
            .fontSize(40).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            .margin({ top: 16 })

          Text('路由器设备管理')
            .fontSize(14).fontColor(this.theme.textSecondary).margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 20 })

        Scroll() {
          Column() {
            if (this.savedDevices.length > 0) {
              Text('我的设备')
                .fontSize(12).fontColor(this.theme.textTertiary)
                .width('100%').padding({ left: 4, bottom: 8 })

              ForEach(this.savedDevices, (device: SavedDevice) => {
                Column() {
                  Row() {
                    Stack() {
                      Image($r('app.media.logo'))
                        .width(40).height(40).borderRadius(10)
                        .objectFit(ImageFit.Cover)
                        .opacity(this.connectingId === device.id ? 0.4 : 1)

                      if (this.connectingId === device.id) {
                        LoadingProgress().width(22).height(22).color(this.theme.primary)
                      }
                    }
                    .width(40).height(40)

                    Column() {
                      Text(device.label || device.host)
                        .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        Text(device.host)
                          .fontSize(10).fontColor(this.theme.textTertiary).margin({ right: 6 })
                        Text(`:${device.port}`)
                          .fontSize(10).fontColor(this.theme.textTertiary)
                        if (this.connectingId === device.id) {
                          Text(' · 连接中...')
                            .fontSize(10).fontColor(this.theme.primary)
                        }
                      }
                    }
                    .margin({ left: 10 }).alignItems(HorizontalAlign.Start).layoutWeight(1)

                    Text('✏️')
                      .fontSize(16).fontColor(this.theme.textTertiary).padding(8)
                      .onClick(() => { this.fillForm(device) })

                    Text('🗑')
                      .fontSize(16).fontColor(this.theme.textTertiary).padding(8)
                      .onClick(() => { this.deleteDevice(device.id) })
                  }
                  .width('100%')
                  .onClick(() => { this.connectAndEnter(device) })
                }
                .width('100%').padding(14).borderRadius(16).margin({ top: 6 })
                .backgroundColor(this.theme.bgCard).backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
              }, (item: SavedDevice): string => item.id)
            }

            // 添加新设备按钮
            Row() {
              Text(this.showAddForm ? '收起 ▲' : '+ 添加新设备')
                .fontSize(12).fontColor(this.theme.textSecondary)
                .padding({ top: 8, bottom: 8 })
            }
            .width('100%').justifyContent(FlexAlign.Center)
            .onClick(() => { this.toggleAddForm() })
            .margin({ top: this.savedDevices.length > 0 ? 8 : 0 })

            if (this.showAddForm) {
              Column() {
                // 名称
                Row() {
                  TextInput({ placeholder: '设备名称（可选）', text: this.label })
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.label = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard).backdropBlur(10)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                // 地址
                Row() {
                  TextInput({ placeholder: 'IP 地址（如 192.168.1.1）', text: this.host })
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.host = v })
                    .layoutWeight(1).height(48)
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard).backdropBlur(10)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                // 端口 + 用户 一行
                Row() {
                  TextInput({ placeholder: '端口', text: this.port })
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent').type(InputType.Number)
                    .onChange((v: string) => { this.port = v })
                    .width('30%').height(48)

                  TextInput({ placeholder: '用户名', text: this.username })
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.username = v })
                    .layoutWeight(1).height(48).margin({ left: 10 })
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard).backdropBlur(10)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                // 密码
                Row() {
                  TextInput({ placeholder: '密码', text: this.password })
                    .type(this.showPassword ? InputType.Normal : InputType.Password)
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.password = v })
                    .layoutWeight(1).height(48)
                  Text(this.showPassword ? '◉' : '◎')
                    .fontSize(18).fontColor(this.theme.textSecondary).padding(8)
                    .onClick(() => { this.showPassword = !this.showPassword })
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 8 }).margin({ bottom: 16 })

                // 按钮
                Row() {
                  Button() {
                    Text('保存设备')
                      .fontSize(14).fontColor(this.theme.textPrimary)
                  }
                  .width('47%').height(44).borderRadius(100)
                  .backgroundColor(this.theme.bgCard)
                  .border({ width: 1, color: this.theme.borderGlass })
                  .enabled(!this.isSaving)
                  .onClick(() => { this.doSave() })

                  Button() {
                    Text('连接并进入')
                      .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                  }
                  .width('47%').height(44).borderRadius(100)
                  .linearGradient({ angle: 135, colors: [[this.theme.primary, 0], [this.theme.secondary, 1]] })
                  .enabled(!this.isConnecting && !this.isSaving)
                  .onClick(() => { this.connectAndEnter() })
                }
                .width('100%').justifyContent(FlexAlign.SpaceBetween)
              }
              .animation({ duration: 300, curve: Curve.FastOutSlowIn })
            }

            if (this.errorMessage) {
              Text(this.errorMessage)
                .fontSize(12).fontColor(this.theme.danger)
                .width('100%').textAlign(TextAlign.Center)
                .margin({ top: 12, bottom: 4 })
            }

            if (this.successMessage) {
              Text(this.successMessage)
                .fontSize(12).fontColor(this.theme.success)
                .width('100%').textAlign(TextAlign.Center)
                .margin({ top: 12, bottom: 4 })
            }
          }
          .width('100%').padding({ left: 20, right: 20, bottom: 40 })
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.isDark ? '#0A0E27' : '#E8ECF1')
  }
}
