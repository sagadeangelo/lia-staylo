import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// === ENDPOINTS: AJUSTA A TUS PUERTOS ===
const String apiBase = 'http://localhost:3000'; // FastAPI
const String ltBase = 'http://localhost:8010';  // LanguageTool

/// Mapeo de idioma UI -> código LT
const Map<String, String> ltLangMap = {
  'es_MX': 'es',
  'es-419': 'es',
  'en_US': 'en-US',
  'en': 'en',
};

class MatchSelection {
  final bool selected;
  final String? replacement;
  final String? manual;
  const MatchSelection({this.selected = false, this.replacement, this.manual});

  MatchSelection copyWith({bool? selected, String? replacement, String? manual}) {
    return MatchSelection(
      selected: selected ?? this.selected,
      replacement: replacement ?? this.replacement,
      manual: manual ?? this.manual,
    );
  }
}

class AppState extends ChangeNotifier {
  /// Health
  bool backendOk = false;
  bool ltOk = false;

  /// Estado de documento
  String currentLang = 'es_MX';
  String currentText = '';
  Map<String, dynamic>? result;

  /// Cargas
  bool isUploading = false;
  double? uploadProgress;

  /// Selecciones por match-KEY
  Map<String, MatchSelection> _selections = {};
  int get selectedCount => _selections.values.where((s) => s.selected).length;

  /// Diccionario local (pantalla Diccionario)
  final List<String> dictionaryWords = [];

  // ---------- KEYS / SELECCIÓN ----------
  String keyForMatch(Map<String, dynamic> m) {
    final off = (m['offset'] ?? 0).toString();
    final len = (m['length'] ?? 0).toString();
    final rid = (m['rule']?['id'] ?? m['ruleId'] ?? 'RULE').toString();
    return '$off:$len:$rid';
  }

  MatchSelection selectionOf(String key) => _selections[key] ?? const MatchSelection();

  void toggleSelectionForMatch(String key) {
    final cur = selectionOf(key);
    _selections[key] = cur.copyWith(selected: !cur.selected);
    notifyListeners();
  }

  void selectAll() {
    if (result == null) return;
    final List matches = (((result!['languageTool'] ?? const {}) as Map)['matches'] ?? const []) as List;
    for (final e in matches) {
      if (e is! Map) continue;
      final k = keyForMatch(e.cast<String, dynamic>());
      _selections[k] = const MatchSelection(selected: true);
    }
    notifyListeners();
  }

  void clearSelections() {
    _selections.clear();
    notifyListeners();
  }

  Future<void> setLang(String lang, {BuildContext? context, bool reanalyze = true}) async {
    currentLang = lang;
    notifyListeners();
    if (reanalyze && currentText.isNotEmpty) {
      await analyzeText(context, text: currentText, lang: currentLang);
    }
  }

  void setDropdownReplacementForMatch(String key, String? value) {
    final cur = selectionOf(key);
    _selections[key] = cur.copyWith(selected: true, replacement: value, manual: null);
    notifyListeners();
  }

  void setManualReplacementForMatch(String key, String value, {bool updateOnly = false}) {
    final cur = selectionOf(key);
    final shouldSelect = value.trim().isNotEmpty || !updateOnly;
    _selections[key] = cur.copyWith(
      selected: shouldSelect,
      manual: value,
      replacement: updateOnly ? cur.replacement : null,
    );
    notifyListeners();
  }

  void clearSelectionForMatch(String key) {
    _selections.remove(key);
    notifyListeners();
  }

  // ---------- CLASIFICACIÓN DE MATCHES ----------
  /// Normaliza cada match con un `clientClass` estable: grammar | punct | style | spelling
  String classifyMatch(Map<String, dynamic> m) {
    final issue = (m['rule']?['issueType'] ?? '').toString().toLowerCase();
    final catId = (m['rule']?['category']?['id'] ?? '').toString().toLowerCase();
    final catName = (m['rule']?['category']?['name'] ?? '').toString().toLowerCase();

    bool anyContains(String s, List<String> keys) =>
        keys.any((k) => s.contains(k));

    if (issue == 'misspelling' ||
        anyContains(catId, ['typo', 'spelling', 'morfologik']) ||
        anyContains(catName, ['typo', 'spelling', 'ortografía', 'morfologik'])) {
      return 'spelling';
    }
    if (issue == 'typographical' ||
        anyContains(catId, ['punct']) ||
        anyContains(catName, ['puntuación', 'punct'])) {
      return 'punct';
    }
    if (issue == 'style' ||
        anyContains(catId, ['style']) ||
        anyContains(catName, ['estilo'])) {
      return 'style';
    }
    return 'grammar';
  }

