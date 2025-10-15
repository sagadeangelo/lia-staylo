import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lia_staylo_api.dart';

class EditorScreen extends StatefulWidget {
  /// Para compatibilidad: puedes enviar initialText (mi versión)
  /// o originalText (tu versión anterior). Se usará el que venga.
  final String? initialText;
  final String? originalText;

  /// Observaciones iniciales (opcional). Si no llegan, se pueden recalcular.
  final List<Map<String, dynamic>>? matches;

  /// Posición a la que saltar al abrir (opcional)
  final int? jumpOffset;
  final int? jumpLength;

  const EditorScreen({
    super.key,
    this.initialText,
    this.originalText,
    this.matches,
    this.jumpOffset,
    this.jumpLength,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _textCtrl;
  String _diff = "";
  bool _applying = false;
  bool _reanalyzing = false;

  /// Mantener las observaciones en estado local para poder refrescarlas
  List<Map<String, dynamic>> _matches = [];

  /// Última posición global del puntero (para abrir menús en long-press)
  Offset? _lastTapDownPosition;

  @override
  void initState() {
    super.initState();

    final seedText = widget.initialText ?? widget.originalText ?? "";
    _textCtrl = TextEditingController(text: seedText);

    _matches = (widget.matches ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

    // Seleccionar la región indicada (si viene)
    if (widget.jumpOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final len = _textCtrl.text.length;
        final start = widget.jumpOffset!.clamp(0, len);
        final end = (widget.jumpLength ?? 0) > 0
            ? (start + widget.jumpLength!).clamp(0, len)
            : (start < len ? start + 1 : start);
        _textCtrl.selection = TextSelection(baseOffset: start, extentOffset: end);
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // ----------------- Utilidades -----------------

  String _tokenFromMatch(Map<String, dynamic> m) {
    final text = _textCtrl.text;
    final off = (m["offset"] ?? 0) as int;
    final len = (m["length"] ?? 0) as int;
    if (off < 0 || len <= 0 || off + len > text.length) return "";
    return text.substring(off, off + len);
  }

  String _decodeBest(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return latin1.decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  /// Lee contenido de un .docx (ZIP) y devuelve texto plano.
  /// - Respeta saltos de párrafo (</w:p>) y tabs (<w:tab/>).
  /// - Ignora etiquetas XML.
  String _readDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final entry = archive.files.firstWhere(
        (f) => !f.isDirectory && f.name.replaceAll('\\', '/') == 'word/document.xml',
        orElse: () => ArchiveFile('missing', 0, Uint8List(0)),
      );
      if (entry.size == 0) return '';

      final xmlBytes = entry.content is List<int>
          ? Uint8List.fromList(entry.content as List<int>)
          : (entry.content as Uint8List);

      var xml = _decodeBest(xmlBytes);

      // Tabs
      xml = xml.replaceAll(RegExp(r'<w:tab\s*/>'), '\t');

      // Saltos de línea dentro de párrafo (<w:br/> y <w:cr/>)
      xml = xml.replaceAll(RegExp(r'<w:(br|cr)\s*/>'), '\n');

      // Cerrar párrafo -> salto de línea
      xml = xml.replaceAll(RegExp(r'</w:p>'), '\n');

      // Quitar todas las etiquetas XML restantes
      xml = xml.replaceAll(RegExp(r'<[^>]+>'), '');

      // Normalizar espacios y líneas múltiples
      final lines = xml.split('\n').map((l) => l.trimRight()).toList();
      final compact = <String>[];
      var lastBlank = false;
      for (final l in lines) {
        final isBlank = l.trim().isEmpty;
        if (isBlank) {
          if (!lastBlank) compact.add('');
          lastBlank = true;
        } else {
          compact.add(l);
          lastBlank = false;
        }
      }
      return compact.join('\n').trimRight();
    } catch (e) {
      return '';
    }
  }

  Future<void> _addTokenToDictionary(String token) async {
    final t = token.trim();
    if (t.isEmpty) return;
    try {
      final ok = await LIAStayloAPI.dictionaryAdd(t);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Agregado «$t» al diccionario")),
        );
        await _reanalyze(); // refresca las observaciones para que desaparezcan falsos positivos
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo agregar al diccionario")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // ----------------- Abrir / Guardar -----------------

  Future<void> _openFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Texto', extensions: ['txt', 'md', 'docx']),
        ],
      );
      if (file == null) return;

      final nameLower = file.name.toLowerCase();
      final bytes = await file.readAsBytes();

      String content;
      if (nameLower.endsWith('.docx')) {
        content = _readDocx(bytes);
        if (content.isEmpty) {
          throw 'No se pudo leer el contenido del DOCX (document.xml vacío o no encontrado).';
        }
      } else {
        content = _decodeBest(bytes);
      }

      setState(() {
        _textCtrl.text = content;
        _diff = ""; // limpiamos diff al cargar un documento nuevo
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archivo cargado: ${file.name}')),
      );

      // Re-analizar automáticamente tras cargar
      await _reanalyze();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $e')),
      );
    }
  }

  Future<void> _saveAs() async {
    final location = await getSaveLocation(
      suggestedName: 'LIA-Staylo_revisado.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Texto', extensions: ['txt', 'md']),
      ],
    );
    if (location == null) return;

