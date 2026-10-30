# -*- coding: utf-8 -*-
"""
图标生成器 —— 一套几何源数据，产出两套素材

设计规范（与 ThemeColors.LIGHT_THEME 配套）
  画布      24 x 24，安全区 2..22（内容不压边）
  描边      1.5px（line）/ 1.45px（sketch）
  端点      圆头、圆角连接
  视觉重心  严格落在 (12,12)，对称图形镜像对称

两套差异
  line    纯几何，零扰动，最规整
  sketch  同样的几何，线条按对称安全函数做 <=0.22px 的呼吸扰动，
          中轴线（x=12 / y=12）绝对不动，所以重心和对称性都不会跑偏

用法
  python scripts/icons/gen.py            # 两套一起生成
  python scripts/icons/gen.py line       # 只生成 line
"""
import os
import re
import math

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__),
                                       '../../store/src/main/resources/base/media'))

# 手绘扰动幅度（px）。超过 0.3 就会"歪"，低于 0.15 看不出来
AMP = 0.28
# 手绘套的端点出头长度（px）—— 速写笔锋的核心特征，不破坏几何
EXT = 0.7


# ---------------------------------------------------------------- 基础工具

def fnum(v):
    """坐标格式化：去掉多余的 0，保证输出紧凑且稳定"""
    s = '%.2f' % v
    s = s.rstrip('0').rstrip('.')
    if s in ('', '-0', '-0.0'):
        s = '0'
    return s


def jitter(x, y):
    """
    对称安全的扰动函数。

    dx 只跟 x 的偏离量和 y 的位置有关，且是 (x-12) 的奇函数；
    dy 同理。因此左右镜像的两点会得到相反的 dx、相同的 dy —— 镜像
    对称关系被完整保留，视觉重心永远钉在 (12,12)。
    """
    dx = AMP * ((x - 12) / 12.0) * math.cos((y - 12) * 0.42)
    dy = AMP * ((y - 12) / 12.0) * math.cos((x - 12) * 0.42)
    return x + dx, y + dy


def extend_ends(pts, ext):
    """
    把折线首尾各延长 ext —— 手绘速写的"笔锋出头"。
    只动首尾两点，中间拐点和整体几何完全不变。
    """
    pts = [tuple(p) for p in pts]
    if len(pts) < 2:
        return pts
    x1, y1 = pts[0]
    x2, y2 = pts[1]
    d = math.hypot(x2 - x1, y2 - y1) or 1.0
    pts[0] = (x1 - (x2 - x1) / d * ext, y1 - (y2 - y1) / d * ext)
    x1, y1 = pts[-1]
    x2, y2 = pts[-2]
    d = math.hypot(x2 - x1, y2 - y1) or 1.0
    pts[-1] = (x1 - (x2 - x1) / d * ext, y1 - (y2 - y1) / d * ext)
    return pts


def pt(x, y, sketch):
    if sketch:
        x, y = jitter(x, y)
    return fnum(x) + ' ' + fnum(y)


def circle_path(cx, cy, r, sketch):
    """圆 -> 4 段三次贝塞尔（扰动后仍是自然的手绘圆）"""
    k = r * 0.5522847498
    raw = [(cx, cy - r),
           (cx + k, cy - r), (cx + r, cy - k), (cx + r, cy),
           (cx + r, cy + k), (cx + k, cy + r), (cx, cy + r),
           (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy),
           (cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)]
    p = [pt(x, y, sketch) for x, y in raw]
    return ('M' + p[0] +
            ' C' + p[1] + ' ' + p[2] + ' ' + p[3] +
            ' C' + p[4] + ' ' + p[5] + ' ' + p[6] +
            ' C' + p[7] + ' ' + p[8] + ' ' + p[9] +
            ' C' + p[10] + ' ' + p[11] + ' ' + p[12] + ' Z')


