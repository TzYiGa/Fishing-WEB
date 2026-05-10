param(
  [string]$MapboxToken = $env:MAPBOX_ACCESS_TOKEN,
  [string]$StyleZhHant = $env:MAPBOX_STYLE_ZH_HANT,
  [string]$StyleZhHans = $env:MAPBOX_STYLE_ZH_HANS,
  [string]$StyleEn = $env:MAPBOX_STYLE_EN,
  [string]$DartDefinesFile = ""
)
# 若未指定 -DartDefinesFile 且專案根目錄有 dart_defines.json，會自動帶入（CWA、Mapbox 等）。

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$flutterBat = Join-Path $env:USERPROFILE "flutter\bin\flutter.bat"
if (-not (Test-Path $flutterBat)) {
  throw "Flutter not found: $flutterBat"
}

$env:Path = "$env:USERPROFILE\flutter\bin;$env:LOCALAPPDATA\Pub\Cache\bin;$env:Path"

if ([string]::IsNullOrWhiteSpace($MapboxToken)) {
  throw "Missing Mapbox token. Use -MapboxToken or set MAPBOX_ACCESS_TOKEN."
}

Write-Host "Stopping old Dart/Flutter processes..." -ForegroundColor Cyan
Get-Process dart,flutter_tester -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Cleaning old build cache..." -ForegroundColor Cyan
if (Test-Path "build") { Remove-Item "build" -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path ".dart_tool") { Remove-Item ".dart_tool" -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "Running flutter pub get..." -ForegroundColor Cyan
& $flutterBat pub get

Write-Host "Starting flutter run -d chrome..." -ForegroundColor Green
$args = @(
  "run",
  "-d",
  "chrome",
  "--dart-define=MAPBOX_ACCESS_TOKEN=$MapboxToken"
)

$definesPath = $DartDefinesFile
if ([string]::IsNullOrWhiteSpace($definesPath)) {
  $candidate = Join-Path $PSScriptRoot "dart_defines.json"
  if (Test-Path $candidate) {
    $definesPath = $candidate
    Write-Host "Using dart_defines.json for CWA / extra defines." -ForegroundColor DarkCyan
  }
}
if (-not [string]::IsNullOrWhiteSpace($definesPath) -and (Test-Path $definesPath)) {
  $args += "--dart-define-from-file=$definesPath"
}

if (-not [string]::IsNullOrWhiteSpace($StyleZhHant)) {
  $args += "--dart-define=MAPBOX_STYLE_ZH_HANT=$StyleZhHant"
}
if (-not [string]::IsNullOrWhiteSpace($StyleZhHans)) {
  $args += "--dart-define=MAPBOX_STYLE_ZH_HANS=$StyleZhHans"
}
if (-not [string]::IsNullOrWhiteSpace($StyleEn)) {
  $args += "--dart-define=MAPBOX_STYLE_EN=$StyleEn"
}

& $flutterBat @args
