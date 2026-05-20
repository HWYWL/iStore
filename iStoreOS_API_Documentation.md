# iStoreOS (OpenWrt LuCI) 系统信息 API 文档

> **设备**: Acer Revo One RL85 (iStoreOS 24.10.5)
> **地址**: http://172.16.10.202
> **采集时间**: 2026-05-18 18:54 CST

---

## 一、认证接口

### 1.1 登录获取 Token

```
POST /cgi-bin/luci/rpc/auth
Content-Type: application/json

{
  "id": 1,
  "method": "login",
  "params": ["root", "<password>"]
}
```

**响应示例**:
```json
{
  "id": 1,
  "result": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "error": null
}
```

返回的 `result` 即为 `auth_token`，后续所有 API 调用需携带此 token。

---

## 二、系统信息获取接口

OpenWrt LuCI 通过 `ubus` (OpenWrt micro bus) 提供系统级信息。所有系统信息通过以下 RPC 端点获取：

```
POST /cgi-bin/luci/rpc/ubus?auth=<auth_token>
Content-Type: application/json
```

### 2.1 获取完整系统信息 (Board Info)

```json
{
  "id": 1,
  "method": "call",
  "params": ["system", "board", {}]
}
```

**响应示例** (对应 `/admin/status/overview` 页面):
```json
{
  "id": 1,
  "result": [
    {
      "kernel": "6.18.18-trim",
      "hostname": "iStoreOS",
      "system": "Acer Revo One RL85",
      "model": "Intel(R) Core(TM) i3-5005U CPU @ 2.00GHz",
      "board_name": "x86/64",
      "release": {
        "distribution": "iStoreOS",
        "version": "24.10.5",
        "revision": "2025123110",
        "target": "x86/64",
        "description": "iStoreOS 24.10.5 2025123110"
      }
    }
  ],
  "error": null
}
```

### 2.2 获取系统运行时信息

```json
{
  "id": 2,
  "method": "call",
  "params": ["system", "info", {}]
}
```

**响应示例**:
```json
{
  "id": 2,
  "result": [
    {
      "uptime": 518400,
      "localtime": 1747568980,
      "load": [51, 47, 50],
      "memory": {
        "total": 8201842688,
        "free": 4841664512,
        "shared": 3812608000,
        "buffered": 51650560
      },
      "swap": {
        "total": 4294967296,
        "free": 3886080000
      }
    }
  ],
  "error": null
}
```

### 2.3 获取网络接口信息

```json
{
  "id": 3,
  "method": "call",
  "params": ["network.interface.lan", "status", {}]
}
```

**响应示例**:
```json
{
  "id": 3,
  "result": [
    {
      "l3_device": "br-lan",
      "proto": "dhcp",
      "ipv4_address": [
        {
          "address": "172.16.10.202",
          "mask": 24
        }
      ],
      "ipv4_gateway": "172.16.10.254",
      "dns_server": ["172.16.100.88", "114.114.114.114"],
      "device": "br-lan",
      "uptime": 29722
    }
  ],
  "error": null
}
```

### 2.4 获取 DHCP 租约配置

```json
{
  "id": 4,
  "method": "call",
  "params": ["uci", "get", {"config": "network"}]
}
```

---

## 三、完整数据采集结果

### 3.1 基本信息

| 字段 | 值 | 来源接口 |
|------|-----|---------|
| **主机名 (Hostname)** | iStoreOS | `system.board` / `/proc/sys/kernel/hostname` |
| **型号 (Model)** | Acer Revo One RL85 | `system.board` |
| **架构 (Architecture)** | Intel(R) Core(TM) i3-5005U CPU @ 2.00GHz | `system.board` |
| **目标平台 (Target)** | x86/64 | `system.board` |
| **固件版本 (Firmware)** | iStoreOS 24.10.5 2025123110 | `system.board` |
| **LuCI 版本** | openwrt-24.10 branch 25.363.17521~c944960 | `system.board` |
| **内核版本 (Kernel)** | 6.18.18-trim | `system.board` |

### 3.2 运行状态

