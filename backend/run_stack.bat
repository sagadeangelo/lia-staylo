@echo off
setlocal
set "BASE=%~dp0"

rem Levanta LanguageTool (puerto 8010) en una ventana
start "LanguageTool 8010" cmd /k call "%BASE%start_lt.bat"

rem Espera 5s y levanta la API FastAPI (puerto 8000) en otra ventana
timeout /t 5 >nul
start "LIA API 8000" cmd /k call "%BASE%start_api.bat"

endlocal
