/**
 * 主题色彩系统（多皮肤 × 多材质）
 * 一套主题 = 色板（ThemePalette 的颜色部分）× 材质（ThemeMaterial）。
 * 色板决定"什么颜色"，材质决定"长什么样"（实色卡片 / 液态玻璃）。
 * 当前皮肤与材质由 AppState 持久化管理，组件通过 AppState.getTheme() 获取。
 */

/** 材质类型：solid 实色 / liquid 液态玻璃 */
export type MaterialKind = 'solid' | 'liquid'

/**
 * 材质定义——主题里"形态"的那一半。
 * 注意：solid 材质下 tintTop/tintBottom/highlightStroke 不参与渲染，卡片用 `bgCard`。
 */
export interface ThemeMaterial {
  kind: MaterialKind
  /** 卡片实时模糊半径（vp，0 = 不模糊） */
  blur: number
  /** 胶囊/小控件模糊半径 */
  blurControl: number
  /** 玻璃上层色（卡片渐变起点） */
  tintTop: string
  /** 玻璃下层色（卡片渐变终点） */
  tintBottom: string
  /** 普通描边颜色 */
  borderColor: string
  borderWidth: number
  /** 镜面高光渐变描边（ArkUI 的 border 不支持渐变，由 GlassCard 用内缩层实现） */
  highlightStroke: Array<[ResourceColor, number]>
  /** 顶部内高光 */
  innerGlow: string
  /** 底部反光 */
  bottomGlow: string
  radiusCard: number
  radiusControl: number
  /** 浮起阴影模糊半径 */
  elevation: number
  elevationY: number
  elevationColor: string
  /** 长列表页不叠模糊（保底：交给页面决定是否降级） */
  listBlurDisabled: boolean
}

/** 实色材质：无模糊、薄描边、克制投影（＝现有外观） */
export const SOLID_MATERIAL: ThemeMaterial = {
  kind: 'solid',
  blur: 0,
  blurControl: 0,
  tintTop: '#FFFFFF',
  tintBottom: '#FFFFFF',
  borderColor: 'rgba(0, 0, 0, 0.05)',
  borderWidth: 1,
  highlightStroke: [['rgba(255, 255, 255, 0)', 0], ['rgba(255, 255, 255, 0)', 1]],
  innerGlow: 'rgba(255, 255, 255, 0)',
  bottomGlow: 'rgba(255, 255, 255, 0)',
  radiusCard: 16,
  radiusControl: 12,
  elevation: 10,
  elevationY: 2,
  elevationColor: 'rgba(40, 50, 70, 0.06)',
  listBlurDisabled: false
}

/** 液态玻璃材质：高保真配方（实时模糊 + 镜面渐变描边 + 内高光 + 双层浮起） */
export const LIQUID_MATERIAL: ThemeMaterial = {
  kind: 'liquid',
  blur: 28,
  blurControl: 16,
  tintTop: 'rgba(255, 255, 255, 0.44)',
  tintBottom: 'rgba(255, 255, 255, 0.22)',
  borderColor: 'rgba(255, 255, 255, 0.10)',
  borderWidth: 1,
  highlightStroke: [
    ['rgba(255, 255, 255, 0.95)', 0],
    ['rgba(255, 255, 255, 0.35)', 0.26],
    ['rgba(255, 255, 255, 0.06)', 0.48],
    ['rgba(255, 255, 255, 0.30)', 0.74],
    ['rgba(255, 255, 255, 0.80)', 1]
  ],
  innerGlow: 'rgba(255, 255, 255, 0.90)',
  bottomGlow: 'rgba(255, 255, 255, 0.42)',
  radiusCard: 26,
  radiusControl: 100,
  elevation: 48,
  elevationY: 22,
  elevationColor: 'rgba(31, 42, 68, 0.20)',
  listBlurDisabled: true
}

/**
 * 主题调色板接口
 * 组件使用 this.theme.<字段> 引用，无需硬编码颜色值
 */
export interface ThemePalette {
  // --- 主色调 ---
  primary: string           // 主题色（按钮、链接、强调元素）
  primaryDark: string       // 主题深色变体（按下态）
  secondary: string         // 辅助色（次要强调）
  accent: string            // 点缀色（图标高亮、标签）

  // --- 语义色 ---
  success: string           // 成功/正常状态
  warning: string           // 警告状态
  danger: string            // 危险/错误状态
  info: string              // 信息提示

