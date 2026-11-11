/**
 * SkinManagePage - 主题管理
 * 主题 = 色板（SKINS，8 套）× 材质（MATERIALS：默认实色 / 液态玻璃）。
 * 两维独立：换色板不改形态，换材质不改配色。选择即时生效并持久化。
 */
import { AppState } from '../../common/store/AppState'
import {
  LIGHT_THEME,
  ThemePalette,
  SKINS,
  SkinDef,
  MATERIALS,
  MaterialDef,
  applyMaterial,
  cardElevation
} from '../../common/theme/ThemeColors'
import { window } from '@kit.ArkUI'
import { vibrator } from '@kit.SensorServiceKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'
import { GlassCard } from '../../common/components/GlassCard'

@Entry
@Component
struct SkinManagePageRoute {
  build() {
    Column() {
      SkinManagePage()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SkinManagePage {
  @State theme: ThemePalette = LIGHT_THEME
  @State topSafeArea: number = 44
  @State currentSkinId: string = 'beige'
  @State currentMaterialId: string = 'solid'
  // 统一由 AppStorage 驱动：任何页面切主题后这里立即重绘
  @StorageLink('skinId') @Watch('onThemeStorageChange') skinId: string = 'beige'
  @StorageLink('uiStyle') @Watch('onThemeStorageChange') uiStyle: string = 'solid'

  onThemeStorageChange(): void {
    this.theme = AppState.getInstance().getTheme()
    this.currentSkinId = AppState.getInstance().getSkin().id
    this.currentMaterialId = AppState.getInstance().getUiStyle()
  }

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.currentSkinId = AppState.getInstance().getSkin().id
    this.currentMaterialId = AppState.getInstance().getUiStyle()
    this.loadTopSafeArea()
  }

  loadTopSafeArea(): void {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        window.getLastWindow(hostCtx as Context).then((win: window.Window) => {
          const avoidArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          const h: number = this.getUIContext().px2vp(avoidArea.topRect.height)
          if (h > 0) {
            this.topSafeArea = h
          }
        }).catch(() => {})
      }
    } catch (e) {}
  }

