/**
 * SkinManagePage - 皮肤管理
 * 展示所有可用皮肤（SKINS 注册表），点击切换，全应用即时生效并持久化
 */
import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette, SKINS, SkinDef } from '../../common/theme/ThemeColors'
import { ICON_PACKS, IconPackDef } from '../../common/theme/IconPack'
import { promptAction, window } from '@kit.ArkUI'
import { vibrator } from '@kit.SensorServiceKit'
import { AppNav } from '../../common/utils/AppNav'
import { AppIcon } from '../../common/components/AppIcon'

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
  @State currentSkinId: string = 'white'
  @State currentIconPackId: string = 'color'

  aboutToAppear(): void {
    this.theme = AppState.getInstance().getTheme()
    this.currentSkinId = AppState.getInstance().getSkin().id
    this.currentIconPackId = AppState.getInstance().getIconPack().id
    this.loadTopSafeArea()
    AppState.getInstance().onThemeChange(() => {
      this.theme = AppState.getInstance().getTheme()
    })
  }

  aboutToDisappear(): void {
    AppState.getInstance().offThemeChange(() => {})
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

  /** 切换皮肤 */
  applySkin(skin: SkinDef): void {
    if (skin.id === this.currentSkinId) return
    this.currentSkinId = skin.id
    AppState.getInstance().setSkin(skin.id)
    // 换装仪式感：轻震动 + 反馈
    try {
      vibrator.startVibration({ type: 'time', duration: 25 }, { id: 0, usage: 'alarm' }).catch(() => {})
    } catch (e) {}
    try {
      this.getUIContext().getPromptAction().showToast({ message: `已切换为「${skin.name}」皮肤 ✨`, duration: 1200 })
    } catch (e) {}
  }

  /** 切换图标包 */
  applyIconPack(pack: IconPackDef): void {
    if (pack.id === this.currentIconPackId) return
    this.currentIconPackId = pack.id
    AppState.getInstance().setIconPack(pack.id)
    this.theme = AppState.getInstance().getTheme()
    try {
      vibrator.startVibration({ type: 'time', duration: 25 }, { id: 0, usage: 'alarm' }).catch(() => {})
    } catch (e) {}
    try {
      this.getUIContext().getPromptAction().showToast({ message: `图标已切换为「${pack.name}」`, duration: 1200 })
    } catch (e) {}
  }

  /** 图标包预览卡片（与皮肤卡片同版式） */
  @Builder
  iconCard(pack: IconPackDef, idx: number) {
    Column() {
      // 预览区（模拟图标在卡片中的样子）
      Column() {
        Row() {
          Text('图标预览')
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
          Blank()
          Text('●')
            .fontSize(10)
            .fontColor(this.theme.success)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        Row({ space: 10 }) {
          ForEach(pack.preview, (iconName: string) => {
            Row() {
              AppIcon({
                name: iconName,
                iconSize: 20,
                colors: [this.theme.textPrimary],
                forcePack: pack.id
              })
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .borderRadius(10)
          }, (iconName: string, i: number): string => `${pack.id}_${i}`)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.theme.bgDark)
      .border({ width: 0.5, color: this.theme.borderGlass })

      // 名称与描述
      Row() {
        Column() {
          Text(pack.name)
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
          Text(pack.desc)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (pack.id === this.currentIconPackId) {
          Row() {
            Text('使用中')
              .fontSize(11)
              .fontColor(Color.White)
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
    .backgroundColor(this.theme.bgCard)
    .shadow({ radius: this.theme.cardShadowRadius, color: this.theme.cardShadow, offsetY: 4 })
    .border({
      width: pack.id === this.currentIconPackId ? 1.5 : 0.5,
      color: pack.id === this.currentIconPackId ? this.theme.primary : this.theme.borderGlass
    })
    .onClick(() => { this.applyIconPack(pack) })
  }

  /** 皮肤预览卡片 */
  @Builder
  skinCard(skin: SkinDef, idx: number) {
    Column() {
      // 预览区（模拟页面配色）
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

        // 模拟卡片
        Row({ space: 6 }) {
          Column()
            .width(36).height(30)
            .borderRadius(8)
            .backgroundColor(skin.theme.primary)
          Column()
            .layoutWeight(1).height(30)
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

      // 名称与描述
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

        // 选中标记
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
    .backgroundColor(this.theme.bgCard)
    .shadow({ radius: this.theme.cardShadowRadius, color: this.theme.cardShadow, offsetY: 4 })
    .border({
      width: skin.id === this.currentSkinId ? 1.5 : 0.5,
      color: skin.id === this.currentSkinId ? this.theme.primary : this.theme.borderGlass
    })
    .onClick(() => { this.applySkin(skin) })
  }

  build() {
    Column() {
      // 标题栏
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
        Text('皮肤管理')
          .fontSize(17)
          .fontColor(this.theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: this.topSafeArea + 4, bottom: 8 })

      // 皮肤网格
      Scroll() {
        Column() {
          Row() {
            Text('选择皮肤')
              .fontSize(13)
              .fontColor(this.theme.textSecondary)
              .fontWeight(FontWeight.Medium)
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 6 })

          // 皮肤网格：每行 2 张卡片，从上往下排列
          Column() {
            ForEach(SKINS, (skin: SkinDef, idx: number) => {
              Row({ space: 12 }) {
                if (idx * 2 < SKINS.length) {
                  this.skinCard(SKINS[idx * 2], idx * 2)
                }
                if (idx * 2 + 1 < SKINS.length) {
                  this.skinCard(SKINS[idx * 2 + 1], idx * 2 + 1)
                }
              }
              .width('100%')
              .margin({ bottom: 14 })
            }, (skin: SkinDef, idx: number): string => `row_${idx}`)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 4 })

          // 图标风格
          Row() {
            Text('选择图标')
              .fontSize(13)
              .fontColor(this.theme.textSecondary)
              .fontWeight(FontWeight.Medium)
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 6 })

          Column() {
            ForEach(ICON_PACKS, (pack: IconPackDef, idx: number) => {
              Row({ space: 12 }) {
                if (idx * 2 < ICON_PACKS.length) {
                  this.iconCard(ICON_PACKS[idx * 2], idx * 2)
                }
                if (idx * 2 + 1 < ICON_PACKS.length) {
                  this.iconCard(ICON_PACKS[idx * 2 + 1], idx * 2 + 1)
                } else {
                  // 单数时补占位，避免最后一张卡片被拉满整行
                  Blank().layoutWeight(1)
                }
              }
              .width('100%')
              .margin({ bottom: 14 })
            }, (pack: IconPackDef, idx: number): string => `iconrow_${idx}`)
          }
          .width('100%')
          .padding({ left: 14, right: 14 })

          Row() {
            AppIcon({ name: 'lightbulb', iconSize: 13, colors: ['#F59E0B'] })
            Text(' 切换后立即生效，选择会自动保存')
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
