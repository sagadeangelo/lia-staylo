// lib/utils/lia_project.dart
import 'dart:convert';

class LIAProject {
  final String version;
  final String kind; // "text" (en esta iteración)
  final String lang; // 'es' | 'en-US'
  final String? backend;
  final String text;

  /// Resultado del último análisis (opcional). Si está vacío, al cargar se re-analiza.
  final Map<String, dynamic>? analysis;

  /// Conjunto de claves seleccionadas (rule@offset:length)
  final Set<String> selectedKeys;

  /// Reemplazo elegido manualmente por clave
  final Map<String, String> chosenReplacement;

  LIAProject({
    required this.version,
    required this.kind,
    required this.lang,
    required this.text,
    required this.selectedKeys,
    required this.chosenReplacement,
    this.backend,
    this.analysis,
  });

  Map<String, dynamic> toJson() => {
        "version": version,
        "kind": kind,
        "lang": lang,
        "backend": backend,
        "text": text,
        "analysis": analysis,
        "ui": {
          "selectedKeys": selectedKeys.toList(),
          "chosenReplacement": chosenReplacement,
        },
      };

  static LIAProject fromJson(Map<String, dynamic> j) {
    final ui = (j["ui"] as Map?) ?? {};
    final sel = <String>{};
    final selList = ui["selectedKeys"];
    if (selList is List) {
      sel.addAll(selList.map((e) => e.toString()));
    }
    final chosen = <String, String>{};
    final cr = ui["chosenReplacement"];
    if (cr is Map) {
      cr.forEach((k, v) => chosen[k.toString()] = (v ?? "").toString());
    }
    return LIAProject(
      version: (j["version"] ?? "1").toString(),
      kind: (j["kind"] ?? "text").toString(),
      lang: (j["lang"] ?? "es").toString(),
      backend: j["backend"]?.toString(),
      text: (j["text"] ?? "").toString(),
      analysis: (j["analysis"] is Map<String, dynamic>)
          ? (j["analysis"] as Map<String, dynamic>)
          : null,
      selectedKeys: sel,
      chosenReplacement: chosen,
    );
  }

  static String encodePretty(LIAProject p) {
    final encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(p.toJson());
  }

  static LIAProject fromString(String raw) =>
      LIAProject.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
