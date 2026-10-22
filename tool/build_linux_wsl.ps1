<#
.SYNOPSIS
  Builds the Linux .deb from Windows, using Ubuntu 24.04 in WSL.

.DESCRIPTION
  Copies the working tree into the WSL home folder (build output and caches
  excluded; Windows and Linux can't share them), runs tool/build_linux.sh
  there, and copies the .deb back to installer\Output.

.EXAMPLE
  .\tool\build_linux_wsl.ps1
#>
param([string]$Distro = 'Ubuntu-24.04')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$drive = $root.Substring(0, 1).ToLower()
$wslRoot = "/mnt/$drive" + $root.Substring(2).Replace('\', '/')

$script = @"
set -euo pipefail
export PATH="`$HOME/flutter/bin:`$PATH"
mkdir -p ~/dukeboxarr-build
rsync -a --delete --exclude build/ --exclude .dart_tool/ --exclude installer/Output/ \
  --exclude .git/ '$wslRoot/' ~/dukeboxarr-build/
cd ~/dukeboxarr-build
sed -i 's/\r$//' tool/build_linux.sh
bash tool/build_linux.sh
mkdir -p '$wslRoot/installer/Output'
cp installer/Output/*.deb '$wslRoot/installer/Output/'
"@
$tmp = Join-Path $root 'build\wsl_build.sh'
New-Item -ItemType Directory -Force (Split-Path $tmp) | Out-Null
[IO.File]::WriteAllText($tmp, $script.Replace("`r`n", "`n"))
wsl -d $Distro -- bash "$wslRoot/build/wsl_build.sh"
if ($LASTEXITCODE -ne 0) { throw 'Linux build failed' }
Get-ChildItem (Join-Path $root 'installer\Output\*.deb') | ForEach-Object { Write-Host "Package: $($_.FullName)" -ForegroundColor Green }
