/**
 * FileManagerPage - OpenWrt 文件管理器
 * SSH 连接，浏览/查看/编辑/新建/重命名/删除/复制/移动/上传/下载
 */
import { AppState } from '../../common/store/AppState'
import { ThemePalette, LIGHT_THEME } from '../../common/theme/ThemeColors'
import { FileManagerService, FsEntry } from '../../common/fs/FileManagerService'
import { SshService } from '../../common/ssh/SshService'
import { promptAction } from '@kit.ArkUI'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { picker } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppNav } from '../../common/utils/AppNav'

const DOMAIN = 0x0001

@Entry
@Component
export struct FileManagerPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State connected: boolean = false
  @State sftpOk: boolean = false
  @State connError: string = ''
  @State currentPath: string = '/'
  @State entries: FsEntry[] = []
  @State isLoading: boolean = true
  @State errText: string = ''
  // SFTP 一键安装
  @State showInstall: boolean = false
  @State installing: boolean = false
  @State installLogs: string[] = []

  // 多选 / 操作
  @State selectMode: boolean = false
  @State selected: string[] = []
  @State clipboard: string[] = []
  @State clipMode: string = ''   // 'copy' | 'move'

  // 弹窗
  @State showSheet: boolean = false
  @State sheetTitle: string = ''
  @State sheetMode: number = 0   // 0 新建目录 / 1 新建文件 / 2 重命名
  @State newName: string = ''
  @State showDeleteConfirm: boolean = false
  @State deleteTargets: string[] = []
  @State renameTarget: FsEntry | null = null

  // 查看器 / 编辑器
  @State showViewer: boolean = false
  @State viewerPath: string = ''
  @State viewerContent: string = ''
  @State viewerDirty: boolean = false
  @State editMode: boolean = false
  @State toastMsg: string = ''

  private fileSvc: FileManagerService = FileManagerService.getInstance()
  private ssh: SshService = SshService.getInstance()

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.loadTopSafeArea()
    this.doConnect()
  }

  /** 系统返回（含边缘滑动）：非根目录时返回上一级 */
  onBackPress(): boolean {
    if (this.currentPath !== '/') {
      const parent: string = this.currentPath.substring(0, this.currentPath.lastIndexOf('/')) || '/'
      this.loadDir(parent)
      return true
    }
    return false
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

  /** 连接并进入根目录 */
  async doConnect(): Promise<void> {
    this.isLoading = true
    this.connError = ''
    const device = AppState.getInstance().getActiveDevice()
    if (!device) {
      this.connError = '未选择路由器设备'
      this.isLoading = false
      return
    }
    if (!device.username || !device.password) {
      this.connError = '设备未配置 SSH 用户名/密码，请到登录页编辑设备补充'
      this.isLoading = false
      return
    }
    const ok: boolean = await this.ssh.connect(device)
    if (!ok) {
      this.connError = this.ssh.lastError || 'SSH 连接失败，请确认路由器已开启 SSH（端口 22）'
      this.isLoading = false
      return
    }
    this.connected = true
    // 注入宿主上下文（SFTP 临时文件用）
    try {
      this.fileSvc.setHostContext(this.getUIContext().getHostContext() as common.UIAbilityContext)
    } catch (e) {}
    // 检测 SFTP 子系统（命令秒检）
    this.sftpOk = await this.fileSvc.checkSftp()
    if (this.sftpOk) {
      await this.loadDir('/')
    } else {
      // SFTP 未安装：跳过列目录（initSftp 是同步调用，未装时会阻塞等超时导致卡加载）
      this.entries = []
      this.currentPath = '/'
      this.isLoading = false
    }
  }

  /** 追加安装日志（触发 UI 刷新） */
  private installLog(line: string): void {
    this.installLogs.push(line)
  }

  /** 一键安装 SFTP */
  async startInstall(): Promise<void> {
    this.showInstall = true
    this.installing = true
    this.installLogs = []
    this.installLog('🔧 开始检测 SFTP 安装环境…')
    const ok: boolean = await this.fileSvc.installSftp((line: string) => this.installLog(line))
    this.installing = false
    if (ok) {
      // dropbear 重启后旧连接已断 → 重连 + 重新检测
      this.installLog('🔄 重新连接路由器…')
      this.connected = false
      await this.doConnect()
      if (this.sftpOk) {
        this.installLog('✅ SFTP 已可用！')
      } else {
        this.installLog('⚠ 仍检测不到 SFTP，请检查上方日志')
      }
    } else {
      this.installLog('❌ 安装未完成，请查看上方日志或到 LuCI 软件包手动安装')
    }
  }

  /** 加载目录 */
  async loadDir(path: string): Promise<void> {
    this.isLoading = true
    this.errText = ''
    try {
      this.entries = await this.fileSvc.list(path)
      this.currentPath = path
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : '加载失败'
      this.errText = msg
      // SFTP 不可用 → 显示提示条（可一键安装修复）
      if (msg.indexOf('SFTP') >= 0) {
        this.sftpOk = false
      }
    }
    this.isLoading = false
  }

  /** 面包屑路径段 */
  pathSegments(): string[] {
    const p: string = this.currentPath === '/' ? '' : this.currentPath
    return p.split('/').filter((s: string): boolean => s.length > 0)
  }

  /** 点击路径段跳转 */
  jumpToSegment(segIdx: number): void {
    let path: string = '/'
    const segs: string[] = this.pathSegments()
    for (let i = 0; i <= segIdx && i < segs.length; i++) {
      path += segs[i] + '/'
    }
    this.loadDir(path)
  }

  /** 点击条目 */
  onTapEntry(entry: FsEntry): void {
    if (this.selectMode) {
      this.toggleSelect(entry.path)
      return
    }
    if (entry.isDir) {
      this.loadDir(entry.path)
    } else if (FileManagerService.isTextFile(entry.name)) {
      this.openViewer(entry)
    } else {
      this.toast('非文本文件，长按可下载')
    }
  }

  /** 长按进入多选 */
  onLongPressEntry(entry: FsEntry): void {
    if (this.selectMode) {
      this.toggleSelect(entry.path)
    } else {
      this.selectMode = true
      this.selected = [entry.path]
    }
  }

  toggleSelect(path: string): void {
    if (this.selected.indexOf(path) >= 0) {
      this.selected = this.selected.filter((p: string): boolean => p !== path)
    } else {
      this.selected.push(path)
    }
    if (this.selected.length === 0) {
      this.selectMode = false
    }
  }

  /** 名称提示 */
  nameOf(path: string): string {
    return path.substring(path.lastIndexOf('/') + 1)
  }

  // ========== 操作 ==========

  /** 打开输入弹窗 */
  showSheetDialog(title: string, mode: number, initName: string): void {
    this.sheetTitle = title
    this.sheetMode = mode
    this.newName = initName
    this.showSheet = true
  }

  /** 输入弹窗确定 */
  async onSheetOk(): Promise<void> {
    if (this.sheetMode === 0) {
      await this.doMkdir()
    } else if (this.sheetMode === 1) {
      await this.doNewFile()
    } else if (this.sheetMode === 2) {
      await this.doRename()
    }
  }

  /** 新建目录 */
  async doMkdir(): Promise<void> {
    const name: string = this.newName.trim()
    if (!name) { this.toast('请输入名称'); return }
    const target: string = `${this.currentPath.endsWith('/') ? this.currentPath : this.currentPath + '/'}${name}`
    try {
      await this.fileSvc.mkdir(target)
      this.showSheet = false
      this.newName = ''
      this.toast('目录已创建')
      await this.loadDir(this.currentPath)
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '创建失败')
    }
  }

  /** 新建文件 */
  async doNewFile(): Promise<void> {
    const name: string = this.newName.trim()
    if (!name) { this.toast('请输入文件名'); return }
    const target: string = `${this.currentPath.endsWith('/') ? this.currentPath : this.currentPath + '/'}${name}`
    try {
      await this.fileSvc.touch(target)
      this.showSheet = false
      this.newName = ''
      this.toast('文件已创建')
      await this.loadDir(this.currentPath)
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '创建失败')
    }
  }

  /** 重命名 */
  async doRename(): Promise<void> {
    if (!this.renameTarget) return
    const name: string = this.newName.trim()
    if (!name) { this.toast('请输入新名称'); return }
    const parent: string = this.renameTarget.path.substring(0, this.renameTarget.path.lastIndexOf('/')) || '/'
    const newPath: string = `${parent}/${name}`
    try {
      await this.fileSvc.rename(this.renameTarget.path, newPath)
      this.showSheet = false
      this.renameTarget = null
      this.newName = ''
      this.toast('重命名成功')
      await this.loadDir(this.currentPath)
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '重命名失败')
    }
  }

  /** 打开删除确认 */
  askDelete(): void {
    if (this.selected.length === 0) return
    this.deleteTargets = [...this.selected]
    this.showDeleteConfirm = true
  }

  /** 执行删除 */
  async doDelete(): Promise<void> {
    try {
      for (const p of this.deleteTargets) {
        // 判断目标是否为目录
        let isDir: boolean = false
        for (const e of this.entries) {
          if (e.path === p) {
            isDir = e.isDir
            break
          }
        }
        await this.fileSvc.remove(p, isDir)
      }
      this.showDeleteConfirm = false
      this.deleteTargets = []
      this.selectMode = false
      this.selected = []
      this.toast('删除成功')
      await this.loadDir(this.currentPath)
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '删除失败')
    }
  }

  /** 复制到剪贴板 */
  copySelected(): void {
    this.clipboard = [...this.selected]
    this.clipMode = 'copy'
    this.selectMode = false
    this.selected = []
    this.toast(`已复制 ${this.clipboard.length} 项`)
  }

  /** 移动到剪贴板 */
  moveSelected(): void {
    this.clipboard = [...this.selected]
    this.clipMode = 'move'
    this.selectMode = false
    this.selected = []
    this.toast(`已剪切 ${this.clipboard.length} 项`)
  }

  /** 粘贴 */
  async paste(): Promise<void> {
    if (this.clipboard.length === 0) { this.toast('剪贴板为空'); return }
    try {
      for (const src of this.clipboard) {
        const name: string = this.nameOf(src)
        const dst: string = `${this.currentPath.endsWith('/') ? this.currentPath : this.currentPath + '/'}${name}`
        if (this.clipMode === 'copy') {
          await this.fileSvc.copy(src, dst)
        } else {
          await this.fileSvc.rename(src, dst)
        }
      }
      const mode: string = this.clipMode === 'copy' ? '复制' : '移动'
      this.toast(`${mode}完成 ${this.clipboard.length} 项`)
      this.clipboard = []
      this.clipMode = ''
      await this.loadDir(this.currentPath)
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '粘贴失败')
    }
  }

  /** 刷新 */
  async refresh(): Promise<void> {
    await this.loadDir(this.currentPath)
    this.toast('已刷新')
  }

  /** 上传文件（手机 → 路由器，SFTP） */
  async upload(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker()
      const res: Array<string> = await docPicker.select({ maxSelectNumber: 1 })
      if (!res || res.length === 0) return
      const uri: string = res[0]
      const stat = fs.statSync(uri)
      if (stat.size > 10 * 1024 * 1024) {
        this.toast('文件过大（>10MB）')
        return
      }
      // 文件名（uri 末尾）
      const uriParts: string[] = uri.split('/')
      const fname: string = decodeURIComponent(uriParts[uriParts.length - 1])
      this.toast('上传中…')
      await this.fileSvc.uploadFile(uri, this.currentPath, fname)
      this.toast('上传完成')
      await this.loadDir(this.currentPath)
    } catch (e) {
      hilog.error(DOMAIN, 'FileMgr', `upload err: ${JSON.stringify(e)}`)
      this.toast('上传失败（SFTP 需路由器安装 openssh-sftp-server）')
    }
  }

  /** 下载文件（路由器 → 手机分享，SFTP） */
  async download(entry: FsEntry): Promise<void> {
    this.toast('读取中…')
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const filePath: string = `${ctx.cacheDir}/fm_${Date.now()}_${entry.name}`
      await this.fileSvc.downloadToPath(entry.path, filePath)
      // 分享面板
      const uri: string = fileUri.getUriFromPath(filePath)
      const record: systemShare.SharedRecord = {
        uri: uri,
        title: entry.name,
        description: 'OpenWrt 文件下载',
        utd: 'general.file'
      }
      const data: systemShare.SharedData = new systemShare.SharedData(record)
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      await controller.show(ctx, {})
      setTimeout(() => {
        try { fs.unlinkSync(filePath) } catch (e) {}
      }, 60000)
    } catch (e) {
      hilog.error(DOMAIN, 'FileMgr', `download err: ${JSON.stringify(e)}`)
      this.toast(e instanceof Error ? e.message : '下载失败')
    }
  }

  // ========== 文本查看 / 编辑 ==========

  async openViewer(entry: FsEntry): Promise<void> {
    try {
      const content: string = await this.fileSvc.readText(entry.path, this.sftpOk)
      this.viewerPath = entry.path
      this.viewerContent = content
      this.editMode = false
      this.viewerDirty = false
      this.showViewer = true
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '读取失败')
    }
  }

  /** 保存编辑 */
  async saveViewer(): Promise<void> {
    try {
      await this.fileSvc.writeText(this.viewerPath, this.viewerContent)
      this.viewerDirty = false
      this.toast('已保存')
    } catch (e) {
      this.toast(e instanceof Error ? e.message : '保存失败')
    }
  }

  /** toast */
  toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 })
    } catch (e) {}
  }

  // ========== UI ==========

  /** 文件类型图标（统一符号族） */
  entrySymbol(entry: FsEntry): Resource {
    if (entry.isDir) return $r('sys.symbol.folder')
    const lower: string = entry.name.toLowerCase()
    if (FileManagerService.isTextFile(entry.name)) return $r('sys.symbol.doc_text')
    if (lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.zip') || lower.endsWith('.xz')) return $r('sys.symbol.doc_zipper')
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return $r('sys.symbol.ohos_photo')
    if (lower.endsWith('.mp3') || lower.endsWith('.wav')) return $r('sys.symbol.speaker_wave_1')
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) return $r('sys.symbol.film')
    return $r('sys.symbol.doc_plaintext')
  }

  /** 文件类型配色 */
  entryColor(entry: FsEntry): string {
    if (entry.isDir) return '#F59E0B'
    const lower: string = entry.name.toLowerCase()
    if (FileManagerService.isTextFile(entry.name)) return '#3B82F6'
    if (lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.zip') || lower.endsWith('.xz')) return '#8B5CF6'
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return '#EC4899'
    if (lower.endsWith('.mp3') || lower.endsWith('.wav')) return '#06B6D4'
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) return '#F97316'
    return '#64748B'
  }

  /** 主色 → 同色系浅底 */
  tint(hex: string, alpha: number): string {
    let c: string = hex
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    let r: number = 0
    let g: number = 0
    let b: number = 0
    try {
      r = parseInt(c.substring(0, 2), 16)
      g = parseInt(c.substring(2, 4), 16)
      b = parseInt(c.substring(4, 6), 16)
    } catch (e) {
      return 'rgba(0,0,0,0.08)'
    }
    return `rgba(${r},${g},${b},${alpha})`
  }

  build() {
    Stack() {
      Column() {
      // 顶部：文件管理标题 + 当前路径
      Row() {
        Text('‹')
          .fontSize(20).fontColor(this.theme.textPrimary)
          .width(28).height(28).textAlign(TextAlign.Center)
          .onClick(() => AppNav.getInstance().back())
        Text(' 文件管理')
          .fontSize(17).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
        Blank()
        if (this.clipboard.length > 0) {
          Text(`粘贴(${this.clipMode === 'copy' ? '复制' : '移动'} ${this.clipboard.length}项)`)
            .fontSize(12).fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor('#FF8A3D')
            .onClick(() => { this.paste() })
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: this.topSafeArea + 4, bottom: 6 })

      // 路径面包屑
      Scroll() {
        Row({ space: 4 }) {
          Text(' /')
            .fontSize(12).fontColor(this.theme.primary).fontWeight(FontWeight.Medium)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .onClick(() => { this.loadDir('/') })
          ForEach(this.pathSegments(), (seg: string, idx: number) => {
            Text(` ${seg} /`)
              .fontSize(12)
              .fontColor(idx === this.pathSegments().length - 1 ? this.theme.textPrimary : this.theme.primary)
              .fontWeight(idx === this.pathSegments().length - 1 ? FontWeight.Medium : FontWeight.Regular)
              .maxLines(1)
              .onClick(() => { this.jumpToSegment(idx) })
          }, (seg: string, idx: number): string => seg + idx)
        }
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // 内容区
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(36).height(36).color(this.theme.primary)
          Text('加载中…').fontSize(13).fontColor(this.theme.textTertiary).margin({ top: 10 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.connError) {
        Column() {
          Text('⚠ SSH 未连接').fontSize(14).fontColor('#FF5252')
          Text(this.connError).fontSize(12).fontColor(this.theme.textTertiary)
            .margin({ top: 8 }).padding({ left: 30, right: 30 })
          Text('重新连接').fontSize(13).fontColor('#FFFFFF')
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .borderRadius(12).backgroundColor('#FF8A3D')
            .margin({ top: 16 })
            .onClick(() => { this.doConnect() })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          if (this.errText) {
            Text(`⚠ ${this.errText}`).fontSize(12).fontColor(this.theme.warning)
              .width('100%').padding(12)
          }
          // SFTP 未安装提示
          if (!this.sftpOk) {
            Column() {
              Row() {
                Text('⚠ 路由器未安装 SFTP 组件')
                  .fontSize(12).fontColor('#E6A800').fontWeight(FontWeight.Medium)
                Blank()
                // 一键安装按钮
                Text('🔧 一键安装')
                  .fontSize(11).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .borderRadius(12)
                  .backgroundColor('#FF8A3D')
                  .onClick(() => { this.startInstall() })
              }
              .width('100%')
              Text('未安装将无法查看/上传/下载文件。点击按钮自动安装（OpenWrt 24.xx 走 opkg、25.xx 走 apk，自动识别）')
                .fontSize(10).fontColor(this.theme.textSecondary)
                .width('100%')
                .margin({ top: 6 })
                .lineHeight(15)
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor('rgba(230,168,0,0.08)')
            .border({ width: 0.5, color: 'rgba(230,168,0,0.3)' })
            .margin({ left: 14, right: 14, top: 4 })
          }
          // 文件列表
          List({ space: 2 }) {
            ForEach(this.entries, (entry: FsEntry) => {
              ListItem() {
                Row() {
                  // 多选勾选
                  if (this.selectMode) {
                    Circle()
                      .width(18).height(18)
                      .fill(this.selected.indexOf(entry.path) >= 0 ? '#FF8A3D' : 'transparent')
                      .stroke('#FF8A3D')
                      .strokeWidth(1.5)
                      .margin({ right: 10 })
                  }
                  Row() {
                    SymbolGlyph(this.entrySymbol(entry))
                      .fontSize(18)
                      .fontColor([this.entryColor(entry)])
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(10)
                  .backgroundColor(this.tint(this.entryColor(entry), 0.12))
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 10 })
                  Column() {
                    Text(entry.name)
                      .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row() {
                      if (!entry.isDir) {
                        Text(FileManagerService.formatSize(entry.size))
                          .fontSize(10).fontColor(this.theme.textTertiary)
                      }
                      Text(`  ${entry.modified}`)
                        .fontSize(10).fontColor(this.theme.textTertiary)
                    }
                    .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  // 下载按钮（文件）
                  if (!entry.isDir && !this.selectMode) {
                    Row() {
                      Image($r('app.media.download_circle'))
                        .width(18).height(18)
                    }
                      .width(32).height(32).borderRadius(10)
                      .backgroundColor('rgba(255,138,61,0.12)')
                      .justifyContent(FlexAlign.Center)
                      .onClick(() => { this.download(entry) })
                  }
                  if (!this.selectMode) {
                    Text('›').fontSize(18).fontColor(this.theme.textTertiary).margin({ left: 4 })
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .borderRadius(14)
                .backgroundColor(this.theme.bgCard)
                .border({ width: 0.5, color: this.theme.borderGlass })
                .margin({ top: 6 })
                .onClick(() => { this.onTapEntry(entry) })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction(() => { this.onLongPressEntry(entry) })
                )
              }
            }, (entry: FsEntry): string => entry.path)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .scrollBar(BarState.Off)

          // 底部操作栏
          Row({ space: 8 }) {
            if (this.selectMode) {
              Text(`已选 ${this.selected.length}`)
                .fontSize(12).fontColor(this.theme.textPrimary)
                .layoutWeight(1)
              Text('复制').fontSize(12).fontColor(this.theme.primary).onClick(() => this.copySelected())
              Text('移动').fontSize(12).fontColor(this.theme.primary).onClick(() => this.moveSelected())
              Text('重命名').fontSize(12).fontColor(this.theme.primary)
                .onClick(() => {
                  if (this.selected.length !== 1) { this.toast('重命名需单选'); return }
                  const p = this.selected[0]
                  this.renameTarget = this.entries.find((e: FsEntry): boolean => e.path === p) || null
                  if (this.renameTarget) {
                    this.showSheetDialog('重命名', 2, this.renameTarget.name)
                  }
                })
              Text('删除').fontSize(12).fontColor('#FF5252').onClick(() => this.askDelete())
              Text('取消').fontSize(12).fontColor(this.theme.textTertiary)
                .onClick(() => { this.selectMode = false; this.selected = [] })
            } else {
              Text('📁 新建文件夹').fontSize(12).fontColor(this.theme.primary)
                .layoutWeight(1)
                .onClick(() => { this.showSheetDialog('新建文件夹', 0, '') })
              Text('📄 新建文件').fontSize(12).fontColor(this.theme.primary)
                .layoutWeight(1)
                .onClick(() => { this.showSheetDialog('新建文件', 1, '') })
              Row() {
                Image($r('app.media.upload_doc'))
                  .width(15).height(15)
                Text('上传').fontSize(12).fontColor(this.theme.primary)
                  .margin({ left: 3 })
              }
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .onClick(() => { this.upload() })
              Text('🔄 刷新').fontSize(12).fontColor(this.theme.textSecondary)
                .onClick(() => { this.refresh() })
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 10, bottom: 22 })
        }
        .width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .linearGradient({
      angle: 135,
      colors: this.theme.pageGradient
    })

    // ========== 输入弹窗（新建/重命名） ==========
    if (this.showSheet) {
      Column() {
        Text(this.sheetTitle).fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
        TextInput({
          placeholder: this.sheetMode === 1 ? '请输入文件名（含扩展名）' : '请输入名称',
          text: this.newName
        })
          .placeholderColor(this.theme.textTertiary)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(this.theme.bgCard)
          .margin({ top: 14 })
          .onChange((v: string) => { this.newName = v })
        Row({ space: 12 }) {
          Text('取消').fontSize(14).fontColor(this.theme.textSecondary)
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .borderRadius(14).backgroundColor(this.theme.bgCard)
            .onClick(() => { this.showSheet = false })
          Text('确定').fontSize(14).fontColor('#FFFFFF')
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .borderRadius(14).backgroundColor('#FF8A3D')
            .onClick(() => { this.onSheetOk() })
        }
        .margin({ top: 16 })
      }
      .width('86%')
      .padding(20)
      .borderRadius(22)
      .backgroundColor(this.theme.bgCardSolid)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
      .alignItems(HorizontalAlign.Center)
      .position({ x: '7%', y: '32%' })
      .zIndex(100)
    }
    // ========== 删除确认 ==========
    if (this.showDeleteConfirm) {
      Column() {
        Text('⚠ 确认删除').fontSize(16).fontColor('#FF5252').fontWeight(FontWeight.Bold)
        Text(`将删除 ${this.deleteTargets.length} 项，且不可恢复：`)
          .fontSize(12).fontColor(this.theme.textSecondary).margin({ top: 8 })
        Text(this.deleteTargets.map((p: string): string => this.nameOf(p)).join('、'))
          .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 6 })
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 12 }) {
          Text('取消').fontSize(14).fontColor(this.theme.textSecondary)
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .borderRadius(14).backgroundColor(this.theme.bgCard)
            .onClick(() => { this.showDeleteConfirm = false })
          Text('确认删除').fontSize(14).fontColor('#FFFFFF')
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .borderRadius(14).backgroundColor('#FF5252')
            .onClick(() => { this.doDelete() })
        }
        .margin({ top: 16 })
      }
      .width('86%')
      .padding(20)
      .borderRadius(22)
      .backgroundColor(this.theme.bgCardSolid)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
      .alignItems(HorizontalAlign.Center)
      .position({ x: '7%', y: '32%' })
      .zIndex(100)
    }

    // ========== 文本查看/编辑 ==========
    if (this.showViewer) {
      Column() {
        Row() {
          Text(this.nameOf(this.viewerPath))
            .fontSize(15).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (!this.editMode) {
            Text('编辑').fontSize(13).fontColor(this.theme.primary)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(10).backgroundColor('rgba(255,138,61,0.12)')
              .onClick(() => { this.editMode = true })
          } else {
            Text('保存').fontSize(13).fontColor(this.theme.primary)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(10).backgroundColor('rgba(255,138,61,0.12)')
              .onClick(() => { this.saveViewer() })
            Text(' 取消').fontSize(13).fontColor(this.theme.textSecondary)
              .onClick(() => { this.editMode = false; this.openViewer({ name: '', path: this.viewerPath, isDir: false, isLink: false, size: 0, modified: '', isHidden: false }) })
          }
          Text(' ✕').fontSize(16).fontColor(this.theme.textTertiary)
            .onClick(() => {
              if (this.viewerDirty) {
                this.toast('有未保存修改')
              } else {
                this.showViewer = false
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })

        if (this.editMode) {
          TextArea({ text: this.viewerContent })
            .fontSize(13).fontColor(this.theme.textPrimary)
            .fontFamily('monospace')
            .backgroundColor(this.theme.bgCard)
            .layoutWeight(1)
            .margin({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.viewerContent = v
              this.viewerDirty = true
            })
        } else {
          Scroll() {
            Text(this.viewerContent || '（空文件）')
              .fontSize(13).fontColor(this.theme.textPrimary)
              .fontFamily('monospace')
              .lineHeight(20)
              .width('100%')
              .padding(16)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .width('94%')
      .height('92%')
      .borderRadius(24)
      .backgroundColor(this.theme.bgCardSolid)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)' })
      .position({ x: '3%', y: '3%' })
      .zIndex(200)
    }

    // ========== SFTP 一键安装面板 ==========
    if (this.showInstall) {
      Column() {
        Row() {
          Text('🔧 SFTP 一键安装')
            .fontSize(16).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          if (!this.installing) {
            Text(' ✕').fontSize(16).fontColor(this.theme.textTertiary)
              .onClick(() => { this.showInstall = false })
          }
        }
        .width('100%')
        Text(this.installing ? '正在自动检测并安装，请保持页面打开…' : '安装流程已结束，点击 ✕ 关闭')
          .fontSize(11).fontColor(this.theme.textSecondary)
          .width('100%').margin({ top: 4 })
        // 步骤日志
        Scroll() {
          Column() {
            ForEach(this.installLogs, (line: string) => {
              Text(line)
                .fontSize(11).fontColor(this.theme.textPrimary)
                .width('100%')
                .padding({ top: 2, bottom: 2 })
                .lineHeight(16)
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 10 })
        .padding(10)
        .borderRadius(12)
        .backgroundColor(this.theme.bgCard)
        .align(Alignment.TopStart)
        .scrollable(ScrollDirection.Vertical)
        if (this.installing) {
          Row() {
            LoadingProgress().width(22).height(22).color('#FF8A3D')
            Text('  安装中…（更新软件源可能需要 1-2 分钟）')
              .fontSize(12).fontColor(this.theme.textSecondary)
          }
          .width('100%').margin({ top: 10 }).justifyContent(FlexAlign.Center)
        }
      }
      .width('90%')
      .height('70%')
      .padding(18)
      .borderRadius(22)
      .backgroundColor(this.theme.bgCardSolid)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)' })
      .position({ x: '5%', y: '14%' })
      .zIndex(300)
    }
    }
  }

}
