/**
 * IconPack - 图标包资源表
 *
 * 全应用图标统一通过 AppIcon({ name: 'xxx' }) 渲染，name 为下方资源表的键。
 * 说明：$r() 是编译期资源，无法用字符串动态拼接，因此这里维护「图标名 -> 资源」静态表。
 *
 * 当前提供五套图标包，默认「鸿蒙质感」：
 * - hos：鸿蒙超椭圆素材（浅色 / 暗色两套）
 * - color：彩色实心渐变素材
 * - line：自绘几何线稿
 * - harmony：系统符号多色渲染
 * - ios：圆角底 + 白色图形
 */

/**
 * 图标包渲染类型
 * - hos：Image 渲染鸿蒙超椭圆素材（默认）
 * - image：Image 渲染彩色实心素材
 * - line：Image 渲染自绘几何线稿（单色可着色）
 * - harmony：SymbolGlyph 原生多色渲染（HarmonyOS 设计语言）
 * - ios：彩色圆角方块底 + 白色图形（iOS 主屏图标观感）
 */
export type IconPackKind = 'hos' | 'image' | 'line' | 'harmony' | 'ios'

/** 图标包定义 */
export interface IconPackDef {
  id: string
  name: string
  desc: string
  kind: IconPackKind
  preview: string[]
}

/** 图标包注册表 */
export const ICON_PACKS: IconPackDef[] = [
  {
    id: 'hos',
    name: '鸿蒙质感',
    desc: '超椭圆 · 玻璃微光',
    kind: 'hos',
    preview: ['gearshape', 'wifi', 'house']
  },
  {
    id: 'color',
    name: '彩色实心',
    desc: '渐变实色 · 饱满鲜明',
    kind: 'image',
    preview: ['gearshape', 'wifi', 'house']
  },
  {
    id: 'line',
    name: '几何线稿',
    desc: '自绘线稿 · 规整几何',
    kind: 'line',
    preview: ['gearshape', 'wifi', 'house']
  },
  {
    id: 'harmony',
    name: '鸿蒙多彩',
    desc: '系统符号 · 原生多色',
    kind: 'harmony',
    preview: ['gearshape', 'wifi', 'house']
  },
  {
    id: 'ios',
    name: 'iOS 方块',
    desc: '圆角底 · 白色图形',
    kind: 'ios',
    preview: ['gearshape', 'wifi', 'house']
  }
]

/** 默认图标包：鸿蒙质感 */
export const DEFAULT_ICON_PACK: string = 'hos'

/**
 * 鸿蒙多彩图标的分层调色板（主色 / 次色 / 高光）
 * MULTIPLE_COLOR 渲染依赖 fontColor 提供多色，只给一个颜色会退化为单色
 */
export const HARMONY_COLORS: string[] = ['#0A59F7', '#3FB1FF', '#8FD6FF']

