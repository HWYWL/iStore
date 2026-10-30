/**
 * AppIcon - 统一图标组件
 *
 * 全应用图标统一走这里渲染，从而支持「图标包」随皮肤一起切换：
 * - hos     包：Image 渲染鸿蒙超椭圆素材（默认，按皮肤自动切浅色 / 暗色）
 * - color   包：Image 渲染彩色实心渐变素材
 * - line    包：Image 渲染自绘几何线稿（单色着色）
 * - harmony 包：SymbolGlyph 原生多色渲染（HarmonyOS 设计语言）
 * - ios     包：圆角底 + 白色图形
 *
 * 当前图标包通过 AppStorage('iconPackId') 驱动，切换后所有页面即时刷新。
 * 用法：AppIcon({ name: 'wifi', iconSize: 16, colors: [this.theme.primary] })
 */
import {
  getColorRes,
  getHosRes,
  getIconPackById,
  getIOSGradient,
  getLineRes,
  getSymbolRes,
  HARMONY_COLORS,
  hasColorRes,
  hasLineRes,
  IconPackKind
} from '../theme/IconPack'
import { getSkinById, SkinDef, ThemePalette } from '../theme/ThemeColors'

@Component
export struct AppIcon {
  /** 图标名，取自 IconPack 资源表的键 */
  @Prop name: string = ''
  /** 图标尺寸 */
  @Prop iconSize: number = 16
  /** 图标颜色（仅线稿 / 符号类渲染使用；自带底板的素材不使用） */
  @Prop colors: ResourceColor[] = []
  /** 当前图标包 id，由 AppStorage 全局驱动（默认鸿蒙质感） */
  @StorageLink('iconPackId') iconPackId: string = 'hos'
  /** 强制指定图标包（用于图标包预览），为空则跟随全局 */
  @Prop forcePack: string = ''
  /** 当前皮肤 id，用于判断是否需要暗色素材 */
  @StorageLink('skinId') skinId: string = 'white'

  /** 当前皮肤是否为暗色（按背景亮度判断） */
  private isDarkSkin(): boolean {
    const skin: SkinDef = getSkinById(this.skinId)
    const theme: ThemePalette = skin.theme
    const hex: string = theme.bgDark
    if (hex.length !== 7 || hex.charAt(0) !== '#') {
      return false
    }
    const r: number = parseInt(hex.substring(1, 3), 16)
    const g: number = parseInt(hex.substring(3, 5), 16)
    const b: number = parseInt(hex.substring(5, 7), 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) < 128
  }

  /** 鸿蒙风格素材（按皮肤自动切浅色 / 暗色） */
  private hosRes(): Resource {
    return getHosRes(this.name, this.isDarkSkin())
  }

  /** 实际生效的图标包 id */
  private activePackId(): string {
    return this.forcePack !== '' ? this.forcePack : this.iconPackId
  }

  /** 实际生效的图标包渲染类型 */
  private activeKind(): IconPackKind {
    return getIconPackById(this.activePackId()).kind
  }

  /** iOS 图标底色（浅端） */
  private iosTop(): string {
    return getIOSGradient(this.name)[0]
  }

  /** iOS 图标底色（深端） */
  private iosBottom(): string {
    return getIOSGradient(this.name)[1]
  }

  /**
   * 着色矩阵：保留素材 alpha，把 RGB 换成 colors[0]
   * 用于单色线稿素材跟随皮肤主色（不能用 Image.fillColor，会填实空心路径）
   */
  private tintFilter(): number[] {
    let r: number = 0.17
    let g: number = 0.16
    let b: number = 0.15
    if (this.colors.length > 0) {
      const c: ResourceColor = this.colors[0]
      if (typeof c === 'string') {
        const s: string = c as string
        if (s.length === 7 && s.charAt(0) === '#') {
          r = parseInt(s.substring(1, 3), 16) / 255
          g = parseInt(s.substring(3, 5), 16) / 255
          b = parseInt(s.substring(5, 7), 16) / 255
        }
      }
    }
    return [
      0, 0, 0, 0, r,
      0, 0, 0, 0, g,
      0, 0, 0, 0, b,
      0, 0, 0, 1, 0
    ]
  }

  build() {
    if (this.activeKind() === 'image') {
      if (hasColorRes(this.name)) {
        Image(getColorRes(this.name))
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
      } else {
        // 素材缺失时回退系统符号，避免出现空白
        SymbolGlyph(getSymbolRes(this.name))
          .fontSize(this.iconSize)
          .fontColor(this.colors)
      }
    } else if (this.activeKind() === 'hos') {
      // 鸿蒙质感：超椭圆底板 + 渐变 + 玻璃微光（素材内含），不加投影，避免外圈出现淡色光晕
      Image(this.hosRes())
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
    } else if (this.activeKind() === 'line') {
      // 几何线稿：单色素材跟随皮肤主色着色
      if (hasLineRes(this.name)) {
        Image(getLineRes(this.name))
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .colorFilter(this.tintFilter())
      } else {
        SymbolGlyph(getSymbolRes(this.name))
          .fontSize(this.iconSize)
          .fontColor(this.colors)
      }
    } else if (this.activeKind() === 'ios') {
      // 圆角方块底 + 白色图形，尺寸与其它图标包占位一致，不改变既有布局
      Stack() {
        Column()
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.iconSize * 0.28)
          .linearGradient({
            angle: 145,
            colors: [[this.iosTop(), 0.0], [this.iosBottom(), 1.0]]
          })
        SymbolGlyph(getSymbolRes(this.name))
          .fontSize(this.iconSize * 0.58)
          .fontColor([Color.White])
      }
      .width(this.iconSize)
      .height(this.iconSize)
    } else if (this.activeKind() === 'harmony') {
      // 多色渲染：按分层调色板上色，调用点的单色 colors 不适用
      SymbolGlyph(getSymbolRes(this.name))
        .fontSize(this.iconSize)
        .fontColor(HARMONY_COLORS)
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
    } else {
      SymbolGlyph(getSymbolRes(this.name))
        .fontSize(this.iconSize)
        .fontColor(this.colors)
    }
  }
}
