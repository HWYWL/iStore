---
id: mod-pet
type: submodule-design
status: draft
title: 子模块：网络小管家（养成 / 心情 / 日记）
parent: mod-state
depends-on: [mod-theme]
---

## Responsibility

把监控数据变成**有情绪的表达**——这是产品的核心差异化原则，不是彩蛋（用户已确认）。四个部件：

- **`PetStore`**：管家本体。`level`(1–99)/`xp`/`full`(饱食)/`energy`/`mood`/`skinId`/装扮，每天递减模拟
  饥饿；存储名 `pet_store`。
- **`MoodEngine`**：心情文案引擎。按路由器实时状态（温度/负载/内存/网速/运行天数）+ 养成状态（心情/等级）
  生成状态相关文案，再叠加十几条日常闲聊；每次轮播约 65% 概率优先取状态相关文案，并避开上一条。
- **`DiaryStore`**：网络日记。按天收集事件（`new_device`/`traffic`/`offline`/`security`/`peak`），保留 30 天。
- **`FunStore`**：成就、里程碑、设备作息采样，存储名 `iStore_fun_store`。

## Boundary

- 依赖：`AppState`（主题/皮肤）、`ApiService`（读实时数据）、`FormatUtils`；与 `LiveRateStore` 共用同一份速率。
- 被依赖：`pages/pet/PetPage`、`pages/pet/SkinPickerPage`、`pages/dashboard/DashboardTab`、
  `pages/apps/{AchievementPage,MileStonePage,DiaryPage,RouterLevelPage,RouterMoodPage,ShareCardPage}`、
  `pages/apps/AppsPage`（Bento 卡）、`storeability`（启动时 init）。
- 不做：不改路由器任何配置、不发系统通知（通知归 `NotifyStore`）、不引入服务端/账号——全部本地数据。

## Invariants

- **文案 <= 14 字**：气泡单行显示，前缀「☀ 心情 · 」占 6 字，超长会截断。
- **文案与状态挂钩**：新增文案优先加进 `statePool`（按实际指标分支），闲聊池只补足多样性；轮播要避开
  上一条，避免连续重复。
- **每日结算一次**：`PetStore` 以 `lastDay` 判断跨天递减，必须在 `init` 内完成，不依赖页面是否打开。
- **任务完成 = 打开对应页面**：`PetStore.TASK_ROUTES`（网络体检/网络助手/流量报告/设备活动/安全中心）与
  `PetPage` 的任务列表顺序严格一一对应，奖励数组 `TASK_ENERGY` 同序；`TASK_SCHEMA` 版本变更时清空历史
  勾选，防止旧数据污染。
- **皮肤与主题同源**：装扮的 `skinId` 取自 `common/theme` 的 `SKINS`（见 `mod-theme`），不要在宠物模块
  里另维护一套颜色。

## Known limitations

- 全部数据在本地 Preferences，卸载或清除数据即丢失，没有导出/迁移。
- 「打开页面即完成任务」的判定可被反复进入页面刷取（每日判定由 `task_day` 限制）。
- 小管家叙事目前只落在心情/日记/成就几个页面，仪表盘与部分功能页仍是纯数据表达——按产品原则，这类
  新功能的默认落点是管家叙事。