/** 图标名 -> 彩色实心素材 */
const COLOR_MEDIA: Record<string, Resource> = {
  'AI_help_write': $r('app.media.ic_color_ai_help_write'),
  'archivebox': $r('app.media.ic_color_archivebox'),
  'arrow_clockwise': $r('app.media.ic_color_arrow_clockwise'),
  'arrow_counterclockwise': $r('app.media.ic_color_arrow_counterclockwise'),
  'arrow_down': $r('app.media.ic_color_arrow_down'),
  'arrow_left_arrow_right': $r('app.media.ic_color_arrow_left_arrow_right'),
  'arrow_up_and_down_square_portrait': $r('app.media.ic_color_arrow_up_and_down_square_portrait'),
  'arrow_up_right': $r('app.media.ic_color_arrow_up_right'),
  'bag': $r('app.media.ic_color_bag'),
  'battery': $r('app.media.ic_color_battery'),
  'bell': $r('app.media.ic_color_bell'),
  'bolt': $r('app.media.ic_color_bolt'),
  'book': $r('app.media.ic_color_book'),
  'calendar': $r('app.media.ic_color_calendar'),
  'camera': $r('app.media.ic_color_camera'),
  'card_package': $r('app.media.ic_color_card_package'),
  'checkmark_circle': $r('app.media.ic_color_checkmark_circle'),
  'circle_grid_2x2': $r('app.media.ic_color_circle_grid_2x2'),
  'clock': $r('app.media.ic_color_clock'),
  'cloud': $r('app.media.ic_color_cloud'),
  'code_square': $r('app.media.ic_color_code_square'),
  'crown': $r('app.media.ic_color_crown'),
  'display': $r('app.media.ic_color_display'),
  'doc_plaintext': $r('app.media.ic_color_doc_plaintext'),
  'doc_text': $r('app.media.ic_color_doc_text'),
  'doc_zipper': $r('app.media.ic_color_doc_zipper'),
  'dot_radiowaves_left_and_right': $r('app.media.ic_color_dot_radiowaves_left_and_right'),
  'download': $r('app.media.ic_color_download'),
  'externaldrive': $r('app.media.ic_color_externaldrive'),
  'eye_slash': $r('app.media.ic_color_eye_slash'),
  'face_smiling': $r('app.media.ic_color_face_smiling'),
  'film': $r('app.media.ic_color_film'),
  'fish': $r('app.media.ic_color_fish'),
  'flag': $r('app.media.ic_color_flag'),
  'flame': $r('app.media.ic_color_flame'),
  'folder': $r('app.media.ic_color_folder'),
  'fork_knife': $r('app.media.ic_color_fork_knife'),
  'gauge_with_dots_needle_33percent': $r('app.media.ic_color_gauge_with_dots_needle_33percent'),
  'gearshape': $r('app.media.ic_color_gearshape'),
  'globe_badge_message': $r('app.media.ic_color_globe_badge_message'),
  'hand_tap': $r('app.media.ic_color_hand_tap'),
  'heart': $r('app.media.ic_color_heart'),
  'house': $r('app.media.ic_color_house'),
  'info_circle': $r('app.media.ic_color_info_circle'),
  'label': $r('app.media.ic_color_label'),
  'lightbulb': $r('app.media.ic_color_lightbulb'),
  'link': $r('app.media.ic_color_link'),
  'list_bullet': $r('app.media.ic_color_list_bullet'),
  'list_square_bill': $r('app.media.ic_color_list_square_bill'),
  'lock': $r('app.media.ic_color_lock'),
  'lock_open': $r('app.media.ic_color_lock_open'),
  'magnifyingglass': $r('app.media.ic_color_magnifyingglass'),
  'medal': $r('app.media.ic_color_medal'),
  'media_center': $r('app.media.ic_color_media_center'),
  'message': $r('app.media.ic_color_message'),
  'moon': $r('app.media.ic_color_moon'),
  'movie': $r('app.media.ic_color_movie'),
  'ohos_photo': $r('app.media.ic_color_ohos_photo'),
  'paintbrush': $r('app.media.ic_color_paintbrush'),
  'pause_fill': $r('app.media.ic_color_pause_fill'),
  'person_2': $r('app.media.ic_color_person_2'),
  'person_3': $r('app.media.ic_color_person_3'),
  'person_shield': $r('app.media.ic_color_person_shield'),
  'phone': $r('app.media.ic_color_phone'),
  'pin': $r('app.media.ic_color_pin'),
  'play_circle': $r('app.media.ic_color_play_circle'),
  'play_circle_fill': $r('app.media.ic_color_play_circle_fill'),
  'plus_circle': $r('app.media.ic_color_plus_circle'),
  'power': $r('app.media.ic_color_power'),
  'printer': $r('app.media.ic_color_printer'),
  'qrcode': $r('app.media.ic_color_qrcode'),
  'rectangle_on_rectangle': $r('app.media.ic_color_rectangle_on_rectangle'),
  'rectangle_stack': $r('app.media.ic_color_rectangle_stack'),
  'security_shield': $r('app.media.ic_color_security_shield'),
  'share': $r('app.media.ic_color_share'),
  'shirt': $r('app.media.ic_color_shirt'),
  'speaker': $r('app.media.ic_color_speaker'),
  'speaker_wave_1': $r('app.media.ic_color_speaker_wave_1'),
  'square_grid_2x2': $r('app.media.ic_color_square_grid_2x2'),
  'square_grid_3x1_below_line_grid_1x2': $r('app.media.ic_color_square_grid_3x1_below_line_grid_1x2'),
  'square_stack_3d': $r('app.media.ic_color_square_stack_3d'),
  'star': $r('app.media.ic_color_star'),
  'star_trophy': $r('app.media.ic_color_star_trophy'),
  'staroflife': $r('app.media.ic_color_staroflife'),
  'sun_max': $r('app.media.ic_color_sun_max'),
  'template_fill': $r('app.media.ic_color_template_fill'),
  'thermometer': $r('app.media.ic_color_thermometer'),
  'wand_and_stars': $r('app.media.ic_color_wand_and_stars'),
  'warning': $r('app.media.ic_color_warning'),
  'watch': $r('app.media.ic_color_watch'),
  'waveform': $r('app.media.ic_color_waveform'),
  'wifi': $r('app.media.ic_color_wifi'),
  'wifi_router': $r('app.media.ic_color_wifi_router'),
  'xmark': $r('app.media.ic_color_xmark'),
  'xmark_circle': $r('app.media.ic_color_xmark_circle'),
  'yuansign_moneybag': $r('app.media.ic_color_yuansign_moneybag')
}

