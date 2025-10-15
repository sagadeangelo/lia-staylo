@echo off
setlocal
chcp 65001 >nul

REM Puerto que usa LIA-Staylo para LT (debe coincidir con ltBase en AppState)
set "LT_PORT=8010"

REM Intentar localizar el JAR del servidor de LanguageTool
set "LT_JAR="
for %%F in (
  "%~dp0LanguageTool\languagetool-server.jar"
  "%~dp0languagetool-server.jar"
  "%~dp0LanguageTool\LanguageTool-*.jar"
  "%~dp0LanguageTool-*.jar"
) do (
  if not defined LT_JAR if exist "%%~fF" set "LT_JAR=%%~fF"
)

if not defined LT_JAR (
  echo [ERROR] No se encontro languagetool-server.jar ni LanguageTool-*.jar
  echo Descarga el ZIP "LanguageTool Standalone", extraelo y coloca el JAR junto a este .bat.
  pause
  exit /b 2
)

echo Iniciando LanguageTool en puerto %LT_PORT%
echo JAR: %LT_JAR%

REM Opcion A (recomendada)
java -Xmx1G -jar "%LT_JAR%" -p %LT_PORT% --allow-origin "*"

REM Opcion B (alternativa, solo si A falla)
REM java -Xmx1G -cp "%LT_JAR%" org.languagetool.server.HTTPServer -p %LT_PORT% --allow-origin "*"

pause
endlocal
