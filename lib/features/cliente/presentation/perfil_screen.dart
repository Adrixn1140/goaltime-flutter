import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Perfil del usuario.
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      title: 'Perfil',
      message: 'Datos del perfil y cierre de sesión (Fase 3).',
    );
  }
}