/** 图标名 -> 几何线稿素材（自绘线稿，单色可着色） */
const LINE_MEDIA: Record<string, Resource> = {
  'ai_help_write': $r('app.media.ic_line_ai_help_write'),
  'archivebox': $r('app.media.ic_line_archivebox'),
  'arrow_clockwise': $r('app.media.ic_line_arrow_clockwise'),
  'arrow_counterclockwise': $r('app.media.ic_line_arrow_counterclockwise'),
  'arrow_down': $r('app.media.ic_line_arrow_down'),
  'arrow_left_arrow_right': $r('app.media.ic_line_arrow_left_arrow_right'),
  'arrow_up_and_down_square_portrait': $r('app.media.ic_line_arrow_up_and_down_square_portrait'),
  'arrow_up_right': $r('app.media.ic_line_arrow_up_right'),
  'bag': $r('app.media.ic_line_bag'),
  'battery': $r('app.media.ic_line_battery'),
  'bell': $r('app.media.ic_line_bell'),
  'bolt': $r('app.media.ic_line_bolt'),
  'book': $r('app.media.ic_line_book'),
  'calendar': $r('app.media.ic_line_calendar'),
  'camera': $r('app.media.ic_line_camera'),
  'card_package': $r('app.media.ic_line_card_package'),
  'checkmark_circle': $r('app.media.ic_line_checkmark_circle'),
  'circle_grid_2x2': $r('app.media.ic_line_circle_grid_2x2'),
  'clock': $r('app.media.ic_line_clock'),
  'cloud': $r('app.media.ic_line_cloud'),
  'code_square': $r('app.media.ic_line_code_square'),
  'crown': $r('app.media.ic_line_crown'),
  'display': $r('app.media.ic_line_display'),
  'doc_plaintext': $r('app.media.ic_line_doc_plaintext'),
  'doc_text': $r('app.media.ic_line_doc_text'),
  'doc_zipper': $r('app.media.ic_line_doc_zipper'),
  'dot_radiowaves_left_and_right': $r('app.media.ic_line_dot_radiowaves_left_and_right'),
  'download': $r('app.media.ic_line_download'),
  'externaldrive': $r('app.media.ic_line_externaldrive'),
  'eye_slash': $r('app.media.ic_line_eye_slash'),
  'face_smiling': $r('app.media.ic_line_face_smiling'),
  'film': $r('app.media.ic_line_film'),
  'fish': $r('app.media.ic_line_fish'),
  'flag': $r('app.media.ic_line_flag'),
  'flame': $r('app.media.ic_line_flame'),
  'folder': $r('app.media.ic_line_folder'),
  'fork_knife': $r('app.media.ic_line_fork_knife'),
  'gauge_with_dots_needle_33percent': $r('app.media.ic_line_gauge_with_dots_needle_33percent'),
  'gearshape': $r('app.media.ic_line_gearshape'),
  'globe_badge_message': $r('app.media.ic_line_globe_badge_message'),
  'hand_tap': $r('app.media.ic_line_hand_tap'),
  'heart': $r('app.media.ic_line_heart'),
  'house': $r('app.media.ic_line_house'),
  'info_circle': $r('app.media.ic_line_info_circle'),
  'label': $r('app.media.ic_line_label'),
  'lightbulb': $r('app.media.ic_line_lightbulb'),
  'link': $r('app.media.ic_line_link'),
  'list_bullet': $r('app.media.ic_line_list_bullet'),
  'list_square_bill': $r('app.media.ic_line_list_square_bill'),
  'lock': $r('app.media.ic_line_lock'),
  'lock_open': $r('app.media.ic_line_lock_open'),
  'magnifyingglass': $r('app.media.ic_line_magnifyingglass'),
  'medal': $r('app.media.ic_line_medal'),
  'media_center': $r('app.media.ic_line_media_center'),
  'message': $r('app.media.ic_line_message'),
  'moon': $r('app.media.ic_line_moon'),
  'movie': $r('app.media.ic_line_movie'),
  'ohos_photo': $r('app.media.ic_line_ohos_photo'),
  'paintbrush': $r('app.media.ic_line_paintbrush'),
  'pause_fill': $r('app.media.ic_line_pause_fill'),
  'person_2': $r('app.media.ic_line_person_2'),
  'person_3': $r('app.media.ic_line_person_3'),
  'person_shield': $r('app.media.ic_line_person_shield'),
  'phone': $r('app.media.ic_line_phone'),
  'pin': $r('app.media.ic_line_pin'),
  'play_circle': $r('app.media.ic_line_play_circle'),
  'play_circle_fill': $r('app.media.ic_line_play_circle_fill'),
  'plus_circle': $r('app.media.ic_line_plus_circle'),
  'power': $r('app.media.ic_line_power'),
  'printer': $r('app.media.ic_line_printer'),
  'qrcode': $r('app.media.ic_line_qrcode'),
  'rectangle_on_rectangle': $r('app.media.ic_line_rectangle_on_rectangle'),
  'rectangle_stack': $r('app.media.ic_line_rectangle_stack'),
  'security_shield': $r('app.media.ic_line_security_shield'),
  'share': $r('app.media.ic_line_share'),
  'shirt': $r('app.media.ic_line_shirt'),
  'speaker': $r('app.media.ic_line_speaker'),
  'speaker_wave_1': $r('app.media.ic_line_speaker_wave_1'),
  'square_grid_2x2': $r('app.media.ic_line_square_grid_2x2'),
  'square_grid_3x1_below_line_grid_1x2': $r('app.media.ic_line_square_grid_3x1_below_line_grid_1x2'),
  'square_stack_3d': $r('app.media.ic_line_square_stack_3d'),
  'star': $r('app.media.ic_line_star'),
  'star_trophy': $r('app.media.ic_line_star_trophy'),
  'staroflife': $r('app.media.ic_line_staroflife'),
  'sun_max': $r('app.media.ic_line_sun_max'),
  'template_fill': $r('app.media.ic_line_template_fill'),
  'thermometer': $r('app.media.ic_line_thermometer'),
  'wand_and_stars': $r('app.media.ic_line_wand_and_stars'),
  'warning': $r('app.media.ic_line_warning'),
  'watch': $r('app.media.ic_line_watch'),
  'waveform': $r('app.media.ic_line_waveform'),
  'wifi': $r('app.media.ic_line_wifi'),
  'wifi_router': $r('app.media.ic_line_wifi_router'),
  'xmark': $r('app.media.ic_line_xmark'),
  'xmark_circle': $r('app.media.ic_line_xmark_circle'),
  'yuansign_moneybag': $r('app.media.ic_line_yuansign_moneybag')
}

