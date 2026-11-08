# HC Customs - Agregar modelos de MakerWorld
# Lee los links de Modelos\links.txt y por cada uno:
#   1. Crea Modelos\<Nombre>\ con todas las fotos en JPG, descripcion.txt (texto para Instagram) e info.txt
#   2. Lo agrega a la web (productos.json + fotos en img\) y regenera el PDF
#   3. Pregunta antes de subir los cambios a GitHub

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Drawing

$Repo    = Split-Path $PSScriptRoot -Parent
$Modelos = Join-Path (Split-Path $Repo -Parent) 'Modelos'
$Links   = Join-Path $Modelos 'links.txt'
$Json    = Join-Path $Repo 'productos.json'
$UA      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
$Utf8    = New-Object System.Text.UTF8Encoding($false)
$Edge    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$GhUser  = 'josuecastro230801-stack'

$Hashtags = @{
  adornos      = '#navidad #adornosnavideños #decoracionnavideña'
  cocina       = '#cortadoresdegalletas #reposteria #galletasdecoradas'
  hogar        = '#decoracion #hogar #navidad'
  regalos      = '#regalos #regalospersonalizados #llaveros'
  herramientas = '#accesorios #gopro #utilidades'
}

function Write-Titulo($t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan }

function Get-Text($url) {
  # La cookie lang=es hace que MakerWorld devuelva el título y la descripción traducidos
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $s.Cookies.Add((New-Object System.Net.Cookie('lang', 'es', '/', 'makerworld.com')))
  $r = Invoke-WebRequest -Uri $url -UserAgent $UA -WebSession $s -Headers @{ Accept = 'application/json' } -UseBasicParsing
  $ms = New-Object System.IO.MemoryStream
  $r.RawContentStream.CopyTo($ms)
  return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Save-Url($url, $path) {
  Invoke-WebRequest -Uri $url -UserAgent $UA -OutFile $path -UseBasicParsing
}

function Limpiar-Html($html) {
  if (-not $html) { return '' }
  $t = $html -replace '(?s)<boostme>.*?</boostme>', ''
  $t = $t -replace '<(br|/p|/li|/h\d)[^>]*>', "`n"
  $t = $t -replace '<[^>]+>', ''
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  $t = ($t -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "`n"
  return $t.Trim()
}

function Nombre-Carpeta($nombre, $id) {
  $n = ($nombre -replace '[<>:"/\\|?*]', '' -replace '\s+', ' ').Trim().TrimEnd('.')
  if ($n.Length -gt 60) { $n = $n.Substring(0, 60).Trim() }
  if (-not $n) { $n = "Modelo $id" }
  $dir = Join-Path $Modelos $n
  if ((Test-Path $dir) -and -not (Test-Path (Join-Path $dir "id-$id.txt"))) { $dir = Join-Path $Modelos "$n ($id)" }
  return $dir
}

# Convierte cualquier foto a JPG (máx. 1440 px de ancho, fondo blanco) para Instagram
function Convertir-Jpg($origen, $destino) {
  try {
    $img = [System.Drawing.Image]::FromFile($origen)
    $w = [Math]::Min(1440, $img.Width); $h = [int]($img.Height * $w / $img.Width)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $w, $h)
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $p = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]92)
    $bmp.Save($destino, $codec, $p)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    Remove-Item $origen
    return $true
  } catch {
    if ($img) { $img.Dispose() }
    return $false
  }
}

function Elegir-Categoria($data) {
  Write-Host 'Categoría:' -ForegroundColor Yellow
  $i = 1
  foreach ($c in $data.categorias) { Write-Host "  $i) $($c.nombre)"; $i++ }
  Write-Host '  N) Nueva categoría'
  while ($true) {
    $r = (Read-Host 'Elige el número').Trim()
    if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $data.categorias.Count) { return $data.categorias[[int]$r - 1].id }
    if ($r -match '^[nN]$') {
      $nombre = (Read-Host 'Nombre de la nueva categoría').Trim()
      if (-not $nombre) { continue }
      $sub = (Read-Host 'Frase corta para la categoría (Enter para dejar vacío)').Trim()
      $id = ($nombre.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^a-z0-9]+', '-').Trim('-')
      $colores = '#6b4e16', '#0f6b6b', '#7a2e4d', '#3d5a1f', '#5a3d8a'
      $color = $colores[$data.categorias.Count % $colores.Count]
      $data.categorias += [pscustomobject]@{ id = $id; nombre = $nombre; sub = $sub; color = $color }
      return $id
    }
  }
}

