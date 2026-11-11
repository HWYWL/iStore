---
id: mod-remote
type: module-design
status: active
title: 模块：远程通道（SSH / SFTP / C++ NAPI）
parent: istore-architecture
---

## Responsibility

给 App 一条绕过 HTTP 的直连路由器通道，并把它包装成两个 ArkTS 单例：

- `common/ssh/SshService`：SSH 会话、命令执行（终端）、SFTP 的增删改查与上传下载、端口探测；
- `common/fs/FileManagerService`：在 SshService 之上做文件管理业务（列表排序、文本读写与大小上限、
  mkdir/touch/copy/rename、临时下载、上传、包管理器探测）。

底层 `store/src/main/cpp` 是一套基于 putty 的 C++ 实现，编译成 `libentry.so`，通过 NAPI 暴露
（`napiInterface`/`napiSftp`/`napiPortForward`/`key_manager`；`protocol/` 下按 ssh / telnet / serial 分
Session 实现，由 `SessionManager`/`SessionFactory` 管理）。TS 侧契约在
`cpp/types/libentry/Index.d.ts`，在 `store/oh-package.json5` 里以本地依赖 `libentry.so` 引入。

它还兼任 `mod-api` 的**兜底数据源**：ubus 读不到的数据（设备树、bridge 端口映射）由 ApiClient 经
SshService 取。

## Boundary

- **只有 `SshService` 与 `FileManagerService` 可以 import `libentry.so`**，页面不得直连 NAPI。
- 依赖：`common/store/DeviceStore` 的 `SavedDevice`（host/port/username/password/sshPort），不读 Preferences 其它域。
- 被依赖：`pages/apps/SshTerminalPage`、`pages/apps/FileManagerPage`、`common/security/SecurityHubEngine`、
  `api/ApiClient`（兜底）。
- 不做：不发起 HTTP 请求、不改路由器配置（写操作只经用户显式执行命令/文件操作）。

## Invariants

- **单例单会话**：`SshService` 全局只有一个 `sessionId`，同一时刻只能连一台设备；切设备/重连必须先
  `disconnect`（`ApiClient.configure()` 会替你做）。
- **端口按候选列表探测**：设备保存的 `sshPort` → 上次成功端口 → `22`/`2222`/`2022`/`2202`/`8022`，
  逐个尝试，全失败才算连不上。
- **SFTP 需要显式初始化**：`initSftp` 后 `sftpInited` 才为真，文件操作前先 `checkSftp()`；
  `NO_BIN`/`NO_SFTP` 表示路由器缺 sftp-server，要给出"未安装"的明确提示而不是泛化失败。
- **大文件有硬上限**：文本读取（`readText`）超过约 1.5 MB 直接拒绝、临时下载超过 20 MB 拒绝，
  避免把路由器文件整个读进内存。
- 连接凭据永远来自当前设备的 `SavedDevice`，与 `mod-api` 的 `ConnectionConfig` 是两套（SSH 端口 ≠ HTTP 端口）。

## Known limitations

- C++ 侧导出的**端口转发**（`startLocal/Remote/DynamicPortForwarding` 等）与**密钥管理**
  （`generateKeyPair`/`decryptPrivateKey`）在 ArkTS 里没有任何调用者，属于已编译进包的未用能力。
- `telnetSession` / `serialSession` 已实现但无入口，产品上只使用 SSH。
- 该层没有任何自动化测试，改动依赖真机（`store/src/ohosTest` 只有模板用例）。