def arc_path(cx, cy, r, a0, a1, sketch):
    """
    圆弧 -> 贝塞尔段。角度用度，0=三点钟方向，正角顺时针（屏幕坐标 y 向下）。
    a1 可以大于 360，表示继续顺时针绕。
    """
    sweep = a1 - a0
    if abs(sweep) < 0.01:
        return ''
    segs = max(1, int(math.ceil(abs(sweep) / 90.0)))
    step = sweep / segs
    out = ''
    sx = cx + r * math.cos(math.radians(a0))
    sy = cy + r * math.sin(math.radians(a0))
    out += 'M' + pt(sx, sy, sketch)
    a = a0
    for _ in range(segs):
        b = a + step
        k = r * 4.0 / 3.0 * math.tan(math.radians(step) / 4.0)
        x1 = cx + r * math.cos(math.radians(a)) - k * math.sin(math.radians(a))
        y1 = cy + r * math.sin(math.radians(a)) + k * math.cos(math.radians(a))
        x2 = cx + r * math.cos(math.radians(b)) + k * math.sin(math.radians(b))
        y2 = cy + r * math.sin(math.radians(b)) - k * math.cos(math.radians(b))
        ex = cx + r * math.cos(math.radians(b))
        ey = cy + r * math.sin(math.radians(b))
        out += ' C' + pt(x1, y1, sketch) + ' ' + pt(x2, y2, sketch) + ' ' + pt(ex, ey, sketch)
        a = b
    return out


def round_rect_path(x, y, w, h, rx, sketch):
    """圆角矩形 -> 路径（扰动后四角仍然是圆角，不会变成歪多边形）"""
    if rx <= 0:
        pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)]
        return 'M' + ' L'.join(pt(px, py, sketch) for px, py in pts) + ' Z'
    rx = min(rx, w / 2.0, h / 2.0)
    d = 'M' + pt(x + rx, y, sketch)
    d += ' L' + pt(x + w - rx, y, sketch)
    d += ' A' + raw_arc(x + w - rx, y + rx, rx, -90, 0, sketch)
    d += ' L' + pt(x + w, y + h - rx, sketch)
    d += ' A' + raw_arc(x + w - rx, y + h - rx, rx, 0, 90, sketch)
    d += ' L' + pt(x + rx, y + h, sketch)
    d += ' A' + raw_arc(x + rx, y + h - rx, rx, 90, 180, sketch)
    d += ' L' + pt(x, y + rx, sketch)
    d += ' A' + raw_arc(x + rx, y + rx, rx, 180, 270, sketch)
    return d + ' Z'


def raw_arc(cx, cy, r, a0, a1, sketch):
    """接在已有路径后的圆弧，返回 ' rx ry 0 0 1 x y' 形式"""
    ex = cx + r * math.cos(math.radians(a1))
    ey = cy + r * math.sin(math.radians(a1))
    sweep = 1 if a1 > a0 else 0
    return f' {fnum(r)} {fnum(r)} 0 0 {sweep} ' + pt(ex, ey, sketch)


# ---------------------------------------------------------------- 形状渲染

def render(shape, sketch):
    kind = shape[0]
    a = shape[1]

    if kind == 'circle':
        cx, cy, r = a
        if sketch:
            return '<path d="' + circle_path(cx, cy, r, True) + '"/>'
        return f'<circle cx="{fnum(cx)}" cy="{fnum(cy)}" r="{fnum(r)}"/>'

    if kind == 'dot':
        cx, cy, r = a
        d = circle_path(cx, cy, r, sketch) if sketch else None
        if d:
            return '<path d="' + d + '" fill="#000000"/>'
        return f'<circle cx="{fnum(cx)}" cy="{fnum(cy)}" r="{fnum(r)}" fill="#000000"/>'

    if kind == 'line':
        x1, y1, x2, y2 = a
        if sketch:
            p1, p2 = extend_ends([(x1, y1), (x2, y2)], EXT)
            return '<path d="M' + pt(p1[0], p1[1], True) + ' L' + pt(p2[0], p2[1], True) + '"/>'
        return f'<line x1="{fnum(x1)}" y1="{fnum(y1)}" x2="{fnum(x2)}" y2="{fnum(y2)}"/>'

    if kind in ('polyline', 'polygon'):
        pts = [tuple(p) for p in a]
        if kind == 'polyline' and sketch:
            pts = extend_ends(pts, EXT)
        if kind == 'polyline' and not sketch:
            return '<path d="M' + ' L'.join(pt(x, y, False) for x, y in pts) + '"/>'
        return '<path d="' + ('M' + ' L'.join(pt(x, y, sketch) for x, y in pts) +
                              (' Z' if kind == 'polygon' else '')) + '"/>'

    if kind == 'rect':
        x, y, w, h, rx = a
        if sketch:
            return '<path d="' + round_rect_path(x, y, w, h, rx, True) + '"/>'
        rxa = f' rx="{fnum(rx)}"' if rx > 0 else ''
        return (f'<rect x="{fnum(x)}" y="{fnum(y)}" width="{fnum(w)}" '
                f'height="{fnum(h)}"{rxa}/>')

    if kind == 'frect':
        x, y, w, h, rx = a
        d = round_rect_path(x, y, w, h, rx, sketch)
        return '<path d="' + d + '" fill="#000000"/>'

    if kind == 'fpoly':
        pts = list(a)
        return ('<path d="M' + ' L'.join(pt(x, y, sketch) for x, y in pts) +
                ' Z" fill="#000000"/>')

    if kind == 'arc':
        cx, cy, r, a0, a1 = a
        return '<path d="' + arc_path(cx, cy, r, a0, a1, sketch) + '"/>'

    if kind == 'raw':
        return '<path d="' + (jitter_path(a, AMP) if sketch else a) + '"/>'

    raise ValueError('unknown shape: ' + kind)


