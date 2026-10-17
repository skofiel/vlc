#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Render the application icon bitmaps from the SVG sources written by
# generate.py.
#
# Requires rsvg-convert (librsvg), ImageMagick and png2icns (libicns).
#
# Usage: render.sh SRCDIR

set -e

SRCDIR=${1:-.}
cd "$SRCDIR"

ICON=share/icons/vlc.svg
TILE=extras/package/macosx/asset_sources/vlc_app_icon.svg
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

render() { # svg size output
    rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
}

# Linux/hicolor and Qt resources. The seasonal variants (xmas, aprilfools,
# kb) use the same icon until dedicated designs exist.
for size in 16 32 48 128 256; do
    for name in vlc vlc-xmas vlc-aprilfools vlc-kb; do
        out=share/icons/${size}x${size}/$name.png
        [ -f "$out" ] && render "$ICON" "$size" "$out"
    done
done
for size in 16 32; do
    for name in vlc vlc-xmas vlc-aprilfools; do
        out=share/icons/${size}x${size}/$name.xpm
        [ -f "$out" ] || continue
        # keep the variable declaration, the XPM files are included by C code
        decl=$(grep -m1 '^static' "$out")
        convert "share/icons/${size}x${size}/vlc.png" "$TMP/icon.xpm"
        { echo '/* XPM */'; echo "$decl"; sed '1,/^static/d' "$TMP/icon.xpm"; } > "$out"
    done
done

render "$ICON" 512 share/vlc512x512.png
render "$ICON" 512 share/upnp_server/vlc512x512.png
render "$ICON" 32 share/upnp_server/vlc.png
render "$ICON" 128 share/lua/http/images/vlc-48.png
render "$ICON" 16 share/lua/http/images/vlc16x16.png

# Windows
for size in 16 32 48 256; do
    render "$ICON" $size "$TMP/ico$size.png"
done
convert "$TMP/ico16.png" "$TMP/ico32.png" "$TMP/ico48.png" "$TMP/ico256.png" share/icons/vlc.ico

# macOS
for size in 16 32 48 128 256 512 1024; do
    render "$TILE" $size "$TMP/icns$size.png"
done
for name in VLC VLC-Xmas VLC26 VLC26-Dev; do
    png2icns "modules/gui/macosx/Resources/App-Icons/$name.icns" \
        "$TMP"/icns16.png "$TMP"/icns32.png "$TMP"/icns48.png "$TMP"/icns128.png \
        "$TMP"/icns256.png "$TMP"/icns512.png "$TMP"/icns1024.png >/dev/null
done
