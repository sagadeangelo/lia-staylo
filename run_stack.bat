@echo on
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title LIA-Staylo — DEBUG de rutas

echo ========= DEBUG =========
echo SELF: %~dp0

REM Detectar si existe backend\main.py desde la RAIZ
if exist "%~dp0backend\main.py" (
  set "PROJ=%~dp0"
  set "BACKEND=%~dp0backend\"
  set "UV_TARGET=backend.main:app"
) else (
  echo [X] No encuentro "%~dp0backend\main.py"
)

REM Detectar si este .bat estuviera en backend\
if exist "%~dp0main.py" (
  set "BACKEND=%~dp0"
  for %%I in ("%~dp0..") do set "PROJ=%%~fI\"
  set "UV_TARGET=main:app"
)

echo PROJ:    %PROJ%
echo BACKEND: %BACKEND%
echo UVICORN: %UV_TARGET%

REM VENV: primero raiz\.venv, luego backend\.venv
set "VENV_PY=%PROJ%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" set "VENV_PY=%BACKEND%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" set "VENV_PY="

echo VENV_PY: %VENV_PY%
if not defined VENV_PY (
  echo [X] No encontre Python del venv. Probando python global...
  where python
) else (
  if exist "%VENV_PY%" (echo [OK] Existe venv) else (echo [X] No existe ^(ruta incorrecta^))
)

REM JAR: raiz o backend
set "LT_JAR=%PROJ%\LanguageTool\languagetool-server.jar"
if not exist "%LT_JAR%" set "LT_JAR=%BACKEND%\LanguageTool\languagetool-server.jar"

echo LT_JAR: %LT_JAR%
if exist "%LT_JAR%" (echo [OK] Existe LT JAR) else (echo [X] No existe JAR)

echo =========================
echo Comprueba que:
echo  - Exista backend\main.py
echo  - Exista .venv\Scripts\python.exe (en raiz o en backend)
echo  - Exista LanguageTool\languagetool-server.jar (en raiz o backend)
echo.
pause
endlocal
