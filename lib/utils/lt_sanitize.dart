/// Sanitizador defensivo para cualquier bloque de texto
/// que aún se pinte “en crudo” en alguna vista antigua.
/// - Convierte "{value: X}" -> "X"
/// - Elimina líneas "Token: value" y "Fragmento: {value}"
/// - Limpia comas duplicadas y saltos múltiples
class LtSanitize {
  static final _valueWrapper = RegExp(
    r'\{?\s*value\s*:\s*([^{}]+?)\s*\}?',
    caseSensitive: false,
  );

  static final _tokenValueLine = RegExp(
    r'(?m)^(Token\s*:)\s*(?:value|\{?\s*value\s*:\s*[^}]*\}?)\s*$',
    caseSensitive: false,
  );

  static final _fragmentValueLine = RegExp(
    r'(?m)^(Fragmento\s*:)\s*(?:value|\{?\s*value\s*:\s*[^}]*\}?)\s*$',
    caseSensitive: false,
  );

  static String clean(String raw) {
    var s = raw;

    // 1) Reemplaza {value: X} por X
    s = s.replaceAllMapped(_valueWrapper, (m) => m.group(1)!.trim());

    // 2) Borra líneas problemáticas "Token: value" / "Fragmento: {value}"
    s = s.replaceAll(_tokenValueLine, '');
    s = s.replaceAll(_fragmentValueLine, '');

    // 3) Limpia "Sugerencias: , ..." y comas duplicadas
    s = s.replaceAll(RegExp(r'Sugerencias:\s*,\s*'), 'Sugerencias: ');
    s = s.replaceAll(RegExp(r'\s*,\s*,+'), ', ');

    // 4) Colapsa líneas en blanco repetidas
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return s;
  }
}