| 字段 | 值 | 来源接口 |
|------|-----|---------|
| **运行时间 (Uptime)** | 6天 0小时 27分 31秒 | `system.info` → `uptime` (秒) |
| **系统时间 (Local Time)** | 2026-05-18 18:54:44 CST | `system.info` → `localtime` (Unix时间戳) |
| **平均负载 (Load)** | 1min: 0.51, 5min: 0.47, 15min: 0.50 | `system.info` → `load[]` (乘以100) |
| **CPU 使用率** | ~3-8%（实时浮动） | Dashboard 前端 JS 计算 |
| **CPU 温度** | ~50-51℃ | `/sys/class/thermal/thermal_zone0/temp` |

### 3.3 内存信息

| 字段 | 值 | 来源 |
|------|-----|------|
| **总内存 (Total)** | 7.63 GiB | `system.info` → `memory.total` |
| **可用内存 (Available)** | 4.50 GiB (58%) | `system.info` → `memory.free` + `buffered` + part of `shared` |
| **已使用 (Used)** | 6.41 GiB (83%) | 含缓存/缓冲 |
| **缓冲 (Buffered)** | 49.27 MiB | `system.info` → `memory.buffered` |
| **缓存 (Cached)** | 3.40 GiB | `system.info` → `memory.shared` |
| **实际内存使用率** | ~41% | 排除缓存/缓冲后的实际使用 |
| **交换区 (Swap)** | 空闲 3.62 GiB / 总计 4.00 GiB (90%) | `system.info` → `swap` |

### 3.4 存储信息

| 字段 | 值 |
|------|-----|
| **磁盘空间** | 21.25 GiB / 159.44 GiB (13%) |
| **临时空间 (/tmp)** | 2.28 MiB / 3.82 GiB (0%) |
| **/dev/shm** | 148.00 KiB / 64.00 MiB (0%) |

### 3.5 网络信息

| 字段 | 值 | 来源 |
|------|-----|------|
| **网络协议 (Protocol)** | DHCP 客户端 | `network.interface.lan.status` → `proto` |
| **IPv4 地址** | 172.16.10.202/24 | `network.interface.lan.status` → `ipv4_address` |
| **网关 (Gateway)** | 172.16.10.254 | `network.interface.lan.status` → `ipv4_gateway` |
| **DNS 1** | 172.16.100.88 | `network.interface.lan.status` → `dns_server` |
| **DNS 2** | 114.114.114.114 | `network.interface.lan.status` → `dns_server` |
| **网络设备** | br-lan (桥接) | `network.interface.lan.status` → `device` / `l3_device` |
| **MAC 地址** | 3E:CA:C9:84:7D:14 | `network.interface.lan.status` → `macaddr` |
| **IPv6** | 未启用 | - |
| **连接状态** | 已连接 (8小时15分44秒) | `network.interface.lan.status` → `uptime` |
| **DHCP 租约剩余** | 9天 15小时 44分 | 前端计算 |
| **活动连接数** | 121 / 262144 (0%) | `net.netfilter.nf_conntrack_max` |

### 3.6 实时网络流量

#### br-lan (LAN 桥接接口)
| 指标 | 入站 (Inbound/Download) | 出站 (Outbound/Upload) |
|------|------------------------|------------------------|
| **当前速度** | 11.33 Kibit/s (1.42 KiB/s) | 1.27 Kibit/s (162 B/s) |
| **平均速度** | 11.12 Kibit/s (1.39 KiB/s) | 3.12 Kibit/s (399 B/s) |
| **峰值速度** | 26.15 Kibit/s (3.27 KiB/s) | 8.16 Kibit/s (1.02 KiB/s) |

#### eth0 (物理网口)
| 指标 | 入站 (Inbound/Download) | 出站 (Outbound/Upload) |
|------|------------------------|------------------------|
| **当前速度** | 129.57 Kibit/s (16.20 KiB/s) | 2.99 Mibit/s (382.65 KiB/s) |
| **平均速度** | 18.93 Kibit/s (2.37 KiB/s) | 164.07 Kibit/s (20.51 KiB/s) |
| **峰值速度** | 129.57 Kibit/s (16.20 KiB/s) | 2.99 Mibit/s (382.65 KiB/s) |
| **累计接收** | 54.66 MiB | - |
| **累计发送** | - | 50.31 MiB |