/** 图标名 -> 鸿蒙超椭圆风格素材（浅色） */
const HOS_MEDIA: Record<string, Resource> = {
  'AI_help_write': $r('app.media.ic_hos_ai_help_write'),
  'archivebox': $r('app.media.ic_hos_archivebox'),
  'arrow_clockwise': $r('app.media.ic_hos_arrow_clockwise'),
  'arrow_counterclockwise': $r('app.media.ic_hos_arrow_counterclockwise'),
  'arrow_down': $r('app.media.ic_hos_arrow_down'),
  'arrow_left_arrow_right': $r('app.media.ic_hos_arrow_left_arrow_right'),
  'arrow_up_and_down_square_portrait': $r('app.media.ic_hos_arrow_up_and_down_square_portrait'),
  'arrow_up_right': $r('app.media.ic_hos_arrow_up_right'),
  'bag': $r('app.media.ic_hos_bag'),
  'battery': $r('app.media.ic_hos_battery'),
  'bell': $r('app.media.ic_hos_bell'),
  'bolt': $r('app.media.ic_hos_bolt'),
  'book': $r('app.media.ic_hos_book'),
  'calendar': $r('app.media.ic_hos_calendar'),
  'camera': $r('app.media.ic_hos_camera'),
  'card_package': $r('app.media.ic_hos_card_package'),
  'checkmark_circle': $r('app.media.ic_hos_checkmark_circle'),
  'circle_grid_2x2': $r('app.media.ic_hos_circle_grid_2x2'),
  'clock': $r('app.media.ic_hos_clock'),
  'cloud': $r('app.media.ic_hos_cloud'),
  'code_square': $r('app.media.ic_hos_code_square'),
  'crown': $r('app.media.ic_hos_crown'),
  'display': $r('app.media.ic_hos_display'),
  'doc_plaintext': $r('app.media.ic_hos_doc_plaintext'),
  'doc_text': $r('app.media.ic_hos_doc_text'),
  'doc_zipper': $r('app.media.ic_hos_doc_zipper'),
  'dot_radiowaves_left_and_right': $r('app.media.ic_hos_dot_radiowaves_left_and_right'),
  'download': $r('app.media.ic_hos_download'),
  'externaldrive': $r('app.media.ic_hos_externaldrive'),
  'eye_slash': $r('app.media.ic_hos_eye_slash'),
  'face_smiling': $r('app.media.ic_hos_face_smiling'),
  'film': $r('app.media.ic_hos_film'),
  'fish': $r('app.media.ic_hos_fish'),
  'flag': $r('app.media.ic_hos_flag'),
  'flame': $r('app.media.ic_hos_flame'),
  'folder': $r('app.media.ic_hos_folder'),
  'fork_knife': $r('app.media.ic_hos_fork_knife'),
  'gauge_with_dots_needle_33percent': $r('app.media.ic_hos_gauge_with_dots_needle_33percent'),
  'gearshape': $r('app.media.ic_hos_gearshape'),
  'globe_badge_message': $r('app.media.ic_hos_globe_badge_message'),
  'hand_tap': $r('app.media.ic_hos_hand_tap'),
  'heart': $r('app.media.ic_hos_heart'),
  'house': $r('app.media.ic_hos_house'),
  'info_circle': $r('app.media.ic_hos_info_circle'),
  'label': $r('app.media.ic_hos_label'),
  'lightbulb': $r('app.media.ic_hos_lightbulb'),
  'link': $r('app.media.ic_hos_link'),
  'list_bullet': $r('app.media.ic_hos_list_bullet'),
  'list_square_bill': $r('app.media.ic_hos_list_square_bill'),
  'lock': $r('app.media.ic_hos_lock'),
  'lock_open': $r('app.media.ic_hos_lock_open'),
  'magnifyingglass': $r('app.media.ic_hos_magnifyingglass'),
  'medal': $r('app.media.ic_hos_medal'),
  'media_center': $r('app.media.ic_hos_media_center'),
  'message': $r('app.media.ic_hos_message'),
  'moon': $r('app.media.ic_hos_moon'),
  'movie': $r('app.media.ic_hos_movie'),
  'ohos_photo': $r('app.media.ic_hos_ohos_photo'),
  'paintbrush': $r('app.media.ic_hos_paintbrush'),
  'pause_fill': $r('app.media.ic_hos_pause_fill'),
  'person_2': $r('app.media.ic_hos_person_2'),
  'person_3': $r('app.media.ic_hos_person_3'),
  'person_shield': $r('app.media.ic_hos_person_shield'),
  'phone': $r('app.media.ic_hos_phone'),
  'pin': $r('app.media.ic_hos_pin'),
  'play_circle': $r('app.media.ic_hos_play_circle'),
  'play_circle_fill': $r('app.media.ic_hos_play_circle_fill'),
  'plus_circle': $r('app.media.ic_hos_plus_circle'),
  'power': $r('app.media.ic_hos_power'),
  'printer': $r('app.media.ic_hos_printer'),
  'qrcode': $r('app.media.ic_hos_qrcode'),
  'rectangle_on_rectangle': $r('app.media.ic_hos_rectangle_on_rectangle'),
  'rectangle_stack': $r('app.media.ic_hos_rectangle_stack'),
  'security_shield': $r('app.media.ic_hos_security_shield'),
  'share': $r('app.media.ic_hos_share'),
  'shirt': $r('app.media.ic_hos_shirt'),
  'speaker': $r('app.media.ic_hos_speaker'),
  'speaker_wave_1': $r('app.media.ic_hos_speaker_wave_1'),
  'square_grid_2x2': $r('app.media.ic_hos_square_grid_2x2'),
  'square_grid_3x1_below_line_grid_1x2': $r('app.media.ic_hos_square_grid_3x1_below_line_grid_1x2'),
  'square_stack_3d': $r('app.media.ic_hos_square_stack_3d'),
  'star': $r('app.media.ic_hos_star'),
  'star_trophy': $r('app.media.ic_hos_star_trophy'),
  'staroflife': $r('app.media.ic_hos_staroflife'),
  'sun_max': $r('app.media.ic_hos_sun_max'),
  'template_fill': $r('app.media.ic_hos_template_fill'),
  'thermometer': $r('app.media.ic_hos_thermometer'),
  'wand_and_stars': $r('app.media.ic_hos_wand_and_stars'),
  'warning': $r('app.media.ic_hos_warning'),
  'watch': $r('app.media.ic_hos_watch'),
  'waveform': $r('app.media.ic_hos_waveform'),
  'wifi': $r('app.media.ic_hos_wifi'),
  'wifi_router': $r('app.media.ic_hos_wifi_router'),
  'xmark': $r('app.media.ic_hos_xmark'),
  'xmark_circle': $r('app.media.ic_hos_xmark_circle'),
  'yuansign_moneybag': $r('app.media.ic_hos_yuansign_moneybag')
}

