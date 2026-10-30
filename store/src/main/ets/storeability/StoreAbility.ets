import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
/**
 * 应用主 Ability
 * 应用入口，设置窗口模式为未指定（跟随系统），管理应用生命周期
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { TrafficStatStore } from '../common/store/TrafficStatStore'
import { FunStore } from '../common/store/FunStore'
import { DiaryStore } from '../common/store/DiaryStore'
import { applyRotationBySystemLock } from '../common/utils/WindowUtils'

const DOMAIN = 0x0000

export default class StoreAbility extends UIAbility {
  // 主窗口引用：回到前台时按系统旋转锁状态重新套用方向
  private mainWindow: window.Window | null = null

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'StoreAbility', 'Failed to set colorMode: %{public}s', JSON.stringify(err))
    }
    // 统一初始化本地持久化存储：页面内 getUIContext().getHostContext() 可能拿不到上下文，
    // 一旦初始化失败，流量统计 / 设备作息 / 日记等会一直是空数据
    TrafficStatStore.getInstance().init(this.context).catch((e: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'TrafficStatStore init failed: %{public}s', JSON.stringify(e))
    })
    FunStore.getInstance().init(this.context).catch((e: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'FunStore init failed: %{public}s', JSON.stringify(e))
    })
    DiaryStore.getInstance().init(this.context).catch((e: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'DiaryStore init failed: %{public}s', JSON.stringify(e))
    })
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onCreate')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onWindowStageCreate')
    // 获取主窗口并设置全屏布局，消除状态栏和导航栏的白色边框
    let mainWindow: window.Window
    try {
      mainWindow = windowStage.getMainWindowSync()
      this.mainWindow = mainWindow
    } catch (err) {
      hilog.error(0xFF00, 'iStore', 'Failed to get main window: %{public}s', String(err))
      return
    }
    mainWindow.setWindowLayoutFullScreen(true).then(() => {
      hilog.info(DOMAIN, 'StoreAbility', 'Succeeded in setting full-screen layout')
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'Failed to set full-screen layout: %{public}s', JSON.stringify(err))
    })

    // 沉浸式：状态栏/导航栏透明，图标默认白色（App 默认深色主题）；2in1 不支持该系统栏属性
    if (deviceInfo.deviceType !== '2in1') {
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'StoreAbility', 'Failed to set system bar transparent: %{public}s', JSON.stringify(err))
      })
    }

    // 方向：跟随传感器但受系统「旋转锁定」开关管控（AUTO_ROTATION_RESTRICTED）
    applyRotationBySystemLock(this.context, mainWindow).catch((e: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'applyRotationBySystemLock failed: %{public}s', JSON.stringify(e))
    })

    windowStage.loadContent('pages/entry/LoginPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'StoreAbility', 'Failed to load content: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'StoreAbility', 'Succeeded in loading content')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onWindowStageDestroy')
    this.mainWindow = null
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onForeground')
    // 回前台重新声明一次方向策略，避免异常场景下方向模式被重置
    if (this.mainWindow !== null) {
      applyRotationBySystemLock(this.context, this.mainWindow).catch((e: BusinessError) => {
        hilog.error(DOMAIN, 'StoreAbility', 'foreground rotation sync failed: %{public}s', JSON.stringify(e))
      })
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onBackground')
  }
}
