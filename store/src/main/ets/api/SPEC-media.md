---
id: mod-api-media
type: submodule-design
status: draft
title: 子模块：外部媒体客户端（Immich / Jellyfin）
parent: mod-api
---

## Responsibility

访问局域网里的两个「跑在路由器上的媒体服务」——Immich 相册（`api/ImmichClient.ets`）与 Jellyfin 影音库
（`api/JellyfinClient.ets`）：凭据鉴权、拉列表与详情、拼可播放的媒体地址。

它们和路由器的 ubus 通道**没有**关系，只是碰巧放在 `api/` 目录下：目标服务器是用户在路由器上另装的
服务，通过局域网 IP + 端口 + 凭据访问。

## Boundary

- 依赖：`@kit.NetworkKit`（自带 `http`）、`models/Models`。
- 被依赖：`pages/dashboard/AlbumTab`、`pages/apps/Jellyfin*`（列表/详情/播放页），凭据由
  `ImmichStore` / `JellyfinStore` 按 `deviceId` 保存后注入。
- 不做：不 import `ApiClient`/`ApiService`，不参与 ubus 会话，不影响路由器连接状态。失败时降级为
  「服务未启用/连不上」，不能把路由器的连接状态带坏。
- 凭据按设备隔离（key 用 `deviceId`），切设备必须拿到对应设备的凭据，不能复用上一台的 token。

## 关键机制

- Immich：只用 **API Key**（`x-api-key` 请求头，缩略图走 `?apiKey=` 查询参数），用户需在 Immich 后台
  自建密钥，App 不做账号密码登录。
- Jellyfin：`POST /Users/AuthenticateByName` + `X-Emby-Authorization` 换 `AccessToken`，后续请求带
  `X-Emby-Token`；播放页用直连流地址。客户端只负责鉴权与拼 URL，播放交给系统播放器。

（细节以两个文件为准，此规格只固定边界与"凭据按设备隔离"这条约束。）
