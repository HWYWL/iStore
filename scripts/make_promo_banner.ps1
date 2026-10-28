<#
.SYNOPSIS
  Render 1920x1080 PC promo banners from real device screenshots.
.DESCRIPTION
  Copy, highlight rectangles and layout live in scripts/promo_copy.json.
  Usage: ./scripts/make_promo_banner.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$copyPath = Join-Path $root 'scripts\promo_copy.json'
$outDir = Join-Path $root 'images\promo'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cfg = ([IO.File]::ReadAllText($copyPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json

$W = 1920
$H = 1080

function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function New-GlowBrush([single]$cx, [single]$cy, [single]$radius, [System.Drawing.Color]$c, [int]$alpha) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddEllipse($cx - $radius, $cy - $radius, $radius * 2, $radius * 2)
  $br = New-Object System.Drawing.Drawing2D.PathGradientBrush($p)
  $br.CenterPoint = New-Object System.Drawing.PointF($cx, $cy)
  $br.CenterColor = [System.Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B)
  $br.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $c.R, $c.G, $c.B))
  $p.Dispose()
  return $br
}

foreach ($item in $cfg.items) {
  $bmp = New-Object System.Drawing.Bitmap($W, $H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

  # background
  $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255, 7, 12, 26), [System.Drawing.Color]::FromArgb(255, 9, 30, 46), 15.0)
  $g.FillRectangle($bg, $rect)

  $gA = New-GlowBrush 1500 260 760 ([System.Drawing.Color]::FromArgb(255, 46, 200, 240)) 110
  $g.FillEllipse($gA, 740, -500, 1520, 1520); $gA.Dispose()
  $gB = New-GlowBrush 1150 900 700 ([System.Drawing.Color]::FromArgb(255, 130, 110, 255)) 86
  $g.FillEllipse($gB, 450, 200, 1400, 1400); $gB.Dispose()
  $gC = New-GlowBrush 200 980 560 ([System.Drawing.Color]::FromArgb(255, 52, 220, 160)) 46
  $g.FillEllipse($gC, -360, 420, 1120, 1120); $gC.Dispose()

  $gridPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, 255, 255, 255)), 1
  for ($x = 0; $x -le $W; $x += 80) { $g.DrawLine($gridPen, $x, 0, $x, $H) }
  for ($y = 0; $y -le $H; $y += 80) { $g.DrawLine($gridPen, 0, $y, $W, $y) }

  # screenshot card
  $shotPath = Join-Path $root ($item.shot -replace '/', '\')
  $shot = [System.Drawing.Image]::FromFile($shotPath)
  $cardW = 1100
  $cardH = [int]($cardW * $shot.Height / $shot.Width)
  $cardX = 770
  $cardY = [int](($H - $cardH) / 2) - 10

  for ($s = 46; $s -ge 10; $s -= 6) {
    $a = [int](46 * (1 - $s / 50.0))
    $sp = New-RoundedPath ($cardX - $s * 0.4) ($cardY + 16 - $s * 0.1) ($cardW + $s * 0.8) ($cardH + $s * 0.4) 34
    $sb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, 0, 0, 0))
    $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose()
  }

  $cardPath = New-RoundedPath $cardX $cardY $cardW $cardH 30
  $state = $g.Save()
  $g.SetClip($cardPath)
  $g.DrawImage($shot, (New-Object System.Drawing.Rectangle($cardX, $cardY, $cardW, $cardH)))

  $g.Restore($state)

  $borderRect = New-Object System.Drawing.Rectangle($cardX, $cardY, $cardW, $cardH)
  $borderBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($borderRect, [System.Drawing.Color]::FromArgb(230, 92, 225, 255), [System.Drawing.Color]::FromArgb(200, 150, 135, 255), 60.0)
  $borderPen = New-Object System.Drawing.Pen $borderBrush, 3
  $g.DrawPath($borderPen, $cardPath)

  $hl = New-RoundedPath ($cardX + 12) ($cardY + 3) ($cardW - 24) 74 26
  $hlBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle($cardX, $cardY, $cardW, 76)),
    [System.Drawing.Color]::FromArgb(70, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    90.0)
  $g.FillPath($hlBrush, $hl)

  # text
  $fontBadge = New-Object System.Drawing.Font('Microsoft YaHei', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fontSub = New-Object System.Drawing.Font('Microsoft YaHei', 31, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fontPoint = New-Object System.Drawing.Font('Microsoft YaHei', 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $fontDesc = New-Object System.Drawing.Font('Microsoft YaHei', 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fontFooter = New-Object System.Drawing.Font('Microsoft YaHei', 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

  $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 242, 249, 255))
  $softWhite = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(212, 198, 220, 242))
  $muted = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140, 165, 192, 218))

  # title with auto fit
  $titleSize = 88
  $fontTitle = New-Object System.Drawing.Font('Microsoft YaHei', $titleSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  while ($g.MeasureString($item.title, $fontTitle).Width -gt 640 -and $titleSize -gt 48) {
    $fontTitle.Dispose()
    $titleSize -= 4
    $fontTitle = New-Object System.Drawing.Font('Microsoft YaHei', $titleSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  }

  $badgeText = $item.badge
  $badgeSize = $g.MeasureString($badgeText, $fontBadge)
  $bx = 126; $by = 226
  $pw = $badgeSize.Width + 44
  $ph = 50
  $pill = New-RoundedPath $bx $by $pw $ph 25
  $pillBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 92, 214, 255))
  $g.FillPath($pillBrush, $pill)
  $pillPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(130, 92, 214, 255)), 1.5
  $g.DrawPath($pillPen, $pill)
  $g.DrawString($badgeText, $fontBadge, $softWhite, ($bx + 22), ($by + 13))

  $g.DrawString($item.title, $fontTitle, $white, 120, 298)
  $g.DrawString($item.subtitle, $fontSub, $softWhite, 126, 438)

  $ulBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle(126, 508, 400, 6)),
    [System.Drawing.Color]::FromArgb(255, 52, 211, 255),
    [System.Drawing.Color]::FromArgb(0, 139, 124, 255),
    0.0)
  $g.FillRectangle($ulBrush, 126, 508, 270, 5)

  $py = 566
  foreach ($pt in $item.points) {
    $col = [System.Drawing.ColorTranslator]::FromHtml($pt.color)
    $barBrush = New-Object System.Drawing.SolidBrush $col
    $g.FillRectangle($barBrush, 126, $py + 4, 6, 60)
    $g.DrawString($pt.title, $fontPoint, $white, 150, $py - 4)
    $g.DrawString($pt.desc, $fontDesc, $muted, 150, $py + 42)
    $barBrush.Dispose()
    $py += 120
  }

  $g.DrawString($cfg.footer, $fontFooter, $muted, 126, 988)

  $pngPath = Join-Path $outDir ("pc_banner_" + $item.id + "_1920x1080.png")
  $jpgPath = Join-Path $outDir ("pc_banner_" + $item.id + "_1920x1080.jpg")
  $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 92)
  $bmp.Save($jpgPath, $codec, $encParams)

  $shot.Dispose(); $g.Dispose(); $bmp.Dispose()
  Write-Host "SAVED $pngPath"
}