  // --- 背景色 ---
  bgDark: string            // 页面主背景
  bgCard: string            // 卡片背景
  bgCardHover: string       // 卡片悬停/按下背景
  bgGlass: string           // 毛玻璃面板背景
  bgGlassLight: string      // 浅色毛玻璃背景
  bgCardSolid: string       // 不透明卡片背景（弹窗/浮层用，保证内容清晰）

  // --- 文本颜色 ---
  textPrimary: string       // 主要文本（标题、正文）
  textSecondary: string     // 次要文本（描述、标签）
  textTertiary: string      // 辅助文本（时间戳、次要标签）
  textAccent: string        // 强调文本（数值、高亮关键词）

  // --- 边框颜色 ---
  borderGlass: string       // 毛玻璃边框（默认态）
  borderGlassFocus: string  // 毛玻璃边框（聚焦/悬停态）

  // --- 光感（沉浸式投影） ---
  cardShadow: string        // 卡片柔和投影颜色（透明色，如 rgba(0,0,0,0.14)）
  cardShadowRadius: number  // 卡片投影模糊半径（vp）

  // --- 进度条底色（皮肤专属，替代写死的浅色轨道） ---
  progressTrack: string
  // --- 图表多色序列（折线/仪表盘，随皮肤主色变化） ---
  chartColors: string[]
  // --- 浅色强调底（图标/胶囊底，替代写死的浅橙 #FDF0E4 系） ---
  accentSoft: string

  // --- 页面渐变背景（皮肤专属） ---
  pageGradient: Array<[ResourceColor, number]>  // linearGradient colors：[[color, offset], ...]

  // --- 材质（形态，与颜色正交） ---
  material: ThemeMaterial
}

/**
 * 统一亮色主题调色板（米色商务风格）
 * 浅暖米色底 #F6F2EA + 纯白卡片 + 暖橙色高亮 #FF8A3D + 绿色在线 + 黄色告警
 */
export const LIGHT_THEME: ThemePalette = {
  primary: '#FF8A3D',
  primaryDark: '#E07020',
  secondary: '#5B4CC4',
  accent: '#FF8A3D',

  success: '#00A84D',
  warning: '#E6A800',
  danger: '#D93025',
  info: '#1A73E8',

  bgDark: '#F5F1EE',
  bgCard: '#FFFFFF',
  bgCardHover: 'rgba(0, 0, 0, 0.05)',
  bgGlass: '#F6F2E9',
  bgGlassLight: 'rgba(0, 0, 0, 0.03)',
  bgCardSolid: '#F6F2E9',

  textPrimary: '#2B2A26',
  textSecondary: 'rgba(0, 0, 0, 0.62)',
  textTertiary: 'rgba(0, 0, 0, 0.38)',
  textAccent: '#FF8A3D',

  borderGlass: 'rgba(0, 0, 0, 0.08)',
  borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

  cardShadow: 'rgba(180, 160, 120, 0.14)',
  cardShadowRadius: 14,
  progressTrack: '#F0EBE0',
  chartColors: ['#FF8A3D', '#00A84D', '#E6A800', '#1A73E8', '#5B4CC4'],
  accentSoft: '#FDF0E4',
  pageGradient: [['#F6F2EA', 0], ['#FAF7F0', 0.5], ['#F6F2EA', 1]],
  material: SOLID_MATERIAL
}

/**
 * 材质定义（供主题页展示）：与色板正交，决定界面形态而非颜色
 */
export interface MaterialDef {
  id: MaterialKind
  name: string
  desc: string
}

export const MATERIALS: MaterialDef[] = [
  { id: 'solid', name: '默认', desc: '实色卡片 · 柔和投影' },
  { id: 'liquid', name: '液态玻璃', desc: '实时模糊 · 镜面高光' }
]

/**
 * 十六进制颜色按比例混合（t 为 hexB 的占比），返回 rgba 字符串。
 * alpha < 1 时渐变可透出下层统一的柔光背景，让多栏共享同一块底。
 */
