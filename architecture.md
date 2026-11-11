---
id: istore-architecture
type: architecture-design
status: active
title: iStore 路由管家 — 架构
parent: istore-goal
---

## Shape

单个 HarmonyOS entry 模块（`store`，ArkTS，HarmonyOS 6.1.0，target/compatible 均 23），一个 UIAbility
`StoreAbility` 承载全部界面，两个扩展 ability：桌面卡片 `EntryFormAbility`、备份 `StoreBackupAbility`。
手机 / 平板 / 2in1 同一份代码，靠窗口宽度（600 vp / 1100 vp 两个断点）切换单栏、双栏、三栏布局。

路由器侧没有常驻插件：所有数据通过路由器**自带**的接口取。因此这个 App 的核心复杂度不在 UI，
而在「不同 OpenWrt 衍生版固件、不同权限状态下的数据获取与兜底」。

## Build & verify（本机）

工具链在 `F:\OpenHarmony`，共两个 SDK 根，**用错根必然编译失败**：

| 路径 | 内容 | 能否用于构建 |
|---|---|---|
| `F:\OpenHarmony\command-line-tools\sdk` | 一体化 HarmonyOS SDK（`default/{openharmony,hms}`，API 26） | ✅ `DEVECO_SDK_HOME` 必须指这里 |
| `F:\OpenHarmony\Sdk` | 按 API 号分目录的 OpenHarmony SDK（`23`、`26.0.0`，无 `hms`） | ❌ 报 `00303312 Cannot find the corresponding SDK version` |

已验证可行的编译检查（无签名、约 25 s）：

```sh
DEVECO_SDK_HOME='F:\OpenHarmony\command-line-tools\sdk' \
  F:/OpenHarmony/command-line-tools/bin/hvigorw.bat --mode module \
  -p module=store@default -p buildMode=debug default@CompileArkTS --no-daemon
```

前置：首次构建先跑 `ohpm.bat install --all`（会生成被 gitignore 的 `oh_modules`）。
最简单的入口是 `./scripts/ci.ps1`（`-Lint` 加代码检查、`-Pack` 打包）；它已会在 `DEVECO_SDK_HOME`
未设置时自动指到 `<command-line-tools>/sdk`。

每次构建还会先跑 `scripts/check-pages.ps1`：校验「新增页面四处登记」是否齐全（`main_pages.json` /
`PageRegistry` / `AppNav.PAGE_TITLES` / `PageHost`），漏登记直接中断构建。首次运行就查出两个死页面
（`RouteTablePage`、`HelpPage`），现已登记为磁贴。

### Lint 门禁

**口径：0 error 通过，warn 不阻塞**（用户确认）。lint 步骤保留在 CI 里，不因存量告警而摘掉检查。

- **成败由 `scripts/ci.ps1` 判定，不看 codelinter 的退出码**：codelinter 6.0.240 只要有任何 defect
  就返回非零，且 `-e/--exit-on` 在该版本不生效（三种写法均实测无效）。脚本解析汇总行
  `Defects: N; Errors: M; …`，仅当 `M > 0` 失败；**解析不到汇总行也判失败**，避免工具升级后门禁静默放宽。
- **`@typescript-eslint/await-thenable` 为 warn**：它对「可空或含 `void` 的 Promise 联合类型」固有误报
  （`await` 一个可能为 `null` 的值合法）；对 `libentry.so` 这个原生模块则解析不到类型（`Index.d.ts` 里
  签名本就是 `Promise<...>`，见 `mod-remote`），靠改代码无法消除。其余规则保持 error/recommended。
- **存量 40 个 warn 未清**（2026-11-11 基线），因为三类主力告警都无法在不改语义的前提下消掉：
  `foreach-args-check` 加 keyGenerator 会改变 ForEach 的 diff 行为；`hp-arkui-*` 两条命中的是异步流程
  里刻意驱动 UI 的 `@State` 写回；`reuse-date-instances-check` 命中的是循环内各自不同的 `new Date(...)`。
  收敛它们需要独立任务 + 逐页手测，不能顺手做。
- 未确认：GitHub CI runner 上的 codelinter 版本是否同为 6.0.240（不同则脚本以「no summary line」
  失败——方向安全，但需要在 runner 上实测一次）。

## Layers

```
pages/ (UI，@Component 页面)
   │  只读状态 + 调用业务方法
   ├──> common/store  (AppState / DeviceStore / 各领域 Store，单例 + Preferences 持久化)
   ├──> api/ApiService (类型化业务层，Models DTO + 静态 TTL 缓存)
   ├──> common/nav, common/utils/AppNav, common/components/PageHost  (路由与嵌入)
   └──> common/theme, common/components/AppIcon                      (配色与图标)

api/ApiService ──> api/ApiClient ──HTTP/JSON-RPC──> 路由器 (LuCI /ubus)
                        └──SSH 兜底──> common/ssh/SshService ──NAPI──> libentry.so (C++, SSH/SFTP)

common/ai/AiHelper, common/security/SecurityHubEngine ──> ApiService / SshService   (只派生结论)
```

