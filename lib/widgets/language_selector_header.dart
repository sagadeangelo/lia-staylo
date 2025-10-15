// lib/widgets/language_selector_header.dart

import 'package:flutter/material.dart';
import '../services/lia_staylo_api.dart';

class LanguageSelectorHeader extends StatefulWidget {
  final EdgeInsetsGeometry padding;
  final VoidCallback? onChanged;

  const LanguageSelectorHeader({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.onChanged,
  });

  @override
  State<LanguageSelectorHeader> createState() => _LanguageSelectorHeaderState();
}

class _LanguageSelectorHeaderState extends State<LanguageSelectorHeader> {
  /// 'es-mx' | 'es-latam' | 'en-US'
  late String _choice;

  @override
  void initState() {
    super.initState();
    final cl = LIAStayloAPI.currentLang.toLowerCase();
    if (cl.startsWith('en')) {
      _choice = 'en-US';
    } else if (cl.contains('419')) {
      _choice = 'es-latam';
    } else {
      _choice = 'es-mx';
    }
  }

  Future<void> _selectSpanishMx() async {
    setState(() => _choice = 'es-mx');
    await LIAStayloAPI.setDefaultLang('es-MX'); // se guarda y se usa tal cual
    widget.onChanged?.call();
  }

  Future<void> _selectSpanishLatam() async {
    setState(() => _choice = 'es-latam');
    await LIAStayloAPI.setDefaultLang('es-419');
    widget.onChanged?.call();
  }

  Future<void> _selectEnglish() async {
    setState(() => _choice = 'en-US');
    await LIAStayloAPI.setDefaultLang('en-US');
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isEsMx = _choice == 'es-mx';
    final isEsLatam = _choice == 'es-latam';
    final isEn = _choice == 'en-US';

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Elige el idioma antes de subir tu manuscrito", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text("Español (México)"),
                selected: isEsMx,
                onSelected: (_) => _selectSpanishMx(),
                avatar: const Icon(Icons.flag, size: 16),
              ),
              ChoiceChip(
                label: const Text("Español (Latino)"),
                selected: isEsLatam,
                onSelected: (_) => _selectSpanishLatam(),
                avatar: const Icon(Icons.translate, size: 16),
              ),
              ChoiceChip(
                label: const Text("Inglés (US)"),
                selected: isEn,
                onSelected: (_) => _selectEnglish(),
                avatar: const Icon(Icons.language, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Se aplicarán reglas y diccionario del idioma seleccionado (es-MX / es-419 / en-US).",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
