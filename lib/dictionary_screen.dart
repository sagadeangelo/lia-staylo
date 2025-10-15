import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchDictionary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B2A4A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Agregar palabra al diccionario',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: 'Escribe una palabra',
                    hintStyle: const TextStyle(color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      app.dictionaryAdd(v.trim());
                      _ctrl.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = _ctrl.text.trim();
                  if (v.isNotEmpty) {
                    app.dictionaryAdd(v);
                    _ctrl.clear();
                  }
                },
                child: const Text('Agregar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: app.dictionaryWords.isEmpty
              ? const Center(
                  child: Text('Aún no hay palabras.', style: TextStyle(color: Colors.white70)),
                )
              : ListView.separated(
                  itemCount: app.dictionaryWords.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (_, i) {
                    final w = app.dictionaryWords[i];
                    return ListTile(
                      title: Text(w, style: const TextStyle(color: Colors.white)),
                      trailing: IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => app.removeFromDictionary(w),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