## Modules

| id | 模块 | 位置 | 职责 |
|---|---|---|---|
| `mod-api` | 路由器通信层 | `store/src/main/ets/api/` | 两层的底层通信 + 业务解析，全部路由数据从这里出 |
| `mod-api-media` | 外部媒体客户端 | `api/ImmichClient.ets`, `api/JellyfinClient.ets` | 局域网媒体服务（非路由器） |
| `mod-router-assets` | 路由器端兼容资产 | `api/`（仓库根） | 旧版 CGI 脚本、rpcd ACL、安装脚本 |
| `mod-remote` | 远程通道 | `common/ssh/`, `common/fs/`, `src/main/cpp/` | SSH 终端、SFTP、端口转发的 ArkTS↔C++ 桥 |
| `mod-state` | 状态与持久化 | `common/store/` | 设备表、主题、实时速率、各领域单例状态 |
| `mod-pet` | 网络小管家 | `common/store/` 内 Pet/Fun/Mood/Diary | 情感化表达层（产品核心差异化） |
| `mod-insights` | 本地洞察 | `common/ai/`, `common/security/` | 规则式问答与安全评分 |
| `mod-nav` | 导航与页面注册 | `common/nav/`, `utils/AppNav`, `components/PageHost` | 手机全屏 / 平板内嵌双形态路由，并定义哪一页可以嵌栏 |
| `mod-theme` | 主题与图标 | `common/theme/`, `components/AppIcon`, `components/GlassCard` | 色板（8）× 材质（2）与它们的派生值 |
| `mod-ui` | 页面与布局 | `pages/` | 仪表盘、应用中心、各功能页 |
| `mod-shell` | 应用壳与系统集成 | `storeability/`, `storebackupability/`, `entryformability/`, `widget/` | 生命周期、沉浸式窗口、卡片、备份 |

## Dependency edges (verified from imports)

- `pages` → `common/store`(114 处) / `common/utils`(84) / `common/theme`(68) / `common/components`(52) /
  `api/ApiService`(38) / `models`(27)。页面直接 import `ApiClient` 的只有 `pages/entry/LoginPage.ets`
  和 `pages/apps/SmartHubPage.ets`。
- `common/store` → `api/ApiService`（4 处）、`api/ApiClient`（`AppState` 连接/切换设备）。
- `api/ApiClient` → `common/store/AppState`、`common/store/DeviceStore`、`common/ssh/SshService`、
  `common/utils/FormatUtils`。**注意这是一条回边**：通信层反过来依赖状态层拿当前设备与主题态，
  因此 `common/store` 与 `api` 之间存在真实循环依赖，改动其一需同时看另一侧。
- `common/ai`、`common/security` → `api/ApiService`（+ security 额外用 `SshService`、`NotifyStore`）。
- `common/fs/FileManagerService`、`common/ssh/SshService` 是**唯一** import `libentry.so` 的地方。
- `entryformability` → `common/store/WidgetDataStore`；`storeability` → 若干领域 Store + `utils/WindowUtils`。

## External channels

| 通道 | 用途 | 备注 |
|---|---|---|
| LuCI `/ubus` JSON-RPC | 主通道，账号密码登录换 session | 所有带 LuCI 的 OpenWrt 衍生版原生具备 |
| `/cgi-bin/router-api` + token | 旧版兼容通道 | 仅在设备没有 `/ubus` 时回退，见下 |
| LuCI 表单/cookie 登录 | 部分动作需要 LuCI 侧权限 | `luciHttp` |
| Docker Remote API | 容器统计 | ubus 数据不足时探测/启用 |
| SSH（libentry.so） | ubus 取不到的数据兜底、终端、文件 | 设备树、bridge FDB 等 |
| `api/NetProbe`（`@kit.NetworkKit`） | 外网探测 / 版本检查 / 测速下载 | 非路由器端点的唯一出口 |
| `https://istore.istoreos.com/api/store/list` | iStore 应用目录与版本 | 唯一外部业务接口 |
| Immich / Jellyfin HTTP | 媒体浏览播放 | 局域网地址，凭据按设备存 |

## Invariants

代码目前已经强制或高度依赖的规则，违反就会出错：

1. **页面不直连 `ApiClient`，也不 import `@kit.NetworkKit`**：路由器数据走 `ApiService`，非路由器端点
   （外网探测/版本检查/测速下载）走 `api/NetProbe`。当前**零页面**`import ApiClient`；唯一保留的
   NetworkKit 直连是 `AlbumTab` 的分享下载（需要可取消的长下载），见 `mod-ui`。
2. **切设备必须同时清理两侧缓存**：`ApiClient.configure()` 会断开 SSH、清 `sshPortCache`/ACL 标记/
   速率 in-flight；`AppState.connectToDevice` 还要调 `ApiService.resetCache()`。`ApiService` 的缓存是
   静态 TTL，漏清一次就会把上一台设备的数据/速率串到新设备上。