/** 图标名 -> 鸿蒙超椭圆风格素材（暗色：渐变压暗 15%，玻璃光减半） */
const HOS_MEDIA_DARK: Record<string, Resource> = {
  'AI_help_write': $r('app.media.ic_hos_dark_ai_help_write'),
  'archivebox': $r('app.media.ic_hos_dark_archivebox'),
  'arrow_clockwise': $r('app.media.ic_hos_dark_arrow_clockwise'),
  'arrow_counterclockwise': $r('app.media.ic_hos_dark_arrow_counterclockwise'),
  'arrow_down': $r('app.media.ic_hos_dark_arrow_down'),
  'arrow_left_arrow_right': $r('app.media.ic_hos_dark_arrow_left_arrow_right'),
  'arrow_up_and_down_square_portrait': $r('app.media.ic_hos_dark_arrow_up_and_down_square_portrait'),
  'arrow_up_right': $r('app.media.ic_hos_dark_arrow_up_right'),
  'bag': $r('app.media.ic_hos_dark_bag'),
  'battery': $r('app.media.ic_hos_dark_battery'),
  'bell': $r('app.media.ic_hos_dark_bell'),
  'bolt': $r('app.media.ic_hos_dark_bolt'),
  'book': $r('app.media.ic_hos_dark_book'),
  'calendar': $r('app.media.ic_hos_dark_calendar'),
  'camera': $r('app.media.ic_hos_dark_camera'),
  'card_package': $r('app.media.ic_hos_dark_card_package'),
  'checkmark_circle': $r('app.media.ic_hos_dark_checkmark_circle'),
  'circle_grid_2x2': $r('app.media.ic_hos_dark_circle_grid_2x2'),
  'clock': $r('app.media.ic_hos_dark_clock'),
  'cloud': $r('app.media.ic_hos_dark_cloud'),
  'code_square': $r('app.media.ic_hos_dark_code_square'),
  'crown': $r('app.media.ic_hos_dark_crown'),
  'display': $r('app.media.ic_hos_dark_display'),
  'doc_plaintext': $r('app.media.ic_hos_dark_doc_plaintext'),
  'doc_text': $r('app.media.ic_hos_dark_doc_text'),
  'doc_zipper': $r('app.media.ic_hos_dark_doc_zipper'),
  'dot_radiowaves_left_and_right': $r('app.media.ic_hos_dark_dot_radiowaves_left_and_right'),
  'download': $r('app.media.ic_hos_dark_download'),
  'externaldrive': $r('app.media.ic_hos_dark_externaldrive'),
  'eye_slash': $r('app.media.ic_hos_dark_eye_slash'),
  'face_smiling': $r('app.media.ic_hos_dark_face_smiling'),
  'film': $r('app.media.ic_hos_dark_film'),
  'fish': $r('app.media.ic_hos_dark_fish'),
  'flag': $r('app.media.ic_hos_dark_flag'),
  'flame': $r('app.media.ic_hos_dark_flame'),
  'folder': $r('app.media.ic_hos_dark_folder'),
  'fork_knife': $r('app.media.ic_hos_dark_fork_knife'),
  'gauge_with_dots_needle_33percent': $r('app.media.ic_hos_dark_gauge_with_dots_needle_33percent'),
  'gearshape': $r('app.media.ic_hos_dark_gearshape'),
  'globe_badge_message': $r('app.media.ic_hos_dark_globe_badge_message'),
  'hand_tap': $r('app.media.ic_hos_dark_hand_tap'),
  'heart': $r('app.media.ic_hos_dark_heart'),
  'house': $r('app.media.ic_hos_dark_house'),
  'info_circle': $r('app.media.ic_hos_dark_info_circle'),
  'label': $r('app.media.ic_hos_dark_label'),
  'lightbulb': $r('app.media.ic_hos_dark_lightbulb'),
  'link': $r('app.media.ic_hos_dark_link'),
  'list_bullet': $r('app.media.ic_hos_dark_list_bullet'),
  'list_square_bill': $r('app.media.ic_hos_dark_list_square_bill'),
  'lock': $r('app.media.ic_hos_dark_lock'),
  'lock_open': $r('app.media.ic_hos_dark_lock_open'),
  'magnifyingglass': $r('app.media.ic_hos_dark_magnifyingglass'),
  'medal': $r('app.media.ic_hos_dark_medal'),
  'media_center': $r('app.media.ic_hos_dark_media_center'),
  'message': $r('app.media.ic_hos_dark_message'),
  'moon': $r('app.media.ic_hos_dark_moon'),
  'movie': $r('app.media.ic_hos_dark_movie'),
  'ohos_photo': $r('app.media.ic_hos_dark_ohos_photo'),
  'paintbrush': $r('app.media.ic_hos_dark_paintbrush'),
  'pause_fill': $r('app.media.ic_hos_dark_pause_fill'),
  'person_2': $r('app.media.ic_hos_dark_person_2'),
  'person_3': $r('app.media.ic_hos_dark_person_3'),
  'person_shield': $r('app.media.ic_hos_dark_person_shield'),
  'phone': $r('app.media.ic_hos_dark_phone'),
  'pin': $r('app.media.ic_hos_dark_pin'),
  'play_circle': $r('app.media.ic_hos_dark_play_circle'),
  'play_circle_fill': $r('app.media.ic_hos_dark_play_circle_fill'),
  'plus_circle': $r('app.media.ic_hos_dark_plus_circle'),
  'power': $r('app.media.ic_hos_dark_power'),
  'printer': $r('app.media.ic_hos_dark_printer'),
  'qrcode': $r('app.media.ic_hos_dark_qrcode'),
  'rectangle_on_rectangle': $r('app.media.ic_hos_dark_rectangle_on_rectangle'),
  'rectangle_stack': $r('app.media.ic_hos_dark_rectangle_stack'),
  'security_shield': $r('app.media.ic_hos_dark_security_shield'),
  'share': $r('app.media.ic_hos_dark_share'),
  'shirt': $r('app.media.ic_hos_dark_shirt'),
  'speaker': $r('app.media.ic_hos_dark_speaker'),
  'speaker_wave_1': $r('app.media.ic_hos_dark_speaker_wave_1'),
  'square_grid_2x2': $r('app.media.ic_hos_dark_square_grid_2x2'),
  'square_grid_3x1_below_line_grid_1x2': $r('app.media.ic_hos_dark_square_grid_3x1_below_line_grid_1x2'),
  'square_stack_3d': $r('app.media.ic_hos_dark_square_stack_3d'),
  'star': $r('app.media.ic_hos_dark_star'),
  'star_trophy': $r('app.media.ic_hos_dark_star_trophy'),
  'staroflife': $r('app.media.ic_hos_dark_staroflife'),
  'sun_max': $r('app.media.ic_hos_dark_sun_max'),
  'template_fill': $r('app.media.ic_hos_dark_template_fill'),
  'thermometer': $r('app.media.ic_hos_dark_thermometer'),
  'wand_and_stars': $r('app.media.ic_hos_dark_wand_and_stars'),
  'warning': $r('app.media.ic_hos_dark_warning'),
  'watch': $r('app.media.ic_hos_dark_watch'),
  'waveform': $r('app.media.ic_hos_dark_waveform'),
  'wifi': $r('app.media.ic_hos_dark_wifi'),
  'wifi_router': $r('app.media.ic_hos_dark_wifi_router'),
  'xmark': $r('app.media.ic_hos_dark_xmark'),
  'xmark_circle': $r('app.media.ic_hos_dark_xmark_circle'),
  'yuansign_moneybag': $r('app.media.ic_hos_dark_yuansign_moneybag')
}

