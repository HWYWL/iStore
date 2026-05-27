/**
 * 样式常量定义
 * 统一管理项目中的颜色、尺寸、圆角、字体、动画等设计令牌
 * 所有 UI 组件应引用此类的常量，而非硬编码样式值
 */
export class StyleConstants {
  // ========== 主色调 ==========
  static readonly PRIMARY = '#00D4FF'       // 主题色（青蓝）
  static readonly PRIMARY_DARK = '#0099CC'   // 主题色（深色变体）
  static readonly SECONDARY = '#7B68EE'      // 辅助色（紫罗兰）
  static readonly ACCENT = '#00E5FF'         // 点缀色（亮青）

  // ========== 语义色 ==========
  static readonly SUCCESS = '#00E676'        // 成功/正常（绿色）
  static readonly WARNING = '#FFD740'         // 警告（琥珀色）
  static readonly DANGER = '#FF5252'          // 危险/错误（红色）
  static readonly INFO = '#448AFF'            // 信息（蓝色）

  // ========== 背景色 ==========
  static readonly BG_DARK = '#0A0E27'        // 深色背景主色调
  static readonly BG_CARD = 'rgba(255, 255, 255, 0.06)'      // 卡片背景（半透明）
  static readonly BG_CARD_HOVER = 'rgba(255, 255, 255, 0.12)' // 卡片悬停背景
  static readonly BG_GLASS = 'rgba(18, 22, 55, 0.7)'          // 毛玻璃效果背景
  static readonly BG_GLASS_LIGHT = 'rgba(255, 255, 255, 0.08)' // 浅色毛玻璃背景

  // ========== 文本颜色 ==========
  static readonly TEXT_PRIMARY = '#FFFFFF'                    // 主要文本（白色）
  static readonly TEXT_SECONDARY = 'rgba(255, 255, 255, 0.7)' // 次要文本（半透明白）
  static readonly TEXT_TERTIARY = 'rgba(255, 255, 255, 0.4)'  // 辅助文本（更淡的白）
  static readonly TEXT_ACCENT = '#00D4FF'                     // 强调文本（主题色）

  // ========== 边框颜色 ==========
  static readonly BORDER_GLASS = 'rgba(255, 255, 255, 0.1)'       // 毛玻璃边框
  static readonly BORDER_GLASS_FOCUS = 'rgba(255, 255, 255, 0.25)' // 聚焦状态边框

  // ========== 圆角 ==========
  static readonly RADIUS_SM = 8     // 小圆角（按钮、输入框）
  static readonly RADIUS_MD = 12    // 中圆角（小卡片）
  static readonly RADIUS_LG = 16    // 大圆角（大卡片）
  static readonly RADIUS_XL = 24    // 超大圆角（面板）
  static readonly RADIUS_FULL = 100 // 全圆角（胶囊按钮、圆形头像）

  // ========== 阴影 ==========
  static readonly CARD_SHADOW_RADIUS: number = 20   // 卡片阴影半径
  static readonly GLOW_SHADOW_RADIUS: number = 30   // 发光阴影半径

  // ========== 字体大小 ==========
  static readonly FONT_XS = 10    // 极小字体（标签、辅助信息）
  static readonly FONT_SM = 12    // 小字体（次要文本）
  static readonly FONT_MD = 14    // 中号字体（正文）
  static readonly FONT_LG = 16    // 大号字体（小标题）
  static readonly FONT_XL = 20    // 超大字体（标题）
  static readonly FONT_XXL = 28   // 特大字体（页面大标题）
  static readonly FONT_HERO = 40  // Hero 字体（关键数据展示）

  // ========== 布局尺寸 ==========
  static readonly NAV_BAR_HEIGHT = 64          // 导航栏高度
  static readonly BOTTOM_TAB_HEIGHT = 56       // 底部 Tab 栏高度

  // ========== 动画时长（毫秒） ==========
  static readonly ANIM_FAST = 200    // 快速动画（按钮反馈）
  static readonly ANIM_NORMAL = 300  // 普通动画（页面过渡）
  static readonly ANIM_SLOW = 500    // 慢速动画（复杂场景）

  // ========== 渐变色预设 ==========
  static readonly GRADIENT_PRIMARY: [string, string] = ['#00D4FF', '#7B68EE']  // 主题渐变（青→紫）
  static readonly GRADIENT_SUCCESS: [string, string] = ['#00E676', '#00B248']  // 成功渐变（浅绿→深绿）
  static readonly GRADIENT_WARNING: [string, string] = ['#FFD740', '#FF9100']  // 警告渐变（黄→橙）
  static readonly GRADIENT_DANGER: [string, string] = ['#FF5252', '#D32F2F']   // 危险渐变（浅红→深红）
  static readonly GRADIENT_BG: [string, string] = ['#0A0E27', '#1A1A4E']       // 背景渐变（深蓝→深紫蓝）
}
