#!/usr/bin/env bash
# Builds a static cyanrip binary for release, with the libraries in the
# submodules and every other third-party library built from source, then
# runs cyanrip's tests with it.
#
#   Linux (musl, e.g. Alpine): fully static.
#   macOS: only system libraries and frameworks are linked dynamically.
#   MSYS2 UCRT64/MINGW64: fully static; zlib, bzip2 and libiconv come from
#   MSYS2's static libraries.
#
# Based on cyanrip's .github/static-build.sh, with the same library versions
# and FFmpeg features.  The toolchain, meson, ninja, cmake, nasm, pkg-config,
# autotools and Python must be installed; on Linux, zlib, bzip2, openssl and
# libxml2 with their static libraries too (see .github/workflows/release.yml
# for the packages on each platform).
#
# cyanrip's version gets the +npN of RELEASE_TAG (e.g. v0.9.4-rc3+np3), or
# +np without one.
#
# The binary is written to dist/cyanrip-<os>-<arch>[.exe].  With arguments,
# only the named steps run (e.g. build_ffmpeg build_cyanrip), for iterating
# on one of them.

set -eo pipefail

CURL_VERSION=8.23.0
LIBQRENCODE_VERSION=4.1.1
LAME_VERSION=4.0
LIBOGG_VERSION=1.3.6
LIBVORBIS_VERSION=1.3.7
OPUS_VERSION=1.6.1
FFMPEG_VERSION=9.0.2
OPENSSL_VERSION=4.0.3
LIBXML2_VERSION=2.15.4
CHROMAPRINT_VERSION=1.6.2

build_all() {
    [[ $OS == darwin ]] && build_openssl
    [[ $OS == linux ]] || build_libxml2
    build_curl
    build_libmusicbrainz
    build_libqrencode
    build_chromaprint
    build_libcdio
    build_libcdio_paranoia
    build_lame
    build_libogg
    build_libvorbis
    build_opus
    build_ffmpeg
    build_cyanrip
}

prepare() {
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    case "$(uname -s)" in
        Linux) OS=linux ;;
        Darwin) OS=darwin ;;
        MINGW*|MSYS*|UCRT*|CLANG*) OS=windows ;;
        *) echo "Unsupported system $(uname -s)" >&2; exit 1 ;;
    esac
    ARCH="$(uname -m)"
    [[ $ARCH == arm64 ]] && ARCH=aarch64
    if [[ $OS == windows ]]; then
        [[ -n $MINGW_PREFIX ]] || { echo "Run this from an MSYS2 UCRT64 or MINGW64 shell" >&2; exit 1; }
        PLATFORM="windows-$ARCH-${MSYSTEM,,}"
    else
        PLATFORM="$OS-$ARCH"
    fi
    BUILD="${BUILD_DIR:-$ROOT/_build/static-$PLATFORM}"
    PREFIX="$BUILD/_install"
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    mkdir -p "$BUILD" "$PREFIX" "$ROOT/dist"

    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    CPPFLAGS="-I$PREFIX/include"
    CFLAGS="-O2 -pipe"
    LDFLAGS="-L$PREFIX/lib"
    if [[ $OS == windows ]]; then
        # Headers declare their functions dllimport unless told the
        # libraries are static
        CPPFLAGS+=" -DCURL_STATICLIB -DLIBXML_STATIC -DCHROMAPRINT_NODLL"
        CPPFLAGS+=" -D_FORTIFY_SOURCE=0 -D__USE_MINGW_ANSI_STDIO=1"
        CFLAGS+=" -mtune=generic"
        LDFLAGS+=" -static-libgcc -static-libstdc++"
    fi
    CXXFLAGS="$CFLAGS"
    export PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS
    # Nothing outside the prefix and the system, so Homebrew libraries
    # can't get picked up on macOS
    unset PKG_CONFIG_LIBDIR
}

# Native Windows tools (CMake, Meson) want Windows paths
native() {
    if [[ $OS == windows ]]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

# Downloads and unpacks a release tarball, then enters its directory
do_tarball() {
    local url=$1 dir=$2 compress
    case $url in
        *.xz)  compress=J ;;
        *.bz2) compress=j ;;
        *)     compress=z ;;
    esac
    cd "$BUILD"
    rm -rf "$dir"
    curl -fsSL --retry 5 "$url" | tar -x$compress
    cd "$dir"
}

do_confmakeinstall() {
    ./configure --disable-shared --enable-static --prefix="$PREFIX" "$@"
    make -j"$JOBS"
    make install
}