/** 图标名 -> 系统符号资源 */
const SYMBOL_RES: Record<string, Resource> = {
  'AI_help_write': $r('sys.symbol.AI_help_write'),
  'archivebox': $r('sys.symbol.archivebox'),
  'arrow_clockwise': $r('sys.symbol.arrow_clockwise'),
  'arrow_counterclockwise': $r('sys.symbol.arrow_counterclockwise'),
  'arrow_down': $r('sys.symbol.arrow_down'),
  'arrow_left_arrow_right': $r('sys.symbol.arrow_left_arrow_right'),
  'arrow_up_and_down_square_portrait': $r('sys.symbol.arrow_up_and_down_square_portrait'),
  'arrow_up_right': $r('sys.symbol.arrow_up_right'),
  'bag': $r('sys.symbol.bag'),
  'battery': $r('sys.symbol.battery'),
  'bell': $r('sys.symbol.bell'),
  'bolt': $r('sys.symbol.bolt'),
  'book': $r('sys.symbol.book'),
  'calendar': $r('sys.symbol.calendar'),
  'camera': $r('sys.symbol.camera'),
  'card_package': $r('sys.symbol.card_package'),
  'checkmark_circle': $r('sys.symbol.checkmark_circle'),
  'circle_grid_2x2': $r('sys.symbol.circle_grid_2x2'),
  'clock': $r('sys.symbol.clock'),
  'cloud': $r('sys.symbol.cloud'),
  'code_square': $r('sys.symbol.code_square'),
  'crown': $r('sys.symbol.crown'),
  'display': $r('sys.symbol.display'),
  'doc_plaintext': $r('sys.symbol.doc_plaintext'),
  'doc_text': $r('sys.symbol.doc_text'),
  'doc_zipper': $r('sys.symbol.doc_zipper'),
  'dot_radiowaves_left_and_right': $r('sys.symbol.dot_radiowaves_left_and_right'),
  'download': $r('sys.symbol.download'),
  'externaldrive': $r('sys.symbol.externaldrive'),
  'eye_slash': $r('sys.symbol.eye_slash'),
  'face_smiling': $r('sys.symbol.face_smiling'),
  'film': $r('sys.symbol.film'),
  'fish': $r('sys.symbol.fish'),
  'flag': $r('sys.symbol.flag'),
  'flame': $r('sys.symbol.flame'),
  'folder': $r('sys.symbol.folder'),
  'fork_knife': $r('sys.symbol.fork_knife'),
  'gauge_with_dots_needle_33percent': $r('sys.symbol.gauge_with_dots_needle_33percent'),
  'gearshape': $r('sys.symbol.gearshape'),
  'globe_badge_message': $r('sys.symbol.globe_badge_message'),
  'hand_tap': $r('sys.symbol.hand_tap'),
  'heart': $r('sys.symbol.heart'),
  'house': $r('sys.symbol.house'),
  'info_circle': $r('sys.symbol.info_circle'),
  'label': $r('sys.symbol.label'),
  'lightbulb': $r('sys.symbol.lightbulb'),
  'link': $r('sys.symbol.link'),
  'list_bullet': $r('sys.symbol.list_bullet'),
  'list_square_bill': $r('sys.symbol.list_square_bill'),
  'lock': $r('sys.symbol.lock'),
  'lock_open': $r('sys.symbol.lock_open'),
  'magnifyingglass': $r('sys.symbol.magnifyingglass'),
  'medal': $r('sys.symbol.medal'),
  'media_center': $r('sys.symbol.media_center'),
  'message': $r('sys.symbol.message'),
  'moon': $r('sys.symbol.moon'),
  'movie': $r('sys.symbol.movie'),
  'ohos_photo': $r('sys.symbol.ohos_photo'),
  'paintbrush': $r('sys.symbol.paintbrush'),
  'pause_fill': $r('sys.symbol.pause_fill'),
  'person_2': $r('sys.symbol.person_2'),
  'person_3': $r('sys.symbol.person_3'),
  'person_shield': $r('sys.symbol.person_shield'),
  'phone': $r('sys.symbol.phone'),
  'pin': $r('sys.symbol.pin'),
  'play_circle': $r('sys.symbol.play_circle'),
  'play_circle_fill': $r('sys.symbol.play_circle_fill'),
  'plus_circle': $r('sys.symbol.plus_circle'),
  'power': $r('sys.symbol.power'),
  'printer': $r('sys.symbol.printer'),
  'qrcode': $r('sys.symbol.qrcode'),
  'rectangle_on_rectangle': $r('sys.symbol.rectangle_on_rectangle'),
  'rectangle_stack': $r('sys.symbol.rectangle_stack'),
  'security_shield': $r('sys.symbol.security_shield'),
  'share': $r('sys.symbol.share'),
  'shirt': $r('sys.symbol.shirt'),
  'speaker': $r('sys.symbol.speaker'),
  'speaker_wave_1': $r('sys.symbol.speaker_wave_1'),
  'square_grid_2x2': $r('sys.symbol.square_grid_2x2'),
  'square_grid_3x1_below_line_grid_1x2': $r('sys.symbol.square_grid_3x1_below_line_grid_1x2'),
  'square_stack_3d': $r('sys.symbol.square_stack_3d'),
  'star': $r('sys.symbol.star'),
  'star_trophy': $r('sys.symbol.star_trophy'),
  'staroflife': $r('sys.symbol.staroflife'),
  'sun_max': $r('sys.symbol.sun_max'),
  'template_fill': $r('sys.symbol.template_fill'),
  'thermometer': $r('sys.symbol.thermometer'),
  'wand_and_stars': $r('sys.symbol.wand_and_stars'),
  'warning': $r('sys.symbol.warning'),
  'watch': $r('sys.symbol.watch'),
  'waveform': $r('sys.symbol.waveform'),
  'wifi': $r('sys.symbol.wifi'),
  'wifi_router': $r('sys.symbol.wifi_router'),
  'xmark': $r('sys.symbol.xmark'),
  'xmark_circle': $r('sys.symbol.xmark_circle'),
  'yuansign_moneybag': $r('sys.symbol.yuansign_moneybag')
}

