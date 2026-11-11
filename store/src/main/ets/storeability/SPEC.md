---
id: mod-shell
type: module-design
status: active
title: 模块：应用壳与系统集成（Ability / 卡片 / 备份）
parent: istore-architecture
depends-on: [mod-state]
---

## Responsibility

App 与鸿蒙系统之间的边界：进程生命周期、窗口形态、桌面卡片、备份扩展。这里不做业务，只做"把系统事件
接到业务上"和"把业务数据交给系统"。

| 构件 | 位置 | 职责 |
|---|---|---|
| `StoreAbility` | `ets/storeability/` | 唯一 UIAbility：设 `COLOR_MODE_NOT_SET`（跟随系统深浅色）、沉浸式/全屏窗口、回前台时按系统旋转锁重套方向；`onCreate` 里统一 init 本地 store（`TrafficStatStore`/`FunStore`/`DiaryStore`） |
| `EntryFormAbility` | `ets/entryformability/` | 桌面卡片 `widget_network`：`onAddForm` 归一化尺寸（只认 `2*2`/`2*4`）、`onUpdateForm` 推送 `WidgetDataStore` 快照；数据源是 App 前台轮询写入的 Preferences |
| `widget/pages/WidgetCard.ets` | 卡片 UI | 2×2 / 2×4 两种尺寸的 ArkTS 卡片 |
| `StoreBackupAbility` | `ets/storebackupability/` | 备份扩展（`BackupExtensionAbility`），声明在 `module.json5` 的 `extensionAbilities` |
| `resources/base/profile/form_config.json` | 卡片声明 | 卡片名、默认尺寸、`supportDimensions`、`updateDuration`、`colorMode: auto` |
| `resources/base/profile/main_pages.json` | 路由表 | 见 `mod-nav` |

## Boundary

- 依赖：`common/store`（`WidgetDataStore` 与几个需要 Context 初始化的 store）、`common/utils/WindowUtils`。
- 被依赖：系统（而非代码）——引擎按 `module.json5` 拉起这些 ability。
- 不做：不写业务逻辑、不直接请求路由器（`EntryFormAbility` 只读 Preferences 快照，卡片自己不联网）。

## Invariants

- **需要 Context 的 store 在这里 init**：页面内 `getUIContext().getHostContext()` 可能拿不到上下文，
  漏掉 `onCreate` 的初始化会让流量统计/作息/日记长期为空数据。新增此类 store 时必须在这里补一行。
- **卡片只消费快照**：改为在卡片里请求网络会让卡片刷新与电量失控；`WidgetDataStore` 的快照由前台轮询写入。
- **`module.json5` 是权限与 ability 的唯一真相**：`INTERNET`、`VIBRATE` 与三个 ability 的注册都在那里，
  新增扩展能力要同时改 `srcEntry` 与 profile 文件。
- 深浅色跟随系统（`COLOR_MODE_NOT_SET`），不要在这里强制某一模式。

## Known limitations

- **备份扩展是空壳**：`onBackup`/`onRestore` 只打日志，用户以为的"系统备份"并不会备份设备表或设置。
- 卡片数据只在 App 前台运行时更新（`updateDuration: 1` 小时只是引擎的保底刷新，快照不新就是旧数据），
  没有后台任务。
- 无后台任务/长时任务能力：定时任务与通知监控都随 App 进程存活（见 `mod-state`）。
