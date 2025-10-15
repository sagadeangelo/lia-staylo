// lib/screens/lia_staylo_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lia_staylo_api.dart';

class LIAStayloScreen extends StatefulWidget {
  const LIAStayloScreen({super.key});

  @override
  State<LIAStayloScreen> createState() => _LIAStayloScreenState();
}

class _LIAStayloScreenState extends State<LIAStayloScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? analysis;
  bool loading = false;

  String _lang = 'es-MX'; // 'es-MX' | 'es-419' | 'en-US'

  final _searchCtrl = TextEditingController();
  String _filterType = "all";

  final Set<String> _selectedKeys = <String>{};
  final Map<String, String> _chosenReplacement = <String, String>{};

  // Cache diccionario por idioma
  final Map<String, List<String>> _dictCacheByLang = {
    'es-MX': <String>[],
    'es-419': <String>[],
    'en-US': <String>[],
  };
  final TextEditingController _dictAddCtrl = TextEditingController();
  String _dictSearch = '';
  bool _dictLoading = false;

  // Gestión de proyecto / autoguardado
  String? _projectPath;     // Ruta del .lia si ya se guardó alguna vez
  bool _dirty = false;      // Hay cambios sin guardar
  Timer? _autosaveTimer;    // Debounce autosave
  static const _autosaveDelay = Duration(seconds: 3);

  // ===== utilidades =====
  String _fullText() => (analysis?["text"] ?? "") as String;

  List<Map<String, dynamic>> _allMatches() =>
      ((analysis?["languageTool"]?["matches"] ?? []) as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

  String _keyForMatch(Map<String, dynamic> m) {
    final rule = (m["rule"] ?? "").toString();
    final off = (m["offset"] ?? 0).toString();
    final len = (m["length"] ?? 0).toString();
    return "$rule@$off:$len";
  }

  String _classOfMatch(Map<String, dynamic> m) {
    final preset = (m['lt_clientClass'] ?? '').toString();
    if (preset.isNotEmpty) return preset;

    final rule = (m["rule"] ?? "").toString().toUpperCase();
    final cat  = (m["category"] ?? "").toString().toUpperCase();
    final msg  = (m["message"] ?? "").toString().toLowerCase();

    bool any(String s, List<String> keys) => keys.any((k) => s.contains(k));

    // Spelling
    if (rule.contains('MORFOLOGIK') ||
        rule.contains('HUNSPELL') ||
        rule.contains('SPELL') ||
        rule.contains('TYPO') ||
        any(cat, ['SPELL','TYPO','ORTOGRAF']) ||
        any(msg, ['error ortográfico','palabra desconocida','¿quiso decir','posible error'])) {
      return 'spelling';
    }

    // Space / punctuation
    if (any(rule, ['COMMA','WHITESPACE','PUNCT','ELLIPSIS','DASH','HYPHEN','APOS','QUOTE','BRACKET','PAREN']) ||
        any(cat,  ['PUNCT','WHITESPACE']) ||
        any(msg,  ['espacio','puntuación','coma','punto','comillas','paréntesis','guion','guión','apóstrofo'])) {
      return 'space';
    }

    // Style (incluye CUSTOM_)
    if (any(rule, ['STYLE','CUSTOM_','MULE']) ||
        any(cat,  ['STYLE']) ||
        any(msg,  ['muletilla','registro','más claro','más conciso','estilo'])) {
      return 'style';
    }

    return 'grammar';
  }

  Map<String, int> _countsByTypeFrom(List<Map<String, dynamic>> matches) {
    final counts = <String, int>{"all": matches.length,"grammar": 0,"space": 0,"style": 0,"spelling": 0};
    for (final m in matches) {
      final bucket = _classOfMatch(m);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _countsByType() => _countsByTypeFrom(_allMatches());

  List<Map<String, dynamic>> _filteredMatches() {
    final matches = _allMatches();
    final q = _searchCtrl.text.trim().toLowerCase();

    Iterable<Map<String, dynamic>> seq = matches;

    if (_filterType != "all") {
      seq = seq.where((m) => _classOfMatch(m) == _filterType);
    }

    if (q.isNotEmpty) {
      seq = seq.where((m) {
        final msg = (m["message"] ?? "").toString().toLowerCase();
        final short = (m["shortMessage"] ?? "").toString().toLowerCase();
        final rule = (m["rule"] ?? "").toString().toLowerCase();
        final cat  = (m["category"] ?? "").toString().toLowerCase();
        return msg.contains(q) || short.contains(q) || rule.contains(q) || cat.contains(q);
      });
    }
    return seq.toList();
  }

  String _tokenFromMatch(Map<String, dynamic> m, {String? textOverride}) {
    final text = textOverride ?? _fullText();
    final off  = (m["offset"] ?? 0) as int;
    final len  = (m["length"] ?? 0) as int;
    if (off < 0 || len <= 0 || off + len > text.length) return "";
    return text.substring(off, off + len);
  }

  String _contextSentence(Map<String, dynamic> m) {
    final text = _fullText();
    if (text.isEmpty) return "";
    final off = (m["offset"] ?? 0) as int;
    final len = (m["length"] ?? 0) as int;
    final end = (off + len).clamp(0, text.length);

    final separators = RegExp(r'[\.!\?:;]|[\r\n]');
    int start = off;
    int stop = end;

    for (int i = off - 1; i >= 0; i--) {
      if (separators.hasMatch(text[i])) { start = i + 1; break; }
      if (off - i > 300) break;
      start = 0;
    }
    for (int i = end; i < text.length; i++) {
      if (separators.hasMatch(text[i])) { stop = i + 1; break; }
      if (i - end > 300) break;
      stop = text.length;
    }

    String slice = text.substring(start, stop).trim();
    if (slice.isEmpty) {
      final win = 120;
      final s = (off - win).clamp(0, text.length);
      final e = (end + win).clamp(0, text.length);
      slice = text.substring(s, e).trim();
    }
    return slice;
  }

  // ===== análisis / aplicar =====
  Future<void> _pickAndAnalyze() async {
    final res = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text/Markdown/Word', extensions: ['txt', 'md', 'docx']),
      ],
    );
    if (res == null) return;

    setState(() => loading = true);
    try {
      final file = File(res.path);
      final data = await LIAStayloAPI.analyzeFile(file, lang: _lang);
      setState(() {
        analysis = data;
        _selectedKeys.clear();
        _chosenReplacement.clear();
        _markDirty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error analizando: $e")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _applySafe() async {
    final text = _fullText();
    if (text.isEmpty) return;
    setState(() => loading = true);
    try {
      final resp = await LIAStayloAPI.applySafe(text, lang: _lang);
      final updated = (resp["new_text"] ?? text) as String;
      final re = await LIAStayloAPI.analyzeText(updated, lang: _lang);
      setState(() {
        analysis = re;
        _selectedKeys.clear();
        _chosenReplacement.clear();
        _markDirty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error aplicando: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _applyAllLT() async {
    final text = _fullText();
    if (text.isEmpty) return;
    setState(() => loading = true);
    try {
      final resp = await LIAStayloAPI.applyAll(text, lang: _lang);
      final updated = (resp["new_text"] ?? text) as String;
      final re = await LIAStayloAPI.analyzeText(updated, lang: _lang);
      setState(() {
        analysis = re;
        _selectedKeys.clear();
        _chosenReplacement.clear();
        _markDirty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error aplicando: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _applySelected() async {
    final text = _fullText();
    if (text.isEmpty || _selectedKeys.isEmpty) return;

    final current = _filteredMatches().where((m) => _selectedKeys.contains(_keyForMatch(m))).toList();

    current.sort((a, b) {
      final oa = (a["offset"] ?? 0) as int;
      final ob = (b["offset"] ?? 0) as int;
      return ob.compareTo(oa);
    });

    var newText = text;
    for (final m in current) {
      final off = (m["offset"] ?? 0) as int;
      final len = (m["length"] ?? 0) as int;
      if (off < 0 || len <= 0 || off + len > newText.length) continue;

      final key = _keyForMatch(m);
      String replacement = _chosenReplacement[key] ?? '';
      if (replacement.isEmpty) {
        final reps = (m["replacements"] ?? []) as List;
        if (reps.isEmpty) continue;
        replacement = reps.first.toString();
      }
      newText = newText.replaceRange(off, off + len, replacement);
    }

    setState(() => loading = true);
    try {
      final re = await LIAStayloAPI.analyzeText(newText, lang: _lang);
      setState(() {
        analysis = re;
        _selectedKeys.clear();
        _chosenReplacement.clear();
        _markDirty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error aplicando: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ===== .LIA =====
  Map<String, dynamic> _buildProjectPayload({Map<String, List<String>>? dict}) {
    return {
      "app": "LIA-Staylo",
      "version": "0.6.2",
      "saved_at": DateTime.now().toIso8601String(),
      "lang": _lang,
      "backend": LIAStayloAPI.baseUrl,
      "analysis": analysis ?? {},
      "ui": {
        "filterType": _filterType,
        "search": _searchCtrl.text,
        "selectedKeys": _selectedKeys.toList(),
        "chosenReplacement": _chosenReplacement,
      },
      if (dict != null) "dictionary": dict,
    };
  }

  Future<Map<String, List<String>>> _collectDictionariesSafe() async {
    final dict = <String, List<String>>{};
    for (final lg in ['es-MX', 'es-419', 'en-US']) {
      List<String> words = [];
      try {
        words = await LIAStayloAPI.dictionaryList(lang: lg);
      } catch (_) {
        // si falla el backend, usamos el cache local
      }
      if (words.isEmpty) {
        words = List<String>.from(_dictCacheByLang[lg] ?? const <String>[]);
      }
      dict[lg] = words;
    }
    return dict;
  }

  // Guardar (elige ruta si no existe)
  Future<void> _saveProjectLIA() async {
    try {
      if (_projectPath == null) {
        // Save As
        final loc = await getSaveLocation(
          acceptedTypeGroups: [const XTypeGroup(label: 'LIA Project', extensions: ['lia'])],
          suggestedName: 'proyecto.lia',
        );
        if (loc == null) return;
        _projectPath = loc.path;
      }
      await _saveProjectToPath(_projectPath!, silent: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando proyecto: $e")));
    }
  }

  // Guardar como...
  Future<void> _saveProjectAsLIA() async {
    try {
      final name = _projectFileName() ?? 'proyecto.lia';
      final loc = await getSaveLocation(
        acceptedTypeGroups: [const XTypeGroup(label: 'LIA Project', extensions: ['lia'])],
        suggestedName: name,
      );
      if (loc == null) return;
      _projectPath = loc.path;
      await _saveProjectToPath(_projectPath!, silent: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando: $e")));
    }
  }

  // Escribir a una ruta concreta (sin diálogo)
  Future<void> _saveProjectToPath(String path, {bool silent = true}) async {
    final dict = await _collectDictionariesSafe();
    final payload = _buildProjectPayload(dict: dict);
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    final file = File(path);
    await file.writeAsString(pretty, encoding: const Utf8Codec());
    _dirty = false;
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Proyecto guardado en ${_projectFileName()}")),
      );
    }
    setState(() {}); // refresca título (quita asterisco)
  }

  Future<void> _openProjectLIA() async {
    try {
      final map = await LIAStayloAPI.openProject();
      if (map == null) return;

      final ana = (map["analysis"] ?? {}) as Map<String, dynamic>;
      final ui = (map["ui"] ?? {}) as Map<String, dynamic>;
      final dict = (map["dictionary"] ?? {}) as Map?;

      setState(() {
        analysis = ana;
        _lang = (map["lang"] ?? _lang).toString();
        _filterType = (ui["filterType"] ?? "all").toString();
        _searchCtrl.text = (ui["search"] ?? "").toString();
        _selectedKeys
          ..clear()
          ..addAll(((ui["selectedKeys"] ?? []) as List).map((e) => e.toString()));
        _chosenReplacement
          ..clear()
          ..addAll(Map<String, String>.from(ui["chosenReplacement"] ?? {}));
        _dirty = false;
        _projectPath = null; // no conocemos la ruta original en openProject()
      });

      // Importa diccionarios (merge)
      if (dict is Map) {
        for (final entry in dict.entries) {
          final lg = entry.key.toString();
          final list = (entry.value as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
          for (final w in list) {
            try { await LIAStayloAPI.dictionaryAdd(w, lang: lg); } catch (_) {}
          }
          _dictCacheByLang[lg] = {...?_dictCacheByLang[lg], ...list}.toList()..sort();
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proyecto .LIA cargado")));
      _reloadDictionary();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error leyendo proyecto: $e")));
    }
  }

  // ===== TXT / MD / DOCX =====
  Future<void> _saveAsTxt() async {
    final text = _fullText();
    if (text.isEmpty) return;
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [XTypeGroup(label: 'Texto', extensions: ['txt'])],
      suggestedName: 'manuscrito_revisado.txt',
    );
    if (loc == null) return;
    try {
      final file = File(loc.path);
      await file.writeAsString(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("TXT guardado")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando: $e")));
    }
  }

  Future<void> _saveAsMd() async {
    final text = _fullText();
    if (text.isEmpty) return;
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [XTypeGroup(label: 'Markdown', extensions: ['md'])],
      suggestedName: 'manuscrito_revisado.md',
    );
    if (loc == null) return;
    try {
      final file = File(loc.path);
      await file.writeAsString(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("MD guardado")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando: $e")));
    }
  }

  Future<void> _saveAsDocx() async {
    final text = _fullText();
    if (text.isEmpty) return;
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [XTypeGroup(label: 'Word', extensions: ['docx'])],
      suggestedName: 'manuscrito_revisado.docx',
    );
    if (loc == null) return;
    try {
      final bytes = _buildDocxFromPlainText(text);
      final file = File(loc.path);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("DOCX guardado")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error guardando DOCX: $e")));
    }
  }

  List<int> _buildDocxFromPlainText(String text) {
    String escapeXml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final paragraphs = text.split('\n').map((line) =>
      '<w:p><w:r><w:t xml:space="preserve">${escapeXml(line)}</w:t></w:r></w:p>').join();

    final documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  <w:body>
    $paragraphs
    <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
  </w:body>
</w:document>
''';

    final contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
''';

    final relsRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

    final docRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>
''';

    final coreXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>LIA-Staylo</dc:title><dc:subject>Texto revisado</dc:subject><dc:creator>LIA-Staylo</dc:creator><cp:revision>1</cp:revision>
</cp:coreProperties>
''';

    final appXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>LIA-Staylo</Application>
</Properties>
''';

    final archive = Archive()
      ..addFile(ArchiveFile('[Content_Types].xml', utf8.encode(contentTypes).length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', utf8.encode(relsRels).length, utf8.encode(relsRels)))
      ..addFile(ArchiveFile('word/document.xml', utf8.encode(documentXml).length, utf8.encode(documentXml)))
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', utf8.encode(docRels).length, utf8.encode(docRels)))
      ..addFile(ArchiveFile('docProps/core.xml', utf8.encode(coreXml).length, utf8.encode(coreXml)))
      ..addFile(ArchiveFile('docProps/app.xml', utf8.encode(appXml).length, utf8.encode(appXml)));

    return ZipEncoder().encode(archive)!;
  }

  // ===== diccionario (UI) =====
  Future<void> _addTokenToDictionary(String token) async {
    final t = token.trim();
    if (t.isEmpty) return;
    try {
      await LIAStayloAPI.dictionaryAdd(t, lang: _lang);

      // Actualiza cache local
      final list = _dictCacheByLang[_lang] ?? <String>[];
      if (!list.contains(t)) {
        list.add(t);
        list.sort();
        _dictCacheByLang[_lang] = list;
      }

      // Quita en caliente los errores ortográficos para esa palabra
      _removeCurrentSpellingMatchesForWords({t});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Agregado «$t» al diccionario ($_lang).")),
      );
      _markDirty();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _reloadDictionary() async {
    setState(() => _dictLoading = true);
    try {
      final words = await LIAStayloAPI.dictionaryList(lang: _lang);
      setState(() {
        _dictCacheByLang[_lang] = words..sort();
      });
      // Tras recargar, también limpiamos ortografías presentes
      _removeCurrentSpellingMatchesForWords(words.toSet());
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _dictLoading = false);
    }
  }

  // Eliminar de analysis los errores de ortografía cuyo token está en 'words'
  void _removeCurrentSpellingMatchesForWords(Set<String> words) {
    if (analysis == null) return;
    final wordsLower = words.map((e) => e.toLowerCase()).toSet();

    final matches = _allMatches();
    if (matches.isEmpty) return;

    final text = _fullText();
    final keep = <Map<String, dynamic>>[];
    final removedKeys = <String>[];

    for (final m in matches) {
      final cls = _classOfMatch(m);
      if (cls == 'spelling') {
        final tok = _tokenFromMatch(m, textOverride: text).toLowerCase();
        if (wordsLower.contains(tok)) {
          removedKeys.add(_keyForMatch(m));
          continue; // lo filtramos
        }
      }
      keep.add(m);
    }

    // Limpia selecciones y reemplazos de las entradas removidas
    for (final k in removedKeys) {
      _selectedKeys.remove(k);
      _chosenReplacement.remove(k);
    }

    // Setea analysis con nuevos matches y recuenta
    analysis!["languageTool"] = {"matches": keep};
    final counts = _countsByTypeFrom(keep);
    analysis!["lt_counts"] = counts;

    setState(() {}); // refresca UI
  }

  // ===== init / dispose =====
  @override
  void initState() {
    super.initState();
    LIAStayloAPI.initSavedLang().then((_) {
      setState(() => _lang = LIAStayloAPI.currentLang);
      _reloadDictionary();
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  // Autosave helpers
  void _markDirty() {
    _dirty = true;
    _scheduleAutosave();
    setState(() {}); // para refrescar el título con *
  }

  void _scheduleAutosave() {
    if (_projectPath == null) return; // solo autoguarda si ya existe ruta
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () async {
      try {
        await _saveProjectToPath(_projectPath!, silent: true);
      } catch (_) {
        // Silencioso
      }
    });
  }

  String? _projectFileName() {
    if (_projectPath == null) return null;
    try {
      return File(_projectPath!).uri.pathSegments.last;
    } catch (_) {
      return null;
    }
  }

  String _titleText() {
    final base = "LIA-Staylo";
    final name = _projectFileName();
    if (name == null) return base + (_dirty ? " *" : "");
    return "$base — $name${_dirty ? ' *' : ''}";
  }

  // Confirmación al cerrar (cuando el usuario intenta volver)
  Future<bool> _onWillPop() async {
    // No hay nada que salvar
    final hasContent = _fullText().isNotEmpty || (analysis?["languageTool"]?["matches"] ?? []).isNotEmpty;
    if (!hasContent && !_dirty) return true;

    if (_projectPath == null) {
      // Nunca se guardó: ofrecer guardar
      final action = await _showExitDialog(
        title: "¿Salir sin guardar?",
        message: "Aún no has guardado el proyecto. ¿Deseas guardarlo antes de salir?",
        primaryLabel: "Guardar y salir",
        secondaryLabel: "Salir sin guardar",
      );
      if (action == _ExitAction.primary) {
        await _saveProjectLIA();
        return true;
      } else if (action == _ExitAction.secondary) {
        return true;
      }
      return false;
    } else {
      // Ya guardado: si hay cambios, ofrecer guardar en el mismo archivo
      if (_dirty) {
        final name = _projectFileName() ?? 'proyecto.lia';
        final action = await _showExitDialog(
          title: "Guardar cambios",
          message: "¿Guardar cambios en «$name» antes de salir?",
          primaryLabel: "Guardar y salir",
          secondaryLabel: "Salir sin guardar",
        );
        if (action == _ExitAction.primary) {
          await _saveProjectToPath(_projectPath!, silent: true);
          return true;
        } else if (action == _ExitAction.secondary) {
          return true;
        }
        return false;
      }
      return true;
    }
  }

  Future<_ExitAction?> _showExitDialog({
    required String title,
    required String message,
    required String primaryLabel,
    required String secondaryLabel,
  }) async {
    return showDialog<_ExitAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(_ExitAction.cancel), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.of(context).pop(_ExitAction.secondary), child: Text(secondaryLabel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(_ExitAction.primary), child: Text(primaryLabel)),
        ],
      ),
    );
  }

  Future<void> _confirmAndExit() async {
    final allow = await _onWillPop();
    if (allow) {
      // En desktop, esto cierra el proceso.
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_titleText(), overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: "Guardar proyecto (.LIA)",
                onPressed: _saveProjectLIA,
                icon: const Icon(Icons.save_outlined),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'save_as':
                      await _saveProjectAsLIA();
                      break;
                    case 'open':
                      await _openProjectLIA();
                      break;
                    case 'reanalyze':
                      if (_fullText().isEmpty) return;
                      final data = await LIAStayloAPI.analyzeText(_fullText(), lang: _lang);
                      setState(() {
                        analysis = data;
                        _selectedKeys.clear();
                        _chosenReplacement.clear();
                        _markDirty();
                      });
                      break;
                  }
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'save_as', child: Text('Guardar como…')),
                  PopupMenuItem(value: 'open', child: Text('Abrir proyecto (.LIA)')),
                  PopupMenuItem(value: 'reanalyze', child: Text('Reanalizar')),
                ],
              ),
              IconButton(
                tooltip: "Cerrar",
                onPressed: _confirmAndExit,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 8),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.upload_file), text: "Archivo"),
                Tab(icon: Icon(Icons.analytics_outlined), text: "Resultados"),
                Tab(icon: Icon(Icons.auto_fix_high_outlined), text: "Sugerencias"),
                Tab(icon: Icon(Icons.library_books_outlined), text: "Diccionario"),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              // Archivo
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text("Español (México)"),
                            selected: _lang == 'es-MX',
                            onSelected: (_) async {
                              setState(() => _lang = 'es-MX');
                              await LIAStayloAPI.setLang('es-MX');
                              _reloadDictionary();
                            },
                          ),
                          ChoiceChip(
                            label: const Text("Español (Latino)"),
                            selected: _lang == 'es-419',
                            onSelected: (_) async {
                              setState(() => _lang = 'es-419');
                              await LIAStayloAPI.setLang('es-419');
                              _reloadDictionary();
                            },
                          ),
                          ChoiceChip(
                            label: const Text("Inglés (US)"),
                            selected: _lang == 'en-US',
                            onSelected: (_) async {
                              setState(() => _lang = 'en-US');
                              await LIAStayloAPI.setLang('en-US');
                              _reloadDictionary();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text("Backend: ${LIAStayloAPI.baseUrl}", overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () async {
                                  try {
                                    final h = await LIAStayloAPI.health();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Health OK: $h")));
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Health error: $e")));
                                  }
                                },
                          icon: const Icon(Icons.health_and_safety),
                          label: const Text("Health"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: loading ? null : _pickAndAnalyze,
                          icon: const Icon(Icons.upload),
                          label: Text(loading ? "Analizando..." : "Subir y analizar manuscrito"),
                        ),
                        const SizedBox(width: 12),
                        if (_fullText().isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _saveAsTxt,
                            icon: const Icon(Icons.download),
                            label: const Text("Guardar revisado (TXT)"),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Formatos soportados: .txt, .md, .docx"),
                    ),
                    const SizedBox(height: 24),
                    if (_fullText().isNotEmpty)
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              child: Text(_fullText(), style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                        ),
                      )
                    else
                      const Expanded(child: Center(child: Text("Sin contenido cargado."))),
                  ],
                ),
              ),

              // Resultados
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: loading ? null : _applySafe,
                          icon: const Icon(Icons.build_circle_outlined),
                          label: const Text("Aplicar SEGURAS"),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: loading ? null : _applyAllLT,
                          icon: const Icon(Icons.done_all),
                          label: const Text("Aplicar TODO (LT)"),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () async {
                            if (_fullText().isEmpty) return;
                            final data = await LIAStayloAPI.analyzeText(_fullText(), lang: _lang);
                            setState(() {
                              analysis = data;
                              _selectedKeys.clear();
                              _chosenReplacement.clear();
                              _markDirty();
                            });
                          },
                          tooltip: "Re-analizar",
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Métricas", style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: _statsCard()),
                    const SizedBox(height: 12),
                    _typeChips(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        labelText: "Filtrar observaciones (mensaje/regla)…",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _matchesList()),
                  ],
                ),
              ),

              // Sugerencias
              _SuggestTab(
                onApply: (newText) async {
                  final data = await LIAStayloAPI.analyzeText(newText, lang: _lang);
                  setState(() {
                    analysis = data;
                    _selectedKeys.clear();
                    _chosenReplacement.clear();
                    _markDirty();
                  });
                },
              ),

              // Diccionario
              _dictionaryTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ===== tarjetas / UI auxiliares =====
  Widget _statsCard() {
    final stats = analysis?["stats"] as Map<String, dynamic>?;
    final read = analysis?["readability"] as Map<String, dynamic>?;
    if (stats == null) return const Text("Sin estadísticas. Sube un archivo en la pestaña Archivo.");
    Widget badge(String title, Object? v) => Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text("${v ?? '-'}"),
        ]),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        badge("Palabras", stats["words"]),
        badge("Oraciones", stats["sentences"]),
        badge("Frases largas (>30)", stats["long_sentences"]),
        badge("Marcas de diálogo", stats["dialog_marks"]),
        badge("Legibilidad (ref. Flesch EN)", read?["flesch_en_reference"]),
        badge("Sílabas", read?["syllables"]),
      ],
    );
  }

  Widget _typeChips() {
    final counts = _countsByType();
    ChoiceChip choice(String id, String label, IconData icon) => ChoiceChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16), const SizedBox(width: 6),
        Text("$label (${counts[id] ?? 0})"),
      ]),
      selected: _filterType == id,
      onSelected: (_) {
        setState(() => _filterType = id);
      },
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        choice("all", "Todos", Icons.all_inclusive),
        choice("grammar", "Gramática", Icons.rule),
        choice("space", "Puntuación/Espacios", Icons.space_bar),
        choice("style", "Estilo", Icons.brush),
        choice("spelling", "Ortografía", Icons.spellcheck),
      ],
    );
  }

  Widget _downloadBar() {
    final hasText = _fullText().isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.download_rounded),
            const SizedBox(width: 8),
            const Text("Descargar archivo modificado"),
            const Spacer(),
            OutlinedButton.icon(onPressed: hasText ? _saveAsTxt : null, icon: const Icon(Icons.description), label: const Text("TXT")),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: hasText ? _saveAsMd : null, icon: const Icon(Icons.code), label: const Text("MD")),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: hasText ? _saveAsDocx : null, icon: const Icon(Icons.file_present), label: const Text("DOCX")),
          ],
        ),
      ),
    );
  }

  Future<void> _openChooseDialog(Map<String, dynamic> m) async {
    final key = _keyForMatch(m);
    final reps = (m["replacements"] ?? []) as List;
    final token = _tokenFromMatch(m);

    final controller = TextEditingController(text: reps.isNotEmpty ? reps.first.toString() : token);

    final selected = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Elegir corrección"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (token.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text("Original: $token")),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: (reps.isNotEmpty ? reps.first.toString() : null),
              items: reps.map((e) => DropdownMenuItem(value: e.toString(), child: Text(e.toString()))).toList(),
              onChanged: (v) {
                if (v != null) controller.text = v;
              },
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Sugerencias"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Personalizar reemplazo",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text("Elegir")),
        ],
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      setState(() {
        _chosenReplacement[key] = selected;
        _selectedKeys.add(key);
        _markDirty();
      });
    }
  }

  Widget _matchesToolbar() {
    final filtered = _filteredMatches();
    final allSelected = filtered.isNotEmpty && filtered.every((m) => _selectedKeys.contains(_keyForMatch(m)));
    final anySelected = filtered.any((m) => _selectedKeys.contains(_keyForMatch(m)));

    return Row(
      children: [
        Checkbox(
          value: allSelected,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                for (final m in filtered) _selectedKeys.add(_keyForMatch(m));
              } else {
                for (final m in filtered) _selectedKeys.remove(_keyForMatch(m));
              }
              _markDirty();
            });
          },
        ),
        const Text("Seleccionar todos los visibles"),
        const Spacer(),
        Tooltip(
          message: "Aplicar solo a los seleccionados (usa tu elección o la 1ª sugerencia)",
          child: FilledButton.icon(
            onPressed: anySelected && !loading ? _applySelected : null,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text("Aplicar seleccionados"),
          ),
        ),
      ],
    );
  }

  Widget _matchItem(Map<String, dynamic> m) {
    final reps = (m["replacements"] ?? []) as List;
    final token = _tokenFromMatch(m);
    final ctx = _contextSentence(m);

    final key = _keyForMatch(m);
    final checked = _selectedKeys.contains(key);

    String truncateMiddle(String s, {int max = 120}) {
      if (s.length <= max) return s;
      final head = s.substring(0, (max / 2).floor());
      final tail = s.substring(s.length - (max / 2).floor());
      return "$head…$tail";
    }

    final subtitle = [
      if ((m["shortMessage"] ?? "").toString().isNotEmpty) "Causa: ${m["shortMessage"]}",
      if ((m["rule"] ?? "").toString().isNotEmpty) "Regla: ${m["rule"]}",
      if ((m["category"] ?? "").toString().isNotEmpty) "Categoría: ${m["category"]}",
      if (token.isNotEmpty) "Token: ${truncateMiddle(token)}",
      if (reps.isNotEmpty) "Sugerencias: ${reps.join(", ")}",
      if (_chosenReplacement.containsKey(key)) "Elegida: ${_chosenReplacement[key]}",
      if (ctx.isNotEmpty) "Fragmento: ${truncateMiddle(ctx, max: 160)}",
    ].where((s) => s.isNotEmpty).join("\n");

    return CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      onChanged: (_) {
        setState(() {
          if (checked) { _selectedKeys.remove(key); } else { _selectedKeys.add(key); }
          _markDirty();
        });
      },
      dense: true,
      title: Text(m["message"] ?? ""),
      subtitle: Text(subtitle),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: "Elegir corrección", icon: const Icon(Icons.tune), onPressed: () => _openChooseDialog(m)),
          PopupMenuButton<String>(
            tooltip: "Acciones",
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: token));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copiado: $token")));
              } else if (v == 'addDict') {
                await _addTokenToDictionary(token);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.copy), title: Text("Copiar palabra"))),
              PopupMenuItem(value: 'addDict', child: ListTile(dense: true, leading: Icon(Icons.library_add_check), title: Text("Agregar al diccionario"))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dictionaryTab() {
    final words = (_dictCacheByLang[_lang] ?? const <String>[])
        .where((w) => _dictSearch.trim().isEmpty
            ? true
            : w.toLowerCase().contains(_dictSearch.toLowerCase()))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dictAddCtrl,
                  decoration: const InputDecoration(
                    labelText: "Agregar palabra al diccionario",
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) async {
                    final t = v.trim();
                    if (t.isEmpty) return;
                    await _addTokenToDictionary(t);
                    _dictAddCtrl.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _dictLoading
                    ? null
                    : () async {
                        final t = _dictAddCtrl.text.trim();
                        if (t.isEmpty) return;
                        await _addTokenToDictionary(t);
                        _dictAddCtrl.clear();
                      },
                icon: const Icon(Icons.add),
                label: const Text("Agregar"),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _dictLoading ? null : _reloadDictionary,
                icon: const Icon(Icons.refresh),
                label: const Text("Recargar"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: "Buscar palabra…",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _dictSearch = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _dictLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: words.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final w = words[i];
                      return ListTile(
                        title: Text(w),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: "Eliminar",
                          onPressed: () async {
                            try {
                              await LIAStayloAPI.dictionaryRemove(w, lang: _lang);
                              _reloadDictionary();
                              _markDirty();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _matchesList() {
    final items = _filteredMatches();
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text("No hay observaciones de LanguageTool o no coinciden con el filtro."),
      );
    }
    return Column(
      children: [
        _downloadBar(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: _matchesToolbar()),
        const Divider(height: 1),
        Expanded(child: ListView.separated(itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) => _matchItem(items[i]))),
      ],
    );
  }
}

// ===== SUGGEST TAB =====
class _SuggestTab extends StatefulWidget {
  final ValueChanged<String> onApply;
  const _SuggestTab({required this.onApply});
  @override
  State<_SuggestTab> createState() => _SuggestTabState();
}

class _SuggestTabState extends State<_SuggestTab> {
  final _inputCtrl = TextEditingController();
  String _suggestion = "";
  bool _loading = false;

  Future<void> _runSuggest() async {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() { _loading = true; _suggestion = ""; });
    try {
      final s = await LIAStayloAPI.suggestText(t);
      setState(() => _suggestion = s);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _inputCtrl, minLines: 6, maxLines: 12, decoration: const InputDecoration(labelText: "Pega aquí un párrafo para mejorar", border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton.icon(onPressed: _loading ? null : _runSuggest, icon: const Icon(Icons.auto_fix_high), label: Text(_loading ? "Pensando…" : "Mejorar con IA")),
          const SizedBox(width: 12),
          if (_suggestion.isNotEmpty) OutlinedButton.icon(onPressed: () => widget.onApply(_suggestion), icon: const Icon(Icons.check), label: const Text("Usar en manuscrito")),
        ]),
        const SizedBox(height: 12),
        Expanded(child: Card(elevation: 1, child: Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: Text(_suggestion.isEmpty ? "La reescritura aparecerá aquí." : _suggestion))))),
      ]),
    );
  }
}

enum _ExitAction { primary, secondary, cancel }
