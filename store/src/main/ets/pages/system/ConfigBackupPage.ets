/**
 * ConfigBackupPage - 配置备份 / 恢复
 * sysupgrade -b 备份配置 → SFTP 下载到手机；本地备份 → 上传 → sysupgrade -r 恢复
 * OpenWrt 24.x / 25.x 的 sysupgrade -b/-r 均为标准命令，通用
 */
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'
import { systemShare } from '@kit.ShareKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { picker } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { common } from '@kit.AbilityKit'
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SshService } from '../../common/ssh/SshService'
import { FileManagerService } from '../../common/fs/FileManagerService'

const DOMAIN = 0x0001
const TAG = 'CfgBak'

@Entry
@Component
struct ConfigBackupPageRoute {
  build() {
    Column() {
      ConfigBackupPage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ConfigBackupPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State busy: string = ''          // 当前操作：backup/restore/download
  @State statusMsg: string = ''
  @State backupPath: string = ''    // 已下载的备份文件路径
  @State backupSize: string = ''
  private ssh: SshService = SshService.getInstance()
  private sshTried: boolean = false

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
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

  /** 备份配置到手机 */
  private async doBackup(): Promise<void> {
    if (this.busy) return
    this.busy = 'backup'
    this.statusMsg = '正在路由器上打包配置...'
    try {
      // 打包（sysupgrade -b 生成 tar.gz，24/25 通用）
      const out: string = await this.sshExec('sysupgrade -b /tmp/istore_backup.tar.gz 2>&1; ls -l /tmp/istore_backup.tar.gz')
      const m: RegExpMatchArray | null = out.match(/\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(\d{1,2}:\d{2}|\d{4}-\d{2}-\d{2})\s+(\S+)$/)
      hilog.error(DOMAIN, TAG, `backup out=[${out}]`)
      // 下载到手机
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) {
        this.statusMsg = '备份失败：无法获取应用目录'
        return
      }
      const local: string = `${ctx.cacheDir}/istore_backup.tar.gz`
      this.busy = 'download'
      this.statusMsg = '正在下载备份到手机...'
      await FileManagerService.getInstance().downloadToPath('/tmp/istore_backup.tar.gz', local)
      // 读取大小
      const st = fs.statSync(local)
      this.backupPath = local
      this.backupSize = this.fmtSize(st.size)
      this.statusMsg = '✅ 备份成功，已下载到手机'
    } catch (e) {
      hilog.error(DOMAIN, TAG, `backup err: ${String(e)}`)
      this.statusMsg = '⚠️ 备份失败：请确认 SSH 已连接且路由器支持 sysupgrade'
    }
    this.busy = ''
  }

  /** 分享备份文件 */
  private async shareBackup(): Promise<void> {
    if (!this.backupPath) return
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!ctx) return
      const uri: string = fileUri.getUriFromPath(this.backupPath)
      const record: systemShare.SharedRecord = {
        uri: uri,
        title: 'iStore 配置备份',
        description: 'OpenWrt 配置备份 tar.gz',
        utd: 'general.archive'
      }
      const data: systemShare.SharedData = new systemShare.SharedData(record)
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      await controller.show(ctx, {})
    } catch (e) {
      hilog.error(DOMAIN, TAG, `share err: ${String(e)}`)
    }
  }

  /** 选择本地备份并恢复 */
  private async doRestore(): Promise<void> {
    if (this.busy) return
    try {
      const docPicker = new picker.DocumentViewPicker()
      const res: Array<string> = await docPicker.select({ maxSelectNumber: 1 })
      if (!res || res.length === 0) return
      const uri: string = res[0]
      const stat = fs.statSync(uri)
      if (stat.size > 20 * 1024 * 1024) {
        this.statusMsg = '备份文件过大（>20MB）'
        return
      }
      this.busy = 'restore'
      this.statusMsg = '正在上传备份并执行恢复（设备将重启，请稍候）...'
      // 上传到路由器
      await FileManagerService.getInstance().uploadFile(uri, '/tmp', 'istore_restore.tar.gz')
      // 执行恢复（sysupgrade -r 24/25 通用；执行后设备重启）
      const out: string = await this.sshExec('sysupgrade -r /tmp/istore_restore.tar.gz 2>&1')
      hilog.error(DOMAIN, TAG, `restore out=[${out}]`)
      this.statusMsg = out ? '恢复已触发，设备即将重启并应用备份配置' : '恢复命令已执行'
    } catch (e) {
      hilog.error(DOMAIN, TAG, `restore err: ${String(e)}`)
      this.statusMsg = '⚠️ 恢复失败：请确认备份文件为 sysupgrade 格式（.tar.gz）'
    }
    this.busy = ''
  }

  private fmtSize(bytes: number): string {
    if (bytes <= 0) return '0 B'
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Image($r('app.media.folder_file')).width(18).height(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor('rgba(255,138,61,0.14)')
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('配置备份').fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
          Text('刷机前先备份，出事不慌').fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 2 })
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
          // 说明卡
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(20).fontColor(['#F59E0B'])
              Column() {
                Text('sysupgrade 标准备份格式，OpenWrt 24.x / 25.x 通用')
                  .fontSize(12).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                Text('备份包含网络、WiFi、防火墙等全部配置，恢复后可一键还原')
                  .fontSize(10).fontColor(this.theme.textTertiary).margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
            }
            .width('100%')
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 备份卡
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.download')).fontSize(16).fontColor(['#3B82F6'])
              Text(' 备份当前配置').fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            }
            .width('100%')
            Text('在路由器上打包配置并下载到手机')
              .fontSize(11).fontColor(this.theme.textTertiary).margin({ top: 4 }).width('100%')

            if (this.backupPath) {
              Row() {
                Column() {
                  Row() {
                    SymbolGlyph($r('sys.symbol.archivebox')).fontSize(12).fontColor(['#F59E0B'])
                    Text(' 已保存备份').fontSize(11).fontColor(this.theme.textSecondary)
                  }
                  Text(`${this.backupSize}`).fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                Row() {
                  Text('分享').fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .borderRadius(16).backgroundColor('#FF8A3D')
                .onClick(() => { this.shareBackup() })
              }
              .width('100%').padding(12).borderRadius(12).margin({ top: 10 })
              .backgroundColor('rgba(255,138,61,0.08)')
            }

            Row() {
              if (this.busy === 'backup' || this.busy === 'download') {
                LoadingProgress().width(18).height(18).color('#FFFFFF')
                Text(`  ${this.busy === 'backup' ? '打包中' : '下载中'}...`)
                  .fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              } else {
                Text('开始备份').fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
            }
            .width('100%').height(44).borderRadius(22).margin({ top: 12 })
            .backgroundColor(this.busy === 'backup' || this.busy === 'download' ? '#C9A98A' : '#FF8A3D')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.doBackup() })
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          // 恢复卡
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.share')).fontSize(16).fontColor(['#F97316'])
              Text(' 恢复配置').fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            }
            .width('100%')
            Text('选择备份文件上传并恢复（⚠️ 会重启设备）')
              .fontSize(11).fontColor('#FF5252').margin({ top: 4 }).width('100%')

            Row() {
              if (this.busy === 'restore') {
                LoadingProgress().width(18).height(18).color('#FFFFFF')
                Text('  恢复中...').fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              } else {
                Text('选择备份文件恢复').fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
              }
            }
            .width('100%').height(44).borderRadius(22).margin({ top: 12 })
            .backgroundColor(this.busy === 'restore' ? '#C9A98A' : '#FF5252')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.doRestore() })
          }
          .width('100%').padding(14).borderRadius(16).margin({ top: 12 })
          .backgroundColor(this.theme.bgCard)

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(11).fontColor(this.theme.primary).margin({ top: 12 })
              .textAlign(TextAlign.Center).width('100%')
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
