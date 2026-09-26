import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cliente/presentation/canchas_screen.dart';
import '../../features/cliente/presentation/cliente_shell.dart';
import '../../features/cliente/presentation/mis_reservas_screen.dart';
import '../../features/cliente/presentation/perfil_screen.dart';
import '../../features/cliente/presentation/reserva_screen.dart';
import '../../features/gestion/presentation/dueno_shell.dart';
import '../../features/gestion/presentation/gestion_canchas_screen.dart';
import '../../features/gestion/presentation/horarios_screen.dart';
import '../../features/gestion/presentation/reservas_cancha_screen.dart';
import '../../features/usuarios/presentation/admin_shell.dart';
import '../../features/usuarios/presentation/usuarios_screen.dart';
import 'splash_screen.dart';

/// Proveedor del [GoRouter] de la app. Los redirects dependen del rol.
///
/// `App` llama a `router.refresh()` cuando cambia la sesión (ver `app.dart`): sin eso,
/// iniciar sesión dentro de la pantalla de login dejaría al usuario ahí, con el
/// formulario ya enviado.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.matchedLocation;

      // Mientras se lee el almacenamiento seguro no se sabe todavía si hay sesión. Mandar
      // a /login en ese instante sacaría al usuario de la app y lo haría volver a entrar
      // en cada arranque: se espera en la pantalla de bienvenida (HEUR-1).
      if (auth.restaurando) return path == '/' ? null : '/';

      if (!auth.isAuthenticated) {
        return path == '/login' ? null : '/login';
      }

      if (path == '/' || path == '/login') {
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
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
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
            path: '/cliente/canchas/:id/reserva',
            builder: (context, state) =>
                PantallaReserva(canchaId: int.parse(state.pathParameters['id']!)),
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
          GoRoute(
            path: '/dueno/canchas/:id/horarios',
            builder: (context, state) =>
                HorariosScreen(canchaId: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: '/dueno/canchas/:id/reservas',
            builder: (context, state) =>
                ReservasCanchaScreen(canchaId: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: '/dueno/perfil',
            builder: (context, state) => const PerfilDuenoScreen(),
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
