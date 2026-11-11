/**
 * BrandColors —— 品牌与装饰色的唯一来源
 *
 * 这些颜色**刻意不随主题**：它们标识的是具体服务/插画（Docker 蓝、iStore 绿、
 * Jellyfin 紫、Immich 粉、成就徽章），换色板时不应该变。但字面量散落在几十个
 * 页面里同样是债，所以统一收敛到这里：
 * - 需要的品牌色从这里取，页面里不再写 `'#3B82F6'`
 * - 与"状态"有关的颜色请用 `theme.semantic.*`（危险/警告/成功/信息/中性）
 * - 与"主题"有关的颜色请用 `theme.*`（色板）或 `theme.material.*`（材质）
 *
 * 中性白（盖在有色底上的文字/图标）直接用框架的 `Color.White`，不必进这里。
 */
export class BrandColors {
  /** Docker / 通用服务蓝 */
  static readonly blue: string = '#3B82F6'
  /** 旧版服务蓝（应用图标底、链接） */
  static readonly blueSoft: string = '#448AFF'
  /** 工具行蓝（iStore 系） */
  static readonly sky: string = '#2E7BFF'
  /** iStore / 在线绿 */
  static readonly green: string = '#10B981'
  /** 亮绿（信号/速率提示） */
  static readonly greenBright: string = '#00E676'
  /** 深绿（评分通过） */
  static readonly greenDeep: string = '#00C853'
  /** Jellyfin / 紫 */
  static readonly violet: string = '#8B5CF6'
  /** 靛蓝（次要强调） */
  static readonly indigo: string = '#6366F1'
  /** Immich / 粉 */
  static readonly pink: string = '#EC4899'
  /** 成就 / 奖杯琥珀 */
  static readonly amber: string = '#F59E0B'
  /** SSH / 暖橙 */
  static readonly orange: string = '#F97316'
  /** 危险红（比主题 danger 更醒目，用于删除/离线告警） */
  static readonly red: string = '#FF5252'
  /** 危险红（备选，表单错误） */
  static readonly redAlt: string = '#EF4444'
  /** 中性灰蓝（次要说明文字） */
  static readonly slate: string = '#64748B'
  /** 中性浅灰（未激活/锁定） */
  static readonly slateLight: string = '#94A3B8'
  /** 中性深灰（正文弱化） */
  static readonly gray: string = '#6B7889'
  /** 沙色（小管家插画辅色） */
  static readonly sand: string = '#C9A98A'
  /** 米灰（插画阴影） */
  static readonly beige: string = '#B0A99A'
  /** 磁贴胶囊：绿 */
  static readonly chipGreen: string = '#22C55E'
  /** 磁贴胶囊：紫 */
  static readonly chipViolet: string = '#7A5CFF'
  /** 磁贴胶囊：青 */
  static readonly chipTeal: string = '#17B8A6'
  /** 磁贴胶囊：粉 */
  static readonly chipPink: string = '#FF5C8A'
  /** 磁贴胶囊：灰蓝 */
  static readonly chipSlate: string = '#8A94A6'
}
