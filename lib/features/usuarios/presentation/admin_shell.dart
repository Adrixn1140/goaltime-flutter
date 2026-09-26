import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cliente/presentation/perfil_screen.dart';
import '../state/admin_provider.dart';

/// Shell del rol Admin: usuarios, reporte y perfil.
///
/// El admin tiene tres destinos y ninguno es decorativo: cada uno es una tarea distinta
/// —dar de alta dueño, ver el dinero, cerrar sesión—, así que van en la barra inferior en
/// vez de menú (HEUR-3, HEUR-6).
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexFor(context),
        onDestinationSelected: (i) => _goTo(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Usuarios',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Reporte',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  int _indexFor(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/admin/reporte')) return 1;
    if (path.startsWith('/admin/perfil')) return 2;
    return 0;
  }

  void _goTo(BuildContext context, int index) {
    context.go(switch (index) {
      1 => '/admin/reporte',
      2 => '/admin/perfil',
      _ => '/admin/usuarios',
    });
  }
}

/// Perfil del admin: los mismos datos y el mismo cierre de sesión que los otros roles,
/// más la limpieza de lo que el panel dejó en memoria: la lista de usuarios y el reporte
/// son de la plataforma entera, y verlos tras cerrar sesión sería verlos sin ser admin.
class PerfilAdminScreen extends ConsumerWidget {
  const PerfilAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PerfilScreen(
      alSalir: () async {
        ref.invalidate(usuariosAdminProvider);
        ref.invalidate(reporteProvider);
      },
    );
  }
}
