/**
 * EntryFormAbility - 桌面小组件扩展
 * 负责卡片的创建、更新与删除；数据来自 App 写入的 Preferences（WidgetDataStore）
 */
import { formBindingData, formInfo, FormExtensionAbility, formProvider } from '@kit.FormKit'
import { Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { WidgetDataStore } from '../common/store/WidgetDataStore'

const DOMAIN = 0x0001
const TAG = 'EntryFormAbility'

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm')
    try {
      // 从 want.parameters 读取卡片尺寸（2*2 / 2*4），兼容两种 key 并归一化
      let dimension: string = '2*2'
      const params = want.parameters as Record<string, Object>
      if (params && params['dimension']) {
        dimension = String(params['dimension'])
      } else if (params && params['ohos.extra.param.key.form_dimension']) {
        dimension = String(params['ohos.extra.param.key.form_dimension'])
      }
      dimension = dimension.replace(/"/g, '').replace(/x/gi, '*').trim()
      if (dimension !== '2*4') {
        dimension = '2*2'
      }
      // 缓存尺寸：onUpdateForm 推送数据时带上，避免被覆盖回默认
      WidgetDataStore.saveDimension(dimension)
      const snap = WidgetDataStore.loadWithContextSync(this.context)
      return formBindingData.createFormBindingData({
        rxRate: snap.rxRate,
        txRate: snap.txRate,
        deviceCount: snap.deviceCount,
        online: snap.online,
        deviceName: snap.deviceName,
        cpuUsage: snap.cpuUsage,
        memPercent: snap.memPercent,
        ip: snap.ip,
        todayTraffic: snap.todayTraffic,
        metric: WidgetDataStore.loadMetric(),
        widgetSize: dimension
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onAddForm err: ${JSON.stringify(e)}`)
      return formBindingData.createFormBindingData({
        rxRate: 0, txRate: 0, deviceCount: 0, online: false, deviceName: 'iStore 路由管家',
        cpuUsage: 0, memPercent: 0, ip: '', todayTraffic: 0, metric: 'speed', widgetSize: '2*2'
      })
    }
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm')
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm')
    try {
      WidgetDataStore.loadWithContext(this.context).then((snap) => {
        // 带上缓存尺寸，避免覆盖卡片已设置的 widgetSize
        const dim: string = WidgetDataStore.loadDimension()
        formProvider.updateForm(formId, formBindingData.createFormBindingData({
          rxRate: snap.rxRate,
          txRate: snap.txRate,
          deviceCount: snap.deviceCount,
          online: snap.online,
          deviceName: snap.deviceName,
          cpuUsage: snap.cpuUsage,
          memPercent: snap.memPercent,
          ip: snap.ip,
          todayTraffic: snap.todayTraffic,
          metric: WidgetDataStore.loadMetric(),
          widgetSize: dim
        })).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, `updateForm err: ${err.message}`)
        })
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onUpdateForm err: ${JSON.stringify(e)}`)
    }
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility')
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, `onFormEvent: ${message}`)
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm')
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY
  }
}
