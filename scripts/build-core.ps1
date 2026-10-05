param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$arch = if ($Runtime -eq 'win-arm64') { 'ARM64' } else { 'x64' }
$output = Join-Path $root "build/core/$Runtime"
# Requires Visual Studio 2022 C++ tools, including ARM64 tools for win-arm64.
cmake -S (Join-Path $root 'core') -B $output -G 'Visual Studio 17 2022' -A $arch
if ($LASTEXITCODE -ne 0) { throw 'C core configuration failed.' }
cmake --build $output --config Release
if ($LASTEXITCODE -ne 0) { throw 'C core build failed.' }
# ARM64 binaries cannot run on an x64 build host.
$hostRuntime = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
if ($Runtime -eq $hostRuntime) {
    ctest --test-dir $output -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'C core tests failed.' }
}