# Configures the CMake project in the current directory, building out of tree.
# curl's CMake configuration, which MSYS2 installs for its shared curl, is
# skipped, so the static curl built here is used.
do_cmake() {
    CMAKE_BUILD="$BUILD/_cmake/${PWD##*/}"
    cmake -S "$(native "$PWD")" -B "$(native "$CMAKE_BUILD")" -G Ninja -DCURL_NO_CURL_CMAKE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_INSTALL_PREFIX="$(native "$PREFIX")" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_PREFIX_PATH="$(native "$PREFIX")" \
        -DCMAKE_BUILD_TYPE=Release "$@"
}

do_cmakeinstall() {
    do_cmake "$@"
    ninja -C "$(native "$CMAKE_BUILD")"
    ninja -C "$(native "$CMAKE_BUILD")" install
}

do_mesoninstall() {
    local src=$1 name=$2; shift 2
    rm -rf "${BUILD:?}/${name:?}"
    meson setup "$(native "$BUILD/$name")" "$(native "$src")" \
        --prefix="$(native "$PREFIX")" --libdir=lib --buildtype=release \
        --default-library=static --prefer-static "$@"
    meson install -C "$(native "$BUILD/$name")"
}

# macOS only: the SDK has no OpenSSL.  /etc/ssl/cert.pem is where macOS keeps
# the system root certificates as a PEM bundle, so use it as the default.
build_openssl() {
    do_tarball "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "openssl-$OPENSSL_VERSION"
    ./Configure no-shared no-tests no-docs no-apps \
        --prefix="$PREFIX" --libdir=lib --openssldir=/etc/ssl
    make -j"$JOBS"
    make install_sw
}

# Not on Linux, which has a static libxml2.  The macOS SDK's has no
# pkg-config file, which libmusicbrainz needs to find it.  MSYS2 has the DLL
# beside the static library, and CMake takes the DLL's import library, so
# libmusicbrainz would be built for the DLL while cyanrip links statically.
build_libxml2() {
    do_tarball "https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz" "libxml2-$LIBXML2_VERSION"
    do_confmakeinstall --without-python --without-lzma --without-icu \
        --without-http --with-zlib --with-iconv
}

build_curl() {
    local tls_args=()
    # The system's CA store is used at runtime.  macOS keeps one at a fixed
    # path; on Linux it differs per distribution, so leave it to OpenSSL's
    # default lookup, which a compiled-in but missing bundle path would
    # override with an error.  Windows has Schannel and its own store.
    case $OS in
        darwin)  tls_args=(--with-openssl --with-ca-bundle=/etc/ssl/cert.pem --without-ca-path) ;;
        linux)   tls_args=(--with-openssl --with-ca-fallback --without-ca-bundle --without-ca-path) ;;
        windows) tls_args=(--with-schannel --without-ca-bundle --without-ca-path) ;;
    esac

    do_tarball "https://github.com/curl/curl/releases/download/curl-${CURL_VERSION//./_}/curl-$CURL_VERSION.tar.xz" "curl-$CURL_VERSION"
    # Only HTTP(S) is needed
    do_confmakeinstall "${tls_args[@]}" \
        --disable-{ldap,ldaps,rtsp,dict,telnet,tftp,pop3,imap,smb,smtp,gopher,mqtt,ftp,file} \
        --disable-{manual,docs,libcurl-option,ntlm,unix-sockets} \
        --without-{libpsl,libidn2,nghttp2,brotli,zstd,libssh2,librtmp,zlib}
}

# From the submodule: the libcurl port, so no neon
build_libmusicbrainz() {
    cd "$ROOT/libmusicbrainz"
    do_cmakeinstall
}

build_libqrencode() {
    do_tarball "https://github.com/fukuchi/libqrencode/archive/refs/tags/v$LIBQRENCODE_VERSION.tar.gz" "libqrencode-$LIBQRENCODE_VERSION"
    do_cmakeinstall -DWITH_TOOLS=NO -DWITH_TESTS=NO -DWITHOUT_PNG=YES
}

build_chromaprint() {
    local cxxlib=-lstdc++
    [[ $OS == darwin ]] && cxxlib=-lc++
    # The bundled kissfft is used rather than whichever FFT is found first,
    # so the library depends on nothing but the C++ runtime
    do_tarball "https://github.com/acoustid/chromaprint/releases/download/v$CHROMAPRINT_VERSION/chromaprint-$CHROMAPRINT_VERSION.tar.gz" "chromaprint-$CHROMAPRINT_VERSION"
    do_cmakeinstall -DFFT_LIB=kissfft -DKISSFFT_SOURCE_DIR="$(native "$PWD/src/3rdparty/kissfft")" \
        -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF
    # chromaprint is C++, but its pkg-config file doesn't say so, so linking
    # it statically into a C program would leave the C++ runtime out
    echo "Libs.private: $cxxlib -lm" >> "$PREFIX/lib/pkgconfig/libchromaprint.pc"
}

