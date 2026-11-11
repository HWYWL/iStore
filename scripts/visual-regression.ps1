#Requires -Version 5.1
<#
.SYNOPSIS
  Visual regression harness for iStore (screen capture + pixel diff).

.DESCRIPTION
  Captures a fixed set of screens on a connected device and compares them against
  committed baselines, so a theme/material change that breaks layout is caught
  without eyeballing every page.

  Navigation is text-driven (dumpLayout -> tap by visible label), so it does not
  depend on screen coordinates or window size. Material is switched through the
  theme page when -Material is given.

  Modes:
    -Mode capture   capture current state into <OutDir>/baseline/<material>/<page>.png
    -Mode compare   capture into <OutDir>/current/... and diff against baseline,
                    writing <OutDir>/diff/<material>-<page>.png and failing when the
                    differing-pixel ratio exceeds -Tolerance (percent)

  Usage:
    powershell -File scripts/visual-regression.ps1 -Mode capture -Material solid
    powershell -File scripts/visual-regression.ps1 -Mode compare -Material liquid

.NOTES
  Keep this file ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI when
  there is no BOM, which corrupts non-ASCII text. UI labels are therefore built
  from code points via U().
  Baselines are device-resolution specific: capture on the same device model you
  intend to compare on (PCE-W30, 2880x1920).
#>
param(
  [ValidateSet('capture', 'compare')]
  [string]$Mode = 'compare',
  [ValidateSet('solid', 'liquid', 'as-is')]
  [string]$Material = 'as-is',
  [string]$OutDir = 'visual',
  [double]$Tolerance = 8.0,
  [string]$HdcPath = '',
  [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ---------- UI labels (code points; keeps this file ASCII) ----------
function U([int[]]$Codes) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $Codes) { [void]$sb.Append([char]$c) }
  return $sb.ToString()
}
$L_THEME    = U @(0x4E3B, 0x9898)                          # theme
$L_LIQUID   = U @(0x6DB2, 0x6001, 0x73BB, 0x7483)          # liquid glass
$L_SOLID    = U @(0x9ED8, 0x8BA4)                          # default
$L_NETWORK  = U @(0x7F51, 0x7EDC, 0x7BA1, 0x7406)          # network mgmt
$L_SECURITY = U @(0x5B89, 0x5168, 0x4E2D, 0x5FC3)          # security hub
$L_WIFI     = U @(0x57, 0x69, 0x46, 0x69, 0x20, 0x7BA1, 0x7406)  # WiFi mgmt

# ---------- tools ----------
if (-not $HdcPath) {
  $candidates = @()
  if ($env:OHOS_CLI) { $candidates += (Join-Path (Split-Path -Parent $env:OHOS_CLI) 'sdk/default/openharmony/toolchains/hdc.exe') }
  if ($env:DEVECO_SDK_HOME) { $candidates += (Join-Path $env:DEVECO_SDK_HOME 'default/openharmony/toolchains/hdc.exe') }
  $candidates += 'F:\OpenHarmony\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe'
  $candidates += 'F:\OpenHarmony\Sdk\23\toolchains\hdc.exe'
  foreach ($c in $candidates) { if (Test-Path $c) { $HdcPath = $c; break } }
}
if (-not $HdcPath -or -not (Test-Path $HdcPath)) { Write-Error "hdc.exe not found; pass -HdcPath"; exit 1 }

function Hdc([string[]]$Actions) {
  $hdcArgs = @()
  if ($Device) { $hdcArgs += @('-t', $Device) }
  $hdcArgs += $Actions
  & $HdcPath @hdcArgs 2>&1
}

if (-not $Device) {
  $targets = @(Hdc @('list', 'targets') | Where-Object { $_ -match '\S' -and $_ -notmatch 'Empty' })
  if ($targets.Count -eq 0) { Write-Error "no device connected"; exit 1 }
  $Device = ($targets[0] -replace '\s', '')
  Write-Host "==> device: $Device"
}

$remoteTmp = '/data/local/tmp/istore-visual'
$localTmp = Join-Path $env:TEMP 'istore-visual'
New-Item -ItemType Directory -Force -Path $localTmp | Out-Null
Hdc @('shell', "mkdir -p $remoteTmp") | Out-Null

$L_APPS = U @(0x5E94, 0x7528, 0x4E2D, 0x5FC3)  # app center header
$BUNDLE = 'com.yi.store'
$ABILITY = 'StoreAbility'

function Restart-App {
  Hdc @('shell', "aa force-stop $BUNDLE") | Out-Null
  Start-Sleep -Milliseconds 800
  Hdc @('shell', "aa start -a $ABILITY -b $BUNDLE") | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 1000
    if (Get-Bounds $L_APPS) { Start-Sleep -Milliseconds 1500; return $true }
  }
  Write-Warning 'app did not become ready in time'
  return $false
}

# ---------- pages under test ----------
# Label empty = keep the dashboard (three columns) as-is.
$pages = @(
  @{ Name = 'home';     Label = '' },
  @{ Name = 'network';  Label = $L_NETWORK },
  @{ Name = 'security'; Label = $L_SECURITY },
  @{ Name = 'wifi';     Label = $L_WIFI }
)

