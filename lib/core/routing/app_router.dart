import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cliente/presentation/canchas_screen.dart';
import '../../features/cliente/presentation/cliente_shell.dart';
import '../../features/cliente/presentation/mis_reservas_screen.dart';
import '../../features/cliente/presentation/perfil_screen.dart';
import '../../features/gestion/presentation/dueno_shell.dart';
import '../../features/gestion/presentation/gestion_canchas_screen.dart';
import '../../features/usuarios/presentation/admin_shell.dart';
import '../../features/usuarios/presentation/usuarios_screen.dart';

/// Proveedor del [GoRouter] de la app. Los redirects dependen del rol.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.matchedLocation;

      if (!auth.isAuthenticated) {
        return path == '/login' ? null : '/login';
      }

      if (path == '/login') {
        return _homeFor(auth.role);
      }

      // Evita navegar a un shell de otro rol.
      final home = _homeFor(auth.role);
      if (path.startsWith('/cliente') && auth.role != AppRole.cliente) {
        return home;
      }
      if (path.startsWith('/dueno') && auth.role != AppRole.dueno) {
        return home;
      }
      if (path.startsWith('/admin') && auth.role != AppRole.admin) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ClienteShell(child: child),
        routes: [
          GoRoute(
            path: '/cliente/canchas',
            builder: (context, state) => const CanchasScreen(),
          ),
          GoRoute(
            path: '/cliente/mis-reservas',
            builder: (context, state) => const MisReservasScreen(),
          ),
          GoRoute(
            path: '/cliente/perfil',
            builder: (context, state) => const PerfilScreen(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => DuenoShell(child: child),
        routes: [
          GoRoute(
            path: '/dueno/canchas',
            builder: (context, state) => const GestionCanchasScreen(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin/usuarios',
            builder: (context, state) => const UsuariosScreen(),
          ),
        ],
      ),
    ],
  );
});

String _homeFor(AppRole? role) => switch (role) {
      AppRole.dueno => '/dueno/canchas',
      AppRole.admin => '/admin/usuarios',
      AppRole.cliente || null => '/cliente/canchas',
    };