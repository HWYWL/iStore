# iStoreOS API 接口参考文档

> 本文档基于 iStoreOS Monitor v3.1 逆向梳理，覆盖 iStoreOS（OpenWrt 发行版）Luci 后台的 REST API 与 ubus JSON-RPC 接口。  
> 所有接口均通过 HTTP 调用，Base URL 为 `http://<router-host>/cgi-bin/luci`。

---

## 目录

- [1. 鉴权](#1-鉴权)
- [2. iStore REST API](#2-istore-rest-api)
  - [2.1 系统状态 —— `/istore/system/status/`](#21-系统状态--istoresystemstatus)
  - [2.2 网络状态 —— `/istore/u/network/status/`](#22-网络状态--istoreunetworkstatus)
  - [2.3 系统版本 —— `/istore/u/system/version/`](#23-系统版本--istoreusystemversion)
  - [2.4 网络统计 —— `/istore/u/network/statistics/`](#24-网络统计--istoreunetworkstatistics)
- [3. ubus JSON-RPC 接口](#3-ubus-json-rpc-接口)
  - [3.1 system.board —— 获取主板/系统信息](#31-systemboard--获取主板系统信息)
- [4. 附录](#4-附录)
  - [4.1 请求/响应字符编码](#41-请求响应字符编码)
  - [4.2 错误处理](#42-错误处理)
  - [4.3 速率限制](#43-速率限制)

---

## 1. 鉴权

**所有 API 调用前必须先登录并携带 Cookie。**

### 登录

```http
POST /cgi-bin/luci/
Content-Type: application/x-www-form-urlencoded; charset=utf-8
```

**请求体**（`application/x-www-form-urlencoded`）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `luci_username` | `string` | 是 | 路由器管理员用户名（通常为 `root`） |
| `luci_password` | `string` | 是 | 路由器管理员密码（URL 编码） |

**示例**

```bash
curl -X POST "http://172.16.10.203/cgi-bin/luci/" \
  -H "Content-Type: application/x-www-form-urlencoded; charset=utf-8" \
  -d "luci_username=root&luci_password=your_password"
```

**成功响应**

- HTTP 状态码 `200` 或 `302`
- 响应头 `Set-Cookie` 中包含 `sysauth=<token>`；后续所有 API 请求必须带上该 Cookie

**注意**：登录后须设置 `InstanceFollowRedirects=false`，避免自动跟随 302 重定向导致 Cookie 丢失。

### 请求头规范

所有 API 请求（除登录外）必须携带：

| 请求头 | 说明 |
|--------|------|
| `Cookie` | `sysauth=<token>`（登录后获得） |

---

## 2. iStore REST API

所有 iStore 接口均返回如下统一结构：

```json
{
  "result": { ... },
  "code": 0
}
```

- `result`（`object`）：业务数据，实际返回值
- `code`（`int`）：状态码，`0` 表示成功
- 部分接口可能返回 `data` 字段代替 `result`

如果响应中同时存在 `result` 和 `data`，优先使用 `result`。

---

### 2.1 系统状态 —— `/istore/system/status/`

采集路由器实时系统状态（CPU、内存、运行时长等）。

```http
GET /cgi-bin/luci/istore/system/status/
```

#### 请求参数

无需参数。

#### 响应字段

| 字段 | 类型 | 单位 | 说明 |
|------|------|------|------|
| `cpuUsage` | `int` | % | 当前 CPU 使用率（0–100） |
| `cpuTemperature` | `int` | ℃ | CPU 温度，若无传感器则返回 `-1` |
| `memTotal` | `string` | — | 总内存，人类可读格式（如 `"7.63 GiB"`） |
| `memAvailable` | `string` | — | 可用内存，人类可读格式（如 `"4.50 GiB"`） |
| `memAvailablePercentage` | `int` | % | 可用内存百分比（0–100） |
| `uptime` | `long` | 秒 | 系统运行时长（Unix 时间戳差值形式的秒数） |
| `localtime` | `string` | — | 本地系统时间，格式 `yyyy-MM-dd HH:mm:ss` |

#### 示例响应

```json
{
  "result": {
    "cpuUsage": 12,
    "cpuTemperature": 45,
    "memTotal": "7.63 GiB",
    "memAvailable": "4.50 GiB",
    "memAvailablePercentage": 59,
    "uptime": 534330,
    "localtime": "2026-05-21 13:55:00"
  },
  "code": 0
}
```

#### 使用示例

```bash
curl -s "http://172.16.10.203/cgi-bin/luci/istore/system/status/" \
  -H "Cookie: sysauth=abc123..."
```

---

### 2.2 网络状态 —— `/istore/u/network/status/`

获取当前网络接口的配置与状态。

```http
GET /cgi-bin/luci/istore/u/network/status/
```

#### 请求参数

无需参数。

#### 响应字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `proto` | `string` | 网络协议，如 `"DHCP"`、`"static"`、`"pppoe"` |
| `ipv4addr` | `string` | IPv4 地址（如 `"172.16.10.203"`） |
| `ipv4mask` | `int` | 子网掩码位数（如 `24` 表示 255.255.255.0） |
| `gateway` | `string` | 默认网关地址（如 `"172.16.10.254"`） |
| `dnsList` | `string[]` | DNS 服务器列表 |
| `defaultInterface` | `string` | 默认网络接口名（如 `"br-lan"`） |
| `interface` | `string` | 备用接口名字段（功能同上） |
| `uptimeStamp` | `long` | 网络连接已持续时长（秒） |

#### 示例响应

```json
{
  "result": {
    "proto": "DHCP",
    "ipv4addr": "172.16.10.203",
    "ipv4mask": 24,
    "gateway": "172.16.10.254",
    "dnsList": ["172.16.100.88", "114.114.114.114"],
    "defaultInterface": "br-lan",
    "interface": "br-lan",
    "uptimeStamp": 29744
  },
  "code": 0
}
```

#### 使用示例

```bash
curl -s "http://172.16.10.203/cgi-bin/luci/istore/u/network/status/" \
  -H "Cookie: sysauth=abc123..."
```

---

### 2.3 系统版本 —— `/istore/u/system/version/`

获取设备硬件型号、固件版本、内核版本等信息。

```http
GET /cgi-bin/luci/istore/u/system/version/
```

#### 请求参数

无需参数。

#### 响应字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `model` | `string` | 设备型号（如 `"Acer Revo One RL85"`） |
| `hostname` | `string` | 主机名（如 `"iStoreOS"`） |
| `Hostname` | `string` | 备用主机名字段（功能同上） |
| `arch` | `string` | CPU 架构/型号（如 `"Intel(R) Core(TM) i3-5005U"`） |
| `cpuModel` | `string` | 备用架构字段 |
| `target` | `string` | 目标平台/芯片架构（如 `"x86/64"`） |
| `boardName` | `string` | 备用目标平台字段 |
| `firmwareVersion` | `string` | 固件版本字符串（如 `"iStoreOS 24.10.5 2025123110"`） |
| `version` | `string` | 备用固件版本字段 |
| `firmware` | `string` | 备用固件版本字段 |
| `kernelVersion` | `string` | 内核版本（如 `"6.18.18-trim"`） |
| `kernel` | `string` | 备用内核版本字段 |

> **注意**：不同 iStoreOS 版本中相同语义的字段可能使用不同 key 名（如上表的多字段并列）。建议实现时按优先级依次回退读取。回退顺序见各字段的列表顺序。

#### 示例响应

```json
{
  "result": {
    "model": "Acer Revo One RL85",
    "hostname": "iStoreOS",
    "arch": "Intel(R) Core(TM) i3-5005U",
    "target": "x86/64",
    "firmwareVersion": "iStoreOS 24.10.5 2025123110",
    "kernelVersion": "6.18.18-trim"
  },
  "code": 0
}
```

#### 使用示例

```bash
curl -s "http://172.16.10.203/cgi-bin/luci/istore/u/system/version/" \
  -H "Cookie: sysauth=abc123..."
```

---

### 2.4 网络统计 —— `/istore/u/network/statistics/`

获取实时网络吞吐量统计（上传/下载速度）。**此接口为可选接口**，调用失败不影响主流程。

```http
GET /cgi-bin/luci/istore/u/network/statistics/
```

#### 请求参数

无需参数。

#### 响应字段

响应的数据结构因 iStoreOS 版本不同有多种形态，通过优先级回退方式提取：

**优先级 1：`items` 数组（时间序列）**

取 `items` 数组最后一项对象，按以下字段名顺序查找：

| 上传字段 | 下载字段 | 单位 |
|----------|----------|------|
| `uploadSpeed`, `upSpeed`, `txSpeed`, `tx`, `up`, `upload`, `tx_bytes` | `downloadSpeed`, `downSpeed`, `rxSpeed`, `rx`, `down`, `download`, `rx_bytes` | bytes/s |

数组中每个元素可能还包含嵌套子对象（如以接口名为 key 的 `{"br-lan": {"rx":..., "tx":...}}`），会自动递归查找。

**优先级 2：`slots` 数组**

与 `items` 结构相同，取最后一项。

**优先级 3：`stat` 根对象直接字段**

直接在 `result` 层的顶层字段值中查找。

**优先级 4：`net`（网络状态接口）直接字段**

回退到 `/istore/u/network/status/` 返回对象中的可能速度字段。

#### 示例响应（items 格式）

```json
{
  "result": {
    "items": [
      {"timestamp": 1700000000, "br-lan": {"rx_bytes": 1024000, "tx_bytes": 512000}},
      {"timestamp": 1700000005, "br-lan": {"rx_bytes": 2048000, "tx_bytes": 768000}}
    ]
  },
  "code": 0
}
```

#### 使用示例

```bash
curl -s "http://172.16.10.203/cgi-bin/luci/istore/u/network/statistics/" \
  -H "Cookie: sysauth=abc123..."
```

#### 速度格式化

应用内速度值以 bytes/s 为单位，格式化规则：

| 阈值 | 显示格式 |
|------|----------|
| `< 1024 KB/s` | `XX.X KB/s` |
| `≥ 1024 KB/s` | `XX.X MB/s` |

---

## 3. ubus JSON-RPC 接口

OpenWrt 标准 ubus（micro-bus）接口，通过 Luci 代理访问。用于获取更底层的系统信息。

```http
POST /cgi-bin/luci/admin/ubus/
Content-Type: application/json
```

#### 请求格式（JSON-RPC 2.0）

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": [
    "<session-id>",
    "<object>",
    "<method>",
    { "<param-key>": "<param-value>" }
  ],
  "id": 1
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `params[0]` | `string` | 会话 ID，使用 `"00000000000000000000000000000000"` |
| `params[1]` | `string` | ubus 对象名（如 `"system"`） |
| `params[2]` | `string` | ubus 方法名（如 `"board"`） |
| `params[3]` | `object` | 方法参数，通常为 `{}` |
| `id` | `int` | 请求 ID，任意数值 |

#### 响应格式

```json
{
  "result": [
    <code>,
    { ... }
  ],
  "id": 1
}
```

- `result[0]`（`int`）：返回状态码，`0` 表示成功
- `result[1]`（`object`）：方法返回值，具体结构取决于调用的方法
- `id`（`int`）：与请求中的 `id` 对应

---

### 3.1 system.board —— 获取主板/系统信息

获取设备硬件底层信息，包括主机名、CPU 型号、芯片架构、主板名称等。

```http
POST /cgi-bin/luci/admin/ubus/
Content-Type: application/json
```

#### 请求体

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": [
    "00000000000000000000000000000000",
    "system",
    "board",
    {}
  ],
  "id": 1
}
```

#### 响应字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `hostname` | `string` | 设备主机名 |
| `system` | `string` | CPU 型号/系统描述（从 `/proc/cpuinfo` 提取，如 `"Intel(R) Core(TM) i3-5005U CPU @ 2.00GHz"`） |
| `release` | `object` | 固件发布信息对象 |
| `release.target` | `string` | 目标平台/芯片架构（如 `"x86/64"`、`"armvirt/64"`、`"ramips/mt7621"`） |
| `release.distribution` | `string` | 发行版名称（如 `"iStoreOS"`） |
| `release.version` | `string` | 发行版版本号 |
| `release.revision` | `string` | 发行版修订号 |
| `release.codename` | `string` | 发行版代号 |
| `board_name` | `string` | 主板名称（如 `"acer-revo-one-rl85"`） |

#### 示例响应

```json
{
  "result": [
    0,
    {
      "hostname": "iStoreOS",
      "system": "Intel(R) Core(TM) i3-5005U CPU @ 2.00GHz",
      "release": {
        "target": "x86/64",
        "distribution": "iStoreOS",
        "version": "24.10.5",
        "revision": "2025123110",
        "codename": "openwrt-24.10"
      },
      "board_name": "acer-revo-one-rl85"
    }
  ],
  "id": 1
}
```

#### 芯片架构识别规则

应用通过以下启发式规则从 `system` 字段（CPU 描述字符串）自动推断芯片架构：

| `system` 包含 | 推断结果 |
|---------------|----------|
| `x86` / `i386` / `amd64` / `intel` + `64` / `amd64` | `x86/64` |
| `x86` / `i386` / `amd64` / `intel`（不含 64） | `x86` |
| `arm` + `v8` / `aarch64` / `arm64` | `ARMv8 (64-bit)` |
| `arm` + `v7` | `ARMv7` |
| `arm` + `v6` | `ARMv6` |
| `arm` + `v5` | `ARMv5` |
| `arm`（其他） | `ARM` |
| `mips` + `64` | `MIPS64` |
| `mips` | `MIPS` |
| `riscv` / `risc-v` + `64` | `RISC-V 64` |
| `riscv` / `risc-v` | `RISC-V` |

#### 使用示例

```bash
curl -s "http://172.16.10.203/cgi-bin/luci/admin/ubus/" \
  -H "Content-Type: application/json" \
  -H "Cookie: sysauth=abc123..." \
  -d '{
    "jsonrpc":"2.0",
    "method":"call",
    "params":["00000000000000000000000000000000","system","board",{}],
    "id":1
  }'
```

---

## 4. 附录

### 4.1 请求/响应字符编码

- **请求体**和**响应体**统一使用 **UTF-8** 编码
- 请求头 `Content-Type` 中应显式声明 `charset=utf-8`
- 登录接口使用 `application/x-www-form-urlencoded; charset=utf-8`
- ubus 接口使用 `application/json`（JSON 默认 UTF-8）

### 4.2 错误处理

| 场景 | HTTP 状态码 | 处理策略 |
|------|------------|---------|
| 未登录/Cookie 过期 | `403` 或返回空结果 | 重新调用登录接口获取新 Cookie |
| 网络超时 | 连接超时 / 读取超时 | 重试；连续失败记录 WARN 日志 |
| 接口返回空 | `200` 但 `result` 为 `null` | 优雅降级，跳过该数据项 |
| ubus 调用失败 | `result[0] != 0` 或网络异常 | 回退使用 iStore REST API 的同语义字段 |

**超时建议**：连接超时 5 秒，读取超时 10 秒。

### 4.3 速率限制

iStoreOS Luci 后台未定义显式速率限制。但建议遵循：

- **采集间隔**：≥ 5 秒
- **并发请求**：单线程顺序调用（当前实现采用单线程 `ScheduledExecutor`）
- 避免在 1 秒内对同一端点发起超过 1 次请求，防止路由器 CPU 过载

---

## 快速集成

以下是一个最小化的集成示例（Java），演示登录 + 调用 API：

```java
// 1. 登录
String form = "luci_username=" + URLEncoder.encode("root", "UTF-8")
        + "&luci_password=" + URLEncoder.encode("password", "UTF-8");
HttpURLConnection conn = (HttpURLConnection)
    new URL("http://172.16.10.203/cgi-bin/luci/").openConnection();
conn.setRequestMethod("POST");
conn.setDoOutput(true);
conn.setInstanceFollowRedirects(false);
conn.setRequestProperty("Content-Type",
    "application/x-www-form-urlencoded; charset=utf-8");
// 发送表单...
String cookie = conn.getHeaderField("Set-Cookie");

// 2. 调用 API（以系统状态为例）
HttpURLConnection api = (HttpURLConnection)
    new URL("http://172.16.10.203/cgi-bin/luci/istore/system/status/").openConnection();
api.setRequestProperty("Cookie", cookie);
// 读取响应...
```

---

**文档版本**：1.0  
**适用 iStoreOS 版本**：24.x（含 24.10.x）  
**最后更新**：2026-05-21
