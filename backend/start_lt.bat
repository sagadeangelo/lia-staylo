@echo off
setlocal

REM Este BAT está en: ...\lia-staylo\backend
REM Calcula la carpeta raíz del proyecto (...\lia-staylo)
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\..\" >nul
set "PROJECT_ROOT=%CD%"
popd

REM Carpeta de LanguageTool y JAR
set "LT_DIR=%PROJECT_ROOT%\LanguageTool"
set "LT_JAR=%LT_DIR%\languagetool-server.jar"

if not exist "%LT_JAR%" (
  echo [ERROR] No se encontro el JAR:
  echo   %LT_JAR%
  echo Verifica que la carpeta LanguageTool contenga languagetool-server.jar
  pause
  exit /b 1
)

echo Iniciando LanguageTool en http://127.0.0.1:8010 ...

REM Lanza LT desde su carpeta para que cargue bien dependencias
pushd "%LT_DIR%"
java -jar "%LT_JAR%" ^
  --port 8010 ^
  --allow-origin "*" ^
  --public
popd

endlocal
