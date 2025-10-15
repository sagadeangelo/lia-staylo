// lib/screens/suggestions_screen.dart
import 'package:flutter/material.dart';
import '../services/lia_staylo_api.dart';

class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final _inCtrl = TextEditingController();
  final _outCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Precarga automática desde el último análisis
    final last = LIAStayloAPI.lastAnalyzedText;
    if ((last ?? '').trim().isNotEmpty) {
      _inCtrl.text = last!;
    }
  }

  @override
  void dispose() {
    _inCtrl.dispose();
    _outCtrl.dispose();
    super.dispose();
  }

  Future<void> _improve() async {
    final raw = _inCtrl.text.trim();
    if (raw.isEmpty) {
      _snack('Pega un párrafo o selecciona uno desde Resultados.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Primero, “fix” ortografía/espacios básicos en backend
      final fixed = await LIAStayloAPI.applySafe(raw, lang: LIAStayloAPI.currentLang);
      final safeText = (fixed['new_text'] ?? raw).toString().trim().isEmpty
          ? raw
          : (fixed['new_text'] as String);

      // Luego, reescritura ligera (sugerencia)
      final sug = await LIAStayloAPI.suggestText(safeText, lang: LIAStayloAPI.currentLang);
      _outCtrl.text = sug;
    } catch (e) {
      _snack('No se pudo generar sugerencia: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sugerencias')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Card(
              title: 'Pega aquí un párrafo para mejorar',
              child: TextField(
                controller: _inCtrl,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'Pega aquí un párrafo para mejorar',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _improve,
                icon: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Mejorar con IA'),
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'La reescritura aparecerá aquí.',
              child: TextField(
                controller: _outCtrl,
                readOnly: true,
                maxLines: 12,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
