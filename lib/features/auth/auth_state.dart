import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Roles del sistema (multi-dueño).
enum AppRole { cliente, dueno, admin }

/// Estado de sesión de la app.
class AuthState {
  const AuthState({this.isAuthenticated = false, this.role});

  final bool isAuthenticated;
  final AppRole? role;

  AuthState copyWith({bool? isAuthenticated, AppRole? role}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      role: role ?? this.role,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  /// Inicia sesión a partir del rol devuelto por el backend.
  void signIn(String role) {
    AppRole? parsed;
    for (final r in AppRole.values) {
      if (r.name == role) parsed = r;
    }
    state = AuthState(
      isAuthenticated: true,
      role: parsed ?? AppRole.cliente,
    );
  }

  void signOut() => state = const AuthState();
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);