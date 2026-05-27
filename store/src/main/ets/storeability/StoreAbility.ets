import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
/**
 * 应用主 Ability
 * 应用入口，设置窗口模式为未指定（跟随系统），管理应用生命周期
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

const DOMAIN = 0x0000

export default class StoreAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'StoreAbility', 'Failed to set colorMode: %{public}s', JSON.stringify(err))
    }
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
    } catch (err) {
      hilog.error(0xFF00, 'iStore', 'Failed to get main window: %{public}s', String(err))
      return
    }
    mainWindow.setWindowLayoutFullScreen(true).then(() => {
      hilog.info(DOMAIN, 'StoreAbility', 'Succeeded in setting full-screen layout')
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'StoreAbility', 'Failed to set full-screen layout: %{public}s', JSON.stringify(err))
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
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'StoreAbility', 'Ability onBackground')
  }
}
