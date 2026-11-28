# Static cyanrip builds for Linux, macOS and Windows (MSVC and MinGW)

> **This is an experiment.** Besides publishing the binaries, its goal is
> to get every fix it needs into the upstream projects: cyanrip, libcdio,
> libcdio-paranoia and libmusicbrainz. Once they are all upstreamed, this
> repository will be archived or deleted. Build from the upstream projects
> then.

This repository builds static [cyanrip](https://github.com/cyanreg/cyanrip)
binaries for Linux (x86-64, musl), macOS (arm64) and Windows (x86-64, with
both MSVC and MinGW UCRT64). They're built from branches of cyanrip and
the libraries it needs, which carry the fixes not yet upstream. Each
library is a submodule:

| Submodule | Branch | What it adds |
|---|---|---|
| `libcdio-C` | `export-macros` | Meson build; symbols exported through `CDIO_PUBLIC` and friends, so MSVC can build DLLs; reading CDs on Windows and under Wine (TOC, sessions, MCN and ISRCs) |
| `libcdio-paranoia` | `meson-export-symbols` | The same for libcdio-paranoia; binary audio output on Windows |
| `libmusicbrainz` | `msvc-fixes` | libcurl instead of neon (`curl-port`); MSVC fixes and export macros; DLLs installed in `bin` |
| `cyanrip` | `msvc` | MSVC build; backslashes in paths; unreadable cover art not embedded; every track's ISRC; `+npN` after the version |

## Testing

- **CI:** every build runs cyanrip's test suite, including rips of disc
  images. The release builds are static; the CI workflow also makes
  dynamic MSVC and MinGW builds, so that neither toolchain regresses.
- **Real discs:** before a release, the Linux build rips a CD in a real
  drive, and the Windows builds rip the same CD under Wine. The rips are
  compared sample for sample, and checked against AccurateRip.
- The macOS build is only built and tested in CI, not run on a real drive.

## Upstream status

Proposed upstream so far:

| Project | Change | Status |
|---|---|---|
| libcdio | [libcdio-C#127](https://github.com/libcdio/libcdio-C/issues/127): a Meson build alongside autotools | agreed; PR to follow once the open PRs are reviewed |
| libcdio | [libcdio-C#128](https://github.com/libcdio/libcdio-C/pull/128): define `iso9660_find_fs_lsn` on every platform, and deprecate it | open |
| libcdio | [libcdio-C#129](https://github.com/libcdio/libcdio-C/pull/129): keep Linux TOC reads within the track arrays | merged |
| libcdio | [libcdio-C#130](https://github.com/libcdio/libcdio-C/pull/130): find a CUE sheet's files next to it on Windows | open |
| libcdio | [libcdio-C#131](https://github.com/libcdio/libcdio-C/pull/131): read the CD-TEXT that `cdrdao read-toc` writes | open |
| libcdio | [libcdio-C#132](https://github.com/libcdio/libcdio-C/pull/132): read a CD-Extra's TOC on Windows, and fail MMC commands the drive rejects | merged |
| libcdio | [libcdio-C#133](https://github.com/libcdio/libcdio-C/pull/133): ask the drive for the last session, MCN and ISRCs, for Wine, which lacks or half-implements the ioctls | open |
| libcdio-paranoia | [libcdio-paranoia#64](https://github.com/libcdio/libcdio-paranoia/pull/64): declare `getopt` with its prototype, for C23 compilers | merged |
| libcdio-paranoia | [libcdio-paranoia#65](https://github.com/libcdio/libcdio-paranoia/pull/65): `jitter_read` doesn't use bytes the read didn't fill | open |
| libcdio-paranoia | [libcdio-paranoia#66](https://github.com/libcdio/libcdio-paranoia/pull/66): build with MSVC | open |
| libcdio-paranoia | [libcdio-paranoia#68](https://github.com/libcdio/libcdio-paranoia/pull/68): LF line endings on Windows, and `pod2c.pl` stripping CRLF | merged |
| libmusicbrainz | [libmusicbrainz#22](https://github.com/metabrainz/libmusicbrainz/pull/22): replace libneon with libcurl, reuse connections, and set curl up on first use (the `msvc-fixes` branch is based on it) | open |
| cyanrip | [cyanrip#153](https://github.com/cyanreg/cyanrip/pull/153): complete pregap detection (the `msvc` branch is based on it) | open |
| cyanrip | [cyanrip#170](https://github.com/cyanreg/cyanrip/pull/170): rip disc images without paranoia by default | open |
| cyanrip | [cyanrip#173](https://github.com/cyanreg/cyanrip/pull/173): don't embed cover art FFmpeg can't read | open |
| cyanrip | [cyanrip#174](https://github.com/cyanreg/cyanrip/pull/174): run the image tests in Python's UTF-8 mode | open |
| cyanrip | [cyanrip#175](https://github.com/cyanreg/cyanrip/pull/175): FIFO waits re-check their condition after waking | open |
| cyanrip | [cyanrip#176](https://github.com/cyanreg/cyanrip/pull/176): keep the drive offset search within its buffer and radius | open |
| cyanrip | [cyanrip#177](https://github.com/cyanreg/cyanrip/pull/177): read the ISRC of every track | open |

Still only in the branches here:

- libcdio and libcdio-paranoia:
  - the Meson builds, and their fixes for static linking with `prefer_static`;
  - the export macros.
- libmusicbrainz:
  - the MSVC fixes and export macros;
  - static linking of curl and libxml2 with their own dependencies.
- cyanrip:
  - the MSVC build, including its Windows threads in place of pthreads4w;
  - splitting paths at backslashes on Windows.

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

FFmpeg (with zlib, for PNG cover art), curl, libxml2, libqrencode (QR
codes for MusicBrainz submissions) and chromaprint (AcoustID fingerprints)
come from vcpkg. The first build of FFmpeg takes a while. The script builds the
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
`dist\cyanrip-windows-x86_64-msvc.exe`, which needs no DLLs. It builds
FFmpeg from source with MSVC, with the same features as the other builds
(`scripts/ffmpeg-features.sh`), from MSYS2's bash; MSYS2 needs `make`,
`nasm` and `diffutils`.

`.github/workflows/release.yml` builds all four:

- `cyanrip-linux-x86_64`
- `cyanrip-darwin-aarch64`
- `cyanrip-windows-x86_64-ucrt64.exe`
- `cyanrip-windows-x86_64-msvc.exe`

It uploads them as artifacts and attaches them to the GitHub release
when one is published. Run it by hand to get the artifacts without a
release.

The macOS binary is signed ad hoc only, not with an Apple Developer ID.
When it's downloaded with a browser, macOS quarantines it, and Gatekeeper
then refuses to open it. To run it, mark it executable and remove the
quarantine attribute:

```sh
chmod +x cyanrip-darwin-aarch64
xattr -d com.apple.quarantine cyanrip-darwin-aarch64
```

## CI

`.github/workflows/build.yml` runs both scripts on GitHub's Windows
runners:

- MSVC;
- MinGW, under UCRT64 and MINGW64.

The vcpkg binary cache is kept between runs. Run the workflow by hand
with **latest** checked to build the tip of every branch instead of the
pinned commits.