# ------------------------------------------------- 复杂轮廓的路径级扰动

CMD_ARGS = {
    'M': 2, 'L': 2, 'T': 2,
    'H': 1, 'V': 1,
    'C': 6, 'S': 4, 'Q': 4,
    'A': 7, 'Z': 0,
}
TOKEN_RE = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)')


def jitter_path(d, amp):
    """
    对路径里的绝对坐标做同样的对称扰动。
    只抖 M/L/C/S/Q/T 的坐标对，H/V 只抖那一维，A 的圆弧标志位保持原值。
    """
    tokens = TOKEN_RE.findall(d)
    out = []
    i = 0
    while i < len(tokens):
        cmd = tokens[i][0]
        if not cmd:
            out.append(tokens[i][1])
            i += 1
            continue
        out.append(cmd)
        up = cmd.upper()
        n = CMD_ARGS.get(up, 0)
        nums = []
        j = i + 1
        while j < len(tokens) and not tokens[j][0] and len(nums) < n:
            nums.append(tokens[j][1])
            j += 1
        if up == 'Z' or not nums:
            i = j
            continue

        vals = [float(v) for v in nums]
        rel = cmd.islower()
        if up in ('M', 'L', 'T', 'C', 'S', 'Q'):
            for k in range(0, len(vals) - 1, 2):
                if not rel:
                    vals[k], vals[k + 1] = jitter(vals[k], vals[k + 1])
            out.append(' '.join(fnum(v) for v in vals))
        elif up in ('H', 'V'):
            if not rel:
                if up == 'H':
                    vals[0] = jitter(vals[0], 12)[0]
                else:
                    vals[0] = jitter(12, vals[0])[1]
            out.append(' '.join(fnum(v) for v in vals))
        else:  # A：rx ry rot large sweep x y
            if len(vals) == 7 and not rel:
                nx, ny = jitter(vals[5], vals[6])
                vals[5], vals[6] = nx, ny
            out.append(' '.join(fnum(v) for v in vals))
        i = j
    return ' '.join(out)


# ---------------------------------------------------------------- 输出

SVG_HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
            'viewBox="0 0 24 24" fill="none" stroke="#000000" '
            'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">')


def build_svg(shapes, sketch):
    sw = '1.45' if sketch else '1.5'
    body = '\n  '.join(render(s, sketch) for s in shapes)
    return SVG_HEAD.format(sw=sw) + '\n  ' + body + '\n</svg>\n'


def main():
    import defs
    only = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    count = 0
    for name, shapes in defs.ICONS.items():
        base = name.lower()
        if only in ('all', 'line'):
            with open(os.path.join(OUT_DIR, 'ic_line_' + base + '.svg'), 'w',
                      encoding='utf-8', newline='\n') as f:
                f.write(build_svg(shapes, False))
            count += 1
        if only in ('all', 'sketch'):
            with open(os.path.join(OUT_DIR, 'ic_sketch_' + base + '.svg'), 'w',
                      encoding='utf-8', newline='\n') as f:
                f.write(build_svg(shapes, True))
            count += 1
    print('生成 %d 个文件 -> %s' % (count, OUT_DIR))


if __name__ == '__main__':
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
