<#
.SYNOPSIS
  Local / CI build check (no signing, full ArkTS type check).

.DESCRIPTION
  1) Compile ArkTS (default@CompileArkTS): catches compile-time errors in seconds
  2) Optional: pack HAP (requires local signing config)
  3) Optional: run code linter

.NOTES
  Keep this file ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI
  when there is no BOM, which corrupts non-ASCII text.

.EXAMPLE
  ./scripts/ci.ps1
  ./scripts/ci.ps1 -Pack
  ./scripts/ci.ps1 -CliPath "F:\OpenHarmony\command-line-tools\bin"
#>
param(
  [string]$CliPath = $env:OHOS_CLI,
  [switch]$Pack,
  [switch]$Lint
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $CliPath) {
  $CliPath = 'F:\OpenHarmony\command-line-tools\bin'
}
$hvigorw = Join-Path $CliPath 'hvigorw.bat'
if (-not (Test-Path $hvigorw)) {
  Write-Error "hvigorw.bat not found. Pass -CliPath or set OHOS_CLI to command-line-tools/bin"
  exit 1
}

# The all-in-one HarmonyOS SDK that ships next to the CLI tools
# (<command-line-tools>/sdk/default/{openharmony,hms}) is the only SDK root
# hvigor accepts here. Pointing DEVECO_SDK_HOME at the versioned OpenHarmony
# SDK root (e.g. F:\OpenHarmony\Sdk) fails with 00303312.
if (-not $env:DEVECO_SDK_HOME) {
  $sdkRoot = Join-Path (Split-Path -Parent $CliPath) 'sdk'
  if (Test-Path (Join-Path $sdkRoot 'default')) {
    $env:DEVECO_SDK_HOME = $sdkRoot
  }
}
if (-not $env:DEVECO_SDK_HOME) {
  Write-Host "==> DEVECO_SDK_HOME is not set and no bundled SDK found; build will likely fail with 00303312" -ForegroundColor Yellow
} else {
  Write-Host "==> DEVECO_SDK_HOME = $env:DEVECO_SDK_HOME" -ForegroundColor Cyan
}

Push-Location $root
try {
  Write-Host "==> Page registration" -ForegroundColor Cyan
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-pages.ps1')
  if ($LASTEXITCODE -ne 0) { Write-Error "Page registration drift (see above)"; exit $LASTEXITCODE }

  Write-Host "==> Compile ArkTS" -ForegroundColor Cyan
  & $hvigorw --mode module -p module=store@default -p buildMode=debug default@CompileArkTS --no-daemon
  if ($LASTEXITCODE -ne 0) { Write-Error "ArkTS compile failed"; exit $LASTEXITCODE }

  if ($Lint) {
    $linter = Join-Path $CliPath 'codelinter.bat'
    if (Test-Path $linter) {
      Write-Host "==> Code linter" -ForegroundColor Cyan
      # codelinter 6.0.240 exits non-zero on ANY defect and does not honour --exit-on,
      # so gate on the summary line instead: errors fail the build, warnings only report.
      $lintLog = Join-Path $env:TEMP 'codelinter.log'
      & $linter -c code-linter.json5 . 2>&1 | Tee-Object -FilePath $lintLog | Out-Host
      $summary = Select-String -Path $lintLog -Pattern 'Defects:\s*\d+;\s*Errors:\s*(\d+)' | Select-Object -Last 1
      if (-not $summary) {
        Write-Error "Code linter produced no summary line"
        exit 1
      }
      $lintErrors = [int]$summary.Matches[0].Groups[1].Value
      if ($lintErrors -gt 0) {
        Write-Error "Code linter found $lintErrors error(s)"
        exit 1
      }
      Write-Host "==> Lint OK: 0 errors (warnings do not fail the build)" -ForegroundColor Green
    } else {
      Write-Host "==> Skip linter (codelinter.bat not found)" -ForegroundColor Yellow
    }
  }

  if ($Pack) {
    Write-Host "==> Pack HAP (needs signing config)" -ForegroundColor Cyan
    & $hvigorw assembleHap -p buildMode=debug --no-daemon
    if ($LASTEXITCODE -ne 0) { Write-Error "Pack failed"; exit $LASTEXITCODE }
  }

  Write-Host "==> PASS" -ForegroundColor Green
} finally {
  Pop-Location
}
