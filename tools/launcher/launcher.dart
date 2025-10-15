// tools/launcher/launcher.dart
//
// Arranca LanguageTool y el backend (nativo por defecto).
// Si falla, intenta fallback con .bat en packageroot\scripts\.
// Luego lanza la UI (lia_staylo.exe).
//
// Forzar modo (opcional) con variable de entorno:
//   LAUNCH_MODE=native | bats
//
// Estructura esperada en el paquete (packageroot):
//   LIAStaylo\lia_staylo.exe
//   lia_backend\lia_backend.exe
//   LanguageTool\ (languagetool.jar, languagetool-server.jar, libs\*, jre-17.0.16-full\bin\java.exe opcional)
//   scripts\start_lt.bat (opcional)
//   scripts\start_api.bat (opcional)

import 'dart:io';
import 'package:path/path.dart' as p;

/* ===================== Config ===================== */

const int kLtPort  = 8081;
const int kApiPort = 8000;

enum LaunchPref { auto, native, bats }

/* ===================== Utilidades ===================== */

LaunchPref _pref() {
  final v = (Platform.environment['LAUNCH_MODE'] ?? '').toLowerCase();
  if (v == 'native') return LaunchPref.native;
  if (v == 'bats')   return LaunchPref.bats;
  return LaunchPref.auto;
}

String packageroot() {
  // resolvedExecutable -> ...\packageroot\LIAStaylo\launcher.exe
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  return Directory(exeDir).parent.path; // ...\packageroot
}

Future<bool> _waitPort(String host, int port, {int msTimeout = 20000}) async {
  final deadline = DateTime.now().millisecondsSinceEpoch + msTimeout;
  while (DateTime.now().millisecondsSinceEpoch < deadline) {
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(milliseconds: 300));
      s.destroy();
      return true;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
  return false;
}

String? _findJavaInLt(String ltDir) {
  try {
    return Directory(ltDir)
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => p.basename(f.path).toLowerCase() == 'java.exe')
        .path;
  } catch (_) {
    return null;
  }
}

String _dataDir() {
  final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  final d = p.join(base, 'LIA-Staylo');
  Directory(d).createSync(recursive: true);
  return d;
}

/* ===================== Arranque NATIVO ===================== */

Future<bool> startLT_Native({int port = kLtPort}) async {
  final ltDir = p.join(packageroot(), 'LanguageTool');
  final java  = _findJavaInLt(ltDir) ?? 'java';
  final cp    = r'.\languagetool-server.jar;.\languagetool.jar;.\libs\*';

  final serverJar = File(p.join(ltDir, 'languagetool-server.jar')).existsSync();
  final apiJar    = File(p.join(ltDir, 'languagetool.jar')).existsSync();
  print('[Launcher] LT jar exists?  $serverJar');
  print('[Launcher] LT api exists?  $apiJar');
  print('[Launcher] LT java exists? ${java != 'java' || (Platform.environment['PATH'] ?? '').isNotEmpty}');

  if (!serverJar || !apiJar) {
    print('[WARN] Faltan jars de LanguageTool'); 
    return false;
  }

  await Process.start(
    java,
    ['-cp', cp, 'org.languagetool.server.HTTPServer', '--port', '$port'],
    workingDirectory: ltDir,
    mode: ProcessStartMode.detached,
  );

  final ok = await _waitPort('127.0.0.1', port);
  if (ok) print('[Launcher] LT OK en $port');
  else    print('[WARN] LT no levantó en $port (nativo).');
  return ok;
}

Future<bool> startAPI_Native({int port = kApiPort, String ltUrl = 'http://127.0.0.1:$kLtPort'}) async {
  final root = packageroot();
  final exe  = p.join(root, 'lia_backend', 'lia_backend.exe');
  if (!File(exe).existsSync()) {
    print('[WARN] Backend no empaquetado en $exe');
    return false;
  }

  final data = _dataDir();
  final env = {
    ...Platform.environment,
    'LIA_ROOT': root,
    'LIA_DATA': data,
    'LT_URL'  : ltUrl,
    'API_PORT': '$port',
  };

  await Process.start(
    exe, [],
    workingDirectory: data,
    environment: env,
    mode: ProcessStartMode.detached,
  );

  final ok = await _waitPort('127.0.0.1', port);
  if (ok) print('[Launcher] Backend OK en $port');
  else    print('[WARN] Backend no levantó en $port (nativo).');
  return ok;
}

/* ===================== Arranque por .BAT ===================== */

Future<bool> _runBatAndWaitPort(String batName, String working, int port) async {
  final bat = p.join(working, batName);
  if (!File(bat).existsSync()) {
    print('[WARN] $batName no existe en $working');
    return false;
  }
  await Process.start(
    'cmd.exe', ['/d', '/c', batName],
    workingDirectory: working,
    environment: {...Platform.environment, 'LIA_ROOT': packageroot(), 'LIA_DATA': _dataDir()},
    mode: ProcessStartMode.detached,
  );
  return _waitPort('127.0.0.1', port);
}

Future<bool> startLT_Bat({int port = kLtPort}) async {
  final scripts = p.join(packageroot(), 'scripts');
  final ok = await _runBatAndWaitPort('start_lt.bat', scripts, port);
  if (ok) print('[Launcher] LT OK en $port (bat)');
  else    print('[WARN] LT no levantó en $port (bat).');
  return ok;
}

Future<bool> startAPI_Bat({int port = kApiPort}) async {
  final scripts = p.join(packageroot(), 'scripts');
  final ok = await _runBatAndWaitPort('start_api.bat', scripts, port);
  if (ok) print('[Launcher] Backend OK en $port (bat)');
  else    print('[WARN] Backend no levantó en $port (bat).');
  return ok;
}

/* ===================== Orquestación y UI ===================== */

Future<void> bootAll() async {
  print('[Launcher] exeDir = ${File(Platform.resolvedExecutable).parent.path}');
  print('[Launcher] root   = ${packageroot()}');

  final pref = _pref();
  final nativeFirst = (pref != LaunchPref.bats);

  // LanguageTool
  bool ltUp = nativeFirst ? await startLT_Native() : await startLT_Bat();
  if (!ltUp) ltUp = nativeFirst ? await startLT_Bat() : await startLT_Native();

  // Backend
  bool apiUp = nativeFirst ? await startAPI_Native() : await startAPI_Bat();
  if (!apiUp) apiUp = nativeFirst ? await startAPI_Bat() : await startAPI_Native();

  if (!ltUp)  print('[WARN] LT no disponible en $kLtPort (la UI sigue).');
  if (!apiUp) print('[WARN] Backend no disponible en $kApiPort (la UI sigue).');
}

Future<void> startUI() async {
  final uiDir = p.join(packageroot(), 'LIAStaylo');
  // Ajusta el nombre del EXE si difiere:
  final exe   = p.join(uiDir, 'lia_staylo.exe');

  if (!File(exe).existsSync()) {
    print('[WARN] UI exe no encontrado en $exe');
    return;
  }

  print('[Launcher] UI exe candidato: ${p.basename(exe)}');
  await Process.start(exe, [], workingDirectory: uiDir, mode: ProcessStartMode.detached);
}

/* ===================== MAIN ===================== */

Future<void> main() async {
  await bootAll();
  await startUI();
}
