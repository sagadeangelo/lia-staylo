# === Ajusta si tu ruta cambia ===
$proj = "D:\PROYECTOS-FLUTTER\lia-staylo"
$runner = "$proj\build\windows\x64\runner\Release"
$dst    = "$proj\dist_msix\packageroot\LIAStaylo"

# 0) Verifica que la build "buena" existe
@(
  "$runner\lia_staylo.exe",
  "$runner\flutter_windows.dll",
  "$runner\icudtl.dat",
  "$runner\data\flutter_assets\isolate_snapshot_data"
) | % { "{0,-90} {1}" -f $_,(Test-Path $_) }

# 1) Limpia SOLO la carpeta de la app dentro del MSIX (no toques backend/LT)
if (Test-Path $dst) { Get-ChildItem $dst -Force | Remove-Item -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# 2) Copia TODO el bundle del runner (exe, dll, icu, data, plugins, etc.)
Copy-Item "$runner\*" $dst -Recurse -Force

# 3) Sanity check: abre la app desde el MSIX staging (debe verse AZUL y con Health/Upload OK)
Write-Host "`nAbriendo la app staged (debe verse AZUL): $dst\lia_staylo.exe"
& "$dst\lia_staylo.exe"
