import 'package:flutter/material.dart';
import '../theme/lia_theme.dart';
import 'lia_staylo_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // Header con gradiente azul
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [LIATheme.brandBlue, LIATheme.brandBlueDark],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.edit, size: 28, color: Colors.white),
                    const SizedBox(width: 12),
                    Text('LIA-Staylo',
                        style: tt.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        )),
                  ]),
                  const SizedBox(height: 16),
                  Text(
                    'Asistente de estilo y ortografía',
                    style: tt.bodyLarge?.copyWith(
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Cuerpo
          Expanded(
            child: Container(
              width: double.infinity,
              color: LIATheme.surfaceDark,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login),
                            label: const Text('Entrar'),
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const LIAStayloScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.tune),
                            label: const Text('Avanzado'),
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '© 2025 LIA-Staylo',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