  /** 换肤震动反馈：只在真正换了选择时触发 */
  private haptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 25 }, { id: 0, usage: 'alarm' }).catch(() => {})
    } catch (e) {}
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1200 })
    } catch (e) {}
  }

  /** 切换色板 */
  applySkin(skin: SkinDef): void {
    if (skin.id === this.currentSkinId) return
    this.currentSkinId = skin.id
    AppState.getInstance().setSkin(skin.id)
    this.theme = AppState.getInstance().getTheme()
    this.haptic()
    this.toast(`已切换为「${skin.name}」`)
  }

  /** 切换材质（默认 / 液态玻璃） */
  applyMaterialDef(def: MaterialDef): void {
    if (def.id === this.currentMaterialId) return
    this.currentMaterialId = def.id
    AppState.getInstance().setUiStyle(def.id)
    this.theme = AppState.getInstance().getTheme()
    this.haptic()
    this.toast(def.id === 'liquid' ? '已开启液态玻璃' : '已切回默认材质')
  }

  /** 材质预览用的调色板 */
  private previewTheme(def: MaterialDef): ThemePalette {
    return applyMaterial(AppState.getInstance().getSkin().theme, def.id)
  }

  /** 材质卡片：用真实材质渲染一小块预览，让人一眼看出「形态变了」 */
  @Builder
  materialCard(def: MaterialDef) {
    Column() {
      GlassCard({ theme: this.previewTheme(def), radius: 16, paddingTop: 10, paddingRight: 12, paddingBottom: 10, paddingLeft: 12 }) {
        Row({ space: 6 }) {
          
          Column()
            .width(30)
            .height(26)
            .borderRadius(8)
            .backgroundColor(this.previewTheme(def).primary)
          Column() {
            Row()
              .width('70%')
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.theme.textTertiary)
            Row()
              .width('45%')
              .height(5)
              .borderRadius(3)
              .margin({ top: 4 })
              .backgroundColor(this.theme.textTertiary)
              .opacity(0.6)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(34)
      }

      Row() {
        Column() {
          Text(def.name)
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
          Text(def.desc)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (def.id === this.currentMaterialId) {
          Row() {
            AppIcon({ name: 'checkmark_circle', iconSize: 12, colors: [Color.White] })
            Text(' 使用中').fontSize(11).fontColor(Color.White)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.theme.primary)
        }
      }
      .width('100%')
      .padding({ top: 10 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(20)
    .backgroundColor(this.theme.bgCardSolid)
    .border({
      width: def.id === this.currentMaterialId ? 1.5 : 0.5,
      color: def.id === this.currentMaterialId ? this.theme.primary : this.theme.borderGlass
    })
    .shadow(cardElevation(this.theme))
    .onClick(() => { this.applyMaterialDef(def) })
  }

  /** 色板卡片 */
  @Builder
  skinCard(skin: SkinDef) {
    Column() {
      Column() {
        Row() {
          Text('A')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(skin.theme.textPrimary)
          Text(' 皮肤预览')
            .fontSize(11)
            .fontColor(skin.theme.textSecondary)
          Blank()
          Text('●')
            .fontSize(10)
            .fontColor(skin.theme.success)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        Row({ space: 6 }) {
          Column()
            .width(36)
            .height(30)
            .borderRadius(8)
            .backgroundColor(skin.theme.primary)
          Column()
            .layoutWeight(1)
            .height(30)
            .borderRadius(8)
            .backgroundColor(skin.theme.bgCardSolid)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(skin.theme.bgDark)
      .border({ width: 0.5, color: skin.theme.borderGlass })

      Row() {
        Column() {
          Text(skin.name)
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
          Text(skin.desc)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (skin.id === this.currentSkinId) {
          Row() {
            AppIcon({ name: 'checkmark_circle', iconSize: 12, colors: [Color.White] })
            Text(' 使用中').fontSize(11).fontColor(Color.White)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.theme.primary)
        }
      }
      .width('100%')
      .padding({ top: 10 })
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(20)
    .backgroundColor(this.theme.bgCardSolid)
    .border({
      width: skin.id === this.currentSkinId ? 1.5 : 0.5,
      color: skin.id === this.currentSkinId ? this.theme.primary : this.theme.borderGlass
    })
    .shadow(cardElevation(this.theme))
    .onClick(() => { this.applySkin(skin) })
  }

  @Builder
  sectionTitle(title: string, hint: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
        .fontWeight(FontWeight.Medium)
      Text(hint)
        .fontSize(11)
        .fontColor(this.theme.textTertiary)
        .margin({ left: 8 })
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 6 })
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 4, right: 12, top: 2, bottom: 2 })
        }
        .onClick(() => {
          AppNav.getInstance().back()
        })
        Text('主题')
          .fontSize(17)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      Scroll() {
        Column() {
          this.sectionTitle('材质', '决定界面的形态')
          Column({ space: 12 }) {
            this.materialCard(MATERIALS[0])
            this.materialCard(MATERIALS[1])
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 6 })

          this.sectionTitle('色板', '决定界面的配色')
          Column() {
            ForEach(SKINS, (skin: SkinDef, idx: number) => {
              Row({ space: 12 }) {
                if (idx * 2 < SKINS.length) {
                  this.skinCard(SKINS[idx * 2])
                }
                if (idx * 2 + 1 < SKINS.length) {
                  this.skinCard(SKINS[idx * 2 + 1])
                }
              }
              .width('100%')
              .margin({ bottom: 14 })
            }, (skin: SkinDef, idx: number): string => `row_${idx}`)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 4 })

          Row() {
            AppIcon({ name: 'lightbulb', iconSize: 13, colors: ['#F59E0B'] })
            Text(' 材质与色板相互独立，切换后立即生效并自动保存')
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 30 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: this.theme.pageGradient
    })
  }
}