> **注**: 速度数据来源于 `/cgi-bin/luci/admin/status/realtime/bandwidth` 页面的实时图表，前端通过轮询 `/cgi-bin/luci/rpc/ubus` 获取 `luci-rpc.getRealtimeStats` 数据。

---

## 四、响应字段映射表（API ↔ 前端显示）

| 前端显示 | API 字段路径 | 类型 | 备注 |
|---------|-------------|------|------|
| 主机名 | `system.board[0].hostname` | string | |
| 型号 | `system.board[0].system` | string | 或 `model` |
| 架构 | `system.board[0].model` | string | CPU 型号字符串 |
| 目标平台 | `system.board[0].board_name` | string | |
| 固件版本 | `system.board[0].release.description` | string | |
| 内核版本 | `system.board[0].kernel` | string | |
| 本地时间 | `system.info[0].localtime` | unix timestamp | 需转换 |
| 运行时间 | `system.info[0].uptime` | int (seconds) | 需格式化 |
| 平均负载 | `system.info[0].load[]` | int[3] | 值/100 得实际负载 |
| 总内存 | `system.info[0].memory.total` | int (bytes) | |
| 可用内存 | `system.info[0].memory.free` | int (bytes) | |
| 缓冲内存 | `system.info[0].memory.buffered` | int (bytes) | |
| 交换区总量 | `system.info[0].swap.total` | int (bytes) | |
| 交换区空闲 | `system.info[0].swap.free` | int (bytes) | |
| 网络协议 | `network.interface.lan.status[0].proto` | string | "dhcp"/"static"等 |
| IPv4 地址 | `network.interface.lan.status[0].ipv4_address[0].address` | string | |
| 子网掩码 | `network.interface.lan.status[0].ipv4_address[0].mask` | int | |
| 网关 | `network.interface.lan.status[0].ipv4_gateway` | string | |
| DNS | `network.interface.lan.status[0].dns_server[]` | string[] | |
| 网络设备 | `network.interface.lan.status[0].device` | string | |
| CPU 温度 | 非标准 ubus，读 `/sys/class/thermal/thermal_zone0/temp` | int | 值/1000 得℃ |

---

## 五、Python 采集示例代码

