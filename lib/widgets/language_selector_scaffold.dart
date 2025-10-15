import 'package:flutter/material.dart';
import 'language_selector_header.dart';

/// Contenedor que muestra el header de idioma arriba del contenido.
class LanguageSelectorScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const LanguageSelectorScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LanguageSelectorHeader(title: title),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}
