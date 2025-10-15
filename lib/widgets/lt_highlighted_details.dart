import 'package:flutter/material.dart';

/// Muestra un bloque de detalles (texto plano) resaltando las etiquetas
/// Regla / Causa / Token / Sugerencias / Fragmento como “chips” amarillo crema.
class LtHighlightedDetails extends StatelessWidget {
  const LtHighlightedDetails({
    super.key,
    required this.text,
    this.fontSize = 13,
    this.lineHeight = 1.35,
  });

  final String text;
  final double fontSize;
  final double lineHeight;

  static const _cream = Color(0xFFFFE9A8);
  static const _creamBg = Color(0x33FFE9A8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(
          fontSize: fontSize,
          height: lineHeight,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(fontSize: fontSize, height: lineHeight);

    final spans = _buildSpans(text);

    return SelectableText.rich(TextSpan(style: base, children: spans));
  }

  List<InlineSpan> _buildSpans(String raw) {
    final pattern = RegExp(
      r'(Regla:|Causa:|Token:|Sugerencias:|Fragmento:|Rule:|Cause:|Suggestions:|Fragment:)',
      caseSensitive: true,
    );

    final spans = <InlineSpan>[];
    var last = 0;

    for (final m in pattern.allMatches(raw)) {
      if (m.start > last) {
        spans.add(TextSpan(text: raw.substring(last, m.start)));
      }
      final label = m.group(0)!;

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        child: Container(
          margin: const EdgeInsets.only(right: 6, top: 1, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _creamBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cream.withAlpha(140), width: 0.6),
          ),
          child: Text(
            label.replaceAll(':', ''),
            style: const TextStyle(
              color: _cream,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ));
      spans.add(const TextSpan(text: ' '));
      last = m.end;
    }

    if (last < raw.length) {
      spans.add(TextSpan(text: raw.substring(last)));
    }

    return spans;
  }
}
