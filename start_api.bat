@echo off
setlocal
chcp 65001 >nul

REM Asegúrate de ejecutar este .bat en la carpeta que contiene server.js y package.json
if not exist node_modules (
  echo Instalando dependencias NPM...
  npm install
)

set LT_BASE=http://localhost:8010
set PORT=3000
echo Iniciando API en puerto %PORT% (LT=%LT_BASE%)...
npm start

pause
endlocal
