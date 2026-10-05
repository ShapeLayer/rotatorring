param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root 'apps/windows/Rotatorring/Rotatorring.csproj'
$output = Join-Path $root "build/windows/$Runtime"
dotnet publish $project -c Release -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $output
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
Write-Host "Built $output/Rotatorring.exe"