# ---------- Inicio ----------
if (-not (Test-Path $Modelos)) { New-Item -ItemType Directory $Modelos | Out-Null }
if (-not (Test-Path $Links)) {
  [IO.File]::WriteAllText($Links, "# Pega aquí los links de MakerWorld, uno por línea. Las líneas que empiezan con # se ignoran.`r`n", $Utf8)
}

$lineas = [IO.File]::ReadAllLines($Links, [Text.Encoding]::UTF8)
$pendientes = @($lineas | Where-Object { $_ -match 'makerworld\.com/.*models/(\d+)' })
if ($pendientes.Count -eq 0) {
  Write-Host 'No hay links en Modelos\links.txt. Pega los links (uno por línea), guarda el archivo y vuelve a correr esto.' -ForegroundColor Yellow
  Start-Process notepad.exe $Links
  exit
}

$data = [IO.File]::ReadAllText($Json, [Text.Encoding]::UTF8) | ConvertFrom-Json
$fallidos = @()
$agregados = @()

foreach ($link in $pendientes) {
  $id = [int64]([regex]::Match($link, 'models/(\d+)').Groups[1].Value)
  Write-Titulo "Modelo $id"
  try {
    $d = Get-Text "https://makerworld.com/api/v1/design-service/design/$id" | ConvertFrom-Json
    $titulo = if ($d.titleTranslated) { $d.titleTranslated.Trim() } else { $d.title.Trim() }
    $resumen = Limpiar-Html $(if ($d.summaryTranslated) { $d.summaryTranslated } else { $d.summary })
    $fotos = @(@($d.coverUrl) + @($d.designExtension.design_pictures | ForEach-Object { $_.url }) | Where-Object { $_ } | Select-Object -Unique)
    Write-Host "$titulo  ($($fotos.Count) fotos)"

    $yaEsta = @($data.productos | Where-Object { $_.id -eq $id }).Count -gt 0
    $nombre = $titulo; $desc = ''; $cat = $null
    if ($yaEsta) {
      Write-Host 'Ya está en la web; solo se crea la carpeta.' -ForegroundColor DarkYellow
      $p = $data.productos | Where-Object { $_.id -eq $id } | Select-Object -First 1
      $nombre = $p.nombre; $desc = $p.desc; $cat = $p.cat
    } else {
      $r = (Read-Host "Nombre para el catálogo (Enter = '$titulo')").Trim()
      if ($r) { $nombre = $r }
      # Sugerencia: primera oración del resumen, máximo ~150 caracteres cortando en palabra
      $auto = ($resumen -split "`n" | Where-Object { $_.Length -gt 20 } | Select-Object -First 1)
      if (-not $auto) { $auto = '' }
      $auto = ($auto -split '(?<=[.!?])\s+')[0]
      if ($auto.Length -gt 150) { $auto = $auto.Substring(0, $auto.LastIndexOf(' ', 150)).TrimEnd(',', ';', ':') + '.' }
      Write-Host "Descripción sugerida: $auto" -ForegroundColor DarkGray
      $r = (Read-Host 'Descripción corta (Enter = usar la sugerida)').Trim()
      $desc = if ($r) { $r } else { $auto }
      $cat = Elegir-Categoria $data
    }

    # Carpeta con fotos para Instagram
    $dir = Nombre-Carpeta $nombre $id
    New-Item -ItemType Directory -Force $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir "id-$id.txt"), "$id", $Utf8)
    $i = 0
    foreach ($u in $fotos) {
      $i++
      $tmp = Join-Path $dir ('{0:D2}.tmp' -f $i)
      Save-Url $u $tmp
      if (-not (Convertir-Jpg $tmp (Join-Path $dir ('{0:D2}.jpg' -f $i)))) {
        $ext = [IO.Path]::GetExtension(($u -split '\?')[0]); if (-not $ext) { $ext = '.img' }
        Move-Item -Force $tmp (Join-Path $dir ('{0:D2}{1}' -f $i, $ext))
      }
      Write-Host "  foto $i/$($fotos.Count)"
    }

    $tags = '#impresion3d #3dprinting #honduras #hechoenhonduras #hccustoms'
    if ($cat -and $Hashtags.ContainsKey($cat)) { $tags = "$tags $($Hashtags[$cat])" }
    $ig = @"
