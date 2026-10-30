# -*- coding: utf-8 -*-
"""
彩色图标配色表

每个图标一个主色（亮 → 深 做渐变），造型沿用 defs.py 的几何：
  闭合轮廓填主色，落在轮廓里的细节线挖成白色（= 镂空），
  暴露在轮廓外的线条用主色描边。
这样出来的是 iOS / Material Filled 那种「图标自己带颜色」的样子，
外面不再套任何圆底或方块底。
"""

# name(lower) -> (亮色, 深色)
COLORS = {
    # ---------------- 文件 / 存储：蓝
    'folder': ('#5AA9FF', '#2563EB'),
    'doc_text': ('#6FB6FF', '#2F6FDB'),
    'tray': ('#5AA9FF', '#2563EB'),
    'externaldrive': ('#63B3FF', '#1D4ED8'),
    'archivebox': ('#4FA0FF', '#1E5FD0'),
    'rectangle_stack': ('#6FB6FF', '#2F6FDB'),
    'square_stack_3d': ('#3FD3E6', '#0E7490'),
    'qrcode': ('#5AA9FF', '#1E5FD0'),

    # ---------------- 开发 / 工具：靛紫
    'code_square': ('#7C9CFF', '#4338CA'),
    'gearshape': ('#8FA8FF', '#4C51BF'),
    'cpu': ('#8FA8FF', '#4338CA'),
    'cpu_alt': ('#8FA8FF', '#4338CA'),
    'terminal': ('#7C9CFF', '#3730A3'),
    'wrench': ('#8FA8FF', '#4C51BF'),

    # ---------------- 网络 / 连接：青蓝
    'wifi': ('#56B8FF', '#1D6FE0'),
    'wifi_router': ('#56B8FF', '#1D6FE0'),
    'globe_badge_message': ('#4FB8F5', '#1868C9'),
    'network': ('#4FB8F5', '#1868C9'),
    'link': ('#4FB8F5', '#1868C9'),
    'arrow_up_right': ('#FFC63D', '#D97706'),
    'arrow_up_and_down_square_portrait': ('#5AC8FA', '#0E7490'),
    'arrow_clockwise_alt': ('#56B8FF', '#1D6FE0'),
    'arrow_counterclockwise': ('#56B8FF', '#1D6FE0'),
    'arrow_left_arrow_right': ('#5AC8FA', '#0E7490'),
    'dot_radiowaves_left_and_right': ('#56B8FF', '#1D6FE0'),

    # ---------------- 安全 / 健康：绿
    'security_shield': ('#4ADE80', '#16A34A'),
    'person_shield': ('#52D98E', '#15803D'),
    'staroflife': ('#4ADE80', '#059669'),
    'checkmark_shield': ('#4ADE80', '#16A34A'),

    # ---------------- 媒体 / 相册：粉
    'ohos_photo': ('#FF8FB8', '#DB2777'),
    'movie': ('#FF8FB8', '#BE185D'),
    'music_note': ('#FF9BC2', '#DB2777'),
    'speaker': ('#FF9BC2', '#BE185D'),
    'speaker_wave_1': ('#FF9BC2', '#BE185D'),
    'play_circle': ('#FF9BC2', '#BE185D'),
    'media_center': ('#FF8FB8', '#BE185D'),

    # ---------------- 应用 / 商店：橙
    'square_grid_2x2': ('#FFA45C', '#EA580C'),
    'bag': ('#FF8A5B', '#E0452C'),
    'square_grid_3x1_below_line_grid_1x2': ('#FFA45C', '#EA580C'),
    'circle_grid_2x2': ('#FFA45C', '#EA580C'),
    'template_fill': ('#FFB067', '#D97706'),
    'wand_and_stars': ('#FFB067', '#C2410C'),

    # ---------------- AI / 助手：紫
    'ai_help_write': ('#B18CFF', '#7C3AED'),
    'lightbulb': ('#FFC63D', '#D97706'),
    'face_smiling': ('#FFC63D', '#D97706'),
    'heart': ('#FF8FB8', '#DB2777'),

    # ---------------- 数据 / 排行：黄
    'chart': ('#FFC63D', '#D97706'),
    'list_square_bill': ('#FFC63D', '#B45309'),
    'yuansign_moneybag': ('#FFC63D', '#B45309'),
    'gauge_with_dots_needle_33percent': ('#FFC63D', '#D97706'),
    'waveform': ('#5AC8FA', '#0E7490'),

    # ---------------- 徽章 / 成就：金
    'medal': ('#FFD166', '#C27803'),
    'star_trophy': ('#FFD166', '#C27803'),
    'crown': ('#FFD166', '#B45309'),
    'flag': ('#FFA45C', '#EA580C'),
    'book': ('#8FA8FF', '#4C51BF'),
    'diary': ('#8FA8FF', '#4C51BF'),
    'calendar': ('#FFA45C', '#EA580C'),
    'clock': ('#FFC63D', '#D97706'),

    # ---------------- 通知 / 社交
    'bell': ('#FFB067', '#D97706'),
    'message': ('#56B8FF', '#1D6FE0'),
    'share': ('#56B8FF', '#1D6FE0'),
    'person': ('#8FA8FF', '#4C51BF'),
    'person_2': ('#8FA8FF', '#4C51BF'),

    # ---------------- 其它
    'bolt': ('#FFC63D', '#D97706'),
    'flame': ('#FF8A5B', '#E0452C'),
    'drop': ('#56B8FF', '#1D6FE0'),
    'house': ('#FFA45C', '#EA580C'),
    'cloud': ('#7FD4FF', '#1D6FE0'),
    'fish': ('#56B8FF', '#1868C9'),
    'shirt': ('#FF9BC2', '#DB2777'),
    'fork_knife': ('#FFA45C', '#EA580C'),
    'game_controller': ('#B18CFF', '#7C3AED'),
    'tag': ('#FFA45C', '#EA580C'),
    'label': ('#FFA45C', '#EA580C'),
    'paintbrush': ('#B18CFF', '#7C3AED'),
    'xmark_circle': ('#FF8A8A', '#DC2626'),
    'info_circle': ('#56B8FF', '#1D6FE0'),
    'question_circle': ('#56B8FF', '#1D6FE0'),
    'magnifyingglass': ('#8FA8FF', '#4C51BF'),
    'plus_circle': ('#4ADE80', '#16A34A'),
    'trash': ('#FF8A8A', '#DC2626'),
    'hand_tap': ('#FFA45C', '#EA580C'),
    'sun_max': ('#FFC63D', '#D97706'),
}

DEFAULT = ('#8FA8FF', '#4C51BF')


def color_of(name):
    return COLORS.get(name.lower(), DEFAULT)