/** 按 id 查找图标包（不存在时返回默认包） */
export function getIconPackById(id: string): IconPackDef {
  for (let i = 0; i < ICON_PACKS.length; i++) {
    if (ICON_PACKS[i].id === id) {
      return ICON_PACKS[i]
    }
  }
  return ICON_PACKS[0]
}

/** 是否已有该图标的彩色实心素材 */
export function hasColorRes(name: string): boolean {
  return COLOR_MEDIA[name] !== undefined
}

/** 取彩色实心素材；调用前先用 hasColorRes 判断 */
export function getColorRes(name: string): Resource {
  const res: Resource | undefined = COLOR_MEDIA[name]
  return res !== undefined ? res : COLOR_MEDIA['info_circle']
}

/** 是否已有该图标的几何线稿素材 */
export function hasLineRes(name: string): boolean {
  return LINE_MEDIA[name] !== undefined
}

/** 取几何线稿素材；调用前先用 hasLineRes 判断 */
export function getLineRes(name: string): Resource {
  const res: Resource | undefined = LINE_MEDIA[name]
  return res !== undefined ? res : LINE_MEDIA['info_circle']
}

/** 取鸿蒙风格素材 */
export function getHosRes(name: string, dark: boolean): Resource {
  const table: Record<string, Resource> = dark ? HOS_MEDIA_DARK : HOS_MEDIA
  const res: Resource | undefined = table[name]
  if (res !== undefined) return res
  return dark ? HOS_MEDIA_DARK['info_circle'] : HOS_MEDIA['info_circle']
}

/** 取系统符号资源，未知 name 回退为 info_circle */
export function getSymbolRes(name: string): Resource {
  const res: Resource | undefined = SYMBOL_RES[name]
  return res !== undefined ? res : SYMBOL_RES['info_circle']
}

/** iOS 图标底色板：每项为「上浅下深」的同色系组合 */
const IOS_PALETTE: string[][] = [
  ['#0A84FF', '#0060DF'],
  ['#30D158', '#1FA84A'],
  ['#FF9F0A', '#E07B00'],
  ['#FF375F', '#D61B45'],
  ['#BF5AF2', '#9333D6'],
  ['#64D2FF', '#2AA9E0'],
  ['#5E5CE6', '#3B39C9'],
  ['#FF6482', '#E03B60']
]

/**
 * 按图标名稳定映射到一组 iOS 底色，保证同一图标每次都是同一个颜色
 * @param name 图标名
 * @returns [浅色端, 深色端]
 */
export function getIOSGradient(name: string): string[] {
  let h: number = 0
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) % 100000
  }
  const pair: string[] = IOS_PALETTE[h % IOS_PALETTE.length]
  return [pair[0], pair[1]]
}
