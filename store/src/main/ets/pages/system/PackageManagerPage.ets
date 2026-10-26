/**
 * PackageManagerPage - 软件包管理
 * 自动检测包管理器：OpenWrt 24.x 用 opkg，25.x 用 apk
 * 支持已装列表 / 搜索安装 / 卸载
 */
import { window, promptAction } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SshService } from '../../common/ssh/SshService'

const DOMAIN = 0x0001
const TAG = 'PkgMgr'

interface PkgItem {
  name: string
  version: string
}

@Entry
@Component
export struct PackageManagerPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State pkgMgr: string = ''        // opkg / apk
  @State osVer: string = ''         // OpenWrt 版本
  @State pkgs: PkgItem[] = []
  @State loading: boolean = false
  @State busy: boolean = false
  @State statusMsg: string = ''
  @State newPkg: string = ''
  @State filtered: string = ''
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    this.detect()
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  private async sshExec(cmd: string): Promise<string> {
    try {
      if (!this.ssh.isConnected()) {
        if (this.sshTried) return ''
        this.sshTried = true
        const device = AppState.getInstance().getActiveDevice()
        if (!device || !device.username || !device.password) return ''
        const ok: boolean = await this.ssh.connect(device)
        if (!ok) return ''
      }
      return await this.ssh.exec(cmd)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ssh err: ${String(e)}`)
      return ''
    }
  }

  /** 检测包管理器与系统版本（OpenWrt 24.x = opkg，25.x = apk） */
  private async detect(): Promise<void> {
    this.statusMsg = '正在检测包管理器...'
    const verOut: string = await this.sshExec("cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_RELEASE | cut -d\\' -f2")
    this.osVer = verOut.trim()
    const mgr: string = await this.sshExec('command -v apk >/dev/null 2>&1 && echo apk || echo opkg')
    this.pkgMgr = mgr.trim()
    if (this.pkgMgr !== 'apk' && this.pkgMgr !== 'opkg') {
      this.pkgMgr = ''
      this.statusMsg = '⚠️ 未检测到 opkg / apk 包管理器'
      return
    }
    this.statusMsg = ''
    this.loadList()
  }

  /** 加载已安装列表 */
  private async loadList(): Promise<void> {
    if (this.loading) return
    this.loading = true
    // opkg list-installed 输出「name - version - desc」；apk info 输出「name-x.y.z」
    const out: string = this.pkgMgr === 'apk'
      ? await this.sshExec('apk info 2>/dev/null')
      : await this.sshExec('opkg list-installed 2>/dev/null')
    const items: PkgItem[] = []
    if (out) {
      const lines: string[] = out.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const l: string = lines[i].trim()
        if (!l) continue
        if (this.pkgMgr === 'apk') {
          // apk info 输出格式 name-x.y.z-rN
          const m: RegExpMatchArray | null = l.match(/^(.+)-(\d[\w.+-]*)$/)
          if (m) {
            items.push({ name: m[1], version: m[2] })
          } else {
            items.push({ name: l, version: '' })
          }
        } else {
          // opkg list-installed 输出 name - version - desc
          const m: RegExpMatchArray | null = l.match(/^(\S+)\s*-\s*(\S+)/)
          if (m) {
            items.push({ name: m[1], version: m[2] })
          }
        }
      }
    }
    items.sort((a: PkgItem, b: PkgItem) => a.name.localeCompare(b.name))
    this.pkgs = items
    this.loading = false
  }

  /** 搜索安装 */
  private async installPkg(): Promise<void> {
    const name: string = this.newPkg.trim()
    if (!name || this.busy) return
    try {
      promptAction.showDialog({
        title: `安装 ${name}`,
        message: `将通过 ${this.pkgMgr} 安装「${name}」，可能需要更新软件源，是否继续？`,
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '安装', color: '#FF8A3D' }
        ]
      }).then(async (res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index !== 1) return
        this.busy = true
        this.statusMsg = '正在更新软件源并安装...'
        const cmd: string = this.pkgMgr === 'apk'
          ? `apk update >/dev/null 2>&1; apk add ${name} 2>&1 | tail -3`
          : `opkg update >/dev/null 2>&1; opkg install ${name} 2>&1 | tail -3`
        const out: string = await this.sshExec(cmd)
        hilog.error(DOMAIN, TAG, `install out=[${out}]`)
        const ok: boolean = !out.includes('Unknown package') && !out.includes('failed') &&
          (out.includes('installed') || out.includes('Installing') || out.includes('OK') || out.length === 0)
        this.statusMsg = ok ? `✅ 「${name}」安装完成` : `⚠️ 安装失败：${out.split('\n').pop()}`
        this.busy = false
        this.loadList()
      })
    } catch (e) {}
  }

  /** 卸载 */
  private removePkg(p: PkgItem): void {
    if (this.busy) return
    try {
      promptAction.showDialog({
        title: `卸载 ${p.name}`,
        message: `将卸载「${p.name}」及依赖它的配置，是否继续？`,
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '卸载', color: '#FF5252' }
        ]
      }).then(async (res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index !== 1) return
        this.busy = true
        this.statusMsg = '正在卸载...'
        const cmd: string = this.pkgMgr === 'apk'
          ? `apk del ${p.name} 2>&1 | tail -3`
          : `opkg remove ${p.name} 2>&1 | tail -3`
        const out: string = await this.sshExec(cmd)
        hilog.error(DOMAIN, TAG, `remove out=[${out}]`)
        this.statusMsg = out.includes('No packages removed') || out.includes('not installed')
          ? '该包未安装或已移除'
          : `✅ 已卸载「${p.name}」`
        this.busy = false
        this.loadList()
      })
    } catch (e) {}
  }

  private visiblePkgs(): PkgItem[] {
    const f: string = this.filtered.trim().toLowerCase()
    if (!f) return this.pkgs
    return this.pkgs.filter((p: PkgItem) => p.name.toLowerCase().includes(f))
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.app_gear')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('软件包管理').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('opkg / apk 自动适配').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)

        Text('返回')
          .fontSize(13).fontColor(this.theme.primary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('rgba(255,138,61,0.1)')
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%').padding({ left: 16, right: 16, top: this.topSafeArea + 4 })

      Scroll() {
        Column() {
          // 包管理器状态卡
          Row() {
            Column() {
              Text(this.pkgMgr ? `${this.pkgMgr.toUpperCase()} 包管理器` : '检测中...')
                .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
              Text(this.osVer ? `OpenWrt ${this.osVer}` : '版本读取中')
                .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(`${this.pkgs.length} 个已装包`)
              .fontSize(11).fontColor(this.theme.primary)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor('rgba(255,138,61,0.1)')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 安装输入
          Row({ space: 8 }) {
            TextInput({ placeholder: '包名，如 etherwake / tcpdump', text: this.newPkg })
              .fontSize(12).height(40).layoutWeight(1)
              .backgroundColor('#FFFFFF').borderRadius(12)
              .onChange((v: string) => { this.newPkg = v })
            Row() {
              if (this.busy) {
                LoadingProgress().width(16).height(16).color('#FFFFFF')
              } else {
                Text('安装').fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
            }
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(18).backgroundColor(this.busy ? '#C9A98A' : '#FF8A3D')
            .onClick(() => { this.installPkg() })
          }
          .width('100%').margin({ top: 10 })

          // 列表过滤
          Row({ space: 8 }) {
            TextInput({ placeholder: '过滤已安装包', text: this.filtered })
              .fontSize(12).height(36).layoutWeight(1)
              .backgroundColor('#FFFFFF').borderRadius(12)
              .onChange((v: string) => { this.filtered = v })
            Row() {
              Text('刷新').fontSize(12).fontColor('#FF8A3D').fontWeight(FontWeight.Bold)
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(14).backgroundColor('rgba(255,138,61,0.1)')
            .onClick(() => { this.loadList() })
          }
          .width('100%').margin({ top: 8 })

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(11).fontColor(this.theme.primary).margin({ top: 10 })
              .textAlign(TextAlign.Center).width('100%')
          }

          // 已装列表
          if (this.loading) {
            Column() {
              LoadingProgress().width(30).height(30).color(this.theme.primary)
              Text('正在读取软件包列表...').fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 10 })
            }
            .width('100%').padding(30).alignItems(HorizontalAlign.Center)
          } else {
            Text(`已安装（${this.visiblePkgs().length}）`)
              .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
              .width('100%').margin({ top: 14 })
            ForEach(this.visiblePkgs(), (p: PkgItem) => {
              Row() {
                Column() {
                  Text(p.name).fontSize(12).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (p.version) {
                    Text(p.version).fontSize(9).fontColor(this.theme.textTertiary).margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)

                Row() {
                  Text('卸载').fontSize(10).fontColor('#FF5252')
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(12)
                .backgroundColor('rgba(255,82,82,0.1)')
                .onClick(() => { this.removePkg(p) })
              }
              .width('100%').padding(12).borderRadius(14).margin({ top: 8 })
              .backgroundColor(this.theme.bgCard)
            }, (p: PkgItem): string => p.name)
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
