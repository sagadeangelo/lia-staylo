# stop_stack.ps1 - stop LT + backend
$ErrorActionPreference = "Stop"

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

Kill-Port 8081
Kill-Port 8000
Write-Host "Stopped processes on ports 8081 and 8000."
