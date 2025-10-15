# run_stack.ps1 - start LT + backend hidden
$ErrorActionPreference = "Stop"

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LTDir   = Join-Path $Root "LanguageTool"
$BackDir = Join-Path $Root "backend\dist\lia-backend"

$LT_Port  = 8081
$API_Port = 8000

# Kill helpers
function Kill-Port([int]$port) {
  $lines = netstat -ano | Select-String ":$port"
  if (-not $lines) { return }
  foreach ($ln in $lines) {
    $parts = ($ln -split '\s+') | Where-Object { $_ -ne '' }
    $pid = $parts[-1]
    if ($pid -match '^\d+$' -and $pid -ne '0') {
      try { taskkill /PID $pid /F | Out-Null } catch {}
    }
  }
}

# Close anything listening
Kill-Port $LT_Port
Kill-Port $API_Port

# Check folders
if (-not (Test-Path $LTDir))   { throw "LanguageTool not found: $LTDir" }
if (-not (Test-Path $BackDir)) { throw "Backend onedir not found: $BackDir" }

# Logs
$LogDir = Join-Path $Root "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LTOut = Join-Path $LogDir "lt_${ts}.out.log"
$LTErr = Join-Path $LogDir "lt_${ts}.err.log"
$APIOut = Join-Path $LogDir "api_${ts}.out.log"
$APIErr = Join-Path $LogDir "api_${ts}.err.log"

# Start LT (hidden)
$java = Join-Path $LTDir "jre-17.0.16-full\bin\java.exe"
if (-not (Test-Path $java)) { $java = "java" }
$LTArgs = @(
  "-cp", ".;languagetool-server.jar;languagetool-standalone.jar",
  "org.languagetool.server.HTTPServer", "--port", "$LT_Port", "--allow-origin"
)
Start-Process -FilePath $java -ArgumentList $LTArgs -WorkingDirectory $LTDir `
  -WindowStyle Hidden -RedirectStandardOutput $LTOut -RedirectStandardError $LTErr

Start-Sleep -Seconds 2

# Start backend (hidden)
$exe = Join-Path $BackDir "lia-backend.exe"
if (-not (Test-Path $exe)) { throw "lia-backend.exe not found in $BackDir" }

$env:LT_URL = "http://127.0.0.1:$LT_Port"
Start-Process -FilePath $exe -WorkingDirectory $BackDir `
  -WindowStyle Hidden -RedirectStandardOutput $APIOut -RedirectStandardError $APIErr

# Health check
function Wait-UrlOk($url, $name) {
  $ok = $false
  for ($i=0; $i -lt 20; $i++) {
    try {
      $r = Invoke-WebRequest $url -TimeoutSec 2
      if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch {}
    Start-Sleep -Seconds 1
  }
  if ($ok) { Write-Host "$name: OK -> $url" -ForegroundColor Green }
  else     { Write-Host "$name: FAILED -> $url" -ForegroundColor Yellow }
}

Wait-UrlOk "http://127.0.0.1:$LT_Port/v2/languages" "LanguageTool"
Wait-UrlOk "http://127.0.0.1:$API_Port/health"      "Backend"
Write-Host "Logs: $LTOut | $LTErr | $APIOut | $APIErr"
