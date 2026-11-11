---
id: mod-router-assets
type: module-design
status: active
title: 模块：路由器端兼容资产（api/）
parent: istore-architecture
---

## Responsibility

仓库根 `api/` 不是 App 代码，而是**部署到路由器上、或被 App 直接拉取的静态资产**。它承担三件事：

- `router-api`：POSIX sh 写的 CGI 程序（安装到 `/www/cgi-bin/router-api`），提供 `?action=...&token=...`
  形式的 REST 响应，是 App `legacy` 连接模式的另一端。
- `install.sh` / `uninstall.sh` / `qwrt-setup.sh`：一键安装脚本（uhttpd CGI 前缀、token 生成与写入、
  rpcd ACL 下发、幂等重装）。
- `istore-app.json`：rpcd ACL 文件，声明 App 需要的 ubus 读/写权限（`system`、`network.interface`、
  `uci`、`file`、`iwinfo`、`luci` 等）。`qwrt-setup.sh` 把它写入 `/usr/share/rpcd/acl.d/`。
- `version.json`：应用更新源，`pages/other/AboutPage.ets` 从这里读最新版本与下载地址。

## Boundary

- 与被 App 编译打包进 HAP 的 `store/src/main/ets/api/`（`mod-api`）**不是同一件事**：那边是客户端代码，
  这边是路由器侧产物。两边共享同一份动作名契约（`action` 名称与 `RouterApiResponse` 结构）。
- 脚本必须能在**任意 busybox/精简 OpenWrt** 上跑：只用 `sh` + `ubus`/`uci`/`jsonfilter` + 可选 `wget`
  /`curl`/`uclient-fetch`，不依赖 bash、不依赖 opkg 装包（缺 `uhttpd` 时才尝试安装）。
- 不做：不嵌入 App、不参与构建流程，也不被 CI 检查（纯 shell，无编译期校验）。

## Why it still exists

整个方案的前提是「新设备零安装」——优先走路由器自带的 LuCI `/ubus`。`router-api` + `install.sh` 这一套是
历史方案，仅用于兼容已保存的旧设备（旧设备存的是 token，不是账号密码）。**已确认的决策是：保留只为老设备
平滑迁移，新设备不再安装，存量迁移完成后可以删除。**

因此：不要在 App 里新增对 `router-api` 动作的依赖，也不要在此基础上扩展功能；`istore-app.json` 的 ACL 与
`qwrt-setup.sh` 仍在新设备上有用（部分固件缺 rpcd ACL 时 App 需要它，或由 App 的 `qwrtAutoFix` 自愈）。

## Invariants

- `action=ping` 无 token 也必须可用（安装脚本靠它自检）。
- token 从 `/etc/router-api-token`（600）与 `uci router-api.config.auth_token` 两处读取，二者不一致时
  以文件为准。
- 脚本必须可重复执行（幂等）：重复安装不能破坏已有 token 和 Web 服务器配置。
- 任何自动化行为都要"探测后降级"：检测不到 `uhttpd` 就尝试安装，装不上就明确报错退出，不静默成功。

## Known limitations

- `router-api`（33 KB 单文件 shell）自身没有测试，改动只能靠真机验证。
- `version.json` 的版本号需要人工与 `AppScope/app.json5` 的 `versionName`/`versionCode` 对齐，没有构建期校验
  （曾出现过 `store/oh-package.json5` 停在 3.5.0、而实际版本已是 3.8.0 的漂移）。
