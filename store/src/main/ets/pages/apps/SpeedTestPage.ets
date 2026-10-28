/**
 * 网速全国排位赛
 * wget 下载已知大小测试文件计时测速，按档位给出「击败全国 xx%」排位
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { ApiService } from '../../api/ApiService'
import { SshService } from '../../common/ssh/SshService'
import { http } from '@kit.NetworkKit'
import { componentSnapshot } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { systemShare } from '@kit.ShareKit'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

// 固定大小测速文件：完整下载后从响应体取字节数（不依赖 dataReceive 事件）
interface TestFile {
  url: string
  size: number      // 请求的字节数（HTTP Range 分块，10MB/1MB）
  timeout: number   // 毫秒
}

// 国内源 + Range 分块：只下载固定大小数据块，完整拿到即算速（不依赖事件/路由器）
const TEST_FILES: TestFile[] = [
  { url: 'https://dldir1.qq.com/weixin/Windows/WeChatSetup.exe', size: 10 * 1024 * 1024, timeout: 12000 },
  { url: 'https://mirrors.aliyun.com/ubuntu-releases/22.04/ubuntu-22.04.3-live-server-amd64.iso', size: 10 * 1024 * 1024, timeout: 12000 },
  { url: 'https://dldir1.qq.com/weixin/Windows/WeChatSetup.exe', size: 1024 * 1024, timeout: 8000 }
]

@Entry
@Component
struct SpeedTestPageRoute {
  build() {
    Column() {
      SpeedTestPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SpeedTestPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State testing: boolean = false
  @State done: boolean = false
  @State mbps: number = 0
  @State rankText: string = ''
  @State rankKey: string = 'bolt'
  @State note: string = ''
  @State countdown: number = 0      // 测速倒计时（秒）
  @State showCard: boolean = false  // 小红书风分享卡
  private countTimer: number = -1
  private api: ApiService = new ApiService()
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false

  /** App 侧 HTTP 下载测速：限时下载累计字节数（不依赖路由器命令） */
  /** 完整下载固定大小文件，返回 [字节数, 耗时ms]（不依赖 dataReceive） */
  /** Range 分块下载：请求固定大小数据块，完整拿到 result 即算速（不依赖 dataReceive 事件） */
  private async appDownload(file: TestFile, msLimit: number): Promise<number[]> {
    const req: http.HttpRequest = http.createHttp()
    const t0: number = Date.now()
    try {
      const hdr: Record<string, string> = { 'Range': `bytes=0-${file.size - 1}` }
      const resp: http.HttpResponse = await req.request(file.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: msLimit,
        header: hdr
      })
      const ms: number = Date.now() - t0
      if (resp.responseCode === 206) {
        const arr: ArrayBuffer = resp.result as ArrayBuffer
        return [arr.byteLength, ms]
      }
      hilog.error(0x0001, 'SpeedTest', `src no-range code=${resp.responseCode}`)
      return [0, ms]
    } catch (e) {
      const ec: Record<string, Object> = e as Record<string, Object>
      hilog.error(0x0001, 'SpeedTest', `dl err code=${ec['code']} msg=${ec['message']}`)
      return [0, Date.now() - t0]
    } finally {
      try { req.destroy() } catch (e) {}
    }
  }

  /** SSH 执行命令（懒连接，失败返回空）——wget 不在 rpcd 白名单，必须走 SSH */
  private async sshExec(cmd: string): Promise<string> {
    try {
      if (!this.ssh.isConnected()) {
        if (this.sshTried) return ''
        this.sshTried = true
        const device = AppState.getInstance().getActiveDevice()
        if (!device || !device.username || !device.password) {
          return ''
        }
        const ok: boolean = await this.ssh.connect(device)
        if (!ok) return ''
      }
      return await this.ssh.exec(cmd)
    } catch (e) {
      hilog.error(0x0001, 'SpeedTest', `sshExec err: ${String(e)}`)
      return ''
    }
  }

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
  }

  async runTest(): Promise<void> {
    if (this.testing) return
    this.testing = true
    hilog.error(0x0001, 'SpeedTest', 'runTest begin')
    try {
      this.done = false
      this.showCard = false
      this.note = '正在下载测速文件...'
      this.countdown = 15
      // 15 秒倒计时（UI 显示）
      if (this.countTimer !== -1) {
        clearInterval(this.countTimer)
      }
      this.countTimer = setInterval(() => {
        this.countdown = this.countdown - 1
        if (this.countdown <= 0) {
          clearInterval(this.countTimer)
          this.countTimer = -1
        }
      }, 1000)
      // Range 分块测速：10MB 优先，超时换下一个源，最后 1MB 兜底
      // 每源超时 = min(自身超时, 剩余预算)，保证 15 秒内必出结果
      const t0: number = Date.now()
      let totalBytes: number = 0
      let useMs: number = 0
      for (let i = 0; i < TEST_FILES.length; i++) {
        const elapsed: number = Date.now() - t0
        const remain: number = 15000 - elapsed
        if (remain <= 1200) {
          break
        }
        const limit: number = Math.min(TEST_FILES[i].timeout, remain - 1000)
        const r: number[] = await this.appDownload(TEST_FILES[i], limit)
        const b: number = r[0]
        const el: number = r[1]
        hilog.error(0x0001, 'SpeedTest', `src ${i} bytes=${b} ms=${el}`)
        if (b >= 900 * 1024) {
          totalBytes = b
          useMs = el
          break
        }
      }
      // 等倒计时走完（保证总耗时 ~15 秒）
      while (this.countdown > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 500))
      }
      if (totalBytes > 10000 && useMs > 200) {
        const result: number = (totalBytes * 8) / (useMs / 1000) / 1000000
        this.mbps = result
        this.done = true
        this.note = `下载 ${(totalBytes / 1024 / 1024).toFixed(1)}MB · ${(useMs / 1000).toFixed(1)}s`
        this.rank(result)
      } else {
        this.note = '测速失败：测速源均不可达（请检查外网与防火墙）'
      }
      hilog.error(0x0001, 'SpeedTest', 'runTest end')
    } catch (e) {
      hilog.error(0x0001, 'SpeedTest', `runTest err: ${String(e)}`)
      this.note = '测速异常，请重试'
    } finally {
      this.testing = false
      if (this.countTimer !== -1) {
        clearInterval(this.countTimer)
        this.countTimer = -1
      }
    }
  }

  /** 拉起系统分享（测速结果文本） */
  private async shareResult(): Promise<void> {
    if (!this.done) return
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) return
      // 1. 截图结果卡（小红书风卡片）
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().get('speedCard')
      // 2. 打包 PNG
      const packer: image.ImagePacker = image.createImagePacker()
      const buf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 })
      packer.release()
      // 3. 写文件
      const filePath: string = `${ctx.cacheDir}/speed_card.png`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, buf)
      fs.closeSync(file)
      // 4. 系统分享图片
      const uri: string = fileUri.getUriFromPath(filePath)
      const record: systemShare.SharedRecord = {
        uri: uri,
        title: '我的网速排位',
        description: this.rankText,
        utd: 'general.image'
      }
      const data: systemShare.SharedData = new systemShare.SharedData(record)
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      await controller.show(ctx, {})
    } catch (e) {
      hilog.error(0x0001, 'SpeedTest', `share img err: ${String(e)}`)
    }
  }

  /** 段位图标（统一符号族） */
  rankSymbol(): Resource {
    if (this.rankKey === 'crown') return $r('sys.symbol.crown')
    if (this.rankKey === 'rocket') return $r('sys.symbol.star')
    if (this.rankKey === 'bolt') return $r('sys.symbol.bolt')
    if (this.rankKey === 'smile') return $r('sys.symbol.face_smiling')
    if (this.rankKey === 'calm') return $r('sys.symbol.heart')
    if (this.rankKey === 'clock') return $r('sys.symbol.clock')
    return $r('sys.symbol.battery')
  }

  private rank(mbps: number): void {
    if (mbps >= 900) {
      this.rankKey = 'crown'
      this.rankText = '击败全国 99% 的用户，宽带界的天花板！'
    } else if (mbps >= 300) {
      this.rankKey = 'rocket'
      this.rankText = '击败全国 95% 的用户，飞一般的速度！'
    } else if (mbps >= 100) {
      this.rankKey = 'bolt'
      this.rankText = '击败全国 80% 的用户，网速很能打！'
    } else if (mbps >= 50) {
      this.rankKey = 'smile'
      this.rankText = '击败全国 60% 的用户，中上水平。'
    } else if (mbps >= 20) {
      this.rankKey = 'calm'
      this.rankText = '击败全国 40% 的用户，够用就行。'
    } else if (mbps >= 5) {
      this.rankKey = 'clock'
      this.rankText = '击败全国 10% 的用户…嗯，慢工出细活。'
    } else {
      this.rankKey = 'battery'
      this.rankText = '网速比蜗牛快一点点，建议检查网络。'
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
          Text('网速排位赛')
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
          // 结果卡（小红书风分享卡）：外层米色背景容器保证截图四角不透明（不显示白色）
          if (this.done) {
            Column() {
              Column() {
                Text('⚡ 网速排位赛')
                  .fontSize(12).fontColor('rgba(255,255,255,0.85)')
                SymbolGlyph(this.rankSymbol())
                  .fontSize(44)
                  .fontColor(['#FFFFFF'])
                  .margin({ top: 10 })
                Text(this.mbps.toFixed(1))
                  .fontSize(58).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontFamily('monospace')
                  .margin({ top: 4 })
                Text('Mbps 下载速度')
                  .fontSize(13).fontColor('rgba(255,255,255,0.9)')
                Text(this.rankText)
                  .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                  .margin({ top: 12 }).textAlign(TextAlign.Center)
                Text(this.note)
                  .fontSize(10).fontColor('rgba(255,255,255,0.7)').margin({ top: 8 })
                // 分隔线
                Row()
                  .width('70%').height(0.6)
                  .backgroundColor('rgba(255,255,255,0.4)')
                  .margin({ top: 14 })
                Text('# 网速 # 宽带 # 我家网络真快')
                  .fontSize(11).fontColor('rgba(255,255,255,0.85)').margin({ top: 10 })
              }
              .width('100%').padding({ top: 26, bottom: 26, left: 20, right: 20 })
              .borderRadius(24)
              .linearGradient({
                angle: 135,
                colors: [['#FF9A5C', 0], ['#FF8A3D', 0.55], ['#FF7043', 1]]
              })
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#F6F2EA')
            .margin({ top: 8 })
            .id('speedCard')

          } else {
            Column() {
              Text('🚀').fontSize(46)
              Text('测测你家宽带排第几')
                .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                .margin({ top: 10 })
              Text('下载测试文件测速，约 10~20 秒')
                .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 4 })
            }
            .width('100%').padding(30).borderRadius(24).margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .alignItems(HorizontalAlign.Center)
          }

          if (this.testing) {
            Column() {
              Row() {
                LoadingProgress().width(20).height(20).color('#FF8A3D')
                Text(`  测速中 ${this.countdown}s`).fontSize(12).fontColor(this.theme.textSecondary)
              }
              Progress({ value: 15 - this.countdown, total: 15 })
                .width('70%').height(6).margin({ top: 10 })
                .color('#FF8A3D').backgroundColor('#F0EBE0')
            }
            .width('100%').justifyContent(FlexAlign.Center).margin({ top: 16 })
            .alignItems(HorizontalAlign.Center)
          }

          if (!this.done && this.note) {
            Text(this.note)
              .fontSize(11).fontColor('#FF5252').margin({ top: 12 }).textAlign(TextAlign.Center)
          }

          if (this.done) {
            // 完成：左「再测一次」+ 右「分享测速」（同色系橙色，风格一致）
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(15).fontColor(['#FFFFFF'])
                Text('  再测一次')
                  .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
              .layoutWeight(1).height(46).borderRadius(23)
              .backgroundColor('#FF8A3D')
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.runTest() })

              Row() {
                SymbolGlyph($r('sys.symbol.share'))
                  .fontSize(15).fontColor(['#FFFFFF'])
                Text('  分享测速')
                  .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
              .layoutWeight(1).height(46).borderRadius(23)
              .backgroundColor('#FF8A3D')
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.shareResult() })
            }
            .width('100%').margin({ top: 16 })
          } else {
            Row() {
              Text(this.testing ? '测速中...' : '开始测速')
                .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            }
            .width('100%').height(48).borderRadius(24)
            .backgroundColor(this.testing ? '#C9A98A' : '#FF8A3D')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 16 })
            .onClick(() => { this.runTest() })
          }

          Text('测速使用公共测试服务器，结果仅供参考')
            .fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 12 })
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
