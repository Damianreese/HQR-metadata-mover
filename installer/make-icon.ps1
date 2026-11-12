<#
  Draws app.ico for HQR Metadata Mover: two boxes with arrows between them, white on the HQR blue rounded
  square used by the other HQR apps. Run it again only if the icon needs to change.
#>
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'app.ico'
$blue = [System.Drawing.ColorTranslator]::FromHtml('#2A78D6')

function New-IconPng([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)

  # Rounded square background.
  $r = $size * 0.22; $d = $r * 2; $e = $size - 1
  $bg = New-Object System.Drawing.Drawing2D.GraphicsPath
  $bg.AddArc(0, 0, $d, $d, 180, 90); $bg.AddArc($e - $d, 0, $d, $d, 270, 90)
  $bg.AddArc($e - $d, $e - $d, $d, $d, 0, 90); $bg.AddArc(0, $e - $d, $d, $d, 90, 90); $bg.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush($blue)), $bg)

  # The symbol is drawn on a 24-unit grid, scaled into the middle of the square.
  $k = $size * 0.70 / 24; $o = $size * 0.15
  $P = { param($x, $y) New-Object System.Drawing.PointF(($o + $x * $k), ($o + $y * $k)) }
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [Math]::Max(1.4, 2.3 * $k))
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'

  foreach ($box in @(2.5, 12.5)) {
    $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $x = $o + $box * $k; $w = 9 * $k; $rr = 2 * 2 * $k
    $bp.AddArc($x, $x, $rr, $rr, 180, 90); $bp.AddArc($x + $w - $rr, $x, $rr, $rr, 270, 90)
    $bp.AddArc($x + $w - $rr, $x + $w - $rr, $rr, $rr, 0, 90); $bp.AddArc($x, $x + $w - $rr, $rr, $rr, 90, 90); $bp.CloseFigure()
    $g.DrawPath($pen, $bp)
  }
  # Top-right arrow (from the first box toward the second) and its mirror at the bottom-left.
  $a = New-Object System.Drawing.Drawing2D.GraphicsPath
  $a.AddLine((& $P 14.5 5), (& $P 17 5)); $a.AddArc(($o + 14 * $k), ($o + 5 * $k), (6 * $k), (6 * $k), 270, 90); $a.AddLine((& $P 20 8), (& $P 20 9.5))
  $g.DrawPath($pen, $a)
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((& $P 17.6 7.6), (& $P 20 10), (& $P 22.4 7.6)))
  $m = New-Object System.Drawing.Drawing2D.GraphicsPath
  $m.AddLine((& $P 9.5 19), (& $P 7 19)); $m.AddArc(($o + 4 * $k), ($o + 13 * $k), (6 * $k), (6 * $k), 90, 90); $m.AddLine((& $P 4 16), (& $P 4 14.5))
  $g.DrawPath($pen, $m)
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((& $P 6.4 16.4), (& $P 4 14), (& $P 1.6 16.4)))

  $g.Dispose()
  $ms = New-Object IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  , $ms.ToArray()
}

# .ico file: header, one directory entry per size, then each size as PNG data.
$sizes = 16, 24, 32, 48, 64, 256
$pngs = $sizes | ForEach-Object { , (New-IconPng $_) }
$fs = [IO.File]::Create($out); $w = New-Object IO.BinaryWriter($fs)
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $dim = if ($s -ge 256) { 0 } else { $s }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
  $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Close()
"Wrote $out"
[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'app-preview.png'), $pngs[-1])

# Microsoft Store package images: the icon centered on a transparent canvas of each required size.
$assets = Join-Path (Split-Path $PSScriptRoot -Parent) 'store\Assets'
New-Item -ItemType Directory -Force $assets | Out-Null
function Save-Asset([string]$name, [int]$w, [int]$h, [int]$icon) {
  $ms = New-Object IO.MemoryStream(, (New-IconPng $icon))
  $img = [System.Drawing.Image]::FromStream($ms)
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($img, [int](($w - $icon) / 2), [int](($h - $icon) / 2), $icon, $icon); $g.Dispose()
  $bmp.Save((Join-Path $assets $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $img.Dispose()
}
Save-Asset 'StoreLogo.png' 50 50 50
Save-Asset 'Square44x44Logo.png' 44 44 44
Save-Asset 'Square150x150Logo.png' 150 150 100
Save-Asset 'Wide310x150Logo.png' 310 150 100
"Wrote Store images to $assets"
# 300x300 logo for the Partner Center listing (uploaded there, not part of the package).
[IO.File]::WriteAllBytes((Join-Path (Split-Path $assets -Parent) 'StoreLogo-300.png'), (New-IconPng 300))
