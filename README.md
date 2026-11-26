# cyanrip for Windows: MSVC and MinGW builds

> **This is an experiment.** It is a place to work out first-class
> support for [cyanrip](https://github.com/cyanreg/cyanrip) on Windows
> with MSVC, alongside MinGW, across cyanrip and the libraries it needs.
> Once all of the changes below are upstreamed, this repository will be
> archived or deleted. Build from the upstream projects then.

This repository builds cyanrip and the libraries it needs from the
branches that let them build with MSVC, and runs cyanrip's tests. Each
library is a submodule:

| Submodule | Branch | What it adds |
|---|---|---|
| `libcdio-C` | `export-macros` | Meson build; symbols exported through `CDIO_PUBLIC` and friends, so MSVC can build DLLs |
| `libcdio-paranoia` | `meson-export-symbols` | The same for libcdio-paranoia; binary audio output on Windows |
| `libmusicbrainz` | `msvc-fixes` | libcurl instead of neon (`curl-port`); MSVC fixes and export macros; DLLs installed in `bin` |
| `cyanrip` | `msvc` | MSVC build; backslashes in paths; unreadable cover art not embedded |

The same branches are built with MinGW as well, so neither toolchain
regresses.

## Upstream status

What has been proposed upstream so far:

- libcdio: [libcdio-C#127](https://github.com/libcdio/libcdio-C/issues/127)
  proposes the Meson build. [libcdio-C#130](https://github.com/libcdio/libcdio-C/pull/130)
  finds a CUE sheet's files next to it on Windows.
- libcdio-paranoia: [libcdio-paranoia#66](https://github.com/libcdio/libcdio-paranoia/pull/66)
  fixes the MSVC build.
- cyanrip: [cyanrip#173](https://github.com/cyanreg/cyanrip/pull/173)
  stops embedding cover art FFmpeg can't read, and
  [cyanrip#174](https://github.com/cyanreg/cyanrip/pull/174) runs the image
  tests in Python's UTF-8 mode, which they need on Windows. The `msvc` branch is based
  on [cyanrip#153](https://github.com/cyanreg/cyanrip/pull/153), the pregap
  detection work.

Still only in the branches here:

- the Meson build and export macros of libcdio and libcdio-paranoia;
- libmusicbrainz's libcurl port and MSVC fixes;
- cyanrip's MSVC build itself, and splitting paths at backslashes.

## Getting the sources

```sh
git clone --recurse-submodules <this repository>
```

or, in an existing clone, `git submodule update --init`.

The submodules are pinned to commits known to build. To move them to the
tip of their branches:

```sh
git submodule update --remote
git commit -am "Update the submodules"
```

## Building with MSVC

From a Visual Studio developer PowerShell, with
[vcpkg](https://vcpkg.io) cloned and bootstrapped somewhere and `VCPKG_ROOT`
pointing at it. The vcpkg that comes with Visual Studio only works with
manifests, so it won't do.

```powershell
pip install meson ninja pkgconf
scripts\build-msvc.ps1
```

FFmpeg (with zlib, for PNG cover art), curl and libxml2 come
from vcpkg. The first build of FFmpeg takes a while. The script builds the
libraries in `_build\msvc`, installs them in `_install\msvc`, builds
cyanrip against them and runs its tests. Options:

- `-BuildType debugoptimized` keeps debug information;
- `-SkipVcpkg` skips installing the vcpkg packages;
- `-SkipTests` skips the tests;
- `-Prefix` and `-BuildDir` choose other directories.

To run `cyanrip.exe` from `_install\msvc\bin`, put vcpkg's
`installed\x64-windows\bin` on `PATH`, which has the FFmpeg, curl and
libxml2 DLLs.

## Building with MinGW

From an MSYS2 UCRT64, MINGW64 or CLANG64 shell:

```sh
scripts/build-mingw.sh
```

It installs the packages it needs with pacman (skip that with
`INSTALL_DEPS=0`), then builds everything in `_build/<msystem>` and
installs it in `_install/<msystem>`. `BUILDTYPE`, `PREFIX`, `BUILD_DIR` and
`SKIP_TESTS=1` change the defaults.

## Static release binaries

`scripts/build-static.sh` builds one static `cyanrip` binary into `dist/`:

- **Linux:** run it on a musl system such as Alpine, for a fully static binary.
- **macOS:** only system libraries stay dynamic.
- **Windows:** run it from an MSYS2 UCRT64 or MINGW64 shell, for a fully static `.exe`.

It builds every library from source: the ones in the submodules, plus
curl, LAME, Ogg, Vorbis, Opus, FFmpeg, libqrencode and chromaprint. It uses
the versions and FFmpeg features of cyanrip's own release builds, then runs
cyanrip's tests.

`scripts\build-msvc.ps1 -Static` does the same with MSVC: vcpkg's
`x64-windows-static` triplet and the static CRT, giving
`dist\cyanrip-windows-x86_64-msvc.exe`, which needs no DLLs.

`.github/workflows/release.yml` builds all four:

- `cyanrip-linux-x86_64`
- `cyanrip-darwin-aarch64`
- `cyanrip-windows-x86_64-ucrt64.exe`
- `cyanrip-windows-x86_64-msvc.exe`

It uploads them as artifacts and attaches them to the GitHub release
when one is published. Run it by hand to get the artifacts without a
release.

## CI

`.github/workflows/build.yml` runs both scripts on GitHub's Windows
runners:

- MSVC;
- MinGW, under UCRT64 and MINGW64.

The vcpkg binary cache is kept between runs. Run the workflow by hand
with **latest** checked to build the tip of every branch instead of the
pinned commits.
