import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lia_staylo/app_state.dart';

/// Lanza el flujo: muestra el sheet de progreso y arranca la subida+análisis.
Future<void> showUploadAndAnalyze(BuildContext context) async {
  final app = context.read<AppState>();

  // Abrimos el sheet primero para que el usuario vea el progreso desde el inicio.
  // Lo cerramos desde AppState cuando termine o haya error.
  // ignore: unawaited_futures
  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF0B2A4A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _UploadSheet(),
  );

  // Arranca el flujo en segundo plano.
  // Si AppState ya maneja la selección del archivo, esto solo la dispara.
  // Cualquier excepción se maneja dentro de AppState para no cerrar el sheet abruptamente.
  // ignore: unawaited_futures
  app.pickUploadAndAnalyze(context);
}

class _UploadSheet extends StatelessWidget {
  const _UploadSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Consumer<AppState>(
          builder: (_, app, __) {
            final pct = (app.uploadProgress.clamp(0.0, 1.0) * 100).round();
            final busy = app.isUploading;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_upload, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Subiendo y analizando…',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (!busy)
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: busy ? app.uploadProgress : 1,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.uploadStage.isEmpty ? 'Preparando…' : app.uploadStage,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    Text('$pct%', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
