import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { promptAction } from '@kit.ArkUI'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { getAppVersion } from '../../common/utils/AppVersion'
import { AppNav } from '../../common/utils/AppNav'

const VERSION_URL = 'https://raw.githubusercontent.com/HWYWL/iStore/main/api/version.json'
const PROJECT_URL = 'https://github.com/HWYWL/iStore'
const QQ_GROUP = '1101685827'

@Entry
@Component
struct AboutPageRoute {
  build() {
    Column() {
      AboutPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct AboutPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State latestVersion: string = '点击下方按钮检查'
  @State isReady: boolean = false
  @State checking: boolean = false     // 检查更新中
  @State checkDone: boolean = false    // 已完成检查
  @State checkText: string = ''        // 检查结果提示（已是最新/发现新版本/获取失败）

  /** 复制 QQ 群号到剪贴板，弹窗提示，1.5 秒后消失 */
  copyQqGroup(): void {
    try {
      const sysPaste: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, QQ_GROUP)
      sysPaste.setData(data).then(() => {
        this.showCopyToast()
      }).catch((e: Error) => {
        hilog.error(0x0001, 'AboutPage', `copy failed: ${JSON.stringify(e)}`)
      })
    } catch (e) {
      hilog.error(0x0001, 'AboutPage', `copy err: ${JSON.stringify(e)}`)
    }
  }

  private showCopyToast(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '复制成功',
        duration: 1500
      })
    } catch (e) {
      hilog.error(0x0001, 'AboutPage', `toast err: ${JSON.stringify(e)}`)
    }
  }

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    // 直接进入页面，不阻塞等待远程版本（由「检查更新」按钮触发）
    this.latestVersion = '点击下方按钮检查'
    this.isReady = true
  }

  /** 检查更新：点击按钮才请求远程版本信息 */
  async checkUpdate(): Promise<void> {
    if (this.checking) return
    this.checking = true
    this.checkDone = false
    this.checkText = ''
    let req: http.HttpRequest | null = null
    try {
      req = http.createHttp()
      const result = await Promise.race([
        req.request(VERSION_URL, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 4000,
          readTimeout: 4000
        }),
        new Promise<null>(r => setTimeout(() => r(null), 5000))
      ])
      if (result && (result as http.HttpResponse).responseCode === 200) {
        const resp = result as http.HttpResponse
        let bodyStr = ''
        if (typeof resp.result === 'string') {
          bodyStr = resp.result as string
        } else {
          const decoder = new util.TextDecoder('utf-8')
          bodyStr = decoder.decodeToString(new Uint8Array(resp.result as ArrayBuffer))
        }
        const body = JSON.parse(bodyStr) as Record<string, Object>
        const ver: string = (body['version'] as string) || ''
        if (ver) {
          this.latestVersion = ver
          const cur: string = getAppVersion()
          if (this.isNewer(ver, cur)) {
            this.checkText = `发现新版本 ${ver}，当前 ${cur}`
          } else {
            this.checkText = '已是最新版本'
          }
        } else {
          this.latestVersion = '获取失败'
          this.checkText = '版本信息解析失败，可重试'
        }
      } else {
        this.latestVersion = '获取失败'
        this.checkText = '网络异常，可重试'
      }
    } catch (_e) {
      this.latestVersion = '获取失败'
      this.checkText = '网络异常，可重试'
    } finally {
      try { req?.destroy() } catch (_e) {}
    }
    this.checking = false
    this.checkDone = true
  }

  /** 版本号比较：remote > current 返回 true */
  private isNewer(remote: string, cur: string): boolean {
    try {
      const r: number[] = remote.split('.').map((x: string) => parseInt(x) || 0)
      const c: number[] = cur.split('.').map((x: string) => parseInt(x) || 0)
      const max: number = Math.max(r.length, c.length)
      for (let i = 0; i < max; i++) {
        const rv: number = i < r.length ? r[i] : 0
        const cv: number = i < c.length ? c[i] : 0
        if (rv > cv) return true
        if (rv < cv) return false
      }
      return false
    } catch (e) {
      return false
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        Row() {
          Row() {
            Text(' 关于')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try {
              AppNav.getInstance().back()
            } catch (e) {
              hilog.error(0x0001, 'AboutPage', `router.back failed: ${e}`)
            }
          })
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Scroll() {
          Column() {
            Column() {
              Image($r('app.media.logo'))
                .width(72).height(72).borderRadius(18)
                .objectFit(ImageFit.Cover)
                .margin({ bottom: 12 })

              Text('iStore 路由管家')
                .fontSize(24)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4 })

              Text('基于 OpenWrt 的路由器管理工具')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
            }
            .width('100%')
            .padding({ top: 20, bottom: 20 })
            .borderRadius(14)
            .margin({ top: 4 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
            .alignItems(HorizontalAlign.Center)

            Column() {
              Text('版本信息')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('当前版本', getAppVersion())

              // 最新版本行（带检查更新按钮）
              Row() {
                Text('最新版本')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                  .width(68)
                Text(this.latestVersion)
                  .fontSize(12)
                  .fontColor(this.checkText.includes('发现新版本') ? '#00C853' : this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium)
                Blank()
                if (this.checking) {
                  Row() {
                    LoadingProgress().width(14).height(14).color('#FF8A3D')
                    Text('  检查中...').fontSize(11).fontColor(this.theme.primary)
                  }
                } else {
                  Row() {
                    Text(this.checkDone ? (this.checkText.includes('发现新版本') ? '去更新' : '再查一次') : '检查更新')
                      .fontSize(11)
                      .fontColor(this.checkDone && this.checkText.includes('发现新版本') ? '#FFFFFF' : this.theme.primary)
                      .fontWeight(FontWeight.Bold)
                  }
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .borderRadius(14)
                  .backgroundColor(this.checkDone && this.checkText.includes('发现新版本') ? '#FF8A3D' : 'rgba(255,138,61,0.1)')
                  .onClick(() => { this.checkUpdate() })
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })

              if (this.checkText) {
                Text(this.checkText)
                  .fontSize(10)
                  .fontColor(this.checkText.includes('发现新版本') ? '#00C853' : this.theme.textTertiary)
                  .margin({ top: 6 })
                  .width('100%')
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('作者信息')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('作者', '一叶秋枫')

              // Q 群行（含复制按钮）
              Row() {
                Text('QQ 群')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                  .width(68)
                Text(QQ_GROUP)
                  .fontSize(12)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Medium)
                Blank()
                // 复制按钮（save 图标）
                Row() {
                  Image($r('app.media.app_copy'))
                    .width(16).height(16)
                }
                .width(28).height(28).borderRadius(14)
                .backgroundColor('rgba(68,138,255,0.1)')
                .justifyContent(FlexAlign.Center)
                .onClick(() => this.copyQqGroup())
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('项目地址')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              Row() {
                Text(PROJECT_URL)
                  .fontSize(11)
                  .fontColor(this.theme.primary)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(' 🔗')
                  .fontSize(14)
                  .margin({ left: 6 })
              }
              .width('100%')
              .onClick(() => {
                try {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
                  ctx.openLink(PROJECT_URL)
                } catch (e) {
                  hilog.error(0x0001, 'AboutPage', `openLink failed: ${e}`)
                }
              })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Column() {
              Text('鸣谢')
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })
                .width('100%')

              this.infoRow('开发框架', 'HarmonyOS NEXT ArkTS')
              this.infoRow('系统要求', 'HarmonyOS 6.1.0+')
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 10 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })

            Text('© 2026 iStore 一叶秋枫')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 20, bottom: 12 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder infoRow(label: string, value: string, valueColor?: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .width(68)
      Text(value)
        .fontSize(12)
        .fontColor(valueColor || this.theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
  }
}
