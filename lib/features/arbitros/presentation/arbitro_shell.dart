import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ArbitroShell extends StatelessWidget {
  const ArbitroShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final ruta = GoRouterState.of(context).uri.path;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: ruta.endsWith('/directorio')
            ? 1
            : ruta.endsWith('/cuenta')
            ? 2
            : 0,
        onDestinationSelected: (i) => context.go(
          ['/arbitro/perfil', '/arbitro/directorio', '/arbitro/cuenta'][i],
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_outlined),
            label: 'Mi perfil arbitral',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Árbitros'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Mi cuenta',
          ),
        ],
      ),
    );
  }
}
