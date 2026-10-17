#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Check that po/POTFILES.in lists every source file containing translatable
# strings (and only existing files), so that no string is silently left out of
# the translation template.
#
# Usage: check_potfiles.py [srcdir]

import os
import re
import subprocess
import sys

SCANNED_DIRS = ('bin', 'include', 'lib', 'modules', 'src')
SCANNED_EXTS = ('.c', '.cpp', '.h', '.hpp', '.m', '.qml', '.js')

# Translation markers, cf. the xgettext keywords in po/Makevars
MARKER = re.compile(
    r'\b(?:_|N_|_NS|Q_|_PNS|qtr|qsTr|vlc_ngettext|vlc_pgettext)\(\s*"')


def read_list(path):
    entries = set()
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                entries.add(line)
    return entries


def source_files(srcdir):
    try:
        out = subprocess.run(['git', '-C', srcdir, 'ls-files', '--', *SCANNED_DIRS],
                             check=True, capture_output=True, text=True).stdout
        files = out.splitlines()
    except (OSError, subprocess.CalledProcessError):
        files = []
        for top in SCANNED_DIRS:
            for root, _, names in os.walk(os.path.join(srcdir, top)):
                for name in names:
                    files.append(os.path.relpath(os.path.join(root, name), srcdir))
    return sorted(f for f in files if f.endswith(SCANNED_EXTS))


def has_marker(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return MARKER.search(f.read()) is not None
    except OSError:
        return False


def main():
    srcdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..')
    potfiles = read_list(os.path.join(srcdir, 'po', 'POTFILES.in'))
    skipped = read_list(os.path.join(srcdir, 'po', 'POTFILES.skip'))

    stale = sorted(f for f in potfiles if not os.path.exists(os.path.join(srcdir, f)))
    missing = [f for f in source_files(srcdir)
               if f not in potfiles and f not in skipped
               and has_marker(os.path.join(srcdir, f))]

    for f in stale:
        print(f'po/POTFILES.in: listed file does not exist: {f}')
    for f in missing:
        print(f'po/POTFILES.in: missing file with translatable strings: {f}')
    if stale or missing:
        print('Fix po/POTFILES.in (or add intentionally ignored files to po/POTFILES.skip)')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
