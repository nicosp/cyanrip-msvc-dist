# cyanrip for Windows: MSVC and MinGW builds

This repository builds [cyanrip](https://github.com/cyanreg/cyanrip) and the
libraries it needs from the branches that let them build with MSVC, and
runs cyanrip's tests. Each library is a submodule:

| Submodule | Branch | What it adds |
|---|---|---|
| `libcdio-C` | `export-macros` | Meson build; symbols exported through `CDIO_PUBLIC` and friends, so MSVC can build DLLs |
| `libcdio-paranoia` | `meson-export-symbols` | The same for libcdio-paranoia; binary audio output on Windows |
| `libmusicbrainz` | `msvc-fixes` | libcurl instead of neon (`curl-port`); MSVC fixes and export macros; DLLs installed in `bin` |
| `cyanrip` | `msvc` | MSVC build; backslashes in paths; unreadable cover art not embedded |

The same branches are built with MinGW as well, so neither toolchain
regresses.

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
[vcpkg](https://vcpkg.io) cloned somewhere and `VCPKG_ROOT` pointing at it:

```powershell
pip install meson ninja pkgconf
scripts\build-msvc.ps1
```

FFmpeg (with zlib, for PNG cover art), curl, libxml2 and pthreads4w come
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

## CI

`.github/workflows/build.yml` runs both scripts on GitHub's Windows
runners:

- MSVC;
- MinGW, under UCRT64 and MINGW64.

The vcpkg binary cache is kept between runs. Run the workflow by hand
with **latest** checked to build the tip of every branch instead of the
pinned commits.
