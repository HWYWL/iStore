#Requires -Version 5.1
<#
.SYNOPSIS
  Page registration consistency check.

.DESCRIPTION
  A new feature page has to be registered in four places (see mod-nav spec).
  Missing any of them does not fail compilation -- it just breaks silently
  (route not found / not searchable / empty title / cannot open in tablet panel).
  This script turns that silent breakage into a build error.

  Checks:
    1. every `pages/**/*.ets` containing `@Entry` is listed in main_pages.json
    2. every route in main_pages.json (except the entry pages) is in PageRegistry.PAGE_REGISTRY
    3. every route in main_pages.json is in AppNav.PAGE_TITLES
    4. every route in AppNav.EMBEDDABLE is in main_pages.json and has a PageHost branch
    5. no stale route in main_pages.json that has no source file

  Usage: powershell -File scripts/check-pages.ps1 [-Verbose]
  Exit code: 0 = ok, 1 = registration drift found.

.NOTES
  Keep this file ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI when
  there is no BOM, which corrupts non-ASCII text.
#>
param(
  [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ets = Join-Path $root 'store/src/main/ets'
$pagesDir = Join-Path $ets 'pages'
$mainPages = Join-Path $root 'store/src/main/resources/base/profile/main_pages.json'
$registry = Join-Path $ets 'common/nav/PageRegistry.ets'
$appNav = Join-Path $ets 'common/utils/AppNav.ets'
$pageHost = Join-Path $ets 'common/components/PageHost.ets'

foreach ($f in @($mainPages, $registry, $appNav, $pageHost)) {
  if (-not (Test-Path $f)) { Write-Error "missing file: $f"; exit 1 }
}

$problems = New-Object System.Collections.Generic.List[string]

# ---- 1. routes from main_pages.json ----
$json = Get-Content -Raw -Encoding UTF8 $mainPages | ConvertFrom-Json
$routes = @($json.src)
$routeSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $routes) { [void]$routeSet.Add($r) }

# ---- 1b. every @Entry page file must be registered; every route must exist on disk ----
$entryPages = Get-ChildItem -Path $pagesDir -Recurse -Filter *.ets | Where-Object {
  (Get-Content -Raw -Encoding UTF8 $_.FullName) -match '(?m)^\s*@Entry\b'
}
$etsPrefixLen = $ets.Length + 1
foreach ($page in $entryPages) {
  $rel = $page.FullName.Substring($etsPrefixLen) -replace '\\', '/'
  $fileRoute = $rel -replace '\.ets$', ''
  if (-not $routeSet.Contains($fileRoute)) {
    $problems.Add("@Entry page not registered in main_pages.json: $fileRoute")
  }
}
foreach ($r in $routes) {
  $src = Join-Path $ets ($r + '.ets')
  if (-not (Test-Path $src)) {
    $problems.Add("main_pages.json lists a route with no source file: $r")
  }
}

# ---- 2. PageRegistry coverage ----
$registryText = Get-Content -Raw -Encoding UTF8 $registry
$registryRoutes = @([regex]::Matches($registryText, "route:\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$registrySet = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $registryRoutes) { [void]$registrySet.Add($r) }
# entry pages (never shown as tiles) and detail pages (opened with params from another page,
# so they deliberately have no app-center tile of their own)
$notTiles = @(
  'pages/entry/LoginPage',
  'pages/dashboard/MainPage',
  'pages/apps/AppsPage',
  'pages/devices/ClientDetailPage',
  'pages/apps/JellyfinDetailPage',
  'pages/apps/JellyfinPlayerPage'
)
$notTitled = @('pages/entry/LoginPage', 'pages/dashboard/MainPage')
foreach ($r in $routes) {
  if ($notTiles -contains $r) { continue }
  if (-not $registrySet.Contains($r)) {
    $problems.Add("route missing from PageRegistry (no tile / not searchable): $r")
  }
}

# ---- 3. AppNav title coverage ----
$navText = Get-Content -Raw -Encoding UTF8 $appNav
$titleRoutes = @([regex]::Matches($navText, "'(pages/[^']+)':\s*'[^']*'") | ForEach-Object { $_.Groups[1].Value })
$titleSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $titleRoutes) { [void]$titleSet.Add($r) }
foreach ($r in $routes) {
  if ($notTitled -contains $r) { continue }
  if (-not $titleSet.Contains($r)) {
    $problems.Add("route missing from AppNav.PAGE_TITLES (empty page title): $r")
  }
}

# ---- 4. EMBEDDABLE coverage: must exist as route and have a PageHost branch ----
$i = $navText.IndexOf('const EMBEDDABLE')
if ($i -lt 0) { $problems.Add("AppNav: EMBEDDABLE list not found") } else {
  $j = $navText.IndexOf('= [', $i) + 3
  $k = $navText.IndexOf(']', $j)
  $embRoutes = @([regex]::Matches($navText.Substring($j, $k - $j), "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
  $hostText = Get-Content -Raw -Encoding UTF8 $pageHost
  foreach ($r in $embRoutes) {
    if (-not $routeSet.Contains($r)) {
      $problems.Add("EMBEDDABLE route not present in main_pages.json: $r")
    }
    if ($hostText -notmatch [regex]::Escape("url === '" + $r + "'")) {
      $problems.Add("EMBEDDABLE route has no PageHost branch (cannot open in tablet panel): $r")
    }
  }
  if ($VerboseOutput) { Write-Host "embeddable routes checked: $($embRoutes.Count)" }
}

# ---- report ----
if ($VerboseOutput) {
  Write-Host "routes: $($routes.Count) / registry: $($registryRoutes.Count) / titles: $($titleRoutes.Count) / entry pages: $($entryPages.Count)"
}
if ($problems.Count -gt 0) {
  Write-Host "==> Page registration drift:" -ForegroundColor Red
  foreach ($p in $problems) { Write-Host "    - $p" -ForegroundColor Red }
  exit 1
}
Write-Host "==> Page registration OK"
exit 0
