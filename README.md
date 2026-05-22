# iStore

iStore 是一款基于 **HarmonyOS 6.1.0** 开发的路由器管理应用，支持管理 **iStoreOS** 和 **QWRT(开发中) **路由器设备。

## 功能特性

### 界面预览

| 系统监控                          | 磁盘管理                     |
| :---------------------------- | :----------------------- |
| ![系统监控](images/dashboard.jpg) | ![磁盘管理](images/disk.jpg) |

| 网络管理                        | 应用中心                     |
| :-------------------------- | :----------------------- |
| ![网络管理](images/network.jpg) | ![应用中心](images/apps.jpg) |

### 系统监控

- CPU 使用率实时监控
- 内存使用状态
- CPU 温度监控
- 系统信息展示（主机名、内核版本、固件版本等）
- 磁盘挂载点使用情况
- 连接追踪状态

### 设备管理

- DHCP 客户端列表（支持搜索）
- 无线客户端列表（信号强度、速率）
- 设备详情查看

### 网络管理

- LAN/WAN 接口状态
- 网络接口列表（类型识别）
- 流量统计图表

### 家长控制

- 应用过滤开关
- 应用分类管理
- 时间限制设置
- 用户白名单管理

### 系统管理

- 进程列表（CPU/内存排序）
- 路由表查看
- 启动项管理
- 重启/恢复出厂设置

## 技术架构

### 目录结构

```
store/src/main/ets/
├── api/                    # API通信层
│   ├── ApiClient.ets       # 底层HTTP/UBUS客户端
│   └── ApiService.ets      # 业务API封装
├── common/                 # 公共模块
│   ├── components/         # 可复用组件
│   ├── constants/          # 常量定义
│   ├── store/              # 状态管理
│   ├── theme/              # 主题系统
│   └── utils/              # 工具函数
├── models/                 # 数据模型
│   └── Models.ets          # 接口类型定义
├── pages/                  # 页面
│   ├── apps/               # 应用管理
│   ├── dashboard/          # 仪表盘
│   ├── devices/            # 设备详情
│   ├── entry/              # 入口页面
│   ├── network/            # 网络管理
│   ├── other/              # 关于、帮助
│   ├── parental/           # 家长控制
│   ├── process/            # 进程管理
│   └── system/             # 系统设置
└── storeability/           # Ability入口
    └── StoreAbility.ets    # 主Ability
```

### 核心模块

| 模块         | 文件                                                                                        | 功能                            |
| ---------- | ----------------------------------------------------------------------------------------- | ----------------------------- |
| **API客户端** | [ApiClient.ets](file:///e:/code/iStore/store/src/main/ets/api/ApiClient.ets)              | 底层HTTP/UBUS通信，支持iStoreOS和QWRT |
| **API服务**  | [ApiService.ets](file:///e:/code/iStore/store/src/main/ets/api/ApiService.ets)            | 业务API封装，数据转换                  |
| **状态管理**   | [AppState.ets](file:///e:/code/iStore/store/src/main/ets/common/store/AppState.ets)       | 全局状态管理（单例）                    |
| **主题系统**   | [ThemeColors.ets](file:///e:/code/iStore/store/src/main/ets/common/theme/ThemeColors.ets) | 深色/浅色主题配置                     |
| **数据模型**   | [Models.ets](file:///e:/code/iStore/store/src/main/ets/models/Models.ets)                 | 所有接口类型定义                      |

### 网络通信

应用支持与多种路由器固件通信：

1. **iStoreOS** - 使用专有 API `/cgi-bin/luci/istore/...`
2. **QWRT/OpenWrt** - 使用标准 LuCI API `/cgi-bin/luci/?status=1`
3. **UBUS RPC** - OpenWRT 统一总线协议（降级方案）

## 支持的设备

- **iStoreOS** - 完全支持
- **QWRT** - 支持（自动检测并使用兼容API）
- **OpenWrt** - 支持（通过UBUS降级）

## 开发环境

### 要求

- **DevEco Studio**: 4.1 或更高版本
- **HarmonyOS SDK**: 6.1.0
- **Node.js**: 18.19.0 或更高版本

### 构建命令

```bash
# 编译 release 版本
hvigorw assembleHap --mode=release

# 编译 debug 版本
hvigorw assembleHap --mode=debug

# 清理构建
hvigorw clean
```

### 运行项目

1. 打开 DevEco Studio
2. 导入项目：`File → Open → 选择项目目录`
3. 配置签名证书：`File → Project Structure → Signing Configs`
4. 运行：`Run → Run 'entry'` 或快捷键 `Shift+F10`

## 页面清单

| 模块   | 页面                  | 路径                                       |
| ---- | ------------------- | ---------------------------------------- |
| 入口   | LoginPage           | `pages/entry/LoginPage.ets`              |
| 仪表盘  | MainPage            | `pages/dashboard/MainPage.ets`           |
| 设备   | ClientDetailPage    | `pages/devices/ClientDetailPage.ets`     |
| 应用   | AppsPage            | `pages/apps/AppsPage.ets`                |
| 网络   | RouteTablePage      | `pages/network/RouteTablePage.ets`       |
| 家长控制 | ParentalControlPage | `pages/parental/ParentalControlPage.ets` |
| 进程   | ProcessListPage     | `pages/process/ProcessListPage.ets`      |
| 系统   | RebootPage          | `pages/system/RebootPage.ets`            |

## 状态管理

应用使用单例模式管理全局状态：

- **AppState**: 管理设备列表、连接状态、主题切换
- **DeviceStore**: 封装设备持久化逻辑（使用 preferences 存储）

## 主题系统

- 支持深色/浅色双主题
- 主题切换自动刷新所有监听组件
- 主题偏好持久化到 preferences

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