```python
#!/usr/bin/env python3
"""iStoreOS 系统信息采集脚本"""

import requests
import time
import json

BASE_URL = "http://172.16.10.202/cgi-bin/luci"
USERNAME = "root"
PASSWORD = "123456yi"

class StoreOSClient:
    def __init__(self):
        self.session = requests.Session()
        self.auth_token = None

    def login(self):
        """获取认证 token"""
        resp = self.session.post(
            f"{BASE_URL}/rpc/auth",
            json={
                "id": 1,
                "method": "login",
                "params": [USERNAME, PASSWORD]
            }
        )
        data = resp.json()
        if data.get("error"):
            raise Exception(f"Login failed: {data['error']}")
        self.auth_token = data["result"]
        return self.auth_token

    def ubus_call(self, namespace, method, params=None):
        """通用 ubus RPC 调用"""
        if not self.auth_token:
            self.login()
        resp = self.session.post(
            f"{BASE_URL}/rpc/ubus?auth={self.auth_token}",
            json={
                "id": int(time.time()),
                "method": "call",
                "params": [namespace, method, params or {}]
            }
        )
        data = resp.json()
        if data.get("error"):
            raise Exception(f"ubus error: {data['error']}")
        return data["result"]

    def get_system_info(self):
        """获取完整系统信息"""
        board = self.ubus_call("system", "board")[0]
        info = self.ubus_call("system", "info")[0]
        lan = self.ubus_call("network.interface.lan", "status")[0]

        # 计算内存实际使用率（排除缓存/缓冲）
        total = info["memory"]["total"]
        free = info["memory"]["free"]
        buffered = info["memory"]["buffered"]
        shared = info["memory"].get("shared", 0)
        available = free + buffered + shared
        used_real = total - available

        return {
            "hostname": board["hostname"],
            "model": board["system"],
            "architecture": board["model"],
            "target_platform": board["board_name"],
            "firmware_version": board["release"]["description"],
            "kernel_version": board["kernel"],
            "local_time": time.strftime(
                "%Y-%m-%d %H:%M:%S",
                time.localtime(info["localtime"])
            ),
            "uptime_seconds": info["uptime"],
            "uptime_human": f"{info['uptime'] // 86400}d "
                           f"{(info['uptime'] % 86400) // 3600}h "
                           f"{(info['uptime'] % 3600) // 60}m "
                           f"{info['uptime'] % 60}s",
            "load_average": {
                "1min": info["load"][0] / 100,
                "5min": info["load"][1] / 100,
                "15min": info["load"][2] / 100
            },
            "memory": {
                "total_gb": round(total / 1024**3, 2),
                "free_gb": round(free / 1024**3, 2),
                "available_gb": round(available / 1024**3, 2),
                "buffered_gb": round(buffered / 1024**3, 2),
                "usage_percent": round(used_real / total * 100, 1)
            },
            "swap": {
                "total_gb": round(info["swap"]["total"] / 1024**3, 2),
                "free_gb": round(info["swap"]["free"] / 1024**3, 2)
            },
            "network": {
                "protocol": lan.get("proto", "N/A"),
                "ipv4": f"{lan['ipv4_address'][0]['address']}/{lan['ipv4_address'][0]['mask']}",
                "gateway": lan.get("ipv4_gateway", "N/A"),
                "dns": lan.get("dns_server", []),
                "device": lan.get("device", lan.get("l3_device", "N/A")),
                "mac": lan.get("macaddr", "N/A"),
                "connected_seconds": lan.get("uptime", 0)
            }
        }


if __name__ == "__main__":
    client = StoreOSClient()
    info = client.get_system_info()
    print(json.dumps(info, indent=2, ensure_ascii=False))
```

---

## 六、端点速查表

| 端点 | 方法 | 说明 |
|------|------|------|
| `/cgi-bin/luci/rpc/auth` | POST | 用户认证，返回 token |
| `/cgi-bin/luci/rpc/ubus?auth=<token>` | POST | 通用 ubus RPC 调用入口 |
| `/cgi-bin/luci/admin/status/overview` | GET | 状态概览 HTML 页面 |
| `/cgi-bin/luci/admin/status/realtime/bandwidth` | GET | 实时带宽页面 |
| `/cgi-bin/luci/admin/status/realtime/load` | GET | 实时负载页面 |

### 常用 ubus 方法

| namespace.method | 返回内容 |
|-----------------|---------|
| `system.board` | 主机名/型号/固件/内核 |
| `system.info` | 运行时间/内存/负载/时间 |
| `network.interface.lan.status` | LAN 接口 IP/网关/DNS |
| `network.interface.wan.status` | WAN 接口状态 |
| `network.interface.wan6.status` | WAN6 接口状态 |
| `network.device.status` | 网络设备列表及状态 |
| `luci-rpc.getRealtimeStats` | 实时带宽/流量数据 |
| `file.read` | 读取系统文件（如 `/proc/loadavg`） |

---

## 七、注意事项

1. **Token 有效期**: LuCI session token 有超时机制，长时间不活动需重新登录
2. **负载值**: `system.info` 返回的 `load[]` 数组需要除以 100 得到实际负载值
3. **内存使用率**: 总使用率含缓存/缓冲，实际使用率需减去缓冲和缓存
4. **CPU 温度**: 不是标准 ubus 接口，需读取 `/sys/class/thermal/thermal_zone0/temp`（值/1000）
5. **CPU 使用率**: 前端通过 `/proc/stat` 差值计算，非 ubus 直接获取
6. **实时速度**: 通过 `luci-rpc.getRealtimeStats` 轮询获取（每3秒刷新）
7. **CSRF**: 所有 POST 请求需要携带 `sysauth` cookie
