import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../upload_service.dart';

/// Botón que abre el diálogo de archivos (Windows) y sube el archivo al backend.
class UploadButton extends StatefulWidget {
  const UploadButton({
    super.key,
    this.label = 'Subir y analizar manuscrito',
    this.backendBaseUrl = 'http://127.0.0.1:8000',
    this.onDone,
  });

  final String label;
  final String backendBaseUrl;

  /// Callback opcional con el resultado del servidor.
  final void Function(UploadResult result)? onDone;

  @override
  State<UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<UploadButton> {
  bool _busy = false;

  Future<void> _pickAndUpload() async {
    try {
      setState(() => _busy = true);

      // Filtros: .txt, .md, .docx
      final typeGroup = XTypeGroup(
        label: 'Manuscrito',
        extensions: ['txt', 'md', 'docx'],
      );

      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Operación cancelada.')));
        }
        return;
      }

      final path = file.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo obtener la ruta del archivo.')),
          );
        }
        return;
      }

      final service = UploadService(baseUrl: widget.backendBaseUrl);
      final result = await service.uploadFile(File(path));

      if (mounted) {
        if (result.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Subida OK: ${result.message}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fallo: ${result.message}')),
          );
        }
      }

      widget.onDone?.call(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excepción: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _pickAndUpload,
      icon: const Icon(Icons.cloud_upload),
      label: Text(widget.label),
    );
  }
}
