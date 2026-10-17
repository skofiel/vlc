#!/usr/bin/env bash
# Compila el instalador de Windows (.exe) de este fork dentro de la imagen
# Docker de VideoLAN. Se ejecuta desde WSL2 con Docker disponible.
# Guía completa: extras/package/win32/docker/LEEME.md
#
# Variables (todas opcionales):
#   SOURCE_REPO  repositorio de origen           (/mnt/d/Proyectos/VLC)
#   BRANCH       rama que se compila             (design/rediseno)
#   WORKDIR      copia de trabajo en ext4        ($HOME/vlc-win)
#   OUT_DIR      carpeta de resultados           (/mnt/d/Proyectos/VLC-instaladores)
#   VLC_IMAGE    imagen Docker                   (vlc-debian-llvm-ucrt:20260611225331)
#   JOBS         compilaciones en paralelo       (nproc)
#   BUILD_FLAGS  opciones de build.sh            (-a x86_64 -u -r -p -m -i u)
#   EXTRA_FLAGS  opciones añadidas a BUILD_FLAGS (p. ej. "-l" para las traducciones)
#   PORTABLE     1 copia también la versión portable, 0 no (1)

set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-/mnt/d/Proyectos/VLC}"
BRANCH="${BRANCH:-design/rediseno}"
WORKDIR="${WORKDIR:-$HOME/vlc-win}"
OUT_DIR="${OUT_DIR:-/mnt/d/Proyectos/VLC-instaladores}"
VLC_IMAGE="${VLC_IMAGE:-registry.videolan.org/vlc-debian-llvm-ucrt:20260611225331}"
JOBS="${JOBS:-$(nproc)}"
BUILD_FLAGS="${BUILD_FLAGS:--a x86_64 -u -r -p -m -i u}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"
PORTABLE="${PORTABLE:-1}"

# Ruta del código dentro del contenedor. Meson guarda rutas absolutas, así que
# tiene que ser siempre la misma para reaprovechar las compilaciones anteriores.
CONTAINER_SRC=/build/vlc

info()  { printf '\033[1;32m[vlc-win]\033[0m %s\n' "$*"; }
aviso() { printf '\033[1;33m[vlc-win]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[vlc-win]\033[0m %s\n' "$*" >&2; exit 1; }
# Ruta tal como se ve desde Windows, si se puede
winpath() { wslpath -w "$1" 2>/dev/null || printf '%s\n' "$1"; }