function mixColor(hexA: string, hexB: string, t: number, alpha: number = 1): string {
  const a: string = hexA.replace('#', '')
  const b: string = hexB.replace('#', '')
  if (a.length !== 6 || b.length !== 6) {
    return hexA
  }
  const ar: number = parseInt(a.substring(0, 2), 16)
  const ag: number = parseInt(a.substring(2, 4), 16)
  const ab: number = parseInt(a.substring(4, 6), 16)
  const br: number = parseInt(b.substring(0, 2), 16)
  const bg: number = parseInt(b.substring(2, 4), 16)
  const bb: number = parseInt(b.substring(4, 6), 16)
  const r: number = Math.round(ar + (br - ar) * t)
  const g: number = Math.round(ag + (bg - ag) * t)
  const bl: number = Math.round(ab + (bb - ab) * t)
  return `rgba(${r}, ${g}, ${bl}, ${alpha})`
}

/**
 * 把色板变成液态玻璃版本：背景/描边/投影换成玻璃语言，并挂上 LIQUID_MATERIAL。
 * 颜色本身保留（主色/语义色/文本/图表），所以 8 套色板在玻璃材质下仍有各自色彩倾向；
 * pageGradient 换成多色柔光渐变，作为玻璃折射的背景光斑。
 */
export function toLiquidGlassTheme(base: ThemePalette): ThemePalette {
  return {
    primary: base.primary,
    primaryDark: base.primaryDark,
    secondary: base.secondary,
    accent: base.accent,
    success: base.success,
    warning: base.warning,
    danger: base.danger,
    info: base.info,

    bgDark: 'rgba(255, 255, 255, 0.30)',
    bgCard: 'rgba(255, 255, 255, 0.42)',
    bgCardHover: 'rgba(255, 255, 255, 0.56)',
    bgGlass: 'rgba(255, 255, 255, 0.34)',
    bgGlassLight: 'rgba(255, 255, 255, 0.26)',
    bgCardSolid: 'rgba(255, 255, 255, 0.88)',

    textPrimary: base.textPrimary,
    textSecondary: base.textSecondary,
    textTertiary: base.textTertiary,
    textAccent: base.textAccent,

    borderGlass: 'rgba(255, 255, 255, 0.70)',
    borderGlassFocus: 'rgba(255, 255, 255, 0.90)',

    cardShadow: 'rgba(31, 42, 68, 0.14)',
    cardShadowRadius: 18,

    progressTrack: 'rgba(255, 255, 255, 0.38)',
    chartColors: base.chartColors,
    accentSoft: base.accentSoft,
    // 玻璃需要有“东西可折射”：多色柔光渐变替代原来的单色背景
    pageGradient: [
      [mixColor(base.primary, '#FFFFFF', 0.58, 1), 0],
      [mixColor(base.bgDark, '#FFFFFF', 0.34, 1), 0.26],
      [mixColor(base.info, '#FFFFFF', 0.62, 1), 0.52],
      [mixColor(base.secondary, '#FFFFFF', 0.58, 1), 0.76],
      [mixColor(base.primary, '#FFFFFF', 0.72, 1), 1]
    ],
    material: LIQUID_MATERIAL
  }
}

/**
 * 按材质类型应用主题：solid 原样返回（色板已是实色版本），liquid 走玻璃转换。
 */
export function applyMaterial(base: ThemePalette, kind: MaterialKind): ThemePalette {
  return kind === 'liquid' ? toLiquidGlassTheme(base) : base
}

/**
 * 皮肤注册表：每套皮肤的元数据 + 调色板
 * id 用于持久化，后续新增皮肤只需在此追加一个条目。
 */
export interface SkinDef {
  id: string
  name: string
  desc: string
  preview: string[]   // 预览色块（2-3 个代表色）
  theme: ThemePalette
}

