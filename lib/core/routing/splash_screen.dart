import 'package:flutter/material.dart';

/// Pantalla de bienvenida mientras se lee la sesión guardada.
///
/// Existe para que el arranque no parpadee entre "cargando" y "login" cuando el usuario
/// sí tenía sesión: es la misma espera que ve en cuanto abre cualquier otra app (HEUR-1).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            const SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
