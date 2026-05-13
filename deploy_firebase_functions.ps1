# Deploy Cloud Functions (Admin SDK callables). Requires Blaze billing on the Firebase project.
# Run:  .\deploy_firebase_functions.ps1

$ErrorActionPreference = 'Continue'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $root

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

Write-Host "[INFO] Firebase project: $firebaseProjectId"
Write-Host '[INFO] Deploying functions from .\functions ...'

& firebase deploy --only functions --project $firebaseProjectId
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[ERROR] Functions deploy failed.'
    exit 1
}

Write-Host ''
Write-Host 'Done.'
exit 0
