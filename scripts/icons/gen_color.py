# -*- coding: utf-8 -*-
"""
彩色图标生成器（第三套：ic_color_*）

造型沿用 defs.py 的同一份几何，只是换成「实心彩色」画法：

  主体闭合轮廓  ->  主色渐变填充（图标自己就是彩色的，没有外圈底座）
  轮廓内部的细节线 ->  白色描边（视觉上是镂空）
  露在轮廓外的线条 ->  主色描边 2.1px 圆头
  完全内部的小闭合形状 ->  白色填充（挖洞）

输出 24x24 透明背景，由 Image 直接按 40~44px 渲染。

用法：python scripts/icons/gen_color.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import defs
import colors

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__),
                                       '../../store/src/main/resources/base/media'))

CLOSED = ('rect', 'circle', 'polygon', 'frect', 'fpoly')
NUM_RE = re.compile(r'-?\d*\.?\d+')


def fnum(v):
    s = '%.2f' % v
    s = s.rstrip('0').rstrip('.')
    return s if s not in ('', '-0') else '0'


def is_closed(shape):
    kind, a = shape[0], shape[1]
    if kind in CLOSED:
        return True
    if kind == 'raw':
        return a.strip().upper().endswith('Z')
    if kind == 'dot':
        return True
    return False


def bbox(shape):
    """粗略包围盒，用于判断「谁在谁里面」，不需要精确轮廓"""
    kind, a = shape[0], shape[1]
    if kind in ('circle', 'dot'):
        cx, cy, r = a
        return (cx - r, cy - r, cx + r, cy + r)
    if kind in ('rect', 'frect'):
        x, y, w, h = a[0], a[1], a[2], a[3]
        return (x, y, x + w, y + h)
    if kind == 'line':
        x1, y1, x2, y2 = a
        return (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
    if kind in ('polyline', 'polygon', 'fpoly'):
        xs = [p[0] for p in a]
        ys = [p[1] for p in a]
        return (min(xs), min(ys), max(xs), max(ys))
    if kind == 'arc':
        cx, cy, r = a[0], a[1], a[2]
        return (cx - r, cy - r, cx + r, cy + r)
    if kind == 'raw':
        v = [float(x) for x in NUM_RE.findall(a)]
        xs = v[0::2]
        ys = v[1::2]
        if not xs or not ys:
            return (0, 0, 0, 0)
        return (min(xs), min(ys), max(xs), max(ys))
    return (0, 0, 0, 0)


def area(b):
    return max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])


def blend(c1, c2, t):
    """两个 #RRGGBB 之间插值，用于立体图的中间面"""
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return '#' + ''.join('%02X' % round(a[k] + (b[k] - a[k]) * t) for k in range(3))


def special_square_stack_3d(light, dark):
    """
    立方体：线稿版只有顶面能自动填充，侧面是一条条线，
    放在实心图标中间会显得空。这里直接按立体三面画。
    """
    mid = blend(light, dark, 0.5)
    return [
        f'<polygon points="3,7 12,11.5 12,21.5 3,16.5" fill="{dark}"/>',
        f'<polygon points="21,7 12,11.5 12,21.5 21,16.5" fill="{mid}"/>',
        f'<polygon points="12,2.5 21,7 12,11.5 3,7" fill="{light}"/>',
        '<path d="M3 7V16.5L12 21.5L21 16.5V7L12 2.5Z" fill="none" stroke="#FFFFFF" '
        'stroke-width="1.1" stroke-linejoin="round" opacity="0.9"/>',
        '<path d="M12 11.5V21.5" stroke="#FFFFFF" stroke-width="1.1" opacity="0.9"/>',
    ]


# 少数图标的线稿结构不适合自动实心化，单独给造型
SPECIAL = {
    'square_stack_3d': special_square_stack_3d,
}


def contains(outer, inner, tol=0.25):
    return (inner[0] >= outer[0] - tol and inner[1] >= outer[1] - tol and
            inner[2] <= outer[2] + tol and inner[3] <= outer[3] + tol)


# ---------------------------------------------------------------- 渲染

