import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

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
    windowStage.loadContent('pages/LoginPage', (err) => {
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
