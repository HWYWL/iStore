/**
 * PageHost — 功能页组件注册表
 *
 * 分栏（>= 600vp）时，功能页不再走路由跳转，而是由 PageHost 按 URL 直接实例化，
 * 挂载到 MainPage 中栏（双栏）或右栏（三栏）的 NavDestination 内。
 *
 * 新增可嵌入页面时：
 *   1. 页面声明改为 `@Component export struct XxxPage`
 *   2. 在此处补一个 if 分支
 *   3. 在 AppNav 的 PAGE_TITLES / EMBEDDABLE 中登记
 */
import { AppState } from '../store/AppState'
import { LIGHT_THEME, ThemePalette } from '../theme/ThemeColors'
import { AppNav } from '../utils/AppNav'
// 应用 / 功能页
import { AchievementPage } from '../../pages/apps/AchievementPage'
import { AlbumPage } from '../../pages/apps/AlbumPage'
import { ConntrackRankPage } from '../../pages/apps/ConntrackRankPage'
import { DeviceActivityPage } from '../../pages/apps/DeviceActivityPage'
import { DeviceAliasPage } from '../../pages/apps/DeviceAliasPage'
import { DeviceManagePage } from '../../pages/apps/DeviceManagePage'
import { DiaryPage } from '../../pages/apps/DiaryPage'
import { DnsBattlePage } from '../../pages/apps/DnsBattlePage'
import { DockerPage } from '../../pages/apps/DockerPage'
import { EthPortPage } from '../../pages/apps/EthPortPage'
import { FileManagerPage } from '../../pages/apps/FileManagerPage'
import { FortunePage } from '../../pages/apps/FortunePage'
import { JellyfinPage } from '../../pages/apps/JellyfinPage'
import { MileStonePage } from '../../pages/apps/MileStonePage'
import { NetEcgPage } from '../../pages/apps/NetEcgPage'
import { NetworkCheckPage } from '../../pages/apps/NetworkCheckPage'
import { NetworkHelperPage } from '../../pages/apps/NetworkHelperPage'
import { NetworkPage } from '../../pages/apps/NetworkPage'
import { NetworkReportPage } from '../../pages/apps/NetworkReportPage'
import { NotifySettingsPage } from '../../pages/apps/NotifySettingsPage'
import { OafPage } from '../../pages/apps/OafPage'
import { PortTrafficPage } from '../../pages/apps/PortTrafficPage'
import { RouterLevelPage } from '../../pages/apps/RouterLevelPage'
import { RouterMoodPage } from '../../pages/apps/RouterMoodPage'
import { SchedulePage } from '../../pages/apps/SchedulePage'
import { ShareCardPage } from '../../pages/apps/ShareCardPage'
import { SkinManagePage } from '../../pages/apps/SkinManagePage'
import { SmartHubPage } from '../../pages/apps/SmartHubPage'
import { SpeedTestPage } from '../../pages/apps/SpeedTestPage'
import { SshTerminalPage } from '../../pages/apps/SshTerminalPage'
import { StorePage } from '../../pages/apps/StorePage'
import { TopologyPage } from '../../pages/apps/TopologyPage'
import { TrafficBillPage } from '../../pages/apps/TrafficBillPage'
import { TrafficRankPage } from '../../pages/apps/TrafficRankPage'
import { TrafficReportPage } from '../../pages/apps/TrafficReportPage'
import { WidgetSettingsPage } from '../../pages/apps/WidgetSettingsPage'
import { WifiCardPage } from '../../pages/apps/WifiCardPage'
import { WifiPage } from '../../pages/apps/WifiPage'
import { WolPage } from '../../pages/apps/WolPage'
// 其他目录
import { PetPage } from '../../pages/pet/PetPage'
import { ProcessListPage } from '../../pages/process/ProcessListPage'
import { StartupPage } from '../../pages/process/StartupPage'
import { SecurityHubPage } from '../../pages/security/SecurityHubPage'
import { ConfigBackupPage } from '../../pages/system/ConfigBackupPage'
import { FactoryResetPage } from '../../pages/system/FactoryResetPage'
import { NetworkRestartPage } from '../../pages/system/NetworkRestartPage'
import { PackageManagerPage } from '../../pages/system/PackageManagerPage'
import { RebootPage } from '../../pages/system/RebootPage'
import { SystemLogPage } from '../../pages/system/SystemLogPage'
import { AboutPage } from '../../pages/other/AboutPage'

