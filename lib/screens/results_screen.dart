// lib/screens/results_screen.dart
import 'package:flutter/material.dart';

import '../services/lia_staylo_api.dart';
import '../utils/lt_format.dart';
import '../utils/lt_sanitize.dart';
import '../widgets/lt_highlighted_details.dart';

class ResultsScreen extends StatelessWidget {
  /// Texto plano del manuscrito analizado (se muestra a la izquierda).
  final String analyzedText;

  /// Respuesta JSON completa devuelta por el backend para este texto.
  final Map<String, dynamic> analysis;

  const ResultsScreen({
    Key? key,
    required this.analyzedText,
    required this.analysis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Guarda el último texto para que Sugerencias pueda precargarlo.
    LIAStayloAPI.setLastAnalyzedText(analyzedText);

    // Resumen de conteos (grammar / space / style / spelling / all)
    final counts = LIAStayloAPI.countsFromAnalysis(analysis);

    // Matches clasificados (para el panel derecho)
    final matches = LIAStayloAPI.classifyMatchesFromAnalysis(analysis);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados'),
        actions: [
          IconButton(
            tooltip: 'Abrir Sugerencias',
            icon: const Icon(Icons.tips_and_updates_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/suggestions'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SummaryCounts(counts: counts),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  // Izquierda: texto analizado
                  Expanded(
                    flex: 3,
                    child: _Card(
                      title: 'Texto analizado',
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          analyzedText,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Derecha: observaciones (matches)
                  Expanded(
                    flex: 2,
                    child: _Card(
                      title: 'Observaciones',
                      child: matches.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text('No hay observaciones de LanguageTool o no coinciden con el filtro.'),
                            )
                          : ListView.separated(
                              itemCount: matches.length,
                              padding: const EdgeInsets.all(8),
                              separatorBuilder: (_, __) =>
                                  Divider(height: 16, color: Theme.of(context).dividerColor),
                              itemBuilder: (context, i) {
                                final m = matches[i] as Map<String, dynamic>;
                                final cls = (m['lt_clientClass'] ?? '').toString();
                                final msg = (m['message'] ?? '').toString();

                                // 1) Normaliza: token real (no "value"), fragmento y sugerencias limpias.
                                final det = LtFormat.fromRaw(match: m, message: msg);

                                // 2) Texto con etiquetas
                                var detailsText = LtFormat.buildDetailsText(det);

                                // 3) Defensa extra por si algún flujo residual sigue colando "{value: ...}"
                                detailsText = LtSanitize.clean(detailsText);

                                // 4) Render con etiquetas en crema
                                return _ObservationRow(
                                  cls: cls,
                                  header: msg,
                                  detailsText: detailsText,
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Mejorar con IA'),
                onPressed: () => Navigator.of(context).pushNamed('/suggestions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con chips de resumen
class _SummaryCounts extends StatelessWidget {
  final Map<String, int> counts;
  const _SummaryCounts({required this.counts});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _pill(context, 'Todos', counts['all'] ?? 0),
      _pill(context, 'Gramática', counts['grammar'] ?? 0),
      _pill(context, 'Puntuación/Espacios', counts['space'] ?? 0),
      _pill(context, 'Estilo', counts['style'] ?? 0),
      _pill(context, 'Ortografía', counts['spelling'] ?? 0),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _pill(BuildContext context, String label, int n) {
    return Chip(
      label: Text('$label: $n'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      side: BorderSide(color: Theme.of(context).dividerColor),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

/// Ítem de observación (icono por clase + mensaje + detalles resaltados)
class _ObservationRow extends StatelessWidget {
  final String cls;          // 'grammar' | 'space' | 'style' | 'spelling'
  final String header;       // mensaje de la regla
  final String detailsText;  // texto con Regla/Causa/Token/Sugerencias/Fragmento

  const _ObservationRow({
    required this.cls,
    required this.header,
    required this.detailsText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _classIcon(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(header, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              LtHighlightedDetails(text: detailsText),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classIcon() {
    switch (cls) {
      case 'spelling':
        return const Icon(Icons.spellcheck, color: Colors.orange);
      case 'space':
        return const Icon(Icons.more_horiz, color: Colors.blueGrey);
      case 'style':
        return const Icon(Icons.brush_outlined, color: Colors.purple);
      default:
        return const Icon(Icons.rule_folder_outlined, color: Colors.teal);
    }
  }
}

/// Contenedor tipo tarjeta
class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceTint.withOpacity(.06),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
