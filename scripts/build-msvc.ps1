<#
.SYNOPSIS
Builds libcdio, libcdio-paranoia, libmusicbrainz and cyanrip with MSVC,
then runs cyanrip's tests.

.DESCRIPTION
Run it from a Visual Studio developer PowerShell (or after
ilammy/msvc-dev-cmd in CI), with Meson, Ninja and pkgconf on PATH
(pip install meson ninja pkgconf) and vcpkg in VCPKG_ROOT or
VCPKG_INSTALLATION_ROOT.

FFmpeg, curl, libxml2 and pthreads4w come from vcpkg; the libraries in
the submodules are installed into -Prefix, which cyanrip is built
against.
#>
param(
    [string]$Prefix = (Join-Path $PSScriptRoot '..\_install\msvc'),
    [string]$BuildDir = (Join-Path $PSScriptRoot '..\_build\msvc'),
    [ValidateSet('release', 'debugoptimized')]
    [string]$BuildType = 'release',
    [string]$Triplet = 'x64-windows',
    # Skip installing the vcpkg packages, when they already are
    [switch]$SkipVcpkg,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
    Invoke-Checked meson setup @reconfigure $Build $Source --prefix $Prefix --buildtype $BuildType @Options
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw 'cl.exe not found: run this from a Visual Studio developer PowerShell'
}
$vcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { $env:VCPKG_INSTALLATION_ROOT }
if (-not $vcpkgRoot) { throw 'Set VCPKG_ROOT to your vcpkg checkout' }
# The pkg-config Strawberry Perl puts on PATH doesn't work with Meson
if (Get-Command pkgconf -ErrorAction SilentlyContinue) { $env:PKG_CONFIG = 'pkgconf' }

# Dependencies from vcpkg.  FFmpeg needs zlib for PNG cover art, and
# ffprobe for some of the tests.
if (-not $SkipVcpkg) {
    Invoke-Checked (Join-Path $vcpkgRoot 'vcpkg') install --triplet $Triplet `
        'ffmpeg[core,avcodec,avformat,avfilter,swresample,zlib,ffprobe]' curl libxml2 pthreads
}
$vcpkg = Join-Path $vcpkgRoot "installed\$Triplet"
$env:PKG_CONFIG_PATH = "$Prefix\lib\pkgconfig;$vcpkg\lib\pkgconfig"
$env:INCLUDE = "$vcpkg\include;$env:INCLUDE"
$env:LIB = "$vcpkg\lib;$env:LIB"
$env:PATH = "$Prefix\bin;$vcpkg\bin;$vcpkg\tools\ffmpeg;$env:PATH"

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
Invoke-Checked cmake -S "$root\libmusicbrainz" -B "$BuildDir\libmusicbrainz" -G Ninja `
    "-DCMAKE_BUILD_TYPE=$cmakeType" "-DCMAKE_INSTALL_PREFIX=$($Prefix -replace '\\', '/')" `
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot\scripts\buildsystems\vcpkg.cmake" `
    "-DVCPKG_TARGET_TRIPLET=$Triplet"
Invoke-Checked cmake --build "$BuildDir\libmusicbrainz" --target musicbrainz5 musicbrainz5cc
Invoke-Checked cmake --install "$BuildDir\libmusicbrainz"

# cyanrip
Invoke-MesonSetup "$BuildDir\cyanrip" "$root\cyanrip" @()
Invoke-Checked meson compile -C "$BuildDir\cyanrip"
Invoke-Checked meson install -C "$BuildDir\cyanrip"

if (-not $SkipTests) {
    Invoke-Checked meson test -C "$BuildDir\cyanrip" --print-errorlogs
}

Write-Host "cyanrip is installed in $Prefix\bin; it needs $vcpkg\bin on PATH to run."