@Component
export struct PageHost {
  /** 页面路径（与 main_pages.json / AppNav 保持一致） */
  @Prop url: string = ''
  @State theme: ThemePalette = LIGHT_THEME

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
  }

  build() {
    Column() {
      if (this.url === 'pages/apps/AchievementPage') {
        AchievementPage()
      } else if (this.url === 'pages/apps/AlbumPage') {
        AlbumPage()
      } else if (this.url === 'pages/apps/ConntrackRankPage') {
        ConntrackRankPage()
      } else if (this.url === 'pages/apps/DeviceActivityPage') {
        DeviceActivityPage()
      } else if (this.url === 'pages/apps/DeviceAliasPage') {
        DeviceAliasPage()
      } else if (this.url === 'pages/apps/DeviceManagePage') {
        DeviceManagePage()
      } else if (this.url === 'pages/apps/DiaryPage') {
        DiaryPage()
      } else if (this.url === 'pages/apps/DnsBattlePage') {
        DnsBattlePage()
      } else if (this.url === 'pages/apps/DockerPage') {
        DockerPage()
      } else if (this.url === 'pages/apps/EthPortPage') {
        EthPortPage()
      } else if (this.url === 'pages/apps/FileManagerPage') {
        FileManagerPage()
      } else if (this.url === 'pages/apps/FortunePage') {
        FortunePage()
      } else if (this.url === 'pages/apps/JellyfinPage') {
        JellyfinPage()
      } else if (this.url === 'pages/apps/MileStonePage') {
        MileStonePage()
      } else if (this.url === 'pages/apps/NetEcgPage') {
        NetEcgPage()
      } else if (this.url === 'pages/apps/NetworkCheckPage') {
        NetworkCheckPage()
      } else if (this.url === 'pages/apps/NetworkHelperPage') {
        NetworkHelperPage()
      } else if (this.url === 'pages/apps/NetworkPage') {
        NetworkPage()
      } else if (this.url === 'pages/apps/NetworkReportPage') {
        NetworkReportPage()
      } else if (this.url === 'pages/apps/NotifySettingsPage') {
        NotifySettingsPage()
      } else if (this.url === 'pages/apps/OafPage') {
        OafPage()
      } else if (this.url === 'pages/apps/PortTrafficPage') {
        PortTrafficPage()
      } else if (this.url === 'pages/apps/RouterLevelPage') {
        RouterLevelPage()
      } else if (this.url === 'pages/apps/RouterMoodPage') {
        RouterMoodPage()
      } else if (this.url === 'pages/apps/SchedulePage') {
        SchedulePage()
      } else if (this.url === 'pages/apps/ShareCardPage') {
        ShareCardPage()
      } else if (this.url === 'pages/apps/SkinManagePage') {
        SkinManagePage()
      } else if (this.url === 'pages/apps/SmartHubPage') {
        SmartHubPage()
      } else if (this.url === 'pages/apps/SpeedTestPage') {
        SpeedTestPage()
      } else if (this.url === 'pages/apps/SshTerminalPage') {
        SshTerminalPage()
      } else if (this.url === 'pages/apps/StorePage') {
        StorePage()
      } else if (this.url === 'pages/apps/TopologyPage') {
        TopologyPage()
      } else if (this.url === 'pages/apps/TrafficBillPage') {
        TrafficBillPage()
      } else if (this.url === 'pages/apps/TrafficRankPage') {
        TrafficRankPage()
      } else if (this.url === 'pages/apps/TrafficReportPage') {
        TrafficReportPage()
      } else if (this.url === 'pages/apps/WidgetSettingsPage') {
        WidgetSettingsPage()
      } else if (this.url === 'pages/apps/WifiCardPage') {
        WifiCardPage()
      } else if (this.url === 'pages/apps/WifiPage') {
        WifiPage()
      } else if (this.url === 'pages/apps/WolPage') {
        WolPage()
      } else if (this.url === 'pages/pet/PetPage') {
        PetPage()
      } else if (this.url === 'pages/process/ProcessListPage') {
        ProcessListPage()
      } else if (this.url === 'pages/process/StartupPage') {
        StartupPage()
      } else if (this.url === 'pages/security/SecurityHubPage') {
        SecurityHubPage()
      } else if (this.url === 'pages/system/ConfigBackupPage') {
        ConfigBackupPage()
      } else if (this.url === 'pages/system/FactoryResetPage') {
        FactoryResetPage()
      } else if (this.url === 'pages/system/NetworkRestartPage') {
        NetworkRestartPage()
      } else if (this.url === 'pages/system/PackageManagerPage') {
        PackageManagerPage()
      } else if (this.url === 'pages/system/RebootPage') {
        RebootPage()
      } else if (this.url === 'pages/system/SystemLogPage') {
        SystemLogPage()
      } else if (this.url === 'pages/other/AboutPage') {
        AboutPage()
      } else {
        this.FallbackView()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 未登记页面的兜底：提示改为全屏打开 */
  @Builder
  FallbackView() {
    Column() {
      Text('该页面暂不支持在侧栏内展示')
        .fontSize(14)
        .fontColor(this.theme.textSecondary)
        .margin({ bottom: 16 })
      Button('全屏打开')
        .fontSize(14)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.theme.primary)
        .fontColor(Color.White)
        .onClick(() => {
          AppNav.getInstance().openFullscreen(this.url)
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
