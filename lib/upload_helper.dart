// lib/upload_helper.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

Future<void> uploadManuscript(BuildContext context) async {
  try {
    final typeGroups = <XTypeGroup>[
      const XTypeGroup(label: 'Texto', extensions: ['txt', 'md', 'docx']),
    ];
    final XFile? picked = await openFile(acceptedTypeGroups: typeGroups);

    if (picked == null) return; // cancelado por el usuario

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subiendo manuscrito...')),
      );
    }

    final uri = Uri.parse('http://127.0.0.1:8000/upload');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', picked.path));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OK: ${body.toString()}')),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ${resp.statusCode}: ${resp.body}')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fallo: $e')),
      );
    }
  }
}
