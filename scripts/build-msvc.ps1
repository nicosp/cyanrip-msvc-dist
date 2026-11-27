<#
.SYNOPSIS
Builds libcdio, libcdio-paranoia, libmusicbrainz and cyanrip with MSVC,
then runs cyanrip's tests.

.DESCRIPTION
Run it from a Visual Studio developer PowerShell (or after
ilammy/msvc-dev-cmd in CI), with Meson, Ninja and pkgconf on PATH
(pip install meson ninja pkgconf) and vcpkg in VCPKG_ROOT or
VCPKG_INSTALLATION_ROOT.

FFmpeg, curl, libxml2, libqrencode and chromaprint come from vcpkg; the
libraries in the submodules are installed into -Prefix, which cyanrip is
built against.

With -Static everything is linked statically, with the static CRT, into
one cyanrip.exe that needs no DLLs; it's copied to
dist\cyanrip-windows-x86_64-msvc.exe.  FFmpeg is then built from source
instead, with only the features cyanrip needs, as in the other release
builds (see ffmpeg-features.sh).  That needs MSYS2 in MSYS2_ROOT
(default C:\msys64), with make, nasm and diffutils.
#>
param(
    [switch]$Static,
    [string]$Prefix,
    [string]$BuildDir,
    [ValidateSet('release', 'debugoptimized')]
    [string]$BuildType = 'release',
    [string]$Triplet,
    # Skip installing the vcpkg packages, when they already are
    [switch]$SkipVcpkg,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flavour = if ($Static) { 'msvc-static' } else { 'msvc' }
if (-not $Prefix) { $Prefix = Join-Path $root "_install\$flavour" }
if (-not $BuildDir) { $BuildDir = Join-Path $root "_build\$flavour" }
if (-not $Triplet) { $Triplet = if ($Static) { 'x64-windows-static' } else { 'x64-windows' } }
New-Item -ItemType Directory -Force $Prefix, $BuildDir | Out-Null
$Prefix = (Resolve-Path $Prefix).Path
$BuildDir = (Resolve-Path $BuildDir).Path

# No param() block: arguments such as -Dcxx=false must reach the program
# rather than be taken as parameters of this function
function Invoke-Checked {
    $exe, $arguments = $args
    Write-Host "+ $exe $($arguments -join ' ')"
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe exited with $LASTEXITCODE" }
}

function Invoke-MesonSetup {
    param([string]$Build, [string]$Source, [string[]]$Options)
    $reconfigure = @()
    if (Test-Path (Join-Path $Build 'meson-private')) { $reconfigure = @('--reconfigure') }
    # (PowerShell names aren't case-sensitive, so this can't be $static)
    $staticOptions = @()
    if ($Static) { $staticOptions = @('--default-library=static', '--prefer-static', '-Db_vscrt=mt') }
    Invoke-Checked meson setup @reconfigure $Build $Source --prefix $Prefix --buildtype $BuildType @staticOptions @Options
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw 'cl.exe not found: run this from a Visual Studio developer PowerShell'
}
# The vcpkg that comes with Visual Studio, which its developer shells put in
# VCPKG_ROOT, only works with manifests: use a full checkout, which has the
# ports.  GitHub's runners have one in VCPKG_INSTALLATION_ROOT.
$vcpkgRoot = @($env:VCPKG_ROOT, $env:VCPKG_INSTALLATION_ROOT) |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'ports')) } |
    Select-Object -First 1
if (-not $vcpkgRoot) {
    throw 'No vcpkg checkout found: clone https://github.com/microsoft/vcpkg, bootstrap it and set VCPKG_ROOT to it'
}
Write-Host "Using vcpkg in $vcpkgRoot"
# The pkg-config Strawberry Perl puts on PATH doesn't work with Meson
if (Get-Command pkgconf -ErrorAction SilentlyContinue) { $env:PKG_CONFIG = 'pkgconf' }

# Dependencies from vcpkg.  FFmpeg needs zlib for PNG cover art, and
# ffprobe for some of the tests.  Statically, FFmpeg is built below, with
# its libraries from vcpkg.
$packages = @('curl', 'libxml2', 'libqrencode', 'chromaprint')
if ($Static) {
    $packages += @('mp3lame', 'libvorbis', 'opus', 'zlib')
} else {
    $packages += 'ffmpeg[core,avcodec,avformat,avfilter,swresample,zlib,ffprobe]'
}
if (-not $SkipVcpkg) {
    Invoke-Checked (Join-Path $vcpkgRoot 'vcpkg') install --triplet $Triplet @packages
}
$vcpkg = Join-Path $vcpkgRoot "installed\$Triplet"
$env:PKG_CONFIG_PATH = "$Prefix\lib\pkgconfig;$vcpkg\lib\pkgconfig"
$env:INCLUDE = "$vcpkg\include;$env:INCLUDE"
$env:LIB = "$vcpkg\lib;$env:LIB"
$env:PATH = "$Prefix\bin;$vcpkg\bin;$vcpkg\tools\ffmpeg;$env:PATH"

