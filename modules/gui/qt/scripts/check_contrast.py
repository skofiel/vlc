#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Check the WCAG contrast ratio of the foreground colors against the background
# of their color set, for the light and dark palettes of style/systempalette.cpp.
#
# Pairs listed in the known issues file are reported but don't fail the check,
# any other pair below the threshold does (so that no new issue is introduced).
#
# Usage: check_contrast.py [--known-issues FILE] [--update-known-issues] SRCDIR
#   SRCDIR: modules/gui/qt source directory

import argparse
import os
import re
import sys

PALETTES = ('makeLightPalette', 'makeDarkPalette')
# Foreground roles used for text (or icons) drawn on the color set background
FG_ROLES = ('Primary', 'Secondary', 'Link', 'Positive', 'Neutral', 'Negative')
TEXT_THRESHOLD = 4.5        # WCAG 1.4.3, normal text
NON_TEXT_THRESHOLD = 3.0    # WCAG 1.4.11, graphical objects
NON_TEXT_SETS = ('Slider',)

QT_COLORS = {
    'white': (255, 255, 255), 'black': (0, 0, 0), 'red': (255, 0, 0),
    'green': (0, 255, 0), 'blue': (0, 0, 255), 'magenta': (255, 0, 255),
    'yellow': (255, 255, 0), 'cyan': (0, 255, 255), 'gray': (160, 160, 164),
}


def parse_hex(text):
    text = text.strip().strip('"')
    if not re.fullmatch(r'#[0-9a-fA-F]{6}', text):
        return None
    return (int(text[1:3], 16), int(text[3:5], 16), int(text[5:7], 16), 1.0)


def split_args(text):
    args, depth, cur = [], 0, ''
    for ch in text:
        if ch in '({[':
            depth += 1
        elif ch in ')}]':
            depth -= 1
        if ch == ',' and depth == 0:
            args.append(cur.strip())
            cur = ''
        else:
            cur += ch
    args.append(cur.strip())
    return args


def evaluate(expr, constants):
    """Return (r, g, b, alpha) or None if the expression is not understood."""
    expr = re.sub(r'/\*.*?\*/', '', expr).strip()
    m = re.fullmatch(r'Qt::(\w+)', expr)
    if m:
        if m.group(1) == 'transparent':
            return (0, 0, 0, 0.0)
        rgb = QT_COLORS.get(m.group(1))
        return rgb + (1.0,) if rgb else None
    if expr in constants:
        return constants[expr]
    m = re.fullmatch(r'QColor\s*[({]\s*("[^"]*")\s*[)}]', expr)
    if m:
        return parse_hex(m.group(1))
    if expr.startswith('"'):
        return parse_hex(expr)
    m = re.fullmatch(r'setColorAlpha\s*\((.*)\)', expr, re.DOTALL)
    if m:
        args = split_args(m.group(1))
        if len(args) == 2:
            color = evaluate(args[0], constants)
            if color is not None:
                return color[:3] + (float(args[1]),)
    return None


def find_calls(body, name):
    """Yield the argument strings of the name(...) calls in body."""
    for m in re.finditer(r'\b' + name + r'\s*\(', body):
        depth, i = 1, m.end()
        while depth and i < len(body):
            depth += {'(': 1, ')': -1}.get(body[i], 0)
            i += 1
        yield m.start(), body[m.end():i - 1]


def parse_palette(source, func, constants):
    start = source.index('void SystemPalette::' + func + '(')
    end = source.find('\nvoid SystemPalette::', start + 1)
    body = source[start:end if end != -1 else len(source)]

    sets = [(m.start(), m.group(1))
            for m in re.finditer(r'C::ColorSet\s+CS\s*=\s*C::(\w+)\s*;', body)]
    colors = {}
    for pos, args in find_calls(body, 'setColor'):
        args = split_args(args)
        if len(args) != 5 or args[0] != 'CS':
            continue
        current = [name for p, name in sets if p < pos]
        if not current:
            continue
        section, role, state = (a.replace('C::', '') for a in args[1:4])
        colors[(current[-1], section, role, state)] = evaluate(args[4], constants)
    return colors


def blend(fg, bg):
    a = fg[3]
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3)) + (1.0,)


def luminance(c):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in c[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg, bg):
    l1, l2 = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def check(srcdir):
    with open(os.path.join(srcdir, 'style', 'systempalette.hpp'), encoding='utf-8') as f:
        constants = {name: parse_hex(value) for name, value in
                     re.findall(r'COLOR_DEFINITION\((\w+),\s*("[^"]*")\)', f.read())}
    with open(os.path.join(srcdir, 'style', 'systempalette.cpp'), encoding='utf-8') as f:
        source = f.read()

    results = []
    for func in PALETTES:
        palette = 'light' if 'Light' in func else 'dark'
        colors = parse_palette(source, func, constants)
        view_bg = colors.get(('View', 'Bg', 'Primary', 'Normal'))
        colorsets = sorted({key[0] for key in colors})
        for cs in colorsets:
            bg = colors.get((cs, 'Bg', 'Primary', 'Normal'), view_bg)
            if bg is None or view_bg is None:
                continue
            bg = blend(bg, blend(view_bg, (255, 255, 255, 1.0)))
            threshold = NON_TEXT_THRESHOLD if cs in NON_TEXT_SETS else TEXT_THRESHOLD
            for role in FG_ROLES:
                fg = colors.get((cs, 'Fg', role, 'Normal'))
                if fg is None or fg[3] == 0:
                    continue
                ratio = contrast(blend(fg, bg), bg)
                results.append((f'{palette} {cs} Fg.{role}', ratio, threshold))
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('srcdir', help='modules/gui/qt source directory')
    parser.add_argument('--known-issues',
                        help='file listing the pairs known to be below the threshold')
    parser.add_argument('--update-known-issues', action='store_true',
                        help='rewrite the known issues file with the current failures')
    parser.add_argument('--verbose', action='store_true', help='print every pair')
    args = parser.parse_args()

    known = set()
    if args.known_issues and os.path.exists(args.known_issues):
        with open(args.known_issues, encoding='utf-8') as f:
            known = {l.strip() for l in f if l.strip() and not l.startswith('#')}

    results = check(args.srcdir)
    failures = [(name, ratio, threshold) for name, ratio, threshold in results
                if ratio < threshold]

    if args.update_known_issues:
        with open(args.known_issues, 'w', encoding='utf-8') as f:
            f.write('# Color pairs known to be below the WCAG contrast threshold,\n'
                    '# cf. scripts/check_contrast.py. Remove the lines once fixed.\n')
            f.writelines(name + '\n' for name, _, _ in failures)
        return 0

    ret = 0
    for name, ratio, threshold in results:
        status = 'ok'
        if ratio < threshold:
            status = 'known issue' if name in known else 'FAIL'
            if status == 'FAIL':
                ret = 1
        if args.verbose or status != 'ok':
            print(f'{name}: {ratio:.2f}:1 (minimum {threshold}:1) {status}')
    for name in sorted(known - {name for name, _, _ in failures}):
        print(f'{name}: now passes, remove it from the known issues')
    return ret


if __name__ == '__main__':
    sys.exit(main())
