/**
 * JellyfinPlayerPage — Jellyfin 视频播放页
 * 全屏播放：加载态 → Video 播放（网络流直链）
 */
import { AppState } from '../../common/store/AppState'
import { ThemePalette } from '../../common/theme/ThemeColors'
import { JellyfinStore, JellyfinConfig } from '../../common/store/JellyfinStore'
import { JellyfinClient, PlaybackInfo } from '../../api/JellyfinClient'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct JellyfinPlayerPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State loading: boolean = true
  @State errorText: string = ''
  @State playUrl: string = ''
  private itemId: string = ''
  private itemName: string = ''
  private deviceId: string = ''
  private controller: VideoController = new VideoController()
  private client: JellyfinClient | null = null

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.itemId = (params && params['id'] as string) || ''
    this.itemName = (params && params['name'] as string) || ''
    const dev = AppState.getInstance().getActiveDevice()
    this.deviceId = dev ? dev.id : ''
    this.initPlayback()
  }

  async initPlayback(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!hostCtx || !this.deviceId || !this.itemId) {
        this.errorText = '播放参数缺失'
        this.loading = false
        return
      }
      await JellyfinStore.getInstance().init(hostCtx)
      const cfg: JellyfinConfig | null = await JellyfinStore.getInstance().getConfig(this.deviceId)
      if (!cfg || !cfg.baseUrl || !cfg.token) {
        this.errorText = '未配置 Jellyfin'
        this.loading = false
        return
      }
      const client: JellyfinClient = new JellyfinClient(cfg.baseUrl, cfg.token, cfg.userName, cfg.password || '')
      this.client = client
      const info: PlaybackInfo = await client.getPlaybackInfo(this.itemId, cfg.userId)
      this.playUrl = client.buildStreamUrl(info)
      this.loading = false
      hilog.info(0x0001, 'JellyfinPlayer', `playUrl=${this.playUrl.substring(0, 80)}...`)
    } catch (e) {
      this.errorText = `播放失败：${(e as Error).message || String(e)}`
      this.loading = false
    }
  }

  build() {
    Stack() {
      // 视频背景（全屏黑）
      Column()
        .width('100%').height('100%')
        .backgroundColor('#000000')

      if (this.loading) {
        Column() {
          LoadingProgress().width(44).height(44).color(this.theme.primary)
          Text('加载播放流…').fontSize(13).fontColor('#B4AFA4').margin({ top: 12 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorText) {
        Column() {
          Text('⚠ ' + this.errorText)
            .fontSize(13).fontColor('#FF6B6B').textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
          Text('返回').fontSize(14).fontColor(this.theme.primary).padding({ top: 16 })
            .onClick(() => { AppNav.getInstance().back() })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 视频播放
        Video({
          src: this.playUrl,
          controller: this.controller
        })
          .width('100%').height('100%')
          .controls(true)
          .objectFit(ImageFit.Contain)
          .autoPlay(true)
          .onError((err: Error) => {
            hilog.error(0x0001, 'JellyfinPlayer', `video err: ${JSON.stringify(err)}`)
            this.errorText = '视频播放失败（可能格式不支持）'
          })
      }

      // 返回按钮（顶部悬浮）
      Row() {
        Text('‹')
          .fontSize(28).fontColor('#FFFFFF')
          .width(40).height(40)
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(20)
          .textAlign(TextAlign.Center)
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%')
      .padding({ left: 16, top: 36 })
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
  }
}
