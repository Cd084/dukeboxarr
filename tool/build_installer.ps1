<#
.SYNOPSIS
  Builds a release of DukeBoxarr and its Windows installer.

.DESCRIPTION
  1. Reads the version from pubspec.yaml (the single source of truth).
  2. Builds the Flutter Windows release.
  3. Bundles the Visual C++ runtime DLLs next to the exe, so the app runs
     on PCs that don't have the VC++ redistributable installed.
  4. Compiles installer\dukeboxarr.iss with Inno Setup.

  Output: installer\Output\DukeBoxarr-Setup-<version>.exe

.EXAMPLE
  .\tool\build_installer.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$version = (Select-String pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
Write-Host "DukeBoxarr $version" -ForegroundColor Yellow

$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

Write-Host 'Building Flutter release...'
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$release = Join-Path $root 'build\windows\x64\runner\Release'
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item "$env:SystemRoot\System32\$dll" $release -Force
}

Write-Host 'Compiling installer...'
& $iscc "/DAppVersion=$version" /Q (Join-Path $root 'installer\dukeboxarr.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }

$out = Join-Path $root "installer\Output\DukeBoxarr-Setup-$version.exe"
Write-Host "Installer: $out" -ForegroundColor Green
