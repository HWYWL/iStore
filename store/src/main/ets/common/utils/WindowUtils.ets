/**
 * WindowUtils - 窗口沉浸式工具
 * 状态栏/导航栏透明化，让内容真正沉浸（跟随主题切换图标颜色）
 * 注：沉浸光感 uiMaterial 需 API 26+，当前 SDK 使用窗口级沉浸方案
 */
import { window } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'WindowUtils'
const DOMAIN = 0x0001

/**
 * 设置状态栏/导航栏透明并调整图标颜色
 * @param context 页面上下文（getHostContext）
 * @param isDark 深色主题时图标用白色，浅色用黑色
 */
export async function applyImmersiveBar(context: Context, isDark: boolean): Promise<void> {
  if (deviceInfo.deviceType === '2in1') {
    return
  }
  try {
    const win: window.Window = await window.getLastWindow(context)
    win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
      navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, `setWindowSystemBarProperties err: ${e.message}`)
    })
  } catch (e) {
    hilog.error(DOMAIN, TAG, `getLastWindow err: ${JSON.stringify(e)}`)
  }
}

/**
 * 设置窗口显示方向（运行时覆盖 module 配置）
 * @param context 页面上下文
 * @param orientation 如 AUTO_ROTATION（跟随传感器旋转）/ PORTRAIT / LANDSCAPE
 */
export async function setWindowOrientation(context: Context, orientation: window.Orientation): Promise<void> {
  if (deviceInfo.deviceType === '2in1') {
    return
  }
  try {
    const win: window.Window = await window.getLastWindow(context)
    win.setPreferredOrientation(orientation).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, `setPreferredOrientation err: ${e.message}`)
    })
  } catch (e) {
    hilog.error(DOMAIN, TAG, `getLastWindow err: ${JSON.stringify(e)}`)
  }
}

/**
 * 应用方向策略：跟随传感器，但由系统「旋转锁定」开关管控
 *
 * 注意 AUTO_ROTATION(5) 的语义是 ignore auto rotation lock —— 会无视系统旋转锁，
 * 必须用 AUTO_ROTATION_RESTRICTED(8)（controlled by auto rotation lock）。
 * 锁定状态由框架自己处理，无需读取系统设置，锁一开一关立即生效。
 * @param context 页面/Ability 上下文
 * @param targetWin 可复用的主窗口，不传则内部获取
 */
export async function applyRotationBySystemLock(context: Context, targetWin?: window.Window): Promise<void> {
  if (deviceInfo.deviceType === '2in1') {
    return
  }
  try {
    const win: window.Window = targetWin ?? await window.getLastWindow(context)
    await win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
    hilog.info(DOMAIN, TAG, 'rotation applied: AUTO_ROTATION_RESTRICTED')
  } catch (e) {
    hilog.error(DOMAIN, TAG, `applyRotationBySystemLock err: ${JSON.stringify(e)}`)
  }
}
