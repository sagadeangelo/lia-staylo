@echo off
setlocal
title LIA-Staylo API 3000

REM === BASE: donde esta este BAT ===
set "BASE=%~dp0"

REM Intentar colocarnos en la carpeta backend (donde esta main.py)
if exist "%BASE%main.py" (
  cd /d "%BASE%"
) else if exist "%BASE%backend\main.py" (
  cd /d "%BASE%backend"
) else (
  echo [ERROR] No encontre main.py ni en "%BASE%" ni en "%BASE%backend".
  pause
  exit /b 1
)

REM === Crear/activar venv ===
if not exist .venv (
  echo Creando entorno virtual...
  py -m venv .venv
)
call .venv\Scripts\activate

echo Actualizando pip y deps...
py -m pip install --upgrade pip
pip install -r requirements.txt

REM === Apuntar a LanguageTool en 8010 ===
set LT_URL=http://127.0.0.1:8010

echo Iniciando FastAPI en 127.0.0.1:3000 ...
python -m uvicorn main:app --host 127.0.0.1 --port 3000 --reload
