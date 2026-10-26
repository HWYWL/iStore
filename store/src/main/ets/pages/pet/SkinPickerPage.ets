/**
 * SkinPickerPage — 小管家装扮选择（独立页，全屏覆盖导航条）
 * 8 套皮肤联动 App 主题，选中即应用
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { SKINS, SkinDef } from '../../common/theme/ThemeColors'
import { PetStore, PetState } from '../../common/store/PetStore'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AppNav } from '../../common/utils/AppNav'

@Entry
@Component
struct SkinPickerPage {
  @State theme: ThemePalette = AppState.getInstance().getTheme()
  @State pet: PetState = PetStore.getInstance().getState()
  @State topSafeArea: number = 44
  private store: PetStore = PetStore.getInstance()

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (hostCtx) {
      this.store.init(hostCtx).then(() => {
        this.pet = this.store.getState()
      })
    }
    // 状态栏避让
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) {
        window.getLastWindow(ctx as common.Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = px2vp(avoidArea.topRect.height)
          if (h > 0) this.topSafeArea = h
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 选中皮肤 */
  selectSkin(id: string): void {
    this.pet = this.store.setSkin(id)
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Row() {
          Text('🎽').fontSize(20)
          Text(' 小管家装扮').fontSize(20).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Bold)
        }
        Blank()
        Text('完成').fontSize(13).fontColor(this.theme.primary).fontWeight(FontWeight.Bold)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(12)
          .backgroundColor(this.tint(this.theme.primary, 0.1))
          .onClick(() => { AppNav.getInstance().back() })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeArea + 8, bottom: 10 })

      Scroll() {
        Column() {
          // 预览卡
          Row() {
            Text('当前装扮')
              .fontSize(12).fontColor(this.theme.textTertiary)
            Blank()
            Text(this.skinName())
              .fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme.primary)
          }
          .width('100%').margin({ bottom: 10 })

          // 皮肤网格
          Grid() {
            ForEach(SKINS, (s: SkinDef) => {
              GridItem() {
                Column() {
                  // 皮肤预览（代表色块）
                  Row() {
                    Row().width(56).height(56).borderRadius(16).backgroundColor(s.preview[0])
                      .justifyContent(FlexAlign.Center)
                    if (s.preview.length > 1) {
                      Row().width(40).height(40).borderRadius(12).backgroundColor(s.preview[1])
                        .position({ x: 34, y: 26 })
                    }
                  }
                  .width(72).height(56)
                  Text(s.name)
                    .fontSize(12)
                    .fontColor(this.pet.skinId === s.id ? this.theme.primary : this.theme.textSecondary)
                    .fontWeight(FontWeight.Bold)
                    .margin({ top: 8 })
                  if (this.pet.skinId === s.id) {
                    Text('✓ 使用中').fontSize(10).fontColor('#2FBFA8').margin({ top: 3 })
                  }
                }
                .width('100%')
                .padding({ top: 16, bottom: 12 })
                .borderRadius(18)
                .border({ width: this.pet.skinId === s.id ? 2 : 0, color: this.theme.primary })
                .backgroundColor(this.theme.bgCard)
                .shadow({ radius: 10, color: 'rgba(180,160,120,0.1)', offsetY: 3 })
                .onClick(() => { this.selectSkin(s.id) })
              }
            }, (s: SkinDef) => s.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsGap(12)
          .columnsGap(12)
          .width('100%')

          // 说明
          Text('皮肤与 App 主题联动：换皮肤时小管家自动换色')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 20 })

          Blank().height(40)
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 135, colors: this.theme.pageGradient })
  }

  skinName(): string {
    const s: SkinDef | undefined = SKINS.find((k: SkinDef) => k.id === this.pet.skinId)
    return s ? s.name : '米色经典'
  }

  /** 半透明色 */
  tint(hex: string, alpha: number): string {
    let c: string = hex
    if (c.startsWith('#')) c = c.substring(1)
    if (c.length === 3) c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    let r: number = 0
    let g: number = 0
    let b: number = 0
    try {
      r = parseInt(c.substring(0, 2), 16)
      g = parseInt(c.substring(2, 4), 16)
      b = parseInt(c.substring(4, 6), 16)
    } catch (e) {
      return 'rgba(0,0,0,0.06)'
    }
    return `rgba(${r},${g},${b},${alpha})`
  }
}
