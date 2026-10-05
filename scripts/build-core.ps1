param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$arch = if ($Runtime -eq 'win-arm64') { 'ARM64' } else { 'x64' }
$output = Join-Path $root "build/core/$Runtime"
# Use CMake from PATH, or the copy bundled with Visual Studio C++ tools.
$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmakeCommand) {
    $cmake = $cmakeCommand.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (!(Test-Path $vswhere)) { throw 'Install CMake or Visual Studio Desktop development with C++.' }
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installation) { throw 'Visual Studio C++ build tools were not found.' }
    $cmake = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    if (!(Test-Path $cmake)) { throw 'Install the Visual Studio C++ CMake tools or add CMake to PATH.' }
}
$ctest = Join-Path (Split-Path $cmake -Parent) 'ctest.exe'
# CMake chooses the latest supported Visual Studio installation by default.
# ARM64 publishing also requires that installation's C++ ARM64 tools.
& $cmake -S (Join-Path $root 'core') -B $output -A $arch
if ($LASTEXITCODE -ne 0) { throw 'C core configuration failed.' }
& $cmake --build $output --config Release
if ($LASTEXITCODE -ne 0) { throw 'C core build failed.' }
# ARM64 binaries cannot run on an x64 build host.
$hostRuntime = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
if ($Runtime -eq $hostRuntime) {
    & $ctest --test-dir $output -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'C core tests failed.' }
}