  Map<String, dynamic> _withClientClassOnMatches(Map<String, dynamic> ltJson) {
    final List matches = (ltJson['matches'] ?? const []) as List;
    for (final e in matches) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      // si ya viene del backend, respétalo; si no, lo generamos
      m['clientClass'] = m['clientClass'] ?? classifyMatch(m);
    }
    return ltJson;
  }

  // ---------- APLICAR REEMPLAZOS ----------
  Future<void> applySelectedFixes({BuildContext? context}) async {
    if (result == null || currentText.isEmpty) return;

    String text = currentText;
    final List<Map<String, dynamic>> matches = List<Map<String, dynamic>>.from(
      (((result!['languageTool'] ?? const {}) as Map)['matches'] ?? const []) as List,
    ).map((e) => e.cast<String, dynamic>()).toList();

    // del final al inicio para no mover offsets
    matches.sort((a, b) => (b['offset'] as int).compareTo(a['offset'] as int));

    int applied = 0;
    for (final m in matches) {
      final key = keyForMatch(m);
      final sel = selectionOf(key);
      if (!sel.selected) continue;

      final off = (m['offset'] ?? 0) as int;
      final len = (m['length'] ?? 0) as int;
      final replacement = (sel.manual?.isNotEmpty == true ? sel.manual : sel.replacement) ?? '';
      if (replacement.isEmpty) continue;
      if (off < 0 || len <= 0 || off + len > text.length) continue;

      text = text.replaceRange(off, off + len, replacement);
      applied++;
    }

    if (applied > 0) {
      currentText = text;
      _selections.clear();               // ← nada seleccionado tras aplicar
      notifyListeners();
      await analyzeText(context, text: currentText, lang: currentLang);
    }

    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cambios aplicados: $applied')),
      );
    }
  }

  // ---------- HEALTH ----------
  Future<void> checkHealth() async {
    try {
      final r = await http.get(Uri.parse('$apiBase/health')).timeout(const Duration(seconds: 2));
      backendOk = r.statusCode == 200;
    } catch (_) {
      backendOk = false;
    }
    try {
      final r = await http.get(Uri.parse('$ltBase/v2/languages')).timeout(const Duration(seconds: 2));
      ltOk = r.statusCode == 200;
    } catch (_) {
      ltOk = false;
    }
    notifyListeners();
  }

  // ---------- CARGAR / ANALIZAR ----------
  Future<void> pickUploadAndAnalyze(BuildContext context) async {
    try {
      final typeGroup = XTypeGroup(
        label: 'Documentos',
        extensions: ['txt', 'docx', 'pdf'],
        mimeTypes: [
          'text/plain',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'application/pdf'
        ],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      // Validar extensión por seguridad
      final nameLower = file.name.toLowerCase();
      final okExt = nameLower.endsWith('.txt') || nameLower.endsWith('.docx') || nameLower.endsWith('.pdf');
      if (!okExt) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formato no soportado. Usa .txt, .docx o .pdf.')),
        );
        return;
      }

      isUploading = true;
      uploadProgress = null;
      notifyListeners();

      if (nameLower.endsWith('.txt')) {
        final text = await file.readAsString();
        currentText = text;
        _selections.clear(); // ← iniciar sin nada seleccionado
        notifyListeners();
        await analyzeText(context, text: text, lang: currentLang);
      } else {
        await _uploadBinaryAndAnalyze(context, file);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $e')),
      );
    } finally {
      if (isUploading) {
        isUploading = false;
        uploadProgress = 0.0;
        notifyListeners();
      }
    }
  }

  Future<void> _uploadBinaryAndAnalyze(BuildContext context, XFile file) async {
    try {
      final uri = Uri.parse('$apiBase/analyze/file');
      final req = http.MultipartRequest('POST', uri);
      req.fields['lang'] = currentLang;

      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.pdf')
          ? MediaType('application', 'pdf')
          : MediaType('application', 'vnd.openxmlformats-officedocument.wordprocessingml.document');

      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
        contentType: mime,
      ));

      final respStream = await req.send();
      final resp = await http.Response.fromStream(respStream);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        // El backend puede devolver { text, languageTool, ... }
        final lt = (body['languageTool'] ?? body) as Map<String, dynamic>;
        result = {
          'languageTool': _withClientClassOnMatches(Map<String, dynamic>.from(lt)),
        };
        currentText = (body['text'] ?? currentText) as String;
        _selections.clear(); // ← iniciar sin selecciones
        notifyListeners();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ${resp.statusCode}: ${resp.reasonPhrase ?? resp.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fallo de red: $e')),
      );
    } finally {
      isUploading = false;
      uploadProgress = 0.0;
      notifyListeners();
    }
  }

  // ---------- ANALIZAR TEXTO (LanguageTool) ----------
  Future<void> analyzeText(BuildContext? context, {required String text, String? lang}) async {
    final ltLang = ltLangMap[lang ?? currentLang] ?? 'es';
    try {
      final uri = Uri.parse('$ltBase/v2/check');
      final resp = await http.post(uri, body: {
        'text': text,
        'language': ltLang,
      });
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final ltJson = jsonDecode(resp.body) as Map<String, dynamic>;
        result = {
          'languageTool': _withClientClassOnMatches(Map<String, dynamic>.from(ltJson)),
        };
        _selections.clear(); // ← nada seleccionado tras un reanálisis
        notifyListeners();
      } else {
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('LanguageTool respondió ${resp.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al analizar: $e')),
        );
      }
    }
  }

  // ---------- UTILIDADES ----------
  void replaceCurrentText(String newText) {
    currentText = newText;
    notifyListeners();
  }

  Future<void> fetchDictionary() async {
    await Future.delayed(const Duration(milliseconds: 150));
    notifyListeners();
  }

  void dictionaryAdd(String word) {
    if (word.trim().isEmpty) return;
    dictionaryWords.add(word.trim());
    notifyListeners();
  }

  void removeFromDictionary(String word) {
    dictionaryWords.remove(word);
    notifyListeners();
  }
}
