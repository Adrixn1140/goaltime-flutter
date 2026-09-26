import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cliente/presentation/perfil_screen.dart';
import '../state/gestion_provider.dart';

/// Shell del rol Dueño: sus canchas y su perfil.
///
/// El dueño tiene menos secciones que el cliente y una tarea muy concreta —cargar horarios
/// y atender reservas—, así que la navegación es de dos destinos en vez de un menú con
/// entradas que no aplican a este rol (HEUR-3, HEUR-6).
class DuenoShell extends StatelessWidget {
  const DuenoShell({super.key, required this.child});

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
            label: 'Mis canchas',
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

  int _indexFor(BuildContext context) =>
      GoRouterState.of(context).uri.path.startsWith('/dueno/perfil') ? 1 : 0;

  void _goTo(BuildContext context, int index) {
    context.go(index == 1 ? '/dueno/perfil' : '/dueno/canchas');
  }
}

/// Perfil del dueño: la misma pantalla que la del cliente, con la limpieza que le
/// corresponde a este rol.
///
/// Los datos y el cierre de sesión son los mismos, pero las listas que hay que invalidar
/// no: el dueño deja canchas, horarios y reservas en memoria, y sin invalidarlos el
/// próximo usuario que entre en este teléfono vería las canchas de otro.
class PerfilDuenoScreen extends ConsumerWidget {
  const PerfilDuenoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PerfilScreen(
      alSalir: () async {
        ref.invalidate(canchasGestionProvider);
        ref.invalidate(horariosProvider);
        ref.invalidate(reservasCanchaProvider);
      },
    );
  }
}
