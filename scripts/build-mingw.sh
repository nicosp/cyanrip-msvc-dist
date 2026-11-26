#!/usr/bin/env bash
# Builds libcdio, libcdio-paranoia, libmusicbrainz and cyanrip with MinGW,
# then runs cyanrip's tests.
#
# Run it from an MSYS2 UCRT64, MINGW64 or CLANG64 shell.  FFmpeg, curl and
# libxml2 come from MSYS2; the libraries in the submodules are installed
# into $PREFIX, which cyanrip is built against.
#
# Environment:
#   PREFIX        install prefix (default _install/<msystem>)
#   BUILD_DIR     build directory (default _build/<msystem>)
#   BUILDTYPE     Meson build type (default release)
#   INSTALL_DEPS  0 to skip installing the MSYS2 packages
#   SKIP_TESTS    1 to skip cyanrip's tests

set -euo pipefail

case "${MSYSTEM:-}" in
    UCRT64|MINGW64|CLANG64) ;;
    *) echo "Run this from an MSYS2 UCRT64, MINGW64 or CLANG64 shell" >&2; exit 1 ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
msys=${MSYSTEM,,}
prefix=${PREFIX:-$root/_install/$msys}
build=${BUILD_DIR:-$root/_build/$msys}
buildtype=${BUILDTYPE:-release}
mkdir -p "$prefix" "$build"

if [ "${INSTALL_DEPS:-1}" = 1 ]; then
    p=$MINGW_PACKAGE_PREFIX
    pacman -S --needed --noconfirm "$p-toolchain" "$p-meson" "$p-ninja" "$p-cmake" \
        "$p-pkgconf" "$p-ffmpeg" "$p-curl" "$p-libxml2" "$p-libiconv" "$p-python"
fi

# Meson and CMake are native Windows programs: give them Windows paths
win() { cygpath -m "$1"; }
wprefix=$(win "$prefix")

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PATH="$prefix/bin:$PATH"

run() { echo "+ $*"; "$@"; }

meson_setup() {
    local b=$1 src=$2; shift 2
    local reconfigure=()
    [ -d "$b/meson-private" ] && reconfigure=(--reconfigure)
    run meson setup "${reconfigure[@]}" "$(win "$b")" "$(win "$src")" \
        --prefix "$wprefix" --buildtype "$buildtype" "$@"
}

# libcdio
meson_setup "$build/libcdio" "$root/libcdio-C" \
    -Dcxx=false -Dexamples=false -Dtests=false -Dcddb=disabled
run meson install -C "$(win "$build/libcdio")"

# libcdio-paranoia, against the libcdio just installed
meson_setup "$build/libcdio-paranoia" "$root/libcdio-paranoia" \
    --wrap-mode=nofallback -Dexamples=false -Dtests=false
run meson install -C "$(win "$build/libcdio-paranoia")"

# libmusicbrainz.  Its install directories are made absolute from the prefix
# given here, so it can't be changed at install time.
cmaketype=Release
[ "$buildtype" = release ] || cmaketype=RelWithDebInfo
run cmake -S "$(win "$root/libmusicbrainz")" -B "$(win "$build/libmusicbrainz")" -G Ninja \
    -DCMAKE_BUILD_TYPE=$cmaketype -DCMAKE_INSTALL_PREFIX="$wprefix"
run cmake --build "$(win "$build/libmusicbrainz")" --target musicbrainz5 musicbrainz5cc
run cmake --install "$(win "$build/libmusicbrainz")"

# cyanrip
meson_setup "$build/cyanrip" "$root/cyanrip"
run meson compile -C "$(win "$build/cyanrip")"
run meson install -C "$(win "$build/cyanrip")"

if [ "${SKIP_TESTS:-0}" != 1 ]; then
    run meson test -C "$(win "$build/cyanrip")" --print-errorlogs
fi

echo "cyanrip is installed in $prefix/bin"
