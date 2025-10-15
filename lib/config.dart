// lib/config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kReleaseMode;

class AppConfig {
  static String apiBase() {
    // En producción, cambia por tu dominio HTTPS cuando lo tengas
    const prod = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8000');

    if (kReleaseMode) return prod;

    if (Platform.isAndroid) return 'http://10.0.2.2:8000'; // emulador Android
    return 'http://127.0.0.1:8000'; // desktop / iOS simulator
  }

  static Map<String, String> defaultHeaders({String? variant}) => {
    // Si usas variante de UI desde el backend:
    if (variant != null) 'X-Lang-Var': variant, // 'es-MX', 'es-419', 'en-US'
    'Content-Type': 'application/json',
  };
}