    try {
      final file = File(location.path);
      await file.writeAsString(_textCtrl.text, encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo guardado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  // ----------------- Acciones principales -----------------

  Future<void> _applySafe() async {
    setState(() => _applying = true);
    try {
      final resp = await LIAStayloAPI.applySafe(_textCtrl.text);
      setState(() {
        _textCtrl.text = (resp["new_text"] ?? _textCtrl.text) as String;
        _diff = (resp["diff"] ?? "") as String;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Correcciones seguras aplicadas (${resp["applied"] ?? 0})")),
      );
      await _reanalyze();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error aplicando correcciones: $e")),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _applyAllLT() async {
    setState(() => _applying = true);
    try {
      final resp = await LIAStayloAPI.applyAll(_textCtrl.text);
      setState(() {
        _textCtrl.text = (resp["new_text"] ?? _textCtrl.text) as String;
        _diff = (resp["diff"] ?? "") as String;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sugerencias LT aplicadas (${resp["applied"] ?? 0})")),
      );
      await _reanalyze();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error aplicando LT: $e")),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _reanalyze() async {
    setState(() => _reanalyzing = true);
    try {
      final data = await LIAStayloAPI.analyzeText(_textCtrl.text);
      final ms = (data["languageTool"]?["matches"] as List?) ?? [];
      setState(() {
        _matches = ms.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error re-analizando: $e")),
      );
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  // ----------------- UI: ítems de observación -----------------

  Future<void> _onMatchTap(Map<String, dynamic> m) async {
    final off = (m["offset"] ?? 0) as int;
    final len = (m["length"] ?? 0) as int;
    final lenText = _textCtrl.text.length;
    final start = off.clamp(0, lenText);
    final end = len > 0 ? (start + len).clamp(0, lenText) : (start < lenText ? start + 1 : start);
    _textCtrl.selection = TextSelection(baseOffset: start, extentOffset: end);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Cursor movido a $start-$end")),
    );
  }

  Future<void> _showMatchMenu(TapDownDetails details, Map<String, dynamic> m) async {
    final token = _tokenFromMatch(m);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text("Copiar palabra"),
          ),
        ),
        PopupMenuItem(
          value: 'addDict',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.library_add_check),
            title: Text("Agregar al diccionario"),
          ),
        ),
      ],
    );

    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Copiado: $token")),
      );
    } else if (selected == 'addDict') {
      await _addTokenToDictionary(token);
    }
  }

  /// Abre el menú contextual en una posición global.
  Future<void> _showMatchMenuAt(Offset globalPos, Map<String, dynamic> m) {
    return _showMatchMenu(TapDownDetails(globalPosition: globalPos), m);
  }

  /// Centro de la pantalla (fallback si no tenemos posición).
  Offset _centerOfScreen() {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = overlay.size;
    return Offset(size.width / 2, size.height / 2);
  }

