// lib/services/lia_staylo_api.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LIAStayloAPI {
  // -------- Config base --------
  static String baseUrl = const String.fromEnvironment(
    'LIA_STAYLO_BASE',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String currentLang = 'es-MX';
  static const _prefKeyLang = 'lia_lang';
  static const Duration _timeout = Duration(seconds: 60);

  // -------- Buffer de app --------
  /// Último texto analizado (para precargar Sugerencias).
  static String? lastAnalyzedText;
  static void setLastAnalyzedText(String? t) =>
      lastAnalyzedText = (t ?? '').trim().isEmpty ? null : t;

  /// Ruta del proyecto actual (.lia) para sobrescribir sin pedir nombre.
  static String? _lastProjectPath;

  // =========================
  // Utiles de idioma/variante
  // =========================
  static String _normalizeVisibleLang(String? lang) {
    final s = (lang ?? '').trim();
    if (s.isEmpty) return currentLang;
    final low = s.toLowerCase();
    if (low.startsWith('en')) return 'en-US';
    if (low.startsWith('es-419')) return 'es-419';
    if (low.startsWith('es-mx') || low == 'es') return 'es-MX';
    return currentLang;
  }

  static Future<void> setLang(String lang) async {
    final v = _normalizeVisibleLang(lang);
    currentLang = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefKeyLang, v);
  }

  static Future<void> initSavedLang() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString(_prefKeyLang);
    if (saved != null && saved.isNotEmpty) {
      currentLang = _normalizeVisibleLang(saved);
    }
  }

  static Future<void> setDefaultLang(String lang) => setLang(lang);

  static Future<String> getSavedLang() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_prefKeyLang);
    return _normalizeVisibleLang(v ?? currentLang);
  }

  static void setBaseUrl(String url) {
    final u = url.trim();
    if (u.isNotEmpty) baseUrl = u;
  }

  // =========================
  // HTTP helpers
  // =========================
  static Map<String, String> _jsonHeaders({Map<String, String>? extra}) => {
        'Content-Type': 'application/json; charset=utf-8',
        if (extra != null) ...extra,
      };

  static T _decodeJson<T>(http.Response resp) {
    final code = resp.statusCode;
    final body = resp.body;
    if (code < 200 || code >= 300) {
      throw HttpException(
        'HTTP $code: ${body.isNotEmpty ? body : resp.reasonPhrase ?? 'Error'}',
        uri: resp.request?.url,
      );
    }
    if (T == String) return (body) as T;
    if (body.isEmpty) {
      throw const FormatException('Respuesta vacía del servidor');
    }
    final decoded = jsonDecode(body);
    return decoded as T;
  }

  // =========================
  // Endpoints principales
  // =========================
  static Future<Map<String, dynamic>> health() async {
    final uri = Uri.parse('$baseUrl/health');
    final resp = await http.get(uri).timeout(_timeout);
    return _decodeJson<Map<String, dynamic>>(resp);
  }

  static Future<Map<String, dynamic>> analyzeText(
    String text, {
    String? lang,
  }) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/analyze_text');
    final resp = await http
        .post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode({'text': text, 'lang': lg}),
        )
        .timeout(_timeout);

    final data = _decodeJson<Map<String, dynamic>>(resp);

    // Guarda para Sugerencias:
    setLastAnalyzedText(text);

    _attachLtClassification(data);
    return data;
  }

  static Future<Map<String, dynamic>> analyzeFile(
    File file, {
    String? lang,
  }) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/analyze/file');
    final req = http.MultipartRequest('POST', uri);
    req.fields['lang'] = lg;
    req.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send().timeout(_timeout);
    final resp = await http.Response.fromStream(streamed);
    final data = _decodeJson<Map<String, dynamic>>(resp);

    // El backend suele incluir el texto en el JSON ya decodificado.
    final raw = (data['text'] ?? '').toString();
    setLastAnalyzedText(raw);

    _attachLtClassification(data);
    return data;
  }

  static Future<Map<String, dynamic>> applySafe(
    String text, {
    String? lang,
  }) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/apply/safe');
    final resp = await http
        .post(uri, headers: _jsonHeaders(), body: jsonEncode({'text': text, 'lang': lg}))
        .timeout(_timeout);
    final data = _decodeJson<Map<String, dynamic>>(resp);
    _attachLtClassification(data);
    return data;
  }

  static Future<Map<String, dynamic>> applyAll(
    String text, {
    String? lang,
  }) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/apply/all');
    final resp = await http
        .post(uri, headers: _jsonHeaders(), body: jsonEncode({'text': text, 'lang': lg}))
        .timeout(_timeout);
    final data = _decodeJson<Map<String, dynamic>>(resp);
    _attachLtClassification(data);
    return data;
  }

  /// Reescritura ligera local del backend.
  static Future<String> suggestText(
    String text, {
    String? lang,
  }) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/suggest?mode=fix'); // <- endpoint acordado
    final resp = await http
        .post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode({'text': text, 'lang': lg}),
        )
        .timeout(_timeout);
    final data = _decodeJson<Map<String, dynamic>>(resp);
    final s = (data['suggestion'] ?? data['text'] ?? '').toString();
    if (s.isEmpty) {
      throw const FormatException('Respuesta de sugerencia vacía');
    }
    return s;
  }

  // =========================
  // Diccionario
  // =========================
  static String normalizeToken(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[\r\n\t]'), '');
    if (s.contains(' ')) {
      throw ArgumentError('El diccionario solo acepta UNA palabra (sin espacios).');
    }
    return s;
  }

  static Future<bool> dictionaryAdd(String token, {String? lang}) async {
    final t = normalizeToken(token);
    if (t.isEmpty) throw ArgumentError('La palabra está vacía.');
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/dictionary/add');
    final resp = await http
        .post(uri, headers: _jsonHeaders(), body: jsonEncode({'token': t, 'lang': lg}))
        .timeout(_timeout);
    if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 409) return true;
    final reason = resp.body.isNotEmpty ? resp.body : (resp.reasonPhrase ?? 'Error');
    throw HttpException('Dictionary add ${resp.statusCode}: $reason', uri: uri);
  }

  static Future<List<String>> dictionaryList({String? lang}) async {
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/dictionary/list?lang=$lg');
    final resp = await http.get(uri, headers: _jsonHeaders()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final ct = resp.headers['content-type'] ?? '';
      if (ct.contains('application/json')) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['words'] is List) {
          return (data['words'] as List).map((e) => e.toString()).toList();
        }
        throw const FormatException('Formato inesperado en dictionary/list');
      } else {
        return resp.body.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    } else {
      final reason = resp.body.isNotEmpty ? resp.body : (resp.reasonPhrase ?? 'Error');
      throw HttpException('Dictionary list ${resp.statusCode}: $reason', uri: uri);
    }
  }

  static Future<bool> dictionaryRemove(String token, {String? lang}) async {
    final t = token.trim();
    if (t.isEmpty) throw ArgumentError('La palabra a eliminar está vacía.');
    final lg = _normalizeVisibleLang(lang);
    final uri = Uri.parse('$baseUrl/dictionary/remove');
    final resp = await http
        .post(uri, headers: _jsonHeaders(), body: jsonEncode({'token': t, 'lang': lg}))
        .timeout(_timeout);
    if (resp.statusCode == 200 || resp.statusCode == 204 || resp.statusCode == 404) return true;
    final reason = resp.body.isNotEmpty ? resp.body : (resp.reasonPhrase ?? 'Error');
    throw HttpException('Dictionary remove ${resp.statusCode}: $reason', uri: uri);
  }

  // =========================
  // Proyecto .lia — abrir/guardar inteligente
  // =========================

  /// Devuelve la ruta actual del proyecto (si existe).
  static String? getCurrentProjectPath() => _lastProjectPath;

  /// Fuerza la ruta actual (p. ej. tras un "Guardar como").
  static void setCurrentProjectPath(String? path) {
    _lastProjectPath = (path?.trim().isEmpty ?? true) ? null : path!.trim();
  }

  /// Limpia la ruta actual (p. ej. "Nuevo proyecto").
  static void clearCurrentProjectPath() {
    _lastProjectPath = null;
  }

  /// Guarda el proyecto. Si existe ruta previa, **sobrescribe** sin preguntar;
  /// si no, abre diálogo "Guardar como".
  static Future<void> saveProject(
    Map<String, dynamic> data, {
    String suggestedName = 'proyecto.lia',
  }) async {
    if (_lastProjectPath != null) {
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      final file = File(_lastProjectPath!);
      await file.writeAsString(pretty, encoding: utf8);
      return;
    }
    await saveProjectAs(data, suggestedName: suggestedName);
  }

  /// "Guardar como…" siempre pide ubicación y recuerda la ruta.
  static Future<void> saveProjectAs(
    Map<String, dynamic> data, {
    String suggestedName = 'proyecto.lia',
  }) async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: [const XTypeGroup(label: 'LIA Project', extensions: ['lia'])],
      suggestedName: suggestedName,
    );
    if (loc == null) return;
    _lastProjectPath = loc.path;

    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    final xf = XFile.fromData(
      Uint8List.fromList(utf8.encode(pretty)),
      name: suggestedName,
      mimeType: 'application/json',
    );
    await xf.saveTo(loc.path);
  }

  /// Abre un `.lia` (JSON/GZIP/ZIP con JSON). **Recuerda la ruta** para guardados posteriores.
  static Future<Map<String, dynamic>?> openProject() async {
    final typeGroup = const XTypeGroup(label: 'LIA Project', extensions: ['lia']);
    final xfile = await openFile(acceptedTypeGroups: [typeGroup]);
    if (xfile == null) return null;

    _lastProjectPath = xfile.path; // <- recordar ruta del proyecto abierto

    final bytes = await xfile.readAsBytes();
    final j = _tryDecodeJsonMap(bytes) ??
        _tryDecodeGzipJsonMap(bytes) ??
        _tryDecodeZipJsonMap(bytes);
    return j;
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(Uint8List bytes) {
    try {
      final txt = utf8.decode(bytes, allowMalformed: true);
      final data = jsonDecode(txt);
      if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
      if (data is Map) return data.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _tryDecodeGzipJsonMap(Uint8List bytes) {
    try {
      final out = GZipDecoder().decodeBytes(bytes, verify: false);
      final txt = utf8.decode(Uint8List.fromList(out), allowMalformed: true);
      final data = jsonDecode(txt);
      if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
      if (data is Map) return data.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _tryDecodeZipJsonMap(Uint8List bytes) {
    try {
      final arc = ZipDecoder().decodeBytes(bytes, verify: false);
      for (final f in arc.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.json')) {
          final content = f.content as List<int>;
          final txt = utf8.decode(Uint8List.fromList(content), allowMalformed: true);
          final data = jsonDecode(txt);
          if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
          if (data is Map) return data.cast<String, dynamic>();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // =========================
  // Mapeo de categorías (UI)
  // =========================
  static String classifyLtMatch(Map<String, dynamic> m) {
    final ruleObj = m['rule'];
    String id = '';
    String category = '';
    String issue = '';

    if (ruleObj is Map) {
      final rule = ruleObj.cast<String, dynamic>();
      id = (rule['id'] ?? rule['name'] ?? '').toString();
      final c = rule['category'];
      if (c is Map) {
        final cc = c.cast<String, dynamic>();
        category = (cc['id'] ?? cc['name'] ?? '').toString();
      } else if (c is String) {
        category = c;
      }
      issue = (rule['issueType'] ?? '').toString();
    } else if (ruleObj != null) {
      id = ruleObj.toString();
    }

    // Categoría de alto nivel opcional enviada por backend
    final topLevelCat = (m['category'] ?? '').toString();
    if (category.isEmpty && topLevelCat.isNotEmpty) {
      category = topLevelCat;
    }

    final message = (m['message'] ?? '').toString();
    final hay = ('$id $category $issue $topLevelCat').toLowerCase();

    bool any(String s, List<String> keys) => keys.any((k) => s.contains(k));
    final msg = message.toLowerCase();

    // Ortografía
    if (any(hay, ['misspell', 'spelling', 'typo', 'morfologik', 'hunspell', 'typos', 'ortograf']) ||
        any(msg, [
          'error ortográfico',
          'palabra desconocida',
          'quizá quiso decir',
          '¿quiso decir',
          'posible error de escritura'
        ])) {
      return 'spelling';
    }

    // Puntuación / espacios
    if (any(hay, [
          'punct',
          'comma',
          'semicolon',
          'quote',
          'quotes',
          'apostrophe',
          'whitespace',
          'space',
          'ellipsis',
          'dash',
          'hyphen',
          'bracket',
          'parenthesis',
          'uppercasesentencestart',
          'double_punct',
          'multispace',
          'apos',
          'puntuación',
          'espacio'
        ]) ||
        any(msg, [
          'espacio',
          'puntuación',
          'coma',
          'punto',
          'dos espacios',
          'comillas',
          'paréntesis',
          'guion',
          'guión',
          'apóstrofo',
          'mayúscula al inicio',
          'mayúscula inicial',
          'tres puntos'
        ])) {
      return 'space';
    }

    // Estilo (incluye CUSTOM_*)
    if (any(hay, ['style', 'estilo', 'custom_', 'mule', 'wordiness', 'redund', 'register', 'formal', 'informal']) ||
        any(msg, ['muletilla', 'registro formal', 'mejor como', 'más claro', 'más conciso', 'estilo'])) {
      return 'style';
    }

    // Gramática (por defecto)
    return 'grammar';
  }

  /// Adjunta 'lt_clientClass' por match y 'lt_counts' (resumen)
  static void _attachLtClassification(Map<String, dynamic> analysis) {
    if (analysis['languageTool'] is! Map) return;
    final lt = (analysis['languageTool'] as Map).cast<String, dynamic>();
    if (lt['matches'] is! List) return;

    final matches = (lt['matches'] as List).cast<dynamic>();
    final counts = <String, int>{
      'grammar': 0,
      'space': 0,
      'style': 0,
      'spelling': 0,
      'all': matches.length,
    };

    for (final raw in matches) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final cls = classifyLtMatch(m);
      m['lt_clientClass'] = cls;
      counts[cls] = (counts[cls] ?? 0) + 1;
    }
    analysis['lt_counts'] = counts;
  }

  /// Resume conteos a partir del análisis.
  static Map<String, int> countsFromAnalysis(Map<String, dynamic> analysis) {
    if (analysis['lt_counts'] is Map) {
      final mm = (analysis['lt_counts'] as Map).cast<String, dynamic>();
      return mm.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    final fake = Map<String, dynamic>.from(analysis);
    _attachLtClassification(fake);
    final mm = (fake['lt_counts'] as Map).cast<String, dynamic>();
    return mm.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  /// Devuelve los matches con 'lt_clientClass' asignado.
  static List<Map<String, dynamic>> classifyMatchesFromAnalysis(
    Map<String, dynamic> analysis,
  ) {
    if (analysis['languageTool'] is! Map) return const [];
    final lt = (analysis['languageTool'] as Map).cast<String, dynamic>();
    if (lt['matches'] is! List) return const [];
    final list = <Map<String, dynamic>>[];
    for (final raw in (lt['matches'] as List)) {
      if (raw is Map) {
        final m = raw.cast<String, dynamic>();
        m['lt_clientClass'] ??= classifyLtMatch(m);
        list.add(Map<String, dynamic>.from(m));
      }
    }
    return list;
  }
}
