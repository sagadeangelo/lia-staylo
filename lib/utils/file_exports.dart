import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart'; // para apiBase y AppState

String _ensureBaseDir() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
  final docs = Platform.isWindows ? Directory('$home\\Documents') : Directory('$home/Documents');
  final root = docs.existsSync() ? docs.path : home;
  final base = Platform.isWindows ? '$root\\LIA-Staylo' : '$root/LIA-Staylo';
  Directory(base).createSync(recursive: true);
  return base;
}

String _stamp() => DateTime.now().toIso8601String().replaceAll(':', '-');

Future<void> saveProjectAsLia(BuildContext ctx, AppState app) async {
  try {
    final dir = _ensureBaseDir();
    final path = Platform.isWindows
        ? '$dir\\proyecto-${_stamp()}.lia'
        : '$dir/proyecto-${_stamp()}.lia';

    final bytes = utf8.encode(jsonEncode({
      'lang': app.currentLang,
      'text': app.currentText,
      'result': app.result,
    }));

    final xf = XFile.fromData(bytes, name: 'proyecto.lia', mimeType: 'application/json');
    await xf.saveTo(path);

    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Proyecto guardado en:\n$path')));
  } catch (e) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('No se pudo guardar (.lia): $e')));
  }
}

Future<void> exportPlainText(BuildContext ctx, AppState app) async {
  try {
    final dir = _ensureBaseDir();
    final path = Platform.isWindows
        ? '$dir\\texto-${_stamp()}.txt'
        : '$dir/texto-${_stamp()}.txt';

    final xf = XFile.fromData(
      utf8.encode(app.currentText),
      name: 'texto.txt',
      mimeType: 'text/plain',
    );
    await xf.saveTo(path);

    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('TXT exportado en:\n$path')));
  } catch (e) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('No se pudo exportar .txt: $e')));
  }
}

Future<void> exportDocxFromText(BuildContext ctx, AppState app) async {
  try {
    // Pedimos el DOCX al backend para no depender de paquetes extra en Flutter
    final r = await http.post(
      Uri.parse('$apiBase/export/docx'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': app.currentText, 'lang': app.currentLang}),
    );

    if (r.statusCode != 200) {
      throw Exception('Backend respondió ${r.statusCode}: ${r.reasonPhrase ?? r.body}');
    }

    final dir = _ensureBaseDir();
    final path = Platform.isWindows
        ? '$dir\\texto-${_stamp()}.docx'
        : '$dir/texto-${_stamp()}.docx';

    final xf = XFile.fromData(
      r.bodyBytes,
      name: 'texto.docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    await xf.saveTo(path);

    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('DOCX exportado en:\n$path')));
  } catch (e) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('No se pudo exportar .docx: $e')));
  }
}
