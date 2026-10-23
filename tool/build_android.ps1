<#
.SYNOPSIS
  Builds the DukeBoxarr Android APK (Android 15+).

.DESCRIPTION
  Builds a release APK signed with the key that android\key.properties points
  to (see android\app\build.gradle.kts), and copies it to
  installer\Output\DukeBoxarr-<version>.apk.

  Every update must be signed with the same key, or Android refuses to
  install it over the existing app. Back up the key.

.EXAMPLE
  .\tool\build_android.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$version = (Select-String pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
Write-Host "DukeBoxarr $version (Android)" -ForegroundColor Yellow
if (-not (Test-Path android\key.properties)) {
  Write-Warning 'android\key.properties not found: the APK will be signed with the debug key and cannot update a release install.'
}
if (-not $env:JAVA_HOME) {
  $env:JAVA_HOME = (Get-ChildItem "$env:ProgramFiles\Microsoft\jdk-21*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

New-Item -ItemType Directory -Force installer\Output | Out-Null
$out = Join-Path $root "installer\Output\DukeBoxarr-$version.apk"
Copy-Item build\app\outputs\flutter-apk\app-release.apk $out -Force
Write-Host "APK: $out" -ForegroundColor Green
