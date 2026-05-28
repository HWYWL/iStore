/**
 * 登录页面
 * 功能：
 * - 管理已保存的设备列表（增删改查，持久化存储）
 * - 连接指定的路由器设备（支持超时处理）
 * - 主题切换（深色/浅色模式）
 * - 连接成功后跳转到主仪表盘（MainPage）
 */
import { AppState } from '../../common/store/AppState'
import { SavedDevice } from '../../common/store/DeviceStore'
import { ConnectionConfig } from '../../models/Models'
import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct LoginPage {
  // ========== 表单状态 ==========
  @State host: string = ''
  @State port: string = '80'
  @State token: string = ''
  @State label: string = ''
  @State isConnecting: boolean = false
  @State isSaving: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @State showToken: boolean = false
  @State savedDevices: SavedDevice[] = []
  @State showAddForm: boolean = false
  @State editingId: string = ''
  @State connectingId: string = ''
  @State formVersion: number = 0
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  private appState: AppState = AppState.getInstance()
  private connectTimerId: number = -1  // 连接超时定时器 ID

  /** 页面初始化：加载设备列表，检查是否已有活动连接 */
  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context
    await this.appState.init(ctx)
    this.savedDevices = this.appState.devices
    this.isDark = this.appState.isDarkMode
    this.theme = this.appState.getTheme()

    this.appState.onThemeChange(() => {
      this.isDark = this.appState.isDarkMode
      this.theme = this.appState.getTheme()
    })

    // 如果已有活动连接，直接跳转到仪表盘
    if (this.appState.getActiveDeviceId()) {
      try {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/dashboard/MainPage' })
      } catch (e) {
        hilog.error(0x0001, 'LoginPage', `replaceUrl failed: ${e}`)
      }
    }
  }

  /** 从表单输入构造连接配置 */
  getConfig(): ConnectionConfig {
    const host: string = this.host.trim()
    const port: string = this.port || '80'
    return {
      host: host,
      port: Number(port) || 80,
      token: this.token,
      useHttps: false
    }
  }

  /** 保存/更新设备到持久化存储 */
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
          token: config.token,
          useHttps: false,
          lastConnected: existing ? existing.lastConnected : Date.now(),
          version: existing ? existing.version : 0,
          username: existing ? existing.username : '',
          password: existing ? existing.password : ''
        }
        this.editingId = ''
      } else {
        const rand: string = Math.random().toString(36).substring(2, 10)
        device = {
          id: `${config.host}_${rand}`,
          label: deviceLabel,
          host: config.host,
          port: String(config.port),
          token: config.token,
          useHttps: false,
          lastConnected: Date.now(),
          version: 0,
          username: '',
          password: ''
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

  /** 连接设备并进入主页面，支持 8 秒超时 */
  async connectAndEnter(savedDevice?: SavedDevice): Promise<void> {
    // 优先使用已保存设备的参数，否则使用表单输入值
    const host: string = savedDevice ? savedDevice.host : this.host.trim()
    const port: string = savedDevice ? savedDevice.port : this.port
    const token: string = savedDevice ? savedDevice.token : this.token
    const config: ConnectionConfig = { host, port: Number(port) || 80, token, useHttps: false }

    if (!host) {
      this.errorMessage = '请输入设备地址'
      return
    }

    this.isConnecting = true
    this.errorMessage = ''
    this.connectingId = savedDevice ? savedDevice.id : ''
    let timedOut: boolean = false

    // 启动 8 秒超时定时器
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
      // 如果没有保存设备，先创建新设备并持久化
      if (!savedDevice) {
        const device: SavedDevice = {
          id: `${config.host}_${Math.random().toString(36).substring(2, 10)}`,
          label: config.host,
          host: config.host,
          port: String(config.port),
          token: config.token,
          useHttps: false,
          lastConnected: Date.now(),
          version: 0,
          username: '',
          password: ''
        }
        await this.appState.saveDevice(device)
        savedDevice = device
      }

      // 执行实际连接
      const connected: boolean = await this.appState.connectToDevice(savedDevice.id)

      // 超时后不再处理结果
      if (timedOut) return
      if (this.connectTimerId !== -1) {
        clearTimeout(this.connectTimerId)
        this.connectTimerId = -1
      }

      if (connected) {
        // 连接成功，跳转到主仪表盘
        this.isConnecting = false
        this.connectingId = ''
        try {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/dashboard/MainPage' })
        } catch (e) {
          hilog.error(0x0001, 'LoginPage', `pushUrl failed: ${e}`)
        }
      } else {
        // 连接失败，显示具体错误信息
        this.isConnecting = false
        this.connectingId = ''
        const lastErr: string = this.appState.getLastError()
        if (lastErr) {
          this.errorMessage = lastErr
        } else {
          this.errorMessage = '连接失败，请检查地址和 Token'
        }
        setTimeout(() => { this.errorMessage = '' }, 10000)
      }
    } catch (netErr) {
      // 网络异常处理
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
    this.token = ''
    this.label = ''
    this.editingId = ''
    this.errorMessage = ''
    this.formVersion = 0
  }

  fillForm(device: SavedDevice): void {
    this.host = device.host
    this.port = device.port
    this.token = device.token
    this.label = device.label
    this.editingId = device.id
    this.formVersion++
    this.errorMessage = ''
    this.showAddForm = true
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
              }, (item: SavedDevice): string => `${item.id}_v${item.version}`)
            }

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

                Row() {
                  TextInput({ placeholder: '端口', text: this.port })
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent').type(InputType.Number)
                    .onChange((v: string) => { this.port = v })
                    .width('30%').height(48)
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard).backdropBlur(10)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 14 }).margin({ bottom: 10 })

                Row() {
                  TextInput({ placeholder: 'Token', text: this.token })
                    .type(this.showToken ? InputType.Normal : InputType.Password)
                    .placeholderColor(this.theme.textTertiary).fontColor(this.theme.textPrimary)
                    .backgroundColor('transparent')
                    .onChange((v: string) => { this.token = v })
                    .layoutWeight(1).height(48)
                  Text(this.showToken ? '◉' : '◎')
                    .fontSize(18).fontColor(this.theme.textSecondary).padding(8)
                    .onClick(() => { this.showToken = !this.showToken })
                }
                .width('100%').height(48).borderRadius(12)
                .backgroundColor(this.theme.bgCard)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .padding({ left: 14, right: 8 }).margin({ bottom: 16 })

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
              Row() {
                Text('⚠ ' + this.errorMessage)
                  .fontSize(13).fontColor(this.theme.danger)
                  .layoutWeight(1)
              }
              .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(12).margin({ top: 14 })
              .backgroundColor(this.isDark ? 'rgba(255, 82, 82, 0.1)' : 'rgba(255, 82, 82, 0.05)')
              .border({ width: 0.5, color: this.isDark ? 'rgba(255, 82, 82, 0.25)' : 'rgba(255, 82, 82, 0.15)' })
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
