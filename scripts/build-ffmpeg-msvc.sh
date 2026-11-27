#!/usr/bin/env bash
# Builds a static FFmpeg with MSVC and the static CRT, with the features in
# ffmpeg-features.sh.  build-msvc.ps1 -Static runs it, from MSYS2's bash with
# the Visual Studio environment inherited (MSYS2_PATH_TYPE=inherit); MSYS2
# needs make, nasm and diffutils.
#
#   build-ffmpeg-msvc.sh PREFIX BUILD_DIR PKGCONF PKG_CONFIG_PATH MSVC_LINK
#
# Vorbis, Opus and zlib are found with PKGCONF, the Windows pkgconf that
# build-msvc.ps1 uses, in PKG_CONFIG_PATH (a Windows path list, which the
# login shell's profile would replace), so that cl gets Windows paths.
# MSVC_LINK is the path of MSVC's link.exe: its directory goes first on
# PATH, so that MSYS2's own link doesn't hide it.

set -eo pipefail

# The prefix as C:/..., which the installed .pc files must have for Meson
prefix=$(cygpath -m "$1")
build=$(cygpath -u "$2")
pkgconf=$(cygpath -u "$3")
export PKG_CONFIG_PATH="$4"
export PATH="$(dirname "$(cygpath -u "$5")"):$PATH"

source "$(dirname "$0")/ffmpeg-features.sh"

mkdir -p "$build"
cd "$build"
rm -rf "ffmpeg-$FFMPEG_VERSION"
curl -fsSL --retry 5 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" | tar -xJ
cd "ffmpeg-$FFMPEG_VERSION"

./configure --prefix="$prefix" --toolchain=msvc \
    --target-os=win64 --arch=x86_64 --extra-cflags=-MT \
    --pkg-config="$pkgconf" --pkg-config-flags=--static \
    --disable-shared --enable-static "${FFMPEG_FEATURES[@]}" ||
    { tail -n 40 ffbuild/config.log; exit 1; }
make -j"$(nproc)"
make install
