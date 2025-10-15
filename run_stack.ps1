# run_stack.ps1 — arranca LanguageTool + API ocultos y guarda logs (stdout/stderr separados)
# Requisitos:
# - LT jars en: D:\PROYECTOS-FLUTTER\lia-staylo\LanguageTool\ (server y/o standalone)
# - venv en   : D:\PROYECTOS-FLUTTER\lia-staylo\backend\.venv\
# Ejecución oculta (acceso directo):
# powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\PROYECTOS-FLUTTER\lia-staylo\run_stack.ps1"

$ErrorActionPreference = "Stop"

# === Rutas y puertos ===
$Root      = "D:\PROYECTOS-FLUTTER\lia-staylo"
$LTDir     = Join-Path $Root "LanguageTool"
$Backend   = Join-Path $Root "backend"
$VenvPy    = Join-Path $Backend ".venv\Scripts\python.exe"
$LT_Port   = 8081
$API_Port  = 8000

# === Logs (fecha/hora) ===
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ts        = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LTLogOut  = Join-Path $LogDir "lt_${ts}.out.log"
$LTLogErr  = Join-Path $LogDir "lt_${ts}.err.log"
$APILogOut = Join-Path $LogDir "api_${ts}.out.log"
$APILogErr = Join-Path $LogDir "api_${ts}.err.log"

# === Kill-Port seguro (omite PID 0 y usa Get-NetTCPConnection cuando se pueda) ===
function Kill-Port {
  param([int]$Port)

  # 1) Preferente: Get-NetTCPConnection (requiere permisos)
  try {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
    $pids  = $conns.OwningProcess | Sort-Object -Unique
    foreach ($id in $pids) {
      if ($id -and $id -gt 4) {
        try { Stop-Process -Id $id -Force -ErrorAction Stop } catch {}
      }
    }
    return
  } catch {
    # Fallback a netstat
  }

  # 2) Fallback: netstat + regex (toma PID del final)
  try {
    $lines = netstat -ano | Select-String ":$Port"
    if (-not $lines) { return }
    foreach ($ln in $lines) {
      $m = [regex]::Match($ln, '\s+(\d+)\s*$')
      if ($m.Success) {
        $id = [int]$m.Groups[1].Value
        if ($id -gt 4) {
          try { taskkill /PID $id /F | Out-Null } catch {}
        }
      }
    }
  } catch {}
}

# === Cerrar instancias previas en los puertos declarados ===
Kill-Port $LT_Port
Kill-Port $API_Port

# === Checks de prerrequisitos ===
if (-not (Test-Path $LTDir))  { throw "No existe carpeta LanguageTool: $LTDir" }
if (-not (Test-Path $VenvPy)) { throw "No existe Python del venv: $VenvPy" }

# === Arrancar LanguageTool (oculto) ===
$java = Join-Path $LTDir "jre-17.0.16-full\bin\java.exe"
if (-not (Test-Path $java)) { $java = "java" }

# Intento con classpath (server + standalone). Si solo tienes server.jar, usa -jar.
$LTArgsCP  = @('-cp', '.;languagetool-server.jar;languagetool-standalone.jar',
               'org.languagetool.server.HTTPServer', '--port', "$LT_Port", '--allow-origin')
$LTArgsJar = @('-jar', 'languagetool-server.jar', '-p', "$LT_Port", '--allow-origin')

# Decide según los jars presentes
$hasServer     = Test-Path (Join-Path $LTDir 'languagetool-server.jar')
$hasStandalone = Test-Path (Join-Path $LTDir 'languagetool-standalone.jar')

if ($hasServer -and $hasStandalone) {
  Start-Process -FilePath $java -ArgumentList $LTArgsCP -WorkingDirectory $LTDir `
    -WindowStyle Hidden -RedirectStandardOutput $LTLogOut -RedirectStandardError $LTLogErr
} elseif ($hasServer) {
  Start-Process -FilePath $java -ArgumentList $LTArgsJar -WorkingDirectory $LTDir `
    -WindowStyle Hidden -RedirectStandardOutput $LTLogOut -RedirectStandardError $LTLogErr
} else {
  throw "No se encuentra languagetool-server.jar en $LTDir"
}

Start-Sleep -Seconds 2

# === Variables de entorno para el backend ===
$env:LT_URL        = "http://127.0.0.1:$LT_Port"
$env:LIA_RULES_DIR = Join-Path $Backend "rules"

# === Arrancar Backend (oculto) ===
$ApiArgs = @('-m','uvicorn','main:app','--host','127.0.0.1','--port',"$API_Port",'--log-level','info')
Start-Process -FilePath $VenvPy -ArgumentList $ApiArgs -WorkingDirectory $Backend `
  -WindowStyle Hidden -RedirectStandardOutput $APILogOut -RedirectStandardError $APILogErr

# === Verificación rápida de estado ===
Start-Sleep -Seconds 2
try { $ltOk  = (Invoke-WebRequest "http://127.0.0.1:$LT_Port/v2/languages" -TimeoutSec 3).StatusCode -eq 200 } catch { $ltOk = $false }
try { $apiOk = (Invoke-WebRequest "http://127.0.0.1:$API_Port/health"      -TimeoutSec 3).StatusCode -eq 200 } catch { $apiOk = $false }

Write-Host "LT  : $($env:LT_URL)                 => $ltOk"
Write-Host "API : http://127.0.0.1:$API_Port/health => $apiOk"
Write-Host "Logs OUT: $LTLogOut | $APILogOut"
Write-Host "Logs ERR: $LTLogErr | $APILogErr"
