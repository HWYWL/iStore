/**
 * 主题色彩系统
 * 实现深色/浅色双主题切换，通过 ThemePalette 接口统一管理
 * 组件通过 AppState 获取当前主题，切换时自动更新所有引用了 @State theme 的组件
 */

/**
 * 主题调色板接口
 * 定义深色/浅色双主题所需的全部颜色属性
 * 组件使用 this.theme.xxx 引用，无需硬编码颜色值
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
  bgCard: string            // 卡片背景（半透明）
  bgCardHover: string       // 卡片悬停/按下背景
  bgGlass: string           // 毛玻璃面板背景
  bgGlassLight: string      // 浅色毛玻璃背景

  // --- 文本颜色 ---
  textPrimary: string       // 主要文本（标题、正文）
  textSecondary: string     // 次要文本（描述、标签）
  textTertiary: string      // 辅助文本（时间戳、次要标签）
  textAccent: string        // 强调文本（数值、高亮关键词）

  // --- 边框颜色 ---
  borderGlass: string       // 毛玻璃边框（默认态）
  borderGlassFocus: string  // 毛玻璃边框（聚焦/悬停态）
}

/**
 * 深色主题调色板（默认主题）
 * 深蓝紫色调背景 + 高明度文本，营造科技感暗色界面
 */
export const DARK_THEME: ThemePalette = {
  primary: '#00D4FF',
  primaryDark: '#0099CC',
  secondary: '#7B68EE',
  accent: '#00E5FF',

  success: '#00E676',
  warning: '#FFD740',
  danger: '#FF5252',
  info: '#448AFF',

  bgDark: '#0A0E27',
  bgCard: 'rgba(255, 255, 255, 0.06)',
  bgCardHover: 'rgba(255, 255, 255, 0.12)',
  bgGlass: 'rgba(18, 22, 55, 0.7)',
  bgGlassLight: 'rgba(255, 255, 255, 0.08)',

  textPrimary: '#FFFFFF',
  textSecondary: 'rgba(255, 255, 255, 0.7)',
  textTertiary: 'rgba(255, 255, 255, 0.4)',
  textAccent: '#00D4FF',

  borderGlass: 'rgba(255, 255, 255, 0.1)',
  borderGlassFocus: 'rgba(255, 255, 255, 0.25)'
}

/**
 * 浅色主题调色板
 * 浅灰白色调背景 + 低明度文本，适合日间使用
 */
export const LIGHT_THEME: ThemePalette = {
  primary: '#0077CC',
  primaryDark: '#005599',
  secondary: '#5B4CC4',
  accent: '#0099CC',

  success: '#00A84D',
  warning: '#E6A800',
  danger: '#D93025',
  info: '#1A73E8',

  bgDark: '#F0F2F5',
  bgCard: 'rgba(0, 0, 0, 0.03)',
  bgCardHover: 'rgba(0, 0, 0, 0.06)',
  bgGlass: 'rgba(255, 255, 255, 0.85)',
  bgGlassLight: 'rgba(0, 0, 0, 0.03)',

  textPrimary: '#1F1F1F',
  textSecondary: 'rgba(0, 0, 0, 0.6)',
  textTertiary: 'rgba(0, 0, 0, 0.35)',
  textAccent: '#0077CC',

  borderGlass: 'rgba(0, 0, 0, 0.08)',
  borderGlassFocus: 'rgba(0, 0, 0, 0.2)'
}

/**
 * 页面渐变背景色预设
 * 用于 build() 中的 .linearGradient() 背景
 * 深色模式：深蓝 → 中蓝紫 → 深蓝（三段式渐变）
 * 浅色模式：浅灰蓝 → 近白 → 浅灰蓝（三段式渐变）
 */
export const DARK_GRADIENT_START = '#0A0E27'
export const DARK_GRADIENT_MID = '#121637'
export const DARK_GRADIENT_END = '#0A0E27'

export const LIGHT_GRADIENT_START = '#E8ECF1'
export const LIGHT_GRADIENT_MID = '#F5F7FA'
export const LIGHT_GRADIENT_END = '#E8ECF1'