# 1. Comprobaciones
command -v git >/dev/null || error "Falta git: sudo apt install git"
command -v docker >/dev/null || error "Falta Docker. Mira el apartado 3 de LEEME.md"
docker info >/dev/null 2>&1 || error "No se puede hablar con Docker. ¿Está arrancado y tu usuario en el grupo docker? (LEEME.md, apartado 3)"
[ -d "$SOURCE_REPO/.git" ] || error "No hay un repositorio git en $SOURCE_REPO"
case "$WORKDIR" in
    /mnt/*) aviso "WORKDIR está en una unidad de Windows: la compilación será mucho más lenta." ;;
esac

# 2. Código fuente: copia local en el disco de WSL, sacada de la rama del
#    repositorio de Windows (no se usa GitHub). Solo entra lo que está en commits.
git_src() { git -c safe.directory="$SOURCE_REPO" -c safe.directory="$SOURCE_REPO/.git" "$@"; }
if [ ! -d "$WORKDIR/.git" ]; then
    info "Clonando $BRANCH de $SOURCE_REPO en $WORKDIR"
    git_src clone --branch "$BRANCH" "$SOURCE_REPO" "$WORKDIR"
else
    info "Actualizando $WORKDIR con $BRANCH de $SOURCE_REPO"
    git_src -C "$WORKDIR" fetch "$SOURCE_REPO" "$BRANCH"
    git -C "$WORKDIR" checkout --detach FETCH_HEAD
fi
grep -qx '/build-win.log' "$WORKDIR/.git/info/exclude" 2>/dev/null ||
    printf '/build-win.log\n/.docker-home/\n' >> "$WORKDIR/.git/info/exclude"
COMMIT="$(git -C "$WORKDIR" rev-parse --short HEAD)"
info "Commit: $(git -C "$WORKDIR" log -1 --format='%h %s')"

# 3. Imagen y usuario del contenedor
info "Descargando la imagen $VLC_IMAGE (solo la primera vez)"
docker pull "$VLC_IMAGE"

# La imagen trae su propio usuario (con wine ya preparado en su HOME). Si su UID
# coincide con el tuyo se usa tal cual; si no, se usa el tuyo con un HOME propio
# para que los archivos de la copia de trabajo sigan siendo tuyos.
USER_ARGS=()
IMAGE_UID="$(docker run --rm --entrypoint id "$VLC_IMAGE" -u)"
if [ "$IMAGE_UID" != "$(id -u)" ]; then
    aviso "El usuario de la imagen (UID $IMAGE_UID) no es el tuyo ($(id -u)); se usa el tuyo."
    mkdir -p "$WORKDIR/.docker-home"
    USER_ARGS=(--user "$(id -u):$(id -g)" -e HOME="$CONTAINER_SRC/.docker-home")
fi

TTY_ARGS=()
[ -t 0 ] && [ -t 1 ] && TTY_ARGS=(-it)

# 4. Compilación (contribs, VLC e instalador)
LOG="$WORKDIR/build-win.log"
info "Compilando con: build.sh $BUILD_FLAGS $EXTRA_FLAGS (JOBS=$JOBS)"
info "Registro completo en $LOG"
START=$(date +%s)
# shellcheck disable=SC2086 # las opciones se separan a propósito
if docker run --rm "${TTY_ARGS[@]}" "${USER_ARGS[@]}" \
        -v "$WORKDIR:$CONTAINER_SRC" -w "$CONTAINER_SRC" \
        -e JOBS="$JOBS" \
        "$VLC_IMAGE" \
        extras/package/win32/build.sh $BUILD_FLAGS $EXTRA_FLAGS 2>&1 | tee "$LOG"; then
    BUILD_OK=1
else
    BUILD_OK=0
fi
MINUTES=$(( ($(date +%s) - START) / 60 ))

# 5. Resultados
shopt -s nullglob
BUILD_DIRS=("$WORKDIR"/win*-meson)
[ ${#BUILD_DIRS[@]} -gt 0 ] || error "La compilación falló antes de configurar Meson ($MINUTES min). Mira $LOG"
BUILD_DIR="${BUILD_DIRS[0]}"
# Solo cuentan los generados en esta ejecución, no los de una anterior.
INSTALLERS=()
for f in "$BUILD_DIR"/vlc-*.exe "$BUILD_DIR"/vlc-*.msi; do
    [ "$(stat -c %Y "$f")" -ge "$START" ] && INSTALLERS+=("$f")
done

if [ ${#INSTALLERS[@]} -eq 0 ]; then
    error "No se ha generado ningún instalador ($MINUTES min). Mira el final de $LOG"
fi

mkdir -p "$OUT_DIR"
for f in "${INSTALLERS[@]}"; do
    name="$(basename "$f")"
    dest="$OUT_DIR/${name%.*}-$COMMIT.${name##*.}"
    cp -f "$f" "$dest"
    info "Instalador: $(winpath "$dest")"
done

if [ "$PORTABLE" = 1 ]; then
    INSTALL_DIRS=("$BUILD_DIR"/vlc-win*)
    for d in "${INSTALL_DIRS[@]}"; do
        [ -d "$d" ] || continue
        dest="$OUT_DIR/$(basename "$d")-$COMMIT"
        rm -rf "$dest"
        cp -r "$d" "$dest"
        # Con una carpeta «portable» junto a vlc.exe, la configuración se guarda
        # ahí y no se mezcla con la del VLC instalado (%APPDATA%\vlc).
        mkdir -p "$dest/portable"
        info "Versión portable: $(winpath "$dest/vlc.exe")"
    done
fi

if [ "$BUILD_OK" = 1 ]; then
    info "Terminado en $MINUTES min."
else
    aviso "build.sh terminó con error ($MINUTES min), pero hay instaladores generados."
    aviso "Lo más probable es que fallara el paso del MSI; el .exe es válido. Mira $LOG"
    exit 1
fi