3. **只有只读动作自动重试**：传输失败重试一次（250 ms 退避）由 `isReadonlyCall` 按动作名前缀
   （`get*`/`info*`/`status*`/`list*`/`dump*`/`board*`/`read*`/`assoclist`/`login`）门控——写操作
   重试会造成重复执行（重启、删除、安装）。
4. **会话失效只重登一次**：ubus `-32002`/`-32004` 触发强制重登并重试一次，重试请求本身不再重试。
5. **实时速率共用一份**：`LiveRateStore` 的 5 s 心跳（`LIVE_REFRESH_MS`）是全应用唯一的速率来源，
   仪表盘 / 应用中心 / 小管家都订阅它；不要为速率另起 `setInterval`。轮询优先用
   `common/utils/Poller`（可见性门控 + in-flight 锁 + `dispose`）。
6. **新增页面是四处登记**：`resources/base/profile/main_pages.json` → `common/nav/PageRegistry`
   （应用中心磁贴/搜索/拼音首字母） → `common/utils/AppNav.PAGE_TITLES`（+ `EMBEDDABLE` 白名单） →
   `common/components/PageHost`（URL→组件分支）。漏掉任一处的表现分别是「路由不存在 / 搜不到 /
   标题为空 / 平板侧栏打不开」，且不会编译报错——所以 `mod-nav` 是唯一权威清单。
7. **颜色与形态只来自 `common/theme`**：颜色用 `this.theme.*`，卡片形态用 `theme.material.*` 或
   `cardTint/cardBorder/cardElevation/cardRadius`（新代码优先 `GlassCard`），图标用 `AppIcon`（固定
   `hos` 包，已无用户切换）。现状未完全落实，见 `mod-theme` 的 Known limitations。
8. **C++ NAPI 只经 `SshService` / `FileManagerService` 暴露**：页面不得直接 import `libentry.so`。
9. **能力探测而非版本判断**：ubus 缺失、ACL 权限不足、Docker API 未开等按探测结果降级（`ubusMissing`、
   `qwrtAutoFix`、`enableDockerApi`），不按固件版本号分支——这是兼容全系 OpenWrt 的根本手段。

## Decisions

- **连接方式以 ubus 账号密码为主、旧 CGI 为兼容**。旧 `router-api` CGI + token 通道保留的原因已确认：
  历史设备仍存着 token，保留是为了**老设备平滑迁移**，新设备一律不再走它；等存量设备迁移完可以删。
  这也解释了 `api/` 下脚本、安装器与 ACL 文件为什么还在仓库里（`mod-router-assets`）。
- **不引入云端**：没有账号体系、没有自建服务端，所有数据在设备本地与路由器之间流动。异地访问交给
  用户自己的域名/组网地址（登录框接受域名与端口）。
- **单模块而非多 HSP/HAR**：全部代码在一个 entry 模块内，靠目录分层而不是模块边界隔离。
- **主题 = 色板 × 材质**：色板决定颜色，材质（默认实色 / 液态玻璃）决定形态。两者正交、可任意组合，
  所以"换主题"真的改变 UI 而不只是底色。图标包选择已下线（用户可感知的选择只剩色板与材质）。
- **状态用 Preferences + 单例**，不引入第三方状态管理；需要响应式的地方把值镜像进 `AppStorage`
  供 `@StorageLink` 使用（`mod-state` 记录哪些键是镜像）。

## Known limitations

- **超大文件待拆分**（用户已确认，接受现状）：`api/ApiClient.ets` 4716 行（I/O + ubus 动作映射 +
  Docker + ACL 修复 + 解析 + shell 转义集中在一个类）、`api/ApiService.ets` 2129 行、
  `pages/dashboard/DashboardTab.ets` 2595 行、`pages/apps/AppsPage.ets` 1819 行、
  `pages/dashboard/AlbumTab.ets` 1724 行。改动这些文件时优先**局部收敛**，不要顺手大重构。
- **主题约定未完全落实**：仍有大量页面内硬编码色值（如 `PetPage`、`AppsPage`、`SmartHubPage`），
  与不变量 7 有偏差。
- **`common/utils/SecureStorage` 是混淆而非加密**：AES-128-CBC 的密钥与 IV 硬编码在源码里，
  文件头已注明；设备密码/令牌用它加密后再落 Preferences，只能防肉眼窥探。
- **备份扩展是空壳**：`StoreBackupAbility` 只打日志，不提供真实备份/恢复。
- **C++ 端口转发与密钥管理已导出但 ArkTS 未使用**（`napiPortForward`、`key_manager`）。
- 定时任务、通知监控这类后台行为只在 App 进程存活时运行，没有系统级后台常驻。

## 未确认 / 待补

- 上面「Known limitations」除第一项外都是代码读出的事实而非用户确认，若哪项其实是有意为之，
  需要改写成决策而不是限制。
- 未确认：`qwrtAutoFix` 通过注入 crontab 修补 rpcd ACL 的做法，是长期方案还是临时绕过。