# From the submodules, with Meson
build_libcdio() {
    do_mesoninstall "$ROOT/libcdio-C" libcdio \
        -Dcxx=false -Dexamples=false -Dtests=false -Dcddb=disabled -Dvcd-info=disabled \
        -Dcd-drive=false -Dcd-info=false -Dcd-read=false -Diso-info=false -Diso-read=false \
        -Dcdda-player=disabled -Dman=disabled -Dinfo=disabled
}

build_libcdio_paranoia() {
    do_mesoninstall "$ROOT/libcdio-paranoia" libcdio-paranoia \
        --wrap-mode=nofallback -Dcxx=false -Dexamples=false -Dtests=false
}

build_lame() {
    # Since 4.0 the library links against libmpg123 for its decoder, which
    # FFmpeg's configure doesn't add when linking statically.  Only the
    # encoder is used.
    do_tarball "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" "lame-$LAME_VERSION"
    do_confmakeinstall --disable-{frontend,decoder,gtktest}
}

build_libogg() {
    do_tarball "https://downloads.xiph.org/releases/ogg/libogg-$LIBOGG_VERSION.tar.gz" "libogg-$LIBOGG_VERSION"
    do_confmakeinstall
}

build_libvorbis() {
    do_tarball "https://downloads.xiph.org/releases/vorbis/libvorbis-$LIBVORBIS_VERSION.tar.xz" "libvorbis-$LIBVORBIS_VERSION"
    # The configure script hardcodes -force_cpusubtype_ALL on macOS, which
    # the current Xcode linker rejects; the CMake build doesn't
    do_cmakeinstall
}

build_opus() {
    do_tarball "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" "opus-$OPUS_VERSION"
    do_confmakeinstall --disable-{doc,extra-programs}
}

build_ffmpeg() {
    local extra=()
    [[ $OS == windows ]] && extra+=(--extra-ldflags=-static)
    do_tarball "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "ffmpeg-$FFMPEG_VERSION"
    # The same features as cyanrip's own static builds
    ./configure --prefix="$PREFIX" --pkg-config-flags=--static \
        --disable-shared --enable-static "${extra[@]}" \
        --disable-{programs,devices,filters,decoders,hwaccels,encoders,muxers} \
        --disable-{debug,protocols,demuxers,parsers,doc,swscale,network} \
        --disable-{avdevice,autodetect} \
        --disable-bsfs --enable-protocol=file,data \
        --enable-encoder=flac,tta,aac,wavpack,alac,pcm_s16le,pcm_s32le,pcm_f64le \
        --enable-muxer=flac,tta,ipod,wv,mp3,opus,ogg,wav,pcm_s16le,pcm_s32le,image2,singlejpeg \
        --enable-parser=png,mjpeg --enable-decoder=mjpeg,png \
        --enable-demuxer={image2,image_jpeg_pipe,image_png_pipe} \
        --enable-{bzlib,zlib,iconv} \
        --enable-filter={hdcd,aemphasis,ebur128,anullsink,aresample} \
        --enable-lib{mp3lame,vorbis,opus} \
        --enable-encoder={libmp3lame,libvorbis,libopus}
    make -j"$JOBS"
    make install
}

build_cyanrip() {
    local link_args=() exe=""
    # Fully static on Linux (musl) and Windows; on macOS the system
    # libraries and frameworks stay dynamic
    if [[ $OS == linux || $OS == windows ]]; then
        link_args+=(-Dc_link_args=-static)
    fi
    [[ $OS == windows ]] && exe=.exe

    local suffix=+np
    [[ ${RELEASE_TAG:-} == *+* ]] && suffix="+${RELEASE_TAG#*+}"

    rm -rf "${BUILD:?}/cyanrip"
    meson setup "$(native "$BUILD/cyanrip")" "$(native "$ROOT/cyanrip")" \
        --buildtype=release --default-library=static --prefer-static "${link_args[@]}" \
        "-Dversion_suffix=$suffix"
    meson compile -C "$(native "$BUILD/cyanrip")"
    if [[ ${SKIP_TESTS:-0} != 1 ]]; then
        meson test -C "$(native "$BUILD/cyanrip")" --print-errorlogs
    fi
    strip -o "$ROOT/dist/cyanrip-$PLATFORM$exe" "$BUILD/cyanrip/src/cyanrip$exe"
    echo "Built dist/cyanrip-$PLATFORM$exe"
}

prepare
if [[ $# -eq 0 ]]; then
    build_all
else
    for step; do "$step"; done
fi
