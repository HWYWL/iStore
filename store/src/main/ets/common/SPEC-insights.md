---
id: mod-insights
type: module-design
status: active
title: 模块：本地洞察（规则问答 / 安全评分）
parent: istore-architecture
depends-on: [mod-api, mod-remote]
---

## Responsibility

用规则把路由器的原始数据变成**结论**，且不依赖任何服务端：

- `common/ai/AiHelper.ets` —— 「网络助手」。没有模型、没有网络请求：关键词匹配用户问题 → 现取实时数据
  （设备数/系统信息/WAN/连接跟踪）→ 拼出自然语言回答。刻意命名为 AI，但实现是纯本地规则。
- `common/security/SecurityHubEngine.ets` —— 家庭网络安全评分。五个维度（陌生设备 / 开放端口 / 弱密码 /
  固件版本 / 访客网络隔离），每维 0–100 分，汇总为总分并按绿 ≥85 / 黄 60–84 / 红 <60 分档；结果本地
  存储，数据不出家门。

## Boundary

- 依赖：`api/ApiService`（主数据源）、`common/ssh/SshService`（安全扫描需要 SSH 侧信息）、
  `models`、`FormatUtils`；`SecurityHubEngine` 还会读 `NotifyStore` 的设置、写自己的 Preferences 历史。
- 被依赖：`pages/apps/NetworkHelperPage`（助手对话）、`pages/security/SecurityHubPage`、
  `NotificationWatcher`（经由 `AiHealthChecker` 的阈值判断思路，但阈值告警在 `mod-state` 内实现）。
- 不做：不发请求到任何云端、不缓存整份路由器数据、不做写操作；结论只是解释，动作仍由页面显式发起。

## Invariants

- **无网络出口**：这两个模块不得 import `@kit.NetworkKit`，也不得引入第三方 AI SDK。它们只消费
  `ApiService`/`SshService` 已有的结果。
- **拿不到数据就说不知道**：某一维取数失败必须是 `unknown` 而不是判为 `safe`，总分里也要体现；宁可
  分数失真也不能给错结论。
- **阈值可调且集中**：健康告警的阈值由 `NotifyStore` 保存、在「智能通知」页调整，不要在引擎里另写死
  一套默认值。
- 评分结果按时间倒序本地留存，供安全中心展示趋势。

## Known limitations

- 「AI 助手」是关键词规则匹配，问法超出既定词表会答非所问；新增能力的方式是扩词表 + 扩回答模板，
  没有泛化能力。
- 五维评分的判定多为启发式（如固件版本只按版本号新旧推断），存在误判，UI 文案上按「建议排查」而非
  「确诊」表述。
- `SecurityHubEngine` 没有单元测试，规则改动只能靠真机验证。
