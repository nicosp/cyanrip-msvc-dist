#!/usr/bin/env bash
# Builds a static FFmpeg with MSVC and the static CRT, with the features in
# ffmpeg-features.sh.  build-msvc.ps1 -Static runs it, from MSYS2's bash with
# the Visual Studio environment inherited (MSYS2_PATH_TYPE=inherit); MSYS2
# needs make, nasm and diffutils.
#
#   build-ffmpeg-msvc.sh PREFIX BUILD_DIR PKGCONF MSVC_LINK
#
# LAME, Vorbis, Opus and zlib are found with PKGCONF, the Windows pkgconf
# that build-msvc.ps1 uses, through its PKG_CONFIG_PATH, so that cl gets
# Windows paths.  MSVC_LINK is the path of MSVC's link.exe, which MSYS2's
# own link would hide.

set -eo pipefail

# The prefix as C:/..., which the installed .pc files must have for Meson
prefix=$(cygpath -m "$1")
build=$(cygpath -u "$2")
pkgconf=$(cygpath -u "$3")
link=$(cygpath -u "$4")

source "$(dirname "$0")/ffmpeg-features.sh"

mkdir -p "$build"
cd "$build"
rm -rf "ffmpeg-$FFMPEG_VERSION"
curl -fsSL --retry 5 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" | tar -xJ
cd "ffmpeg-$FFMPEG_VERSION"

./configure --prefix="$prefix" --toolchain=msvc --ld="$link" \
    --target-os=win64 --arch=x86_64 --extra-cflags=-MT \
    --pkg-config="$pkgconf" --pkg-config-flags=--static \
    --disable-shared --enable-static "${FFMPEG_FEATURES[@]}"
make -j"$(nproc)"
make install

# FFmpeg names its MSVC libraries libNAME.a; Meson and the .pc files look for
# NAME.lib, as vcpkg's port installs them
libdir=$(cygpath -u "$prefix")/lib
for a in "$libdir"/lib*.a; do
    lib=$(basename "$a" .a)
    mv "$a" "$libdir/${lib#lib}.lib"
done
