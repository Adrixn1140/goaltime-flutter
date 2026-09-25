import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell del rol Cliente: bottom navigation con las 3 secciones.
///
/// HEUR-6: el usuario reconoce su rol; solo ve las acciones que puede hacer.
class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key, required this.child});

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
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer),
            label: 'Canchas',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Mis reservas',
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
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/cliente/mis-reservas')) return 1;
    if (loc.startsWith('/cliente/perfil')) return 2;
    return 0;
  }

  void _goTo(BuildContext context, int index) {
    switch (index) {
      case 1:
        context.go('/cliente/mis-reservas');
      case 2:
        context.go('/cliente/perfil');
      default:
        context.go('/cliente/canchas');
    }
  }
}