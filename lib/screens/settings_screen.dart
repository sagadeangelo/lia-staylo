import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lia_staylo_api.dart';
import '../widgets/language_selector_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _prefsLangKey = 'lia_lang';

  String _lang = 'es-MX';
  String _healthMsg = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _lang = sp.getString(_prefsLangKey) ?? 'es-MX';
    });
  }

  Future<void> _saveLang(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsLangKey, value);
    setState(() => _lang = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Idioma guardado: $value')),
    );
  }

  Future<void> _runHealth() async {
    setState(() => _healthMsg = 'Verificando…');
    try {
      final h = await LIAStayloAPI.health();
      setState(() => _healthMsg = 'OK: $h');
    } catch (e) {
      setState(() => _healthMsg = 'Error: $e');
    }
  }

  Future<void> _clearPrefs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsLangKey);
    setState(() => _lang = 'es-MX');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preferencias restablecidas')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Backend actual',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SelectableText(
            LIAStayloAPI.baseUrl,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 16),

          // Selector de idioma (usa SharedPreferences directamente)
          Text(
            'Idioma de análisis por defecto',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          LanguageSelectorHeader(
            value: _lang,
            onChanged: (v) => _saveLang(v),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _runHealth,
            icon: const Icon(Icons.health_and_safety),
            label: const Text('Probar health del backend'),
          ),
          if (_healthMsg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_healthMsg),
          ],

          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _clearPrefs,
            icon: const Icon(Icons.restore),
            label: const Text('Restablecer preferencias'),
          ),
        ],
      ),
    );
  }
}
