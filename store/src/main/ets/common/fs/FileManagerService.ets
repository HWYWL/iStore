/**
 * FileManagerService - OpenWrt 文件管理服务（基于 libentry SFTP）
 * 全部文件操作走 SFTP 通道：list/read/upload/download/rename/delete 等
 * 安全：删除由 UI 层二次确认
 */
import { SshService } from '../ssh/SshService'
import { SftpFileInfo } from 'libentry.so'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'FileMgr'

/** 文件条目（页面使用） */
export interface FsEntry {
  name: string
  path: string
  isDir: boolean
  isLink: boolean
  size: number
  modified: string
  isHidden: boolean
}

export class FileManagerService {
  private static instance: FileManagerService
  private ssh: SshService = SshService.getInstance()

  static getInstance(): FileManagerService {
    if (!FileManagerService.instance) {
      FileManagerService.instance = new FileManagerService()
    }
    return FileManagerService.instance
  }

  /** 连接状态 */
  isConnected(): boolean {
    return this.ssh.isConnected()
  }

  /** 路径拼接 */
  private join(base: string, name: string): string {
    return `${base.endsWith('/') ? base : base + '/'}${name}`
  }

  /** SftpFileInfo → FsEntry */
  private toEntry(info: SftpFileInfo, base: string): FsEntry {
    const full: string = this.join(base, info.name)
    return {
      name: info.name,
      path: full,
      isDir: info.isDirectory,
      isLink: false,
      size: info.size,
      modified: info.mtime || '',
      isHidden: info.name.startsWith('.')
    }
  }