# ---------- navigation helpers ----------
function Save-Layout {
  Hdc @('shell', "uitest dumpLayout -p $remoteTmp/layout.json") | Out-Null
  Hdc @('file', 'recv', "$remoteTmp/layout.json", (Join-Path $localTmp 'layout.json')) | Out-Null
  return (Join-Path $localTmp 'layout.json')
}

function Get-Bounds([string]$Label) {
  $file = Save-Layout
  if (-not (Test-Path $file)) { return $null }
  $json = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
  $found = $null
  $stack = New-Object System.Collections.Stack
  $stack.Push(@($json, $null))
  while ($stack.Count -gt 0) {
    $item = $stack.Pop()
    $node = $item[0]
    $box = $item[1]
    $attrs = $node.attributes
    if ($attrs -and $attrs.text -and ($attrs.text.Trim() -eq $Label)) { $found = @{ Text = $attrs.bounds; Click = $box }; break }
    if ($attrs -and $attrs.clickable -eq 'true') { $box = $attrs.bounds }
    $children = $node.children
    if ($children) { foreach ($c in $children) { $stack.Push(@($c, $box)) } }
  }
  if (-not $found) { return $null }
  $raw = $found.Click
  if (-not $raw) { $raw = $found.Text }
  $nums = [regex]::Matches($raw, '-?\d+') | ForEach-Object { [int]$_.Value }
  if ($nums.Count -lt 4) { return $null }
  return @{ X = [int](($nums[0] + $nums[2]) / 2); Y = [int](($nums[1] + $nums[3]) / 2) }
}

function Scroll-Apps([int]$Times = 1, [string]$Direction = 'down') {
  # down = reveal lower items (swipe up); up = back to the top of the app center
  $from = 1500; $to = 800
  if ($Direction -eq 'up') { $from = 800; $to = 1500 }
  for ($i = 0; $i -lt $Times; $i++) {
    Hdc @('shell', "uitest uiInput swipe 1150 $from 1150 $to 900") | Out-Null
    Start-Sleep -Milliseconds 500
  }
}

function Tap-Label([string]$Label, [int]$Scrolls = 6) {
  # start from a known position: the app center keeps its scroll offset between
  # runs, so always rewind to the top before searching downward
  Scroll-Apps 6 'up'
  for ($i = 0; $i -le $Scrolls; $i++) {
    $b = Get-Bounds $Label
    if ($b) {
      Hdc @('shell', "uitest uiInput click $($b.X) $($b.Y)") | Out-Null
      Start-Sleep -Milliseconds 1500
      return $true
    }
    Scroll-Apps 1
  }
  return $false
}

function Tap-Back {
  Hdc @('shell', 'uitest uiInput keyEvent Back') | Out-Null
  Start-Sleep -Milliseconds 1200
}

function Set-Material([string]$Kind) {
  if ($Kind -eq 'as-is') { return $true }
  $label = $L_SOLID
  if ($Kind -eq 'liquid') { $label = $L_LIQUID }
  if (-not (Tap-Label $L_THEME)) { Write-Warning 'theme page not reachable; keeping current material'; return $false }
  if (-not (Tap-Label $label 2)) { Write-Warning "material option not found: $Kind"; return $false }
  Tap-Back
  Start-Sleep -Milliseconds 1200
  return $true
}

function Capture([string]$Name, [string]$TargetDir) {
  New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  $remote = "$remoteTmp/$Name.jpeg"
  Hdc @('shell', "snapshot_display -f $remote") | Out-Null
  $local = Join-Path $TargetDir "$Name.png"
  Hdc @('file', 'recv', $remote, "$local.tmp.jpeg") | Out-Null
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile("$local.tmp.jpeg")
  # store at 720px wide: comparison runs at 200px, 720 keeps the diff readable
  # while cutting the committed baseline set from ~15 MB to ~2 MB
  $w = 720
  $h = [int]($img.Height * $w / $img.Width)
  $small = New-Object System.Drawing.Bitmap($w, $h)
  $gfx = [System.Drawing.Graphics]::FromImage($small)
  $gfx.DrawImage($img, 0, 0, $w, $h)
  $gfx.Dispose()
  $small.Save($local, [System.Drawing.Imaging.ImageFormat]::Png)
  $small.Dispose()
  $img.Dispose()
  Remove-Item "$local.tmp.jpeg" -Force
  return $local
}

