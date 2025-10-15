import 'package:flutter/material.dart';
import 'app_shell.dart'; // Asegúrate de que la ruta sea correcta

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si en el futuro quieres cargar idioma/baseUrl antes de arrancar la app,
  // este es el lugar (p.ej. await LIAStayloAPI.initSavedLang();).
  runApp(const LIAStayloApp());
}

class LIAStayloApp extends StatelessWidget {
  const LIAStayloApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3D8CD1); // Azul LIA-Staylo

    return MaterialApp(
      title: 'LIA-Staylo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1220),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) {
        // Mejora la experiencia de scroll en desktop (sin glow azul)
        return ScrollConfiguration(
          behavior: const _NoGlowScrollBehavior(),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // sin efecto de overscroll
  }
}
