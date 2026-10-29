/**
 * SshService - SSH 终端服务（基于 CrossShellNext 的 libssh2 NAPI 封装 libentry）
 * - openProtocol 建立会话（sessionId 管理）
 * - sendTerminalCommand 走 channel exec（Xshell 阻塞模式），Promise 直接返回输出
 * - SFTP 完整（listDirectory/upload/download/rename/delete 等）供文件管理使用
 */
import { SavedDevice } from '../store/DeviceStore'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  openProtocol, sendTerminalCommand, closeProtocol,
  initSftp, listDirectory, SftpFileInfo,
  deleteFile, createDirectory, deleteDirectory, rename,
  uploadFile, downloadFile, cancelTransfer
} from 'libentry.so'

const DOMAIN = 0x0001
const TAG = 'SshService'

/** openProtocol 连接配置（C++ cJSON 解析字段） */
interface ConnectSession {
  connectionType: string
  hostName: string
  port: string
  userName: string
  password: string
  authType: string
  keepAlive: number
}

interface ConnectConfig {
  Session: ConnectSession
  Connection: ConnectConnection
}

/** C++ cJSON 解析要求 Connection.keepalive（数字）与 version（字符串）必填 */
interface ConnectConnection {
  keepalive: number
  version: string
}

export class SshService {
  private static instance: SshService
  private sessionId: number = -1
  private connectedFlag: boolean = false
  private hostName: string = ''
  /** 最近一次操作错误信息（页面诊断用） */
  lastError: string = ''
  /** 自动探测到的 SSH 端口（由 ApiClient 读取 Dropbear 配置后写入） */
  preferredPort: string = ''
  /** 最近一次连接成功的端口 */
  private lastGoodPort: string = ''
  private sftpInited: boolean = false

  static getInstance(): SshService {
    if (!SshService.instance) {
      SshService.instance = new SshService()
    }
    return SshService.instance
  }

  private constructor() {
  }

  /** 连接路由器（libssh2 交互会话），端口自动探测：设备记录 → 探测结果 → 上次成功 → 常见端口 */
  async connect(device: SavedDevice): Promise<boolean> {
    this.disconnect()
    // 等待 closeProtocol 异步完成，避免 C++ 侧 "Session busy" 拒绝
    await this.sleep(400)
    this.lastError = ''
    const ports: string[] = this.portCandidates(device)
    for (let i = 0; i < ports.length; i++) {
      const ok: boolean = await this.tryConnect(device, ports[i])
      if (ok) {
        this.lastGoodPort = ports[i]
        return true
      }
    }
    this.lastError = `SSH 连接失败：路由器未开启 SSH 或端口不是 22（已尝试 ${ports.join('/')}），请确认账号密码`
    return false
  }

  /** 端口候选顺序：设备记录 → 自动探测 → 上次成功 → 22 → 常见自定义端口 */
  private portCandidates(device: SavedDevice): string[] {
    const ports: string[] = []
    const push = (p: string): void => {
      if (p && p.length > 0 && ports.indexOf(p) < 0) {
        ports.push(p)
      }
    }
    const savedPort: string = device.sshPort ? device.sshPort : ''
    push(savedPort)
    push(this.preferredPort)
    push(this.lastGoodPort)
    push('22')
    push('2222')
    push('2022')
    push('2202')
    push('8022')
    return ports
  }

  /** 用指定端口尝试建立 SSH 会话 */
  private async tryConnect(device: SavedDevice, port: string): Promise<boolean> {
    try {
      const sessionCfg: ConnectSession = {
        connectionType: 'SSH',
        hostName: device.host,
        port: port,
        userName: device.username,
        password: device.password,
        authType: 'password',
        keepAlive: 60
      }
      const connCfg: ConnectConnection = { keepalive: 60, version: '1.0' }
      const connectCfg: ConnectConfig = { Session: sessionCfg, Connection: connCfg }
      const cfg: string = JSON.stringify(connectCfg)
      const sid: number = await openProtocol(cfg)
      if (sid < 0) {
        this.lastError = `SSH 端口 ${port} 连接失败`
        hilog.error(DOMAIN, TAG, `openProtocol failed on port ${port}: ${sid}`)
        return false
      }
      this.sessionId = sid
      this.connectedFlag = true
      this.hostName = device.host
      this.sftpInited = false
      this.lastError = ''
      hilog.info(DOMAIN, TAG, `SSH connected: ${device.host}:${port} sid=${sid}`)
      return true
    } catch (e) {
      const msg: string = SshService.errorMessage(e)
      this.lastError = `SSH 端口 ${port} 连接异常: ${msg}`
      hilog.error(DOMAIN, TAG, this.lastError)
      return false
    }
  }

