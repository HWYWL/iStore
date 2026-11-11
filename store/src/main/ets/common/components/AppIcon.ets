/**
 * AppIcon - 统一图标组件
 *
 * 应用固定使用 hos（鸿蒙超椭圆）包，用户已无切换入口；另保留 line（几何线稿）供
 * 需要单色着色的线性场景通过 forcePack 指定（如仪表盘快捷入口）。
 * 图标名 name 是跨包契约，缺资源时回退系统符号，不会渲染成空白。
 */
import {
  DEFAULT_ICON_PACK,
  getHosRes,
  getIconPackById,
  getLineRes,
  getSymbolRes,
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
  /** 强制指定图标包（保留的调试入口），为空则用应用统一的默认包 */
  @Prop forcePack: string = ''
  /** 当前皮肤 id，用于判断是否需要暗色素材 */
  @StorageLink('skinId') skinId: string = 'beige'

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

  /** 实际生效的图标包 id：应用统一使用默认包，不再提供用户切换 */
  private activePackId(): string {
    return this.forcePack !== '' ? this.forcePack : DEFAULT_ICON_PACK
  }

  /** 实际生效的图标包渲染类型 */
  private activeKind(): IconPackKind {
    return getIconPackById(this.activePackId()).kind
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
    if (this.activeKind() === 'line') {
      // 几何线稿：单色素材按调用点传入的颜色着色（线性快捷入口用）
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
    } else {
      // 默认（也是唯一可直接选的）鸿蒙质感包：超椭圆底板 + 渐变 + 玻璃微光（素材内含）
      Image(this.hosRes())
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
    }
  }
}