/** 皮肤注册表（默认第一项为米色经典） */
export const SKINS: SkinDef[] = [
  {
    id: 'beige',
    name: '米色经典',
    desc: '浅暖米色 · 商务极简',
    preview: ['#F6F2EA', '#FF8A3D', '#FFFFFF'],
    theme: LIGHT_THEME
  },
  {
    id: 'white',
    name: '纯净白',
    desc: '清爽纯白 · 简洁明亮',
    preview: ['#F5F7FA', '#3B82F6', '#FFFFFF'],
    theme: {
      primary: '#3B82F6',
      primaryDark: '#2563EB',
      secondary: '#0EA5E9',
      accent: '#3B82F6',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#3B82F6',

      bgDark: '#F0F4FA',
      bgCard: '#FFFFFF',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FFFFFF',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FFFFFF',

      textPrimary: '#1F2937',
      textSecondary: 'rgba(0, 0, 0, 0.62)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#3B82F6',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(31, 41, 55, 0.1)',
      cardShadowRadius: 14,
      progressTrack: '#EEF2F7',
      chartColors: ['#3B82F6', '#00A84D', '#E6A800', '#1A73E8', '#8B7CF6'],
      accentSoft: '#EAF1FC',
      pageGradient: [['#F0F4FA', 0], ['#F7FAFD', 0.5], ['#F0F4FA', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'ivory',
    name: '雾霭白',
    desc: '灰粉渐变 · 轻柔雅致',
    preview: ['#EEE1E1', '#F4F3F8', '#FFFFFF'],
    theme: {
      primary: '#C79B9B',
      primaryDark: '#A97F7F',
      secondary: '#8E9BC4',
      accent: '#C79B9B',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#8E9BC4',

      bgDark: '#EEE1E1',
      bgCard: '#FAF7F7',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FAF7F7',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FAF7F7',

      textPrimary: '#4A4444',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#C79B9B',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(160, 140, 140, 0.16)',
      cardShadowRadius: 14,
      progressTrack: '#EFE9E6',
      chartColors: ['#C79B9B', '#00A84D', '#E6A800', '#8E9BC4', '#5B4CC4'],
      accentSoft: '#F5EDED',
      pageGradient: [['#EEE1E1', 0], ['#F2EDF0', 0.5], ['#F4F3F8', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'apricot',
    name: '杏子暖',
    desc: '杏粉渐变 · 温暖治愈',
    preview: ['#F2C3B1', '#F6EEEB', '#FFF5F0'],
    theme: {
      primary: '#E8936A',
      primaryDark: '#CE7A52',
      secondary: '#C79B8E',
      accent: '#E8936A',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#C79B8E',

      bgDark: '#F2C3B1',
      bgCard: '#FDF8F5',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FDF8F5',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FDF8F5',

      textPrimary: '#5A4438',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#E8936A',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(200, 140, 110, 0.18)',
      cardShadowRadius: 14,
      progressTrack: '#F5E9E0',
      chartColors: ['#E8936A', '#00A84D', '#E6A800', '#C79B8E', '#8B7CF6'],
      accentSoft: '#FBE9DF',
      pageGradient: [['#F2C3B1', 0], ['#F5DCD3', 0.5], ['#F6EEEB', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'mint',
    name: '薄荷青',
    desc: '清新治愈 · 呼吸感',
    preview: ['#E4F3EE', '#2FBFA8', '#FFFFFF'],
    theme: {
      primary: '#2FBFA8',
      primaryDark: '#25A38F',
      secondary: '#67C8B4',
      accent: '#2FBFA8',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#2FBFA8',

      bgDark: '#E4F3EE',
      bgCard: '#FAFFFD',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FAFFFD',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FAFFFD',

      textPrimary: '#22453D',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#2FBFA8',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(80, 160, 140, 0.16)',
      cardShadowRadius: 14,
      progressTrack: '#E3F1EC',
      chartColors: ['#2FBFA8', '#00A84D', '#E6A800', '#2FBFA8', '#5B4CC4'],
      accentSoft: '#E0F4EF',
      pageGradient: [['#E4F3EE', 0], ['#F0F9F5', 0.5], ['#EBF6F1', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'dusk',
    name: '暮紫',
    desc: '优雅静谧 · 科技感',
    preview: ['#EDE9F8', '#8B7CF6', '#FFFFFF'],
    theme: {
      primary: '#8B7CF6',
      primaryDark: '#7262E0',
      secondary: '#A99CF8',
      accent: '#8B7CF6',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#8B7CF6',

      bgDark: '#EDE9F8',
      bgCard: '#FDFCFF',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FDFCFF',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FDFCFF',

      textPrimary: '#3B3460',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#8B7CF6',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(120, 100, 220, 0.16)',
      cardShadowRadius: 14,
      progressTrack: '#ECE8F8',
      chartColors: ['#8B7CF6', '#00A84D', '#E6A800', '#8B7CF6', '#C79B9B'],
      accentSoft: '#EEEAFB',
      pageGradient: [['#EDE9F8', 0], ['#F6F3FC', 0.5], ['#F0EDFA', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'coral',
    name: '珊瑚',
    desc: '活力暖色 · 元气治愈',
    preview: ['#FFD9CE', '#FF7A6E', '#FFFBF9'],
    theme: {
      primary: '#FF7A6E',
      primaryDark: '#E5604F',
      secondary: '#F5A091',
      accent: '#FF7A6E',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#FF7A6E',

      bgDark: '#FFD9CE',
      bgCard: '#FFFBF9',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FFFBF9',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FFFBF9',

      textPrimary: '#5C3A33',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#FF7A6E',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(220, 120, 100, 0.18)',
      cardShadowRadius: 14,
      progressTrack: '#F7E8E4',
      chartColors: ['#FF7A6E', '#00A84D', '#E6A800', '#FF7A6E', '#8B7CF6'],
      accentSoft: '#FDEAE7',
      pageGradient: [['#FFD9CE', 0], ['#FFECE6', 0.5], ['#FFE3DC', 1]],
      material: SOLID_MATERIAL
    }
  },
  {
    id: 'steel',
    name: '黛青',
    desc: '沉稳冷色 · 商务专业',
    preview: ['#DCE8F4', '#4A7FB5', '#FFFFFF'],
    theme: {
      primary: '#4A7FB5',
      primaryDark: '#3A6796',
      secondary: '#7AA3C9',
      accent: '#4A7FB5',

      success: '#00A84D',
      warning: '#E6A800',
      danger: '#D93025',
      info: '#4A7FB5',

      bgDark: '#DCE8F4',
      bgCard: '#FFFFFF',
      bgCardHover: 'rgba(0, 0, 0, 0.05)',
      bgGlass: '#FFFFFF',
      bgGlassLight: 'rgba(0, 0, 0, 0.03)',
      bgCardSolid: '#FFFFFF',

      textPrimary: '#27344A',
      textSecondary: 'rgba(0, 0, 0, 0.6)',
      textTertiary: 'rgba(0, 0, 0, 0.38)',
      textAccent: '#4A7FB5',

      borderGlass: 'rgba(0, 0, 0, 0.08)',
      borderGlassFocus: 'rgba(0, 0, 0, 0.2)',

      cardShadow: 'rgba(90, 130, 170, 0.16)',
      cardShadowRadius: 14,
      progressTrack: '#E6EEF6',
      chartColors: ['#4A7FB5', '#00A84D', '#E6A800', '#4A7FB5', '#8B7CF6'],
      accentSoft: '#E7F0F9',
      pageGradient: [['#DCE8F4', 0], ['#EBF2F9', 0.5], ['#E3EDF6', 1]],
      material: SOLID_MATERIAL
    }
  }
]

/** 按 id 查找皮肤（不存在返回默认米色） */
export function getSkinById(id: string): SkinDef {
  for (let i = 0; i < SKINS.length; i++) {
    if (SKINS[i].id === id) {
      return SKINS[i]
    }
  }
  return SKINS[0]
}

// ============================================================================
// 材质派生值：页面统一用这三个函数画卡片，不要在页面里再写 rgba / 阴影常量
// ============================================================================

/** 卡片填充色：实色用 bgCard，液态玻璃用材质上层色 */
export function cardTint(p: ThemePalette): ResourceColor {
  return p.material.kind === 'liquid' ? p.material.tintTop : p.bgCard
}

/** 卡片描边：玻璃用镜面白描边（顶亮底暗），实色用皮肤描边色 */
export function cardBorder(p: ThemePalette): BorderOptions {
  if (p.material.kind === 'liquid') {
    return {
      width: { top: 1, right: 0.7, bottom: 0.7, left: 0.7 },
      color: {
        top: p.material.innerGlow,
        right: p.material.borderColor,
        bottom: p.material.bottomGlow,
        left: p.material.borderColor
      }
    }
  }
  return { width: 0.5, color: p.borderGlass }
}

/** 卡片浮起阴影（玻璃用更大、更低的投影，产生悬浮感） */
export function cardElevation(p: ThemePalette): ShadowOptions {
  return {
    radius: p.material.kind === 'liquid' ? p.material.elevation : p.cardShadowRadius,
    color: p.material.kind === 'liquid' ? p.material.elevationColor : p.cardShadow,
    offsetX: 0,
    offsetY: p.material.kind === 'liquid' ? p.material.elevationY : 4
  }
}

/** 卡片圆角（随材质：玻璃更大，控件更圆润） */
export function cardRadius(p: ThemePalette): number {
  return p.material.radiusCard
}

/**
 * 列表行/密集卡片的模糊半径：叠几十层页级模糊会掎帧，
 * 玻璃材质下降到控件级（blurControl），实色材质仍为 0。
 */
export function listCardBlur(p: ThemePalette): number {
  return p.material.kind === 'liquid' ? p.material.blurControl : 0
}