  /** 提取错误可读信息（Error.message 不可枚举，JSON.stringify 会显示 {}） */
  static errorMessage(e: Object): string {
    try {
      const err = e as Error
      if (err && err.message && err.message.length > 0) {
        return err.message
      }
      const rec = e as Record<string, Object>
      if (rec && rec['message'] !== undefined) {
        return String(rec['message'])
      }
    } catch (_e) {}
    return JSON.stringify(e)
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms)
    })
  }

  /** 发送命令（channel exec 直接返回输出，绕开回调链路） */
  async sendCommand(cmd: string): Promise<string> {
    hilog.info(DOMAIN, TAG, `sendCommand called: conn=${this.connectedFlag} sid=${this.sessionId}`)
    if (!this.connectedFlag) {
      hilog.warn(DOMAIN, TAG, 'sendCommand skipped: not connected')
      return ''
    }
    try {
      const out: string = await sendTerminalCommand(this.sessionId, cmd)
      hilog.info(DOMAIN, TAG, `sendCommand ok, out ${out.length} bytes`)
      return out
    } catch (e) {
      hilog.error(DOMAIN, TAG, `sendCommand err: ${JSON.stringify(e)}`)
      return ''
    }
  }

  /** 一次性执行命令（channel exec 直接返回输出，Xshell 阻塞模式） */
  async exec(cmd: string): Promise<string> {
    if (!this.connectedFlag) {
      return '未连接 SSH，请先连接'
    }
    return await this.sendCommand(cmd)
  }

  /** 在当前目录下执行命令（App 模拟 cd 状态：前缀 cd） */
  async execInDir(cwd: string, cmd: string): Promise<string> {
    const dir: string = cwd.endsWith('/') ? cwd.slice(0, -1) : cwd
    return await this.exec(`cd '${dir}' && ${cmd}`)
  }

  // ==================== SFTP（文件管理） ====================

  private ensureSftp(): boolean {
    if (!this.connectedFlag) return false
    if (!this.sftpInited) {
      try {
        this.sftpInited = initSftp(this.sessionId)
      } catch (e) {
        hilog.error(DOMAIN, TAG, `initSftp err: ${JSON.stringify(e)}`)
        return false
      }
    }
    return this.sftpInited
  }

  /** 列出目录（SFTP） */
  async sftpList(path: string): Promise<SftpFileInfo[]> {
    if (!this.ensureSftp()) throw new Error('SFTP 初始化失败（可能未安装 openssh-sftp-server）')
    return await new Promise<SftpFileInfo[]>((resolve, reject) => {
      listDirectory(this.sessionId, path, (err: Error | null, result: SftpFileInfo[]) => {
        if (err) {
          reject(err)
        } else {
          resolve(result)
        }
      })
    })
  }

  /** 删除文件/目录（SFTP） */
  async sftpDelete(path: string, isDir: boolean): Promise<void> {
    if (!this.ensureSftp()) throw new Error('SFTP 不可用')
    const fn: (sid: number, p: string, cb: (err: Error | null, ok: boolean) => void) => void =
      isDir ? deleteDirectory : deleteFile
    return await new Promise<void>((resolve, reject) => {
      fn(this.sessionId, path, (err: Error | null, ok: boolean) => {
        if (err || !ok) {
          reject(err || new Error('删除失败'))
        } else {
          resolve()
        }
      })
    })
  }

  /** 新建目录（SFTP） */
  async sftpMkdir(path: string): Promise<void> {
    if (!this.ensureSftp()) throw new Error('SFTP 不可用')
    return await new Promise<void>((resolve, reject) => {
      createDirectory(this.sessionId, path, (err: Error | null, ok: boolean) => {
        if (err || !ok) {
          reject(err || new Error('创建失败'))
        } else {
          resolve()
        }
      })
    })
  }

  /** 重命名/移动（SFTP） */
  async sftpRename(oldPath: string, newPath: string): Promise<void> {
    if (!this.ensureSftp()) throw new Error('SFTP 不可用')
    return await new Promise<void>((resolve, reject) => {
      rename(this.sessionId, oldPath, newPath, (err: Error | null, ok: boolean) => {
        if (err || !ok) {
          reject(err || new Error('重命名失败'))
        } else {
          resolve()
        }
      })
    })
  }

  /** 上传文件（SFTP，带进度） */
  async sftpUpload(fd: number, targetDir: string, fileName: string): Promise<void> {
    if (!this.ensureSftp()) throw new Error('SFTP 不可用')
    return await new Promise<void>((resolve, reject) => {
      uploadFile(
        this.sessionId,
        [{ fd: fd, name: fileName }],
        targetDir,
        () => {},
        (err: Error | null) => {
          if (err) {
            reject(err)
          } else {
            resolve()
          }
        }
      )
    })
  }

  /** 下载文件到本地 fd（SFTP，带进度） */
  async sftpDownload(remotePath: string, fd: number): Promise<void> {
    if (!this.ensureSftp()) throw new Error('SFTP 不可用')
    return await new Promise<void>((resolve, reject) => {
      downloadFile(
        this.sessionId,
        remotePath,
        fd,
        () => {},
        (err: Error | null) => {
          if (err) {
            reject(err)
          } else {
            resolve()
          }
        }
      )
    })
  }

  /** 检测 SFTP 是否可用 */
  async checkSftp(): Promise<boolean> {
    try {
      const list: SftpFileInfo[] = await this.sftpList('/')
      return list !== null && list.length > 0
    } catch (e) {
      return false
    }
  }

  /**
   * 清洗 shell 输出：去提示符行/ANSI 控制符
   */
  static cleanShellOut(s: string): string {
    if (!s) return ''
    let t: string = s.replace(/\u001b\[[0-9;]*[a-zA-Z]/g, '')
    const lines: string[] = t.split('\n')
    const out: string[] = []
    for (let i = 0; i < lines.length; i++) {
      const ln: string = lines[i]
      if (/^\s*\S+@\S+[:\s~].*[#$]\s*$/.test(ln) && ln.length < 80) {
        continue
      }
      out.push(ln)
    }
    return out.join('\n').replace(/\n{3,}/g, '\n\n').trim()
  }

  /** 断开连接 */
  disconnect(): void {
    if (this.sessionId >= 0) {
      try {
        closeProtocol(this.sessionId)
      } catch (e) {
        hilog.error(DOMAIN, TAG, `disconnect err: ${JSON.stringify(e)}`)
      }
    }
    this.sessionId = -1
    this.connectedFlag = false
    this.hostName = ''
    this.sftpInited = false
  }

  /** 是否已连接 */
  isConnected(): boolean {
    return this.connectedFlag
  }

  /** 当前连接主机 */
  host(): string {
    return this.hostName
  }
}
