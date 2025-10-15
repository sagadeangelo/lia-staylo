// lib/home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

/// Ajusta aquí tu URL de backend si la cambias
const String kBackendBase = 'http://127.0.0.1:8000';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _statusMsg = 'Sin contenido cargado.';
  String _health = 'Health';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // --------- Acciones ---------

  Future<void> _checkHealth() async {
    setState(() => _busy = true);
    try {
      final resp = await http.get(Uri.parse('$kBackendBase/health'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        setState(() {
          _health = 'OK';
          _statusMsg = 'Health OK: ${body.toString()}';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backend saludable 👍')),
          );
        }
      } else {
        setState(() {
          _health = 'Error';
          _statusMsg = 'Health ${resp.statusCode}: ${resp.body}';
        });
      }
    } catch (e) {
      setState(() {
        _health = 'Error';
        _statusMsg = 'Health fallo: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      // 1) Selector de archivos
      final groups = <XTypeGroup>[
        const XTypeGroup(label: 'Texto', extensions: ['txt', 'md', 'docx']),
      ];
      final XFile? picked = await openFile(acceptedTypeGroups: groups);
      if (picked == null) return; // cancelado

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subiendo: ${picked.name} ...')),
      );

      // 2) Multipart POST a /upload
      final uri = Uri.parse('$kBackendBase/upload');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', picked.path));

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      // 3) Feedback
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        setState(() => _statusMsg = 'OK: ${body.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo subido correctamente ✅')),
        );
      } else {
        setState(() => _statusMsg = 'Error ${resp.statusCode}: ${resp.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${resp.statusCode}: ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMsg = 'Fallo al subir: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fallo: $e')),
      );
    }
  }

  // --------- UI ---------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E2230), // fondo oscuro como tus capturas
      appBar: AppBar(
        backgroundColor: const Color(0xFF146091), // barra azul
        elevation: 0,
        title: const Text('LIA-Staylo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy ? null : _checkHealth,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(_health),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.folder), text: 'Archivo'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Resultados'),
            Tab(icon: Icon(Icons.auto_fix_high), text: 'Sugerencias'),
            Tab(icon: Icon(Icons.menu_book), text: 'Diccionario'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildArchivoTab(theme),
          _placeholder('Resultados'),
          _placeholder('Sugerencias'),
          _placeholder('Diccionario'),
        ],
      ),
      bottomNavigationBar: Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0B1C28),
          border: Border(
            top: BorderSide(color: Colors.white10, width: 1),
          ),
        ),
        child: const Text(
          'Aquí conectarás con tu flujo de subida',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildArchivoTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _LangChip(text: 'Español (México)', selected: true),
              _LangChip(text: 'Español (Latino)'),
              _LangChip(text: 'Inglés (US)'),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Subir y analizar manuscrito'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF176FA6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              onPressed: _busy ? null : _pickAndUploadFile,
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Formatos soportados: .txt, .md, .docx',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Backend: $kBackendBase',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: Text(
                _statusMsg,
                style: const TextStyle(color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(String title) {
    return Center(
      child: Text(
        '$title (en construcción)',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String text;
  final bool selected;
  const _LangChip({required this.text, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(text),
      selected: selected,
      onSelected: (_) {},
      selectedColor: const Color(0xFF1E88C7),
      backgroundColor: const Color(0xFF0F2C3D),
      labelStyle: const TextStyle(color: Colors.white),
      showCheckmark: false,
      side: const BorderSide(color: Colors.white24),
    );
  }
}
