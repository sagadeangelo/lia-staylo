import 'package:flutter/material.dart';

/// Resalta los prefijos "Token", "Sugerencias" y "Fragmento" dentro de un texto.
class LabelHighlight extends StatelessWidget {
  const LabelHighlight(
    this.text, {
    super.key,
    this.fontSize = 13,
    this.lineHeight = 1.35,
  });

  final String text;
  final double fontSize;
  final double lineHeight;

  // Amarillo crema que contraste en tema oscuro
  static const _creamYellow = Color(0xFFFFE29A);
  static const _labelStyle = TextStyle(
    color: _creamYellow,
    fontWeight: FontWeight.w700,
  );
  static const _valueStyle = TextStyle(
    color: Color(0xFFDDE3EA),
    fontWeight: FontWeight.w400,
  );

  // Coincide con: Token: / Sugerencias: / Fragmento:
  static final _labelRegex =
      RegExp(r'(Token|Sugerencias|Fragmento)\s*:\s*', multiLine: true);

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final matches = _labelRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      return Text(text, style: TextStyle(fontSize: fontSize, height: lineHeight));
    }

    int cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, m.start),
          style: _valueStyle,
        ));
      }
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: _labelStyle));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: _valueStyle));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: fontSize, height: lineHeight),
        children: spans,
      ),
    );
  }
}