def paint(shape, fill_mode, light, dark):
    """fill_mode: 'solid' 主色填充 / 'white' 挖洞 / 'line' 主色描边 / 'white_line' 白描边"""
    kind, a = shape[0], shape[1]
    grad = 'url(#g)'

    if kind in ('rect', 'frect'):
        x, y, w, h, rx = (list(a) + [0])[:5]
        rxa = f' rx="{fnum(rx)}"' if rx else ''
        body = (f'<rect x="{fnum(x)}" y="{fnum(y)}" width="{fnum(w)}" '
                f'height="{fnum(h)}"{rxa}')
    elif kind in ('circle', 'dot'):
        cx, cy, r = a
        body = f'<circle cx="{fnum(cx)}" cy="{fnum(cy)}" r="{fnum(r)}"'
    elif kind == 'polygon' or kind == 'fpoly':
        pts = ' '.join(f'{fnum(x)},{fnum(y)}' for x, y in a)
        body = f'<polygon points="{pts}"'
    elif kind == 'line':
        x1, y1, x2, y2 = a
        body = (f'<line x1="{fnum(x1)}" y1="{fnum(y1)}" '
                f'x2="{fnum(x2)}" y2="{fnum(y2)}"')
    elif kind == 'polyline':
        pts = ' '.join(f'{fnum(x)},{fnum(y)}' for x, y in a)
        body = f'<polyline points="{pts}"'
    elif kind == 'arc':
        import gen
        d = gen.arc_path(a[0], a[1], a[2], a[3], a[4], False)
        body = f'<path d="{d}"'
    elif kind == 'raw':
        body = f'<path d="{a}"'
    else:
        raise ValueError(kind)

    if fill_mode == 'solid':
        return body + f' fill="{grad}"/>'
    if fill_mode == 'white':
        return body + ' fill="#FFFFFF"/>'
    if fill_mode == 'line':
        return (body + f' fill="none" stroke="{grad}" stroke-width="2.1" '
                       'stroke-linecap="round" stroke-linejoin="round"/>')
    if fill_mode == 'white_line':
        return (body + ' fill="none" stroke="#FFFFFF" stroke-width="1.75" '
                       'stroke-linecap="round" stroke-linejoin="round"/>')
    raise ValueError(fill_mode)


def build(name, shapes):
    light, dark = colors.color_of(name)

    key = name.lower()
    if key in SPECIAL:
        out = SPECIAL[key](light, dark)
        head = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
                'viewBox="0 0 24 24" fill="none">\n')
        return head + '  ' + '\n  '.join(out) + '\n</svg>\n'

    bbs = [bbox(s) for s in shapes]
    closed_idx = [i for i, s in enumerate(shapes) if is_closed(s)]

    # 主体 = 面积最大的闭合轮廓
    main = None
    if closed_idx:
        main = max(closed_idx, key=lambda i: area(bbs[i]))
    main_bb = bbs[main] if main is not None else None

    out = []
    for i, s in enumerate(shapes):
        bb = bbs[i]
        if i == main:
            out.append(paint(s, 'solid', light, dark))
            continue
        if is_closed(s):
            # 闭合形状：落在主体内部 -> 挖白洞；否则当作并列的主体填充
            if main_bb is not None and contains(main_bb, bb):
                out.append(paint(s, 'white', light, dark))
            else:
                out.append(paint(s, 'solid', light, dark))
            continue
        # 开放线条：在主体内部 -> 白镂空；否则主色
        if main_bb is not None and contains(main_bb, bb):
            out.append(paint(s, 'white_line', light, dark))
        else:
            out.append(paint(s, 'line', light, dark))

    # 必须用 userSpaceOnUse：纯垂直/水平线条的包围盒有一维为 0，
    # objectBoundingBox 渐变在这种元素上无效，整条线会直接不渲染
    head = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
            'viewBox="0 0 24 24" fill="none">\n'
            '  <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" '
            'x1="3" y1="3" x2="21" y2="21">'
            f'<stop offset="0" stop-color="{light}"/>'
            f'<stop offset="1" stop-color="{dark}"/></linearGradient></defs>')
    return head + '\n  ' + '\n  '.join(out) + '\n</svg>\n'


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    n = 0
    for name, shapes in defs.ICONS.items():
        with open(os.path.join(OUT_DIR, 'ic_color_' + name.lower() + '.svg'),
                  'w', encoding='utf-8', newline='\n') as f:
            f.write(build(name, shapes))
        n += 1
    print('生成 %d 个彩色图标 -> %s' % (n, OUT_DIR))


if __name__ == '__main__':
    main()
