// lib/upload_tester.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const _backend = 'http://127.0.0.1:8000'; // ajusta si cambias host/puerto

class UploadTester extends StatefulWidget {
  const UploadTester({super.key});
  @override
  State<UploadTester> createState() => _UploadTesterState();
}

class _UploadTesterState extends State<UploadTester> {
  bool _busy = false;
  String _log = 'Listo.';

  Future<void> _selectAndUpload() async {
    setState(() { _busy = true; _log = 'Abriendo selector…'; });

    try {
      final group = XTypeGroup(
        label: 'Manuscritos',
        extensions: ['txt','md','doc','docx','pdf','rtf','epub'],
      );

      final XFile? picked = await openFile(
        acceptedTypeGroups: [group],
        confirmButtonText: 'Seleccionar',
      );
      if (picked == null) {
        setState(() { _busy = false; _log = 'Cancelado por el usuario.'; });
        return;
      }

      final path = picked.path;
      if (!File(path).existsSync()) {
        throw Exception('El archivo no existe: $path');
      }

      setState(() { _log = 'Subiendo ${p.basename(path)}…'; });

      final uri = Uri.parse('$_backend/upload');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: p.basename(path)));

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      final text = 'STATUS: ${resp.statusCode}\nBODY:\n${resp.body}';
      setState(() { _log = text; });

      // Mensaje visual
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(resp.statusCode == 200 ? 'Subida OK' : 'Error ${resp.statusCode}'),
          content: SingleChildScrollView(child: Text(resp.body)),
          actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')) ],
        ),
      );
    } catch (e, st) {
      setState(() { _log = 'Fallo: $e\n$st'; });
    } finally {
      setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _selectAndUpload,
              icon: const Icon(Icons.cloud_upload),
              label: Text(_busy ? 'Subiendo…' : 'Seleccionar y subir archivo'),
            ),
            const SizedBox(height: 12),
            const Text('Log:'),
            const SizedBox(height: 6),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(child: SelectableText(_log)),
            ),
          ],
        ),
      ),
    );
  }
}
