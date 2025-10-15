import 'package:flutter/foundation.dart';

/// Estructura normalizada para un match de LanguageTool.
class LtMatchDetails {
  final String message;            // texto visible del match (arriba)
  final String? token;             // token real (desde context offset/length)
  final String? fragment;          // context.text
  final List<String> suggestions;  // sin {value: ...}, deduplicadas
  final String? ruleId;            // opcional
  final String? cause;             // opcional

  const LtMatchDetails({
    required this.message,
    this.token,
    this.fragment,
    this.suggestions = const [],
    this.ruleId,
    this.cause,
  });
}

/// Utilidades para limpiar/parsear matches de LT.
abstract final class LtFormat {
  static final RegExp _reValueWrapper = RegExp(
    r'^\s*\{?\s*value\s*:\s*(.*?)\s*\}?\s*$',
    caseSensitive: false,
  );

  static bool _looksLiteralValue(String s) {
    final x = s.trim().toLowerCase();
    if (x == 'value' || x == '{value}' || x == 'valor') return true;
    if (RegExp(r'^\s*\{?\s*value\s*:', caseSensitive: false).hasMatch(x)) {
      return true;
    }
    return false;
  }

  static String _stripAccents(String s) {
    const from = 'áéíóúüÁÉÍÓÚÜñÑ';
    const to   = 'aeiouuAEIOUUnN';
    final buf = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      buf.write(i >= 0 ? to[i] : c);
    }
    return buf.toString();
  }

  /// Normaliza un replacement que puede venir como Map {value:…} o String "{value: …}".
  static String normalizeReplacement(dynamic r) {
    if (r is Map && r['value'] != null) {
      return r['value'].toString().trim();
    }
    final s = r?.toString().trim() ?? '';
    final m = _reValueWrapper.firstMatch(s);
    return (m != null ? m.group(1)! : s).trim();
  }

  /// Devuelve un LtMatchDetails **limpio** a partir del JSON del match de LT.
  static LtMatchDetails fromRaw({
    required Map<String, dynamic> match,
    required String message,
  }) {
    // --- suggestions ---
    final sug = <String>[];
    final repl = match['replacements'];
    if (repl is List) {
      for (final r in repl) {
        final v = normalizeReplacement(r);
        if (v.isNotEmpty) sug.add(v);
      }
    }
    // dedup insensible a acentos/mayúsculas
    final seen = <String>{};
    final dedup = <String>[];
    for (final s in sug) {
      final key = _stripAccents(s).toLowerCase();
      if (seen.add(key)) dedup.add(s);
    }

    // --- fragment & token desde context ---
    String? fragment;
    String? token;
    final ctx = match['context'];
    if (ctx is Map) {
      final text = (ctx['text'] ?? '').toString();
      fragment = text.isEmpty ? null : text;
      final off = (ctx['offset'] as num?)?.toInt() ?? 0;
      final len = (ctx['length'] as num?)?.toInt() ?? 0;
      if (text.isNotEmpty && len > 0 && off >= 0 && off + len <= text.length) {
        token = text.substring(off, off + len);
      }
    }

    // --- fallbacks seguros ---
    String? _safe(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    // Si no hay token por context, intenta con matchedText primero.
    if (token == null || _looksLiteralValue(token)) {
      final mt = _safe(match['matchedText']);
      if (mt != null && !_looksLiteralValue(mt)) {
        token = mt;
      }
    }
    // Últimos recursos: word/token del payload (pero nunca aceptes “value”)
    if (token == null || _looksLiteralValue(token)) {
      final w = _safe(match['word']);
      if (w != null && !_looksLiteralValue(w)) token = w;
    }
    if (token == null || _looksLiteralValue(token)) {
      final t = _safe(match['token']);
      if (t != null && !_looksLiteralValue(t)) token = t;
    }
    // Si aún así no hay token fiable, mejor vacío (no lo imprimiremos)
    if (token == null || _looksLiteralValue(token)) token = '';

    // metas opcionales
    final ruleId = match['rule'] is Map ? (match['rule']['id']?.toString()) : match['ruleId']?.toString();
    final cause  = match['issueType']?.toString();

    return LtMatchDetails(
      message: message,
      token: token,
      fragment: fragment,
      suggestions: dedup,
      ruleId: ruleId,
      cause: cause,
    );
  }

  /// Construye un String “clásico” para pantallas que siguen usando texto plano.
  static String buildDetailsText(LtMatchDetails d) {
    bool _skip(String? s) =>
        s == null || s.trim().isEmpty || _looksLiteralValue(s ?? '');

    final b = StringBuffer();
    if (!_skip(d.cause)) {
      b.writeln('Causa: ${d.cause}');
    }
    if (!_skip(d.ruleId)) {
      b.writeln('Regla: ${d.ruleId}');
    }
    if (!_skip(d.token)) {
      b.writeln('Token: ${d.token}');
    }
    if (d.suggestions.isNotEmpty) {
      // puedes limitar a .take(12) si quieres
      b.writeln('Sugerencias: ${d.suggestions.join(', ')}');
    }
    if (!_skip(d.fragment)) {
      b.writeln('Fragmento: ${d.fragment}');
    }
    return b.toString().trimRight();
  }
}
