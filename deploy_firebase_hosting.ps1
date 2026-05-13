# Fishing map: Flutter web build + Firebase Hosting deploy
# Run:  .\deploy_firebase_hosting.ps1
# Or double-click deploy_firebase_hosting.bat (launches this script).

$ErrorActionPreference = 'Continue'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $root

try {
    $Host.UI.RawUI.WindowTitle = 'Fishing map - Web deploy'
} catch {}

Write-Host ''
Write-Host '========================================'
Write-Host '  Fishing map - Web build + Firebase Hosting deploy'
Write-Host '========================================'
Write-Host "  Folder: $root"
Write-Host '========================================'
Write-Host ''

# 強制部署到 repo 設定的 Firebase 專案（避免因本機曾執行 firebase use 而部署錯專案）
$fbRc = Join-Path $root '.firebaserc'
$firebaseProjectId = $null
if (Test-Path -LiteralPath $fbRc) {
    try {
        $parsed = Get-Content -LiteralPath $fbRc -Raw | ConvertFrom-Json
        $firebaseProjectId = $parsed.projects.default
    } catch {}
}
if ([string]::IsNullOrWhiteSpace($firebaseProjectId)) {
    Write-Host '[ERROR] Could not read projects.default from .firebaserc'
    exit 1
}
Write-Host "[INFO] Firebase project (from .firebaserc): $firebaseProjectId"
Write-Host "[INFO] After deploy, open Hosting URL for THIS project in Firebase Console, or:"
Write-Host "       https://${firebaseProjectId}.web.app"
Write-Host ''

$gitHash = "nogit"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    try {
        $gh = (& git rev-parse --short HEAD 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($gh)) {
            $gitHash = $gh
        }
    } catch {}
}
$buildVersion = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd.HHmm"), $gitHash
Write-Host "[INFO] Build version: $buildVersion"

$dartDefines = Join-Path $root 'dart_defines.json'
if (-not (Test-Path -LiteralPath $dartDefines)) {
    Write-Host '[ERROR] dart_defines.json not found.'
    Write-Host 'Copy dart_defines.example.json to dart_defines.json and add Mapbox/CWA keys.'
    exit 1
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host '[ERROR] firebase CLI not found.'
    Write-Host 'Install: npm install -g firebase-tools'
    Write-Host 'Then run: firebase login'
    exit 1
}

$flutterExe = $null
$fc = Get-Command flutter -ErrorAction SilentlyContinue
if ($fc) {
    $flutterExe = $fc.Source
} else {
    $fallback = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $fallback) {
        $flutterExe = $fallback
    }
}

if (-not $flutterExe) {
    Write-Host '[ERROR] Flutter SDK not found.'
    Write-Host 'Add Flutter bin to PATH, or install SDK at:'
    Write-Host ("  " + (Join-Path $env:USERPROFILE 'flutter'))
    exit 1
}

Write-Host '[1/2] flutter build web --release (--pwa-strategy=none 減少舊 SW 卡住更新) ...'
& $flutterExe @(
    'build',
    'web',
    '--release',
    '--pwa-strategy=none',
    '--dart-define-from-file=dart_defines.json',
    "--dart-define=APP_VERSION=$buildVersion"
)
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[ERROR] Build failed.'
    exit 1
}

Write-Host ''
Write-Host '[2/2] firebase deploy --only hosting ...'
& firebase deploy --only hosting --project $firebaseProjectId
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[ERROR] Deploy failed.'
    exit 1
}

Write-Host ''
Write-Host 'Done. With Hosting Cache-Control + --pwa-strategy=none, a normal refresh should show updates.'
Write-Host 'If you still see stale JS once, unregister old Service Workers one time (old installs only).'
Write-Host ''
exit 0