✨ $nombre ✨

$desc

🖨️ Impreso en 3D por HC Customs
🎨 Tú eliges los colores
📲 Pedidos por WhatsApp: 8797-3798
🌐 hc-customs-hn.github.io

$tags
"@
    $txt = @"
NOMBRE: $nombre

===== TEXTO PARA INSTAGRAM (copiar y pegar) =====

$ig

===== DESCRIPCIÓN COMPLETA DE MAKERWORLD (traducida) =====

$resumen
"@
    [IO.File]::WriteAllText((Join-Path $dir 'descripcion.txt'), $txt, $Utf8)
    $info = @"
Link: https://makerworld.com/en/models/$id
Título original: $($d.title)
Autor: $($d.designCreator.name)
Licencia: $($d.license)
Descargado: $(Get-Date -Format 'yyyy-MM-dd')
"@
    [IO.File]::WriteAllText((Join-Path $dir 'info.txt'), $info, $Utf8)

    # Web: fotos chicas en img\ y producto en productos.json
    if (-not $yaEsta) {
      $i = 0
      foreach ($u in $fotos) {
        Save-Url "$($u)?x-oss-process=image/resize,w_800" (Join-Path $Repo "img\$id-$i.webp")
        $i++
      }
      $data.productos += [pscustomobject]@{ id = $id; cat = $cat; nombre = $nombre; desc = $desc; fotos = $fotos.Count }
      $agregados += $nombre
    }
    Write-Host "Listo: $dir" -ForegroundColor Green
  } catch {
    Write-Host "No se pudo con $link : $($_.Exception.Message)" -ForegroundColor Red
    $fallidos += $link
  }
}

# Deja en links.txt solo los comentarios y los que fallaron
$quedan = @($lineas | Where-Object { $_ -match '^\s*#' }) + $fallidos
[IO.File]::WriteAllLines($Links, [string[]]$quedan, $Utf8)

if ($agregados.Count -eq 0) {
  Write-Titulo 'Terminado'
  Write-Host 'No hubo productos nuevos para la web.'
  if (-not $env:HCC_TEST) { Start-Process explorer.exe $Modelos }
  exit
}

# Guardar productos y regenerar productos.js
$out = $data | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($Json, $out, $Utf8)
[IO.File]::WriteAllText((Join-Path $Repo 'productos.js'), "window.HCC = $out;`n", $Utf8)

# Regenerar el PDF
Write-Titulo 'Generando el PDF'
$prof = Join-Path $env:TEMP 'hcc-edge'
$src = 'file:///' + ((Join-Path $Repo 'fuente\catalogo.html') -replace '\\', '/')
$pdf = Join-Path $Repo 'catalogo-hc-customs.pdf'
Start-Process -Wait -FilePath $Edge -ArgumentList '--headless=new', '--disable-gpu', '--allow-file-access-from-files', '--no-pdf-header-footer', "--user-data-dir=`"$prof`"", '--virtual-time-budget=20000', "--print-to-pdf=`"$pdf`"", "`"$src`""
Write-Host "PDF actualizado: $pdf"

Write-Titulo 'Subir a la web'
Write-Host "Productos nuevos: $($agregados -join ', ')"
$r = (Read-Host '¿Subir los cambios a hc-customs-hn.github.io? (S/N)').Trim()
if ($r -match '^[sS]') {
  Push-Location $Repo
  try {
    git add -A
    git commit -q -m "Agregar: $($agregados -join ', ')"
    $tok = (gh auth token -u $GhUser).Trim()
    git -c credential.helper= -c "credential.helper=!f(){ echo username=x-access-token; echo password=$tok; }; f" push -q
    Write-Host 'Subido. La página se actualiza en 1 o 2 minutos.' -ForegroundColor Green
  } finally { Pop-Location }
} else {
  Write-Host 'No se subió nada. Los cambios quedan guardados en tu PC.'
}
if (-not $env:HCC_TEST) { Start-Process explorer.exe $Modelos }
