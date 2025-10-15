# start_lt.ps1 - start LanguageTool only (hidden)
$ErrorActionPreference = "Stop"

$Root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LTDir = Join-Path $Root "LanguageTool"
$Port  = 8081

if (-not (Test-Path $LTDir)) { throw "LanguageTool not found: $LTDir" }

$LogDir = Join-Path $Root "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$ts   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutL = Join-Path $LogDir "lt_only_${ts}.out.log"
$ErrL = Join-Path $LogDir "lt_only_${ts}.err.log"

$java = Join-Path $LTDir "jre-17.0.16-full\bin\java.exe"
if (-not (Test-Path $java)) { $java = "java" }
$Args = @(
  "-cp", ".;languagetool-server.jar;languagetool-standalone.jar",
  "org.languagetool.server.HTTPServer", "--port", "$Port", "--allow-origin"
)

Start-Process -FilePath $java -ArgumentList $Args -WorkingDirectory $LTDir `
  -WindowStyle Hidden -RedirectStandardOutput $OutL -RedirectStandardError $ErrL

Write-Host "LanguageTool starting on http://127.0.0.1:$Port"
