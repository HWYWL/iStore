<#
.SYNOPSIS
  Create (or reuse) a GitHub Release and upload an artifact.

.DESCRIPTION
  Requires a GitHub token with repo scope in GITHUB_TOKEN (or GH_TOKEN).
  Idempotent: reuses an existing release for the tag and replaces the asset
  with the same name before uploading.

.EXAMPLE
  $env:GITHUB_TOKEN = 'ghp_xxx'
  ./scripts/publish-release.ps1 -Tag v3.7.0 -Title 'iStore v3.7.0'
#>
param(
  [string]$Repo = 'HWYWL/iStore',
  [string]$Tag = 'v3.7.0',
  [string]$Title = 'iStore v3.7.0',
  [string]$NotesPath,
  [string]$AssetPath = 'build/outputs/default/iStore-default-unsigned.app',
  [string]$AssetName = 'iStore-default-unsigned-v3.7.0.app'
)

$ErrorActionPreference = 'Stop'

$token = $env:GITHUB_TOKEN
if (-not $token) { $token = $env:GH_TOKEN }
if (-not $token) {
  Write-Error 'GITHUB_TOKEN (repo scope) is required. Create one at https://github.com/settings/tokens'
  exit 1
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $NotesPath) {
  $md = Get-ChildItem -Filter '*v3.7.0.md' -File | Select-Object -First 1
  if ($md) { $NotesPath = $md.FullName }
}
if (-not $NotesPath -or -not (Test-Path $NotesPath)) { Write-Error 'Release notes markdown not found.'; exit 1 }
if (-not (Test-Path $AssetPath)) { Write-Error "Asset not found: $AssetPath"; exit 1 }

$body = [System.IO.File]::ReadAllText((Resolve-Path $NotesPath).Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
$headers = @{
  Authorization = "Bearer $token"
  'User-Agent'  = 'iStore-release'
  Accept        = 'application/vnd.github+json'
}

$release = $null
try {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers -Method Get
} catch {
  $release = $null
}

if (-not $release) {
  $payload = @{
    tag_name   = $Tag
    name       = $Title
    body       = $body
    draft      = $false
    prerelease = $false
  } | ConvertTo-Json -Depth 3
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" `
    -Headers $headers -Method Post -Body $payload -ContentType 'application/json; charset=utf-8'
  Write-Host "Created release $($release.id) for $Tag"
} else {
  Write-Host "Reusing release $($release.id) for $Tag"
}

foreach ($a in @($release.assets)) {
  if ($a -and $a.name -eq $AssetName) {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/assets/$($a.id)" -Headers $headers -Method Delete
    Write-Host "Removed previous asset $AssetName"
  }
}

# GitHub rejects the .app extension, so keep the raw bundle and drop the suffix.
$uploadPath = (Resolve-Path $AssetPath).Path
if ([System.IO.Path]::GetExtension($uploadPath).ToLowerInvariant() -eq '.app') {
  if ($AssetName.ToLowerInvariant().EndsWith('.app')) {
    $AssetName = $AssetName.Substring(0, $AssetName.Length - 4)
  }
  Write-Host "GitHub rejects the .app extension; uploading as $AssetName (rename after download)"
}

$bytes = [System.IO.File]::ReadAllBytes($uploadPath)
$uploadHeaders = @{
  Authorization = "Bearer $token"
  'User-Agent'  = 'iStore-release'
  Accept        = 'application/vnd.github+json'
}
$uri = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$AssetName"
$asset = Invoke-RestMethod -Uri $uri -Headers $uploadHeaders -Method Post `
  -ContentType 'application/octet-stream' -Body $bytes -TimeoutSec 600
Write-Host "Uploaded $($asset.name) ($([math]::Round($bytes.Length / 1MB, 2)) MB) state=$($asset.state)"

$url = "https://github.com/$Repo/releases/tag/$Tag"
Write-Host "Release page: $url"
