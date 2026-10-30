# -*- coding: utf-8 -*-
"""
HarmonyOS 风格图标生成器（超椭圆底板 + 柔和渐变 + 玻璃微光 + 白色前景）

规格
  画布      64 x 64，安全区 56 x 56
  底板      连续曲率超椭圆（|x|^p + |y|^p = 1，p = 5），非普通圆角矩形
  渐变      linearGradient 0,0 -> 1,1（135°），两端色取 PALETTES
  玻璃光    白色 radialGradient(0.5 -> 0) 椭圆，圆心偏左上，clipPath 裁进底板
  前景      纯白不透明，线宽 3.6（64 画布），圆头圆角
  投影      交给 ArkUI 用同色系 rgba 落地（SVG 内不做黑色投影）
  暗色      渐变两端压暗 15%，玻璃光透明度减半，投影 alpha 由调用方提到 .45

输出
  ic_hos_<name>.svg        浅色
  ic_hos_dark_<name>.svg   暗色
"""
import os
import re
import math

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.abspath(os.path.join(HERE, '../../store/src/main/resources/base/media'))
OUT_DIR = SRC_DIR

SIZE = 64
PLATE = 56          # 底板边长
CX = CY = SIZE / 2
P_EXP = 5           # 超椭圆指数
GLYPH_BOX = 34      # 前景符号占据的边长
GLYPH_STROKE = 3.6  # 64 画布下的线宽

# 8 组底板渐变（起点色, 终点色）
PALETTES = [
    ('#4A9BFF', '#2E6BF0'),
    ('#48D0FF', '#2E7BF6'),
    ('#FFB05C', '#F2761D'),
    ('#5FE0A8', '#16A877'),
    ('#7AEBD0', '#1FB28F'),
    ('#FF9AC4', '#B95FD6'),
    ('#FF9183', '#F0483E'),
    ('#8B93FF', '#4A46D6'),
]


def squircle_path(cx, cy, size, exp=5, samples=120):
    """生成 |x|^exp + |y|^exp = 1 的超椭圆路径（相对圆心、半边长 a）"""
    a = size / 2.0
    pts = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        ct, st = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(ct) ** (2.0 / exp), ct)
        y = a * math.copysign(abs(st) ** (2.0 / exp), st)
        pts.append((cx + x, cy + y))
    d = 'M' + ' L'.join('%.2f %.2f' % p for p in pts) + ' Z'
    return d


def darken(hex_color, factor=0.85):
    h = hex_color.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return '#%02X%02X%02X' % (int(r * factor), int(g * factor), int(b * factor))


def pick_palette(name):
    h = 7
    for ch in name:
        h = (h * 17 + ord(ch)) % 100003
    return PALETTES[h % len(PALETTES)]


def extract_children(svg_text):
    """取出 ic_line_*.svg 里的图形元素（去掉根标签与 xml 声明）"""
    body = re.sub(r'^.*?<svg[^>]*>', '', svg_text, flags=re.S)
    body = body.replace('</svg>', '')
    # 每个元素一行，保留顺序用于分层透明度
    elems = re.findall(r'<(?:path|circle|line|rect|polyline|polygon|ellipse)\b[^>]*/>', body)
    return elems


def build_svg(name, elems, dark):
    start, end = pick_palette(name)
    if dark:
        start, end = darken(start), darken(end)
    glass_alpha = 0.25 if dark else 0.5

    plate = squircle_path(CX, CY, PLATE, P_EXP)
    glyph_scale = GLYPH_BOX / 24.0
    offset = (SIZE - GLYPH_BOX) / 2.0
    stroke_in_group = GLYPH_STROKE / glyph_scale

    # 前景统一纯白 1.0：自动分档会把「两只眼睛」「二维码模块」这类
    # 同级元素排成不同深浅，反而不对称，鸿蒙原生图标本身也是扁平纯色
    out_glyph = []
    for el in elems:
        el = el.replace('fill="#000000"', 'fill="#FFFFFF"')
        el = el.replace('stroke="#000000"', 'stroke="#FFFFFF"')
        out_glyph.append('    ' + el)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{start}"/>
      <stop offset="1" stop-color="{end}"/>
    </linearGradient>
    <radialGradient id="h" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{glass_alpha}"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="c">
      <path d="{plate}"/>
    </clipPath>
  </defs>
  <g clip-path="url(#c)">
    <path d="{plate}" fill="url(#g)"/>
    <ellipse cx="24" cy="17" rx="30" ry="22" fill="url(#h)"/>
  </g>
  <g transform="translate({offset:.2f} {offset:.2f}) scale({glyph_scale:.4f})"
     fill="none" stroke="#FFFFFF" stroke-width="{stroke_in_group:.3f}"
     stroke-linecap="round" stroke-linejoin="round">
{chr(10).join(out_glyph)}
  </g>
</svg>
'''


def main():
    names = []
    for fn in sorted(os.listdir(SRC_DIR)):
        if fn.startswith('ic_line_') and fn.endswith('.svg'):
            names.append(fn[len('ic_line_'):-len('.svg')])

    count = 0
    for key in names:
        src_path = os.path.join(SRC_DIR, 'ic_line_%s.svg' % key)
        with open(src_path, 'r', encoding='utf-8') as f:
            elems = extract_children(f.read())
        if not elems:
            print('  skip (no shapes): %s' % key)
            continue
        # 图标名用原始大小写（与 IconPack 的键一致）
        for dark in (False, True):
            suffix = '_dark' if dark else ''
            out_name = 'ic_hos%s_%s.svg' % (suffix, key)
            with open(os.path.join(OUT_DIR, out_name), 'w', encoding='utf-8', newline='\n') as f:
                f.write(build_svg(key, elems, dark))
            count += 1
    print('generated %d files from %d glyphs' % (count, len(names)))


if __name__ == '__main__':
    main()
