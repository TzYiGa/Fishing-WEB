# Run from functions\ folder: deploys parent repo's Cloud Functions script.
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
& (Join-Path $repoRoot "deploy_firebase_functions.ps1")
