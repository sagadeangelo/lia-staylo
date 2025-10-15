@echo off
setlocal
chcp 65001 >nul

REM ================== CONFIG ==================
set "API_HOST=127.0.0.1"
set "API_PORT=8000"
REM ============================================

REM Carpeta donde está este .bat
set "BASE=%~dp0"

REM Detecta carpeta del backend (ajusta si tu main.py vive en otra ruta)
if exist "%BASE%main.py" (
  set "BACK=%BASE%"
) else if exist "%BASE%backend\main.py" (
  set "BACK=%BASE%backend\"
) else (
  echo [start_api] No encuentro main.py ni en "%BASE%" ni en "%BASE%backend\".
  echo Coloca este .bat junto a main.py o dentro de la carpeta raiz que contenga "backend\main.py".
  pause
  goto :eof
)

title LIA API %API_HOST%:%API_PORT%
echo [start_api] Carpeta backend: %BACK%

REM ====== Activa venv si existe (.venv o venv) ======
set "VENV_ACTIVATED=0"
if exist "%BACK%\.venv\Scripts\activate.bat" (
  call "%BACK%\.venv\Scripts\activate.bat"
  set "VENV_ACTIVATED=1"
) else if exist "%BACK%\venv\Scripts\activate.bat" (
  call "%BACK%\venv\Scripts\activate.bat"
  set "VENV_ACTIVATED=1"
)

REM ====== Elige intérprete de Python ======
REM - Si venv está activo, "python" ya apunta al del venv.
REM - Si NO hay venv, usa el Python Launcher 3.12.
set "PY=python"
where %PY% >nul 2>&1
if errorlevel 1 (
  set "PY=C:\Windows\py.exe -3.12"
)

REM ====== Asegura UTF-8 ======
set PYTHONUTF8=1

pushd "%BACK%"

REM ====== Instala dependencias si hay requirements.txt (opcional) ======
if exist requirements.txt (
  echo [start_api] Instalando/actualizando dependencias desde requirements.txt...
  %PY% -m pip install --upgrade pip
  %PY% -m pip install -r requirements.txt
) else (
  echo [start_api] Sin requirements.txt. Verificando paquetes basicos...
  %PY% -m pip install --upgrade pip
  %PY% -m pip install fastapi "uvicorn[standard]" python-multipart aiofiles docx2txt python-docx
)

echo [start_api] Iniciando Uvicorn en http://%API_HOST%:%API_PORT% ...
%PY% -m uvicorn main:app --host %API_HOST% --port %API_PORT% --reload

set "ERR=%ERRORLEVEL%"
popd

if not "%ERR%"=="0" (
  echo [start_api] Uvicorn terminó con codigo %ERR%.
  pause
)

endlocal
