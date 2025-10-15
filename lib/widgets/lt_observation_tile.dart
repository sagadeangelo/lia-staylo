import 'package:flutter/material.dart';

class LtObservationTile extends StatelessWidget {
  const LtObservationTile({
    super.key,
    required this.cls,        // 'grammar' | 'space' | 'style' | 'spelling'
    required this.message,    // texto de la observación
    required this.match,      // payload de LanguageTool para ese match
  });

  final String cls;
  final String message;
  final Map<String, dynamic> match;

  static const cream = Color(0xFFFFE9A8);
  static const _creamBg = Color(0x33FFE9A8);
  static const _labelRadius = 8.0;

  TextStyle _valueStyle(BuildContext ctx) =>
      Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            height: 1.35,
            color: Theme.of(ctx).colorScheme.onSurface,
          ) ??
      const TextStyle(fontSize: 13, height: 1.35);

  TextStyle get _labelTextStyle =>
      const TextStyle(color: cream, fontWeight: FontWeight.w800, fontSize: 12.5);

  BoxDecoration get _labelDecoration => BoxDecoration(
        color: _creamBg,
        borderRadius: BorderRadius.circular(_labelRadius),
        border: Border.all(color: cream.withAlpha(140), width: 0.6),
      );

  @override
  Widget build(BuildContext context) {
    final det = _extractDetails(match);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _classIcon(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if ((det.token ?? '').trim().isNotEmpty)
                _richLine(context, label: 'Token', value: det.token!.trim()),
              if (det.suggestions.isNotEmpty)
                _richLine(context, label: 'Sugerencias', value: det.suggestions.join(', ')),
              if ((det.fragment ?? '').trim().isNotEmpty)
                _richLine(context, label: 'Fragmento', value: det.fragment!.trim()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classIcon() {
    switch (cls) {
      case 'spelling': return const Icon(Icons.spellcheck, color: Colors.orange);
      case 'space':    return const Icon(Icons.more_horiz, color: Colors.blueGrey);
      case 'style':    return const Icon(Icons.brush_outlined, color: Colors.purple);
      default:         return const Icon(Icons.rule_folder_outlined, color: Colors.teal);
    }
  }

  Widget _richLine(BuildContext ctx, {required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText.rich(
        TextSpan(
          style: _valueStyle(ctx),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: _labelDecoration,
                child: Text(label, style: _labelTextStyle),
              ),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  // -------- parsing y limpieza --------

  static _MatchDetails _extractDetails(Map<String, dynamic> m) {
    // Replacements normalizados
    final reps = <String>[];
    final repl = m['replacements'];
    if (repl is List) {
      for (final r in repl) {
        String v;
        if (r is Map && r['value'] != null) {
          v = r['value'].toString().trim();
        } else {
          final s = r?.toString().trim() ?? '';
          final mm = RegExp(r'^\s*\{?\s*value\s*:\s*(.*?)\s*\}?\s*$',
                  caseSensitive: false)
              .firstMatch(s);
          v = (mm != null ? mm.group(1)! : s).trim();
        }
        if (v.isNotEmpty) reps.add(v);
      }
    }
    // dedup
    final seen = <String>{};
    final dedup = <String>[];
    for (final s in reps) {
      final key = _stripAccents(s).toLowerCase();
      if (seen.add(key)) dedup.add(s);
    }

    // Fragmento y token confiables
    String? fragment;
    String? token;
    final ctx = m['context'];
    if (ctx is Map) {
      final text = (ctx['text'] ?? '').toString();
      fragment = text.isEmpty ? null : text;
      final off = (ctx['offset'] as num?)?.toInt() ?? 0;
      final len = (ctx['length'] as num?)?.toInt() ?? 0;
      if (text.isNotEmpty && len > 0 && off >= 0 && off + len <= text.length) {
        token = text.substring(off, off + len);
      }
    }
    String? _safe(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }
    bool _looksValue(String s) {
      final x = s.trim().toLowerCase();
      if (x == 'value' || x == '{value}' || x == 'valor') return true;
      if (RegExp(r'^\s*\{?\s*value\s*:', caseSensitive: false).hasMatch(x)) return true;
      return false;
    }
    token ??= _safe(m['matchedText']);
    token ??= _safe(m['word']);
    token ??= _safe(m['token']);
    if (token != null && _looksValue(token!)) token = null;

    // Filtra sugerencias cercanas al token
    final filtered = _filterSuggestions(token, dedup, max: 12);
    return _MatchDetails(token: token, suggestions: filtered, fragment: fragment);
  }

  static List<String> _filterSuggestions(String? token, List<String> items, {int max = 12}) {
    if (items.length <= max) return items;
    final base = _stripAccents(token ?? '').toLowerCase();
    final scored = <(String, int)>[];
    for (final s in items) {
      final x = _stripAccents(s).toLowerCase();
      final lenDelta = (x.length - base.length).abs();
      final score = (base.isEmpty || x.contains(base) || base.contains(x)) ? 0 : lenDelta;
      scored.add((s, score));
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return scored.take(max).map((e) => e.$1).toList();
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
}

class _MatchDetails {
  final String? token;
  final List<String> suggestions;
  final String? fragment;
  const _MatchDetails({this.token, this.suggestions = const [], this.fragment});
}
