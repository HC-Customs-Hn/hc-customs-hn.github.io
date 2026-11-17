# Guarda tu usuario y clave de API de Cults3D cifrados con tu usuario de Windows.
# El archivo queda en Modelos\cults-clave.dat (fuera del repo, no se sube a GitHub).
$ErrorActionPreference = 'Stop'
$Modelos = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Modelos'
$Archivo = Join-Path $Modelos 'cults-clave.dat'
Write-Host 'Configurar Cults3D' -ForegroundColor Cyan
Write-Host 'Crea o copia tu clave en https://cults3d.com/en/api/keys'
$usuario = (Read-Host 'Tu nombre de usuario de Cults3D').Trim()
$clave = Read-Host 'Pega tu clave de API (no se ve al escribir)' -AsSecureString
$cifrada = $clave | ConvertFrom-SecureString
[IO.File]::WriteAllLines($Archivo, [string[]]@($usuario, $cifrada))
Write-Host "Guardado en $Archivo" -ForegroundColor Green