function Compare-Images([string]$Baseline, [string]$Current, [string]$DiffOut, [double]$Tolerance) {
  Add-Type -AssemblyName System.Drawing
  $a = New-Object System.Drawing.Bitmap($Baseline)
  $b = New-Object System.Drawing.Bitmap($Current)
  if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) {
    $msg = "size mismatch $($a.Width)x$($a.Height) vs $($b.Width)x$($b.Height)"
    $a.Dispose(); $b.Dispose()
    return @{ Ratio = 100.0; Note = $msg }
  }

  # Compare structure, not pixels:
  #  - grayscale: live accent colors (rates, charts) should not decide the verdict
  #  - 200px wide: averages text glyphs and chart detail away, keeps card geometry
  #  - mean normalization: screenshots differ by ~2 levels of global brightness
  #    between runs (window compositing), which would otherwise dominate
  # Measured on PCE-W30: same state twice = 5.5-6.5%, solid vs liquid = ~16%.
  $cmpW = 200
  $cmpH = [int]($a.Height * $cmpW / $a.Width)
  $aSmall = New-Object System.Drawing.Bitmap($cmpW, $cmpH)
  $bSmall = New-Object System.Drawing.Bitmap($cmpW, $cmpH)
  $g = [System.Drawing.Graphics]::FromImage($aSmall)
  $g.DrawImage($a, 0, 0, $cmpW, $cmpH)
  $g.Dispose()
  $g2 = [System.Drawing.Graphics]::FromImage($bSmall)
  $g2.DrawImage($b, 0, 0, $cmpW, $cmpH)
  $g2.Dispose()

  $lumA = 0.0; $lumB = 0.0
  for ($y = 0; $y -lt $cmpH; $y++) {
    for ($x = 0; $x -lt $cmpW; $x++) {
      $pa = $aSmall.GetPixel($x, $y); $pb = $bSmall.GetPixel($x, $y)
      $lumA += 0.299 * $pa.R + 0.587 * $pa.G + 0.114 * $pa.B
      $lumB += 0.299 * $pb.R + 0.587 * $pb.G + 0.114 * $pb.B
    }
  }
  $n = $cmpW * $cmpH
  # bring the baseline to the current image's average brightness
  $offset = ($lumB - $lumA) / $n

  $diff = New-Object System.Drawing.Bitmap($cmpW, $cmpH)
  $differed = 0
  for ($y = 0; $y -lt $cmpH; $y++) {
    for ($x = 0; $x -lt $cmpW; $x++) {
      $pa = $aSmall.GetPixel($x, $y); $pb = $bSmall.GetPixel($x, $y)
      $la = 0.299 * $pa.R + 0.587 * $pa.G + 0.114 * $pa.B + $offset
      $lb = 0.299 * $pb.R + 0.587 * $pb.G + 0.114 * $pb.B
      $delta = [Math]::Abs($la - $lb)
      if ($delta -gt 20) {
        $differed++
        $diff.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 255, 0, 0))
      } else {
        $diff.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(60, $pb.R, $pb.G, $pb.B))
      }
    }
  }
  $diff.Save($DiffOut, [System.Drawing.Imaging.ImageFormat]::Png)
  $ratio = 100.0 * $differed / $n
  $aSmall.Dispose(); $bSmall.Dispose()
  $a.Dispose(); $b.Dispose(); $diff.Dispose()
  return @{ Ratio = [Math]::Round($ratio, 2); Note = '' }
}

# ---------- run ----------
# A fresh launch gives a deterministic starting scroll position for the home shot.
[void](Restart-App)

if (-not (Set-Material $Material)) {
  Write-Host "==> material could not be switched; capturing current state" -ForegroundColor Yellow
}

$rootDir = Join-Path $root $OutDir
if ($Mode -eq 'capture') {
  $dir = Join-Path $rootDir "baseline/$Material"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
} else {
  $dir = Join-Path $rootDir "current/$Material"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $diffDir = Join-Path $rootDir 'diff'
  New-Item -ItemType Directory -Force -Path $diffDir | Out-Null
}

$failures = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($p in $pages) {
  if ($p.Label) {
    if (-not (Tap-Label $p.Label)) {
      Write-Warning "page not reachable: $($p.Name)"
      $failures.Add("$($p.Name): not reachable")
      continue
    }
  }
  $file = Capture $p.Name $dir
  if ($Mode -eq 'capture') {
    Write-Host "    captured $($p.Name) -> $file"
  } else {
    $baseline = Join-Path $rootDir "baseline/$Material/$($p.Name).png"
    if (-not (Test-Path $baseline)) {
      $failures.Add("$($p.Name): no baseline")
      $rows.Add([pscustomobject]@{ Page = $p.Name; Material = $Material; Diff = 'n/a'; Status = 'NO BASELINE' })
    } else {
      $diffFile = Join-Path $diffDir "$Material-$($p.Name).png"
      $r = Compare-Images $baseline $file $diffFile $Tolerance
      $status = 'ok'
      if ($r.Ratio -gt $Tolerance) { $status = 'DRIFT' }
      if ($status -eq 'DRIFT') { $failures.Add("$($p.Name): $($r.Ratio)% differs") }
      $rows.Add([pscustomobject]@{ Page = $p.Name; Material = $Material; Diff = "$($r.Ratio)%"; Status = $status })
    }
  }
  if ($p.Label) { Tap-Back }
}

if ($Mode -eq 'compare') {
  $rows | Format-Table -AutoSize | Out-String | Write-Host
  if ($failures.Count -gt 0) {
    Write-Host "==> Visual drift detected (tolerance $Tolerance%):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "    - $f" -ForegroundColor Red }
    Write-Host "    diff images: $diffDir" -ForegroundColor Yellow
    exit 1
  }
  Write-Host "==> Visual OK ($($rows.Count) screens, tolerance $Tolerance%)"
}
exit 0
