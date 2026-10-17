#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run qmllint on the QML sources of the Qt interface.
#
# The VLC.* QML modules are only available as Qt resources at runtime, so an
# import tree (qmldir + QML files) is assembled from the generated res.qrc and
# qmldir files of the build directory.
#
# The C++ types (MainCtx, ColorContext, Navigation...) are not described by
# qmltypes files, so only the checks that don't depend on them are enabled:
# syntax errors, deprecations, signal handlers parameters, etc.

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ENABLED_CHECKS = (
    'deprecated',
    'inheritance-cycle',
    'multiline-strings',
    'required',
    'signal',
    'with',
)


def available_checks(qmllint):
    out = subprocess.run([qmllint, '--help'], capture_output=True, text=True).stdout
    return re.findall(r'^\s+--([a-z-]+) <level>', out, re.MULTILINE)


def build_import_tree(builddir, importdir):
    sources = []
    vlcdir = os.path.join(builddir, 'VLC')
    for module in sorted(os.listdir(vlcdir)):
        moddir = os.path.join(vlcdir, module)
        qrc = os.path.join(moddir, 'res.qrc')
        qmldir = os.path.join(moddir, 'qmldir')
        if not os.path.isfile(qrc) or not os.path.isfile(qmldir):
            continue
        outdir = os.path.join(importdir, 'VLC', module)
        os.makedirs(outdir)
        with open(qmldir, encoding='utf-8') as src, \
             open(os.path.join(outdir, 'qmldir'), 'w', encoding='utf-8') as dst:
            # 'prefer' points to the Qt resources, unavailable here
            dst.writelines(l for l in src if not l.startswith('prefer '))
        for f in ET.parse(qrc).getroot().iter('file'):
            path = f.text
            alias = f.get('alias') or os.path.basename(path)
            shutil.copyfile(path, os.path.join(outdir, alias))
            if path.endswith('.qml'):
                sources.append(path)
    return sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--qmllint', required=True, help='qmllint executable')
    parser.add_argument('--builddir', required=True,
                        help='build directory of the Qt module (containing VLC/*/res.qrc)')
    args = parser.parse_args()

    checks = available_checks(args.qmllint)
    levels = []
    for check in checks:
        levels += ['--' + check, 'warning' if check in ENABLED_CHECKS else 'disable']

    with tempfile.TemporaryDirectory() as importdir:
        sources = build_import_tree(args.builddir, importdir)
        if not sources:
            print('no QML sources found in ' + args.builddir)
            return 1
        ret = subprocess.run([args.qmllint, '-I', importdir] + levels + sources)
    return 0 if ret.returncode == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