  /** 通用超时包装（防止 SFTP 无响应时 UI 无限 loading） */
  private static withTimeout<T>(p: Promise<T>, ms: number, errMsg: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timer: number = setTimeout(() => {
        reject(new Error(errMsg))
      }, ms)
      p.then((v: T) => {
        clearTimeout(timer)
        resolve(v)
      }).catch((e: Error) => {
        clearTimeout(timer)
        reject(e)
      })
    })
  }

  /** 列出目录内容（SFTP，8 秒超时保护） */
  async list(path: string): Promise<FsEntry[]> {
    const infos: SftpFileInfo[] = await FileManagerService.withTimeout(
      this.ssh.sftpList(path), 8000,
      '加载超时：路由器 SFTP 无响应（组件异常或未正确安装）')
    const entries: FsEntry[] = infos.map((i: SftpFileInfo): FsEntry => this.toEntry(i, path))
    // 目录在前，名称排序
    entries.sort((a: FsEntry, b: FsEntry) => {
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return entries
  }

  /** 读取文本文件（SFTP 下载到临时文件，限 1.5MB） */
  async readText(path: string, _useSftp: boolean = true): Promise<string> {
    const entries: FsEntry[] = await this.list(path.substring(0, path.lastIndexOf('/')) || '/')
    for (const e of entries) {
      if (e.path === path && e.isDir) {
        throw new Error('这是一个目录')
      }
      if (e.path === path && e.size > 1536 * 1024) {
        throw new Error('文件过大（>1.5MB），暂不支持查看')
      }
    }
    const content: string = await this.downloadToTemp(path)
    if (content.length > 1536 * 1024) {
      throw new Error('文件过大（>1.5MB），暂不支持查看')
    }
    return content
  }

  /** 写入文本（保存编辑：本地临时文件 → SFTP 上传覆盖） */
  async writeText(path: string, content: string): Promise<void> {
    const ctx = this.getCtx()
    const tmp: string = `${ctx.cacheDir}/fm_write_${Date.now()}.tmp`
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        const encoder = new util.TextEncoder()
        const bytes: Uint8Array = encoder.encodeInto(content)
        fs.writeSync(file.fd, bytes.buffer)
      } finally {
        try { fs.closeSync(file) } catch (e) {}
      }
      const dir: string = path.substring(0, path.lastIndexOf('/')) || '/'
      const name: string = path.substring(path.lastIndexOf('/') + 1)
      const wf = fs.openSync(tmp, fs.OpenMode.READ_ONLY)
      try {
        await this.ssh.sftpUpload(wf.fd, dir, name)
      } finally {
        try { fs.closeSync(wf) } catch (e) {}
      }
    } catch (e) {
      throw new Error(`保存文件失败：${JSON.stringify(e)}`)
    } finally {
      try { fs.unlinkSync(tmp) } catch (e) {}
    }
  }

  /** 新建目录（SFTP） */
  async mkdir(path: string): Promise<void> {
    await this.ssh.sftpMkdir(path)
  }

  /** 新建空文件（上传空内容） */
  async touch(path: string): Promise<void> {
    const ctx = this.getCtx()
    const tmp: string = `${ctx.cacheDir}/fm_touch_${Date.now()}.tmp`
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      try { fs.closeSync(file) } catch (e) {}
      const dir: string = path.substring(0, path.lastIndexOf('/')) || '/'
      const name: string = path.substring(path.lastIndexOf('/') + 1)
      const rf = fs.openSync(tmp, fs.OpenMode.READ_ONLY)
      try {
        await this.ssh.sftpUpload(rf.fd, dir, name)
      } finally {
        try { fs.closeSync(rf) } catch (e) {}
      }
    } catch (e) {
      throw new Error(`新建文件失败：${JSON.stringify(e)}`)
    } finally {
      try { fs.unlinkSync(tmp) } catch (e) {}
    }
  }

  /** 删除（SFTP，UI 层需二次确认） */
  async remove(path: string, isDir: boolean): Promise<void> {
    await this.ssh.sftpDelete(path, isDir)
  }

  /** 重命名 / 移动（SFTP） */
  async rename(oldPath: string, newPath: string): Promise<void> {
    await this.ssh.sftpRename(oldPath, newPath)
  }

  /** 复制（SFTP：下载到临时再上传，限 10MB） */
  async copy(src: string, dst: string): Promise<void> {
    const ctx = this.getCtx()
    const tmp: string = `${ctx.cacheDir}/fm_copy_${Date.now()}.tmp`
    try {
      const wf = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await this.ssh.sftpDownload(src, wf.fd)
      } finally {
        try { fs.closeSync(wf) } catch (e) {}
      }
      const dir: string = dst.substring(0, dst.lastIndexOf('/')) || '/'
      const name: string = dst.substring(dst.lastIndexOf('/') + 1)
      const rf = fs.openSync(tmp, fs.OpenMode.READ_ONLY)
      try {
        await this.ssh.sftpUpload(rf.fd, dir, name)
      } finally {
        try { fs.closeSync(rf) } catch (e) {}
      }
    } catch (e) {
      throw new Error(`复制文件失败：${JSON.stringify(e)}`)
    } finally {
      try { fs.unlinkSync(tmp) } catch (e) {}
    }
  }

  /** 下载文件到临时并返回内容（文本读取/下载用，限 20MB） */
  async downloadToTemp(remotePath: string): Promise<string> {
    const ctx = this.getCtx()
    const tmp: string = `${ctx.cacheDir}/fm_dl_${Date.now()}.tmp`
    try {
      const wf = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await this.ssh.sftpDownload(remotePath, wf.fd)
      } finally {
        try { fs.closeSync(wf) } catch (e) {}
      }
      const stat = fs.statSync(tmp)
      if (stat.size > 20 * 1024 * 1024) {
        throw new Error('文件过大（>20MB），暂不支持')
      }
      const rf = fs.openSync(tmp, fs.OpenMode.READ_ONLY)
      const buf = new ArrayBuffer(stat.size)
      try {
        fs.readSync(rf.fd, buf)
      } finally {
        try { fs.closeSync(rf) } catch (e) {}
      }
      const decoder = new util.TextDecoder()
      return decoder.decodeToString(new Uint8Array(buf))
    } catch (e) {
      throw new Error(`读取文件失败：${JSON.stringify(e)}`)
    } finally {
      try { fs.unlinkSync(tmp) } catch (e) {}
    }
  }

  /** 下载文件到指定本地路径（文件管理"下载"用，120 秒超时保护 + 确保关闭 fd） */
  async downloadToPath(remotePath: string, localPath: string): Promise<void> {
    let wf: fs.File | null = null
    try {
      wf = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      await FileManagerService.withTimeout(
        this.ssh.sftpDownload(remotePath, wf.fd), 120000,
        '下载超时：路由器响应缓慢或文件过大，请重试')
    } catch (e) {
      throw new Error(`下载失败：${JSON.stringify(e)}`)
    } finally {
      try {
        if (wf) {
          fs.closeSync(wf)
        }
      } catch (e) {}
    }
  }

  /** 上传本地文件（文件管理"上传"用） */
  async uploadFile(localPath: string, targetDir: string, fileName: string): Promise<void> {
    try {
      const rf = fs.openSync(localPath, fs.OpenMode.READ_ONLY)
      try {
        await this.ssh.sftpUpload(rf.fd, targetDir, fileName)
      } finally {
        try { fs.closeSync(rf) } catch (e) {}
      }
    } catch (e) {
      throw new Error(`上传文件失败：${JSON.stringify(e)}`)
    }
  }

  /** 检测 SFTP 是否可用（命令秒检，不等 SFTP 超时） */
  async checkSftp(): Promise<boolean> {
    // 快速路径：
    //  NO_BIN  = sftp-server 二进制不存在（未安装）
    //  NO_SFTP = 二进制在但 dropbear 配置显式禁用 SFTP（EnableSftp='0'）
    //  READY   = 二进制在且未被禁用（dropbear 默认启用 SFTP）
    try {
      const r: string = await this.ssh.exec(
        `B=$(ls /usr/lib/openssh/sftp-server /usr/libexec/sftp-server /usr/lib/sftp-server 2>/dev/null | head -1);` +
        `if [ -z "$B" ]; then echo NO_BIN;` +
        `else E=$(uci get dropbear.@dropbear[0].EnableSftp 2>/dev/null); ` +
        `if [ "$E" = "0" ]; then echo NO_SFTP; else echo READY; fi; fi`)
      const t: string = r.trim()
      if (t === 'READY') return true
      if (t === 'NO_BIN' || t === 'NO_SFTP') return false
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `checkSftp cmd err: ${JSON.stringify(e)}`)
    }
    // 兜底：SFTP 实测（仅当命令通道异常时）
    try {
      const list: SftpFileInfo[] = await this.ssh.sftpList('/')
      return list !== null && list.length > 0
    } catch (e) {
      return false
    }
  }

  /**
   * 检测包管理器类型（OpenWrt 版本差异）
   * 返回：'apk'（OpenWrt 25.x）/ 'opkg'（OpenWrt 24.x 及更早）/ ''（无包管理器）
   */
  async detectPkgManager(): Promise<string> {
    try {
      const r: string = await this.ssh.exec(
        `[ -x /bin/apk ] && echo APK || ([ -x /bin/opkg ] && echo OPKG || echo NONE)`)
      const t: string = r.trim()
      if (t === 'APK') return 'apk'
      if (t === 'OPKG') return 'opkg'
      return ''
    } catch (e) {
      hilog.error(DOMAIN, TAG, `detectPkgManager err: ${JSON.stringify(e)}`)
      return ''
    }
  }

  /**
   * 一键安装 SFTP（openssh-sftp-server）
   * @param onLog 步骤输出回调（UI 显示进度）
   * @returns 是否安装成功
   */
  async installSftp(onLog: (line: string) => void): Promise<boolean> {
    try {
      // 1. 检测包管理器（版本差异：24.xx=opkg，25.xx=apk）
      const pm: string = await this.detectPkgManager()
      if (pm === '') {
        onLog('❌ 未检测到 apk / opkg 包管理器，无法自动安装')
        onLog('提示：请确认这是 OpenWrt 系固件')
        return false
      }
      onLog(`✅ 检测到包管理器：${pm === 'apk' ? 'apk（OpenWrt 25.x）' : 'opkg（OpenWrt 24.x 及更早）'}`)

      // 2. 更新软件源
      onLog('⏳ 更新软件源中…（首次可能需要 1-2 分钟）')
      const upCmd: string = pm === 'apk' ? 'apk update 2>&1' : 'opkg update 2>&1'
      const upOut: string = await this.ssh.exec(upCmd)
      const upTrim: string = upOut.trim()
      if (upTrim.length > 0) {
        onLog(upTrim.substring(0, 200))
      }
      if (upTrim.indexOf('error') >= 0 || upTrim.indexOf('failed') >= 0) {
        onLog('⚠ 软件源更新可能有异常，继续尝试安装…')
      }

      // 3. 安装 openssh-sftp-server
      onLog('⏳ 安装 openssh-sftp-server…')
      const insCmd: string = pm === 'apk' ? 'apk add openssh-sftp-server 2>&1' : 'opkg install openssh-sftp-server 2>&1'
      const insOut: string = await this.ssh.exec(insCmd)
      const insTrim: string = insOut.trim()
      if (insTrim.length > 0) {
        onLog(insTrim.substring(0, 300))
      }
      // 成功标志：opkg 出现 Configuring 或 already installed；apk 出现 installed/OK/up to date
      const okOpkg: boolean = insTrim.indexOf('Configuring openssh-sftp-server') >= 0 ||
        insTrim.indexOf('already installed') >= 0 || insTrim.indexOf('Installing') >= 0
      const okApk: boolean = insTrim.indexOf('installed') >= 0 || insTrim.indexOf('OK') >= 0 ||
        insTrim.indexOf('up to date') >= 0
      const failMark: boolean = insTrim.indexOf('error') >= 0 || insTrim.indexOf('No such') >= 0 ||
        insTrim.indexOf('not found') >= 0
      if ((pm === 'apk' && !okApk) || (pm === 'opkg' && !okOpkg) || failMark) {
        if (failMark && pm === 'opkg' && insTrim.indexOf('error') >= 0) {
          onLog('❌ 安装失败：软件源可能不含该包或网络异常')
          return false
        }
      }

      // 4. 验证 sftp-server 二进制（各版本路径不同）
      onLog('🔍 验证 sftp-server 组件…')
      const chk: string = await this.ssh.exec(
        `ls /usr/lib/openssh/sftp-server /usr/libexec/sftp-server /usr/lib/sftp-server 2>/dev/null | head -1`)
      const chkPath: string = chk.trim()
      if (chkPath.length === 0) {
        onLog('⚠ 安装命令已执行，但未找到 sftp-server 二进制')
        onLog('提示：可检查软件源配置，或到 LuCI 软件包页面手动安装 openssh-sftp-server')
        return false
      }
      onLog(`✅ sftp-server 已就绪：${chkPath}`)

      // 5. 配置 dropbear 开机自启 + 启用 SFTP 子系统（防止重启路由器后失效）
      onLog('⚙️ 配置 dropbear 开机自启 SFTP…')
      const cfgCmd: string =
        `uci set dropbear.@dropbear[0].EnableSftp='1' && ` +
        `uci commit dropbear && /etc/init.d/dropbear enable && echo CFG_OK`
      try {
        const cfgOut: string = await this.ssh.exec(cfgCmd)
        if (cfgOut.indexOf('CFG_OK') >= 0) {
          onLog('✅ 开机自启已配置（EnableSftp=1，dropbear 随系统启动）')
        } else {
          onLog('⚠ dropbear 配置输出异常，继续重启尝试')
        }
      } catch (e) {
        onLog('⚠ dropbear 配置命令异常，继续重启尝试')
      }

      // 6. 重启 dropbear 使 SFTP 子系统生效（当前 SSH 连接会断开）
      onLog('🔄 重启 dropbear 服务（当前连接将短暂断开）…')
      try {
        await this.ssh.exec('/etc/init.d/dropbear restart 2>&1; echo DROPBEAR_DONE')
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `dropbear restart (connection dropped): ${JSON.stringify(e)}`)
      }
      onLog('✅ 安装完成！正在重新连接…')
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, `installSftp err: ${JSON.stringify(e)}`)
      onLog(`❌ 安装过程异常：${JSON.stringify(e)}`)
      return false
    }
  }

  /** 读取文件为 base64（下载用） */
  async readBase64(path: string): Promise<string> {
    const content: string = await this.downloadToTemp(path)
    const encoder = new util.TextEncoder()
    const bytes: Uint8Array = encoder.encodeInto(content)
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(bytes)
  }

  /** 写入 base64 内容（上传用） */
  async writeBase64(path: string, b64: string): Promise<void> {
    const helper = new util.Base64Helper()
    const bytes: Uint8Array = helper.decodeSync(b64)
    const decoder = new util.TextDecoder()
    const content: string = decoder.decodeToString(bytes)
    await this.writeText(path, content)
  }

  private static hostCtx: common.UIAbilityContext

  private getCtx(): common.UIAbilityContext {
    return FileManagerService.hostCtx
  }

  /** 注入页面上下文（页面 aboutToAppear 时调用） */
  setHostContext(ctx: common.UIAbilityContext): void {
    FileManagerService.hostCtx = ctx
  }

  /** 友好大小 */
  static formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
    return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`
  }

  /** 文本类型判断（可编辑查看） */
  static isTextFile(name: string): boolean {
    const lower: string = name.toLowerCase()
    const textExts: string[] = [
      'txt', 'conf', 'sh', 'json', 'xml', 'log', 'cfg', 'ini', 'yaml', 'yml',
      'md', 'html', 'js', 'css', 'py', 'lua', 'c', 'h', 'makefile', 'profile',
      'uci', 'version', 'release', 'passwd', 'group', 'hosts', 'resolv.conf'
    ]
    for (const ext of textExts) {
      if (lower.endsWith('.' + ext)) return true
    }
    return lower.indexOf('.') < 0
  }
}