# FFmpeg, statically: with MSVC from MSYS2's bash, through the Windows
# pkgconf so that cl gets Windows paths, and with MSVC's link.exe rather
# than MSYS2's
if ($Static) {
    $msys2 = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { 'C:\msys64' }
    $bash = Join-Path $msys2 'usr\bin\bash.exe'
    if (-not (Test-Path $bash)) { throw "MSYS2's bash not found in ${msys2}: set MSYS2_ROOT" }
    $pkgconf = (Get-Command pkgconf -ErrorAction Stop).Source
    $link = Get-Command link.exe -All -CommandType Application |
        Where-Object { $_.Source -like '*\VC\Tools\MSVC\*' } | Select-Object -First 1
    if (-not $link) { throw "MSVC's link.exe not found on PATH" }
    $env:MSYS2_PATH_TYPE = 'inherit'
    $env:CHERE_INVOKING = '1'
    Invoke-Checked $bash -l (($root -replace '\\', '/') + '/scripts/build-ffmpeg-msvc.sh') `
        $Prefix "$BuildDir\ffmpeg" $pkgconf $link.Source
}

# libcdio
Invoke-MesonSetup "$BuildDir\libcdio" "$root\libcdio-C" @(
    '-Dcxx=false', '-Dexamples=false', '-Dtests=false', '-Dcddb=disabled')
Invoke-Checked meson install -C "$BuildDir\libcdio"

# libcdio-paranoia, against the libcdio just installed
Invoke-MesonSetup "$BuildDir\libcdio-paranoia" "$root\libcdio-paranoia" @(
    '--wrap-mode=nofallback', '-Dexamples=false', '-Dtests=false')
Invoke-Checked meson install -C "$BuildDir\libcdio-paranoia"

# libmusicbrainz.  Its install directories are made absolute from the
# prefix given here, so it can't be changed at install time.
$cmakeType = if ($BuildType -eq 'release') { 'Release' } else { 'RelWithDebInfo' }
$cmakeStatic = @()
if ($Static) {
    # The static CRT, which needs a newer policy than the project asks for.
    # curl's and libxml2's headers declare their functions dllimport unless
    # told the libraries are static.
    $cmakeStatic = @('-DBUILD_SHARED_LIBS=OFF', '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
                     '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded')
    $env:CXXFLAGS = '/DCURL_STATICLIB /DLIBXML_STATIC'
}
Invoke-Checked cmake -S "$root\libmusicbrainz" -B "$BuildDir\libmusicbrainz" -G Ninja `
    "-DCMAKE_BUILD_TYPE=$cmakeType" "-DCMAKE_INSTALL_PREFIX=$($Prefix -replace '\\', '/')" `
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot\scripts\buildsystems\vcpkg.cmake" `
    "-DVCPKG_TARGET_TRIPLET=$Triplet" @cmakeStatic
Remove-Item Env:CXXFLAGS -ErrorAction SilentlyContinue
Invoke-Checked cmake --build "$BuildDir\libmusicbrainz" --target musicbrainz5 musicbrainz5cc
Invoke-Checked cmake --install "$BuildDir\libmusicbrainz"

# cyanrip, whose version gets the +npN of RELEASE_TAG (e.g. v0.9.4-rc3+np3),
# or +np without one.  Statically, curl's headers must be told so.
$versionSuffix = '+np'
if ($env:RELEASE_TAG -match '\+(.+)$') { $versionSuffix = "+$($Matches[1])" }
$cyanripOptions = @("-Dversion_suffix=$versionSuffix")
if ($Static) { $cyanripOptions += '-Dc_args=-DCURL_STATICLIB' }
Invoke-MesonSetup "$BuildDir\cyanrip" "$root\cyanrip" $cyanripOptions
Invoke-Checked meson compile -C "$BuildDir\cyanrip"
Invoke-Checked meson install -C "$BuildDir\cyanrip"

if (-not $SkipTests) {
    Invoke-Checked meson test -C "$BuildDir\cyanrip" --print-errorlogs
}

if ($Static) {
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force $dist | Out-Null
    Copy-Item "$BuildDir\cyanrip\src\cyanrip.exe" "$dist\cyanrip-windows-x86_64-msvc.exe"
    Write-Host "Built dist\cyanrip-windows-x86_64-msvc.exe"
} else {
    Write-Host "cyanrip is installed in $Prefix\bin; it needs $vcpkg\bin on PATH to run."
}
