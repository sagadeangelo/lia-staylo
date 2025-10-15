// lib/app_shell.dart
import 'package:flutter/material.dart';
import 'screens/lia_staylo_screen.dart'; // importa la pantalla raíz correcta

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    // ¡Sin const! LIAStayloScreen no es const.
    return LIAStayloScreen();
  }
}
