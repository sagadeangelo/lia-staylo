# make_dist.ps1 - minimal, ASCII-only
$ErrorActionPreference = "Stop"

# === CONFIG ===
$ProjectRoot = "D:\PROYECTOS-FLUTTER\lia-staylo"
$DistRoot    = "D:\LIA-Staylo_dist"
$AppName     = "LIA-Staylo"
$DistApp     = Join-Path $DistRoot $AppName

# Flutter Windows release
$FlutterWinBuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"

# Backend (PyInstaller onedir)
$BackendRoot     = Join-Path $ProjectRoot "backend"
$PyInstallerOut  = Join-Path $BackendRoot "dist\lia-backend"
$BackendRulesDir = Join-Path $BackendRoot "rules"

# LanguageTool and scripts
$LanguageToolSrc = Join-Path $ProjectRoot "LanguageTool"
$ScriptsSrc      = Join-Path $ProjectRoot "scripts"

# Destinations
$DestAppDir  = Join-Path $DistApp "app"
$DestBackDir = Join-Path $DistApp "backend\dist\lia-backend"
$DestRules   = Join-Path $DistApp "backend\rules"
$DestLTDir   = Join-Path $DistApp "LanguageTool"
$DestScripts = Join-Path $DistApp "scripts"
$DestPrereqs = Join-Path $DistApp "Prereqs"

function New-Dir([string]$p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

Write-Host "Packing into $DistApp ..." -ForegroundColor Cyan

# Clean previous
if (Test-Path $DistApp) { Remove-Item $DistApp -Recurse -Force }
New-Dir $DistRoot
New-Dir $DistApp
New-Dir $DestAppDir
New-Dir $DestBackDir
New-Dir $DestRules
New-Dir $DestLTDir
New-Dir $DestScripts
New-Dir $DestPrereqs

# 1) App Flutter
if (-not (Test-Path $FlutterWinBuildDir)) {
  throw "Flutter build not found: $FlutterWinBuildDir  (run: flutter build windows)"
}
Write-Host "Copying app (Flutter) -> $DestAppDir" -ForegroundColor Green
robocopy $FlutterWinBuildDir $DestAppDir /E /NFL /NDL /NJH /NJS | Out-Null

# 2) Backend (PyInstaller onedir)
if (-not (Test-Path $PyInstallerOut)) {
  throw "PyInstaller output not found: $PyInstallerOut  (freeze backend first)"
}
Write-Host "Copying backend -> $DestBackDir" -ForegroundColor Green
robocopy $PyInstallerOut $DestBackDir /E /NFL /NDL /NJH /NJS | Out-Null

# 3) Rules
if (Test-Path $BackendRulesDir) {
  Write-Host "Copying rules -> $DestRules" -ForegroundColor Green
  robocopy $BackendRulesDir $DestRules /E /NFL /NDL /NJH /NJS | Out-Null
} else {
  Write-Host "Rules folder not found (skipped): $BackendRulesDir" -ForegroundColor Yellow
}

# 4) LanguageTool
if (-not (Test-Path $LanguageToolSrc)) {
  throw "LanguageTool not found: $LanguageToolSrc"
}
Write-Host "Copying LanguageTool -> $DestLTDir" -ForegroundColor Green
robocopy $LanguageToolSrc $DestLTDir /E /NFL /NDL /NJH /NJS | Out-Null

# 5) Scripts (no foreach to avoid parser issues)
$src1 = Join-Path $ScriptsSrc "run_stack.ps1"
$src2 = Join-Path $ScriptsSrc "stop_stack.ps1"
$src3 = Join-Path $ScriptsSrc "start_lt.ps1"

if (Test-Path $src1) { Copy-Item $src1 $DestScripts -Force } else { Write-Host "Missing script: $src1" -ForegroundColor Yellow }
if (Test-Path $src2) { Copy-Item $src2 $DestScripts -Force } else { Write-Host "Missing script: $src2" -ForegroundColor Yellow }
if (Test-Path $src3) { Copy-Item $src3 $DestScripts -Force } else { Write-Host "Missing script: $src3" -ForegroundColor Yellow }

# 6) Optional: VC++ redist (downloaded each time may be blocked by network, so skip by default)
# If you need it locally, uncomment and ensure internet access.
# $VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
# $vcLocal = Join-Path $DestPrereqs "vc_redist.x64.exe"
# if (-not (Test-Path $vcLocal)) {
#   try {
#     Write-Host "Downloading VC++ redist..." -ForegroundColor Green
#     Invoke-WebRequest $VcRedistUrl -OutFile $vcLocal
#   } catch {
#     Write-Host "VC++ download failed (continuing): $($_.Exception.Message)" -ForegroundColor Yellow
#   }
# }

Write-Host "OK: package created at $DistApp" -ForegroundColor Cyan
