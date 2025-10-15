# run_server.py — lanzador robusto de FastAPI para LIA-Staylo
# - Soporta ejecución en venv, código fuente, PyInstaller (onedir/onefile)
# - Encuentra la app vía LIA_APP_MODULE="modulo:atributo" o por candidatos comunes
# - Ajusta sys.path y el directorio de trabajo para evitar imports frágiles

from __future__ import annotations

import os
import sys
import importlib
import importlib.util
from typing import Optional, Tuple, List

# ------------------------
# Config vía variables de entorno (con defaults)
# ------------------------
HOST = os.environ.get("UVICORN_HOST", "127.0.0.1")
PORT = int(os.environ.get("UVICORN_PORT", "8000"))
# Permite definir explícitamente el módulo y atributo de la app: p.ej. "main:app"
APP_SPEC = os.environ.get("LIA_APP_MODULE", "").strip()

# ------------------------
# Utilidades de logging simple (stdout)
# ------------------------
def log(*args: object) -> None:
    print("[run_server]", *args, flush=True)

# ------------------------
# Determinar directorios relevantes y poner cwd correcto
# ------------------------
def guess_base_dirs() -> List[str]:
    """Devuelve una lista de carpetas candidatas donde pueden estar los .py."""
    bases: List[str] = []

    # 1) PyInstaller onefile/onedir
    meipass = getattr(sys, "_MEIPASS", None)
    if isinstance(meipass, str) and os.path.isdir(meipass):
        bases.append(meipass)

    # 2) Carpeta del ejecutable (si existe)
    exe_dir = os.path.dirname(getattr(sys, "executable", sys.argv[0]) or "")
    if exe_dir and os.path.isdir(exe_dir):
        bases.append(exe_dir)

    # 3) Carpeta del script actual
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if script_dir and os.path.isdir(script_dir):
        bases.append(script_dir)

    # 4) Una carpeta arriba (útil si el código está en ./backend o ./src)
    up = os.path.dirname(script_dir)
    if up and os.path.isdir(up):
        bases.append(up)

    # 5) Subcarpetas habituales
    for extra in ("backend", "src", "app"):
        p = os.path.join(script_dir, extra)
        if os.path.isdir(p):
            bases.append(p)

    # Quitar duplicados sin perder orden
    seen: set[str] = set()
    out: List[str] = []
    for p in bases:
        if p not in seen:
            out.append(p)
            seen.add(p)
    return out


def normalize_environment() -> None:
    """Ajusta cwd y sys.path para que los imports funcionen en todos los modos."""
    bases = guess_base_dirs()

    # Establecer cwd a la primera base válida (importante para rutas relativas).
    try:
        if bases and os.path.isdir(bases[0]):
            os.chdir(bases[0])
            log("cwd:", os.getcwd())
    except Exception as e:
        log("Aviso: no pude cambiar cwd:", repr(e))

    # Prepend bases a sys.path si no están ya
    for p in bases:
        if p and p not in sys.path:
            sys.path.insert(0, p)

# ------------------------
# Import helpers
# ------------------------
def parse_app_spec(spec: str) -> Optional[Tuple[str, str]]:
    if not spec or ":" not in spec:
        return None
    mod, attr = spec.split(":", 1)
    mod, attr = mod.strip(), attr.strip()
    if not mod or not attr:
        return None
    return mod, attr


def import_from_spec(spec: str):
    parsed = parse_app_spec(spec)
    if not parsed:
        raise ValueError(f"Formato inválido LIA_APP_MODULE='{spec}' (usa 'modulo:atributo')")
    mod_name, attr_name = parsed
    m = importlib.import_module(mod_name)
    return getattr(m, attr_name)


def import_first_app(candidates: List[str]):
    last_err: Optional[BaseException] = None
    for mod in candidates:
        try:
            m = importlib.import_module(mod)
            if hasattr(m, "app"):
                return getattr(m, "app")
        except BaseException as e:
            last_err = e
    if last_err:
        raise last_err
    return None


def import_from_file(py_path: str, attr: str = "app"):
    if not os.path.isfile(py_path):
        return None
    spec = importlib.util.spec_from_file_location("lia_dynamic_app", py_path)
    if not spec or not spec.loader:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return getattr(mod, attr, None)

# ------------------------
# Localizar la instancia FastAPI 'app'
# ------------------------
def resolve_app():
    errors: List[str] = []

    # 1) Si el usuario fijó LIA_APP_MODULE="modulo:atributo"
    if APP_SPEC:
        try:
            log("Intentando LIA_APP_MODULE =", APP_SPEC)
            return import_from_spec(APP_SPEC)
        except BaseException as e:
            errors.append(f"LIA_APP_MODULE='{APP_SPEC}' falló: {repr(e)}")

    # 2) Candidatos típicos por módulo (requiere que dichos módulos estén importables)
    candidates = [
        "main",
        "backend.main",
        "app.main",
        "src.main",
        # agrega aquí más si lo necesitas
    ]
    try:
        log("Probando candidatos por módulo:", candidates)
        app = import_first_app(candidates)
        if app is not None:
            return app
    except BaseException as e:
        errors.append(f"candidatos {candidates} fallaron: {repr(e)}")

    # 3) Búsqueda por archivos en posibles bases
    search_files: List[str] = []
    for base in guess_base_dirs():
        for name in ("main.py", "app.py", "server.py"):
            search_files.append(os.path.join(base, name))

    log("Explorando archivos:", search_files)
    for path in search_files:
        try:
            app = import_from_file(path, "app")
            if app is not None:
                return app
        except BaseException as e:
            errors.append(f"import_from_file({path}) falló: {repr(e)}")

    # 4) Si nada funcionó, explicar claramente
    msg_lines = [
        "No se pudo localizar una instancia 'app' de FastAPI.",
        "",
        "Soluciones rápidas:",
        " - Define LIA_APP_MODULE, p.ej.:  main:app",
        " - Asegura que exista main.py con 'app = FastAPI()' en el proyecto",
        " - Si empaquetas con PyInstaller, incluye el módulo donde vive 'app'",
        "",
        "Intentos/errores:"
    ] + errors
    raise RuntimeError("\n".join(msg_lines))

# ------------------------
# Punto de entrada
# ------------------------
def main():
    normalize_environment()

    try:
        app = resolve_app()
    except RuntimeError as e:
        # Mensaje claro y salir con código de error para que el lanzador lo vea en logs
        log("ERROR:", str(e))
        sys.exit(2)

    # Ejecutar uvicorn
    try:
        import uvicorn
    except ModuleNotFoundError:
        log("ERROR: uvicorn no está instalado en este entorno.")
        log("Activa el venv correcto y ejecuta:  pip install uvicorn fastapi")
        sys.exit(3)

    log(f"Iniciando Uvicorn en http://{HOST}:{PORT} ...")
    uvicorn.run(app=app, host=HOST, port=PORT, reload=False, log_level="info")


if __name__ == "__main__":
    main()