  Widget _buildMatchItem(Map<String, dynamic> m) {
    final reps = (m["replacements"] ?? []) as List;
    final subtitle = [
      if ((m["rule"] ?? "").toString().isNotEmpty) "Regla: ${m["rule"]}",
      if (reps.isNotEmpty) "Sugerencias: ${reps.join(", ")}",
    ].where((s) => s.isNotEmpty).join("\n");

    final token = _tokenFromMatch(m);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Guardamos la posición del puntero para long-press
      onTapDown: (d) => _lastTapDownPosition = d.globalPosition,
      // Clic derecho (desktop)
      onSecondaryTapDown: (d) {
        _lastTapDownPosition = d.globalPosition;
        _showMatchMenuAt(d.globalPosition, m);
      },
      // Long press (móvil) sin 'onLongPressStart' en tu SDK
      onLongPress: () {
        final pos = _lastTapDownPosition ?? _centerOfScreen();
        _showMatchMenuAt(pos, m);
      },
      child: ListTile(
        leading: const Icon(Icons.rule, size: 20),
        title: Text(m["message"] ?? ""),
        subtitle: Text(
          token.isEmpty ? subtitle : "$subtitle\nToken: $token",
        ),
        dense: true,
        // Tap normal: mover el cursor a la observación
        onTap: () => _onMatchTap(m),
        trailing: PopupMenuButton<String>(
          tooltip: "Acciones",
          onSelected: (v) async {
            if (v == 'copy') {
              await Clipboard.setData(ClipboardData(text: token));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Copiado: $token")),
              );
            } else if (v == 'addDict') {
              await _addTokenToDictionary(token);
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(
              value: 'copy',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.copy),
                title: Text("Copiar palabra"),
              ),
            ),
            PopupMenuItem(
              value: 'addDict',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.library_add_check),
                title: Text("Agregar al diccionario"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- UI principal -----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editor interactivo"),
        actions: [
          IconButton(
            tooltip: 'Abrir…',
            onPressed: _openFile,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'Re-analizar',
            onPressed: _reanalyzing ? null : _reanalyze,
            icon: _reanalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Guardar como…',
            onPressed: _saveAs,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _textCtrl.text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Texto copiado al portapapeles")),
              );
            },
            tooltip: "Copiar texto",
          ),
          IconButton(
            tooltip: "Terminar y volver",
            onPressed: () => Navigator.pop(context, _textCtrl.text),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Row(
        children: [
          // --------- Editor + botones ---------
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _applying ? null : _applySafe,
                        icon: const Icon(Icons.auto_fix_high),
                        label: Text(_applying ? "Aplicando…" : "Aplicar correcciones SEGURAS"),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _applying ? null : _applyAllLT,
                        icon: const Icon(Icons.build_circle_outlined),
                        label: const Text("Aplicar TODO (LT)"),
                      ),
                      const Spacer(),
                      if (_diff.isNotEmpty)
                        const Icon(Icons.info_outline, size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      scrollPadding: const EdgeInsets.all(120),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      // Menú contextual del editor con "Agregar al diccionario"
                      contextMenuBuilder: (context, editableTextState) {
                        final items = editableTextState.contextMenuButtonItems;
                        final sel = editableTextState.textEditingValue.selection;
                        if (!sel.isCollapsed) {
                          items.add(
                            ContextMenuButtonItem(
                              label: 'Agregar al diccionario',
                              onPressed: () {
                                final txt = editableTextState.textEditingValue.text;
                                final start = sel.start.clamp(0, txt.length);
                                final end = sel.end.clamp(0, txt.length);
                                final token = txt.substring(start, end);
                                // Cierra el menú antes de invocar la acción
                                Navigator.of(context).pop();
                                _addTokenToDictionary(token);
                              },
                            ),
                          );
                        }
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: items,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --------- Panel de observaciones + diff ---------
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Observaciones (${_matches.length})",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.hardEdge,
                      child: _matches.isEmpty
                          ? const Center(
                              child: Text("No hay observaciones. Usa Re-analizar."),
                            )
                          : ListView.separated(
                              itemCount: _matches.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => _buildMatchItem(_matches[i]),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Diff (última operación)",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.hardEdge,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _diff.isEmpty
                              ? "Aún no hay diff. Usa los botones para aplicar cambios."
                              : _diff,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
