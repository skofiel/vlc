#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Generate the VLC application icon SVG sources.
#
# The icon is a "play" triangle drawn with three rounded strokes of the same
# width, sharing their end centers at each vertex and woven cyclically (each
# stroke goes over the next one at one vertex).
#
# Usage: generate.py SRCDIR
#   writes:
#   - share/icons/vlc.svg: master icon (transparent background)
#   - extras/package/macosx/asset_sources/vlc_app_icon.svg: macOS tile
#   - modules/gui/qt/pixmaps/misc/cone.svg: flat variant for the Qt
#     interface (no clip path nor filter, #FF8800 is replaced by the accent
#     color at runtime)
#
# Then run render.sh to generate the bitmaps.

import math
import os
import sys

ACCENT = '#FF8800'
COLORS = {
    # stroke: (start, end) gradient colors
    'L': ('#FFB02E', '#FF8F00'),
    'T': ('#FF8A12', '#FF6A00'),
    'B': ('#F45A00', '#E24400'),
}
SHADOW = '#5A1800'


def pt(x, y):
    return f'{x:.2f},{y:.2f}'


def capsule(a, b, r):
    (ax, ay), (bx, by) = a, b
    length = math.hypot(bx - ax, by - ay)
    nx, ny = -(by - ay) / length, (bx - ax) / length
    return (f'M{pt(ax + nx * r, ay + ny * r)} L{pt(bx + nx * r, by + ny * r)} '
            f'A{r:.2f},{r:.2f} 0 0 0 {pt(bx - nx * r, by - ny * r)} '
            f'L{pt(ax - nx * r, ay - ny * r)} '
            f'A{r:.2f},{r:.2f} 0 0 0 {pt(ax + nx * r, ay + ny * r)} Z')


def geometry(height, cx=512, cy=512, ratio=0.24):
    """Return the stroke radius and the three vertex centers."""
    w = height * ratio
    r = w / 2
    s = height - w                      # side of the triangle (centers)
    h = s * math.sqrt(3) / 2            # height of the triangle (centers)
    width = h + w
    x0 = cx - width / 2 + r
    # optical centering: move a quarter of the way from the bounding box
    # center to the centroid of the triangle
    x0 += (width / 2 - r - h / 3) / 4
    return r, (x0, cy - s / 2), (x0 + h, cy), (x0, cy + s / 2)


def glyph(height, cy=512, ids=''):
    """Detailed glyph: gradients and soft shadows under each crossing."""
    r, p1, p2, p3 = geometry(height, cy=cy)
    paths = {'L': capsule(p1, p3, r), 'T': capsule(p1, p2, r), 'B': capsule(p3, p2, r)}
    ends = {'L': (p1, p3), 'T': (p1, p2), 'B': (p2, p3)}
    i = ids
    defs = []
    for k, (c1, c2) in COLORS.items():
        a, b = ends[k]
        defs.append(f'<linearGradient id="g{k}{i}" gradientUnits="userSpaceOnUse" '
                    f'x1="{a[0]:.2f}" y1="{a[1]:.2f}" x2="{b[0]:.2f}" y2="{b[1]:.2f}">'
                    f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/>'
                    f'</linearGradient>')
        defs.append(f'<path id="p{k}{i}" d="{paths[k]}"/>')
        defs.append(f'<clipPath id="c{k}{i}"><use xlink:href="#p{k}{i}"/></clipPath>')
    # the left stroke goes over the top one, near the top vertex only
    defs.append(f'<clipPath id="cTop{i}"><rect x="0" y="0" width="1024" height="{cy}"/></clipPath>')
    defs.append(f'<filter id="blur{i}" x="-20%" y="-20%" width="140%" height="140%">'
                f'<feGaussianBlur stdDeviation="{r * 0.18:.1f}"/></filter>')

    def stroke(k):
        return f'<use xlink:href="#p{k}{i}" fill="url(#g{k}{i})"/>'

    def shadow(over, under):
        return (f'<g clip-path="url(#c{under}{i})"><use xlink:href="#p{over}{i}" '
                f'fill="{SHADOW}" fill-opacity="0.45" filter="url(#blur{i})"/></g>')

    body = [stroke('L'), shadow('B', 'L'), stroke('B'), shadow('T', 'B'), stroke('T'),
            f'<g clip-path="url(#cTop{i})">', shadow('L', 'T'), stroke('L'), '</g>']
    return defs, body


def flat_glyph(height, cy=512):
    """Flat glyph using a single color (replaceable by the accent color)."""
    r, p1, p2, p3 = geometry(height, cy=cy)
    x0, y1 = p1
    # upper half of the left stroke, drawn last (over the top stroke)
    left_top = (f'M{pt(x0 - r, cy)} L{pt(x0 - r, y1)} A{r:.2f},{r:.2f} 0 0 1 '
                f'{pt(x0 + r, y1)} L{pt(x0 + r, cy)} Z')
    lighter = 'fill="#FFFFFF" fill-opacity="0.18"'
    darker = 'fill="#000000" fill-opacity="0.12"'
    body = [
        f'<path d="{capsule(p1, p3, r)}" fill="{ACCENT}"/>',
        f'<path d="{capsule(p1, p3, r)}" {lighter}/>',
        f'<path d="{capsule(p3, p2, r)}" fill="{ACCENT}"/>',
        f'<path d="{capsule(p3, p2, r)}" {darker}/>',
        f'<path d="{capsule(p1, p2, r)}" fill="{ACCENT}"/>',
        f'<path d="{left_top}" fill="{ACCENT}"/>',
        f'<path d="{left_top}" {lighter}/>',
    ]
    return [], body


def document(defs, body, background=()):
    return '\n'.join([
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="1024" height="1024" viewBox="0 0 1024 1024">',
        *(['  <defs>', *('    ' + d for d in defs), '  </defs>'] if defs else []),
        *('  ' + b for b in background), *('  ' + b for b in body), '</svg>', ''])


def macos_tile():
    defs, body = glyph(560, ids='t')
    defs.append('<filter id="tileShadow" x="-10%" y="-10%" width="120%" height="125%">'
                '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/>'
                '<feComponentTransfer><feFuncA type="linear" slope="0.35"/></feComponentTransfer>'
                '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    # macOS 11+ icon grid: 824x824 rounded square centered in 1024x1024
    background = [
        '<rect x="100" y="100" width="824" height="824" rx="185" ry="185" '
        'fill="#181818" filter="url(#tileShadow)"/>',
        '<rect x="101" y="101" width="822" height="822" rx="184" ry="184" fill="none" '
        'stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="2"/>',
    ]
    return document(defs, body, background)


def main():
    srcdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    outputs = {
        'share/icons/vlc.svg': document(*glyph(880)),
        'extras/package/macosx/asset_sources/vlc_app_icon.svg': macos_tile(),
        'modules/gui/qt/pixmaps/misc/cone.svg': document(*flat_glyph(880)),
    }
    for path, content in outputs.items():
        with open(os.path.join(srcdir, path), 'w', encoding='utf-8') as f:
            f.write(content)


if __name__ == '__main__':
    main()
