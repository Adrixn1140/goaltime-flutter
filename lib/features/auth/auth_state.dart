import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'data/auth_repository.dart';

/// Roles del sistema (multi-dueño).
enum AppRole { cliente, dueno, admin }

/// Estado de sesión de la app.
///
/// [restaurando] y [cargando] son distintos a propósito: uno es "todavía no sabemos quién
/// eres" (arranque) y el otro es "estoy mandando tu formulario" (login/registro). El
/// router necesita la primera para no expulsar al usuario al login antes de tiempo, y el
/// formulario necesita la segunda para bloquear el botón (HEUR-1).
class AuthState {
  const AuthState({
    this.isAuthenticated = false,
    this.role,
    this.usuario,
    this.cargando = false,
    this.restaurando = true,
    this.error,
  });

  final bool isAuthenticated;
  final AppRole? role;
  final Usuario? usuario;

  /// Hay una petición de autenticación en vuelo (login, registro o cierre de sesión).
  final bool cargando;

  /// La app está leyendo la sesión guardada. Empieza en `true` y baja a `false` en
  /// cuanto se resuelve, haya sesión o no.
  final bool restaurando;

  final String? error;

  AuthState copyWith({bool? cargando, String? error}) {
    return AuthState(
      isAuthenticated: isAuthenticated,
      role: role,
      usuario: usuario,
      cargando: cargando ?? this.cargando,
      restaurando: restaurando,
      error: error,
    );
  }
}

/// Repositorio de autenticación. Se expone como provider para poder sustituirlo en los
/// tests con un doble que no toque la red.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repo;

  @override
  AuthState build() {
    _repo = ref.watch(authRepositoryProvider);
    // Un 401 en cualquier petición con token significa que la sesión ya no vale: se
    // cierra la sesión local para que el router devuelva al login en vez de dejar al
    // usuario en una pantalla que no va a responder.
    ref.listen<int>(sesionExpiradaProvider, (previous, next) {
      if (previous != null) unawaited(_cerrarSesionPorExpiracion());
    });
    unawaited(_restaurar());
    return const AuthState();
  }

  Future<void> _cerrarSesionPorExpiracion() async {
    debugPrint('La sesión expiró: se borra la sesión local');
    await signOut();
  }

  /// Recupera la sesión guardada al abrir la app. El backend aún no expone "mi perfil",
  /// así que se reconstruye con lo que quedó en el almacenamiento seguro.
  ///
  /// Un fallo al leer (almacenamiento corrupto, error de plataforma) no deja la app
  /// bloqueada en la pantalla de bienvenida: se asume que no hay sesión y se muestra el
  /// login.
  Future<void> _restaurar() async {
    Sesion? sesion;
    try {
      sesion = await _repo.restaurar();
    } catch (error) {
      debugPrint('No se pudo restaurar la sesión: $error');
    }
    if (!ref.mounted) return;
    state = sesion == null
        ? const AuthState(restaurando: false)
        : AuthState(
            isAuthenticated: true,
            role: rolDesdeCodigo(sesion.rol),
            usuario: sesion.usuario,
            restaurando: false,
          );
  }

  /// Inicia sesión. Devuelve `true` si funcionó, para que la pantalla decida si muestra
  /// el error o deja que el router redirija al shell del rol.
  Future<bool> login({required String email, required String password}) {
    return _enviar(() => _repo.login(email: email, password: password));
  }

  /// Registra una cuenta (siempre con rol `cliente`) e inicia sesión con ella.
  Future<bool> register({
    required String nombre,
    required String email,
    required String password,
  }) {
    return _enviar(() => _repo.register(nombre: nombre, email: email, password: password));
  }

  /// Cierra sesión. Aunque el backend no invalide el token, se borra el local para no
  /// dejar al usuario dentro de su propio teléfono (HEUR-3).
  Future<void> signOut() async {
    state = state.copyWith(cargando: true);
    try {
      await _repo.logout();
    } on Object {
      // Si el backend falla, el cierre local se completa igual: es lo que evita dejar al
      // usuario "dentro" con la sesión ya borrada del teléfono.
    } finally {
      state = const AuthState(restaurando: false);
    }
  }

  /// Limpia el mensaje de error (p. ej. al reescribir el formulario).
  void limpiarError() => state = state.copyWith(error: null);

  Future<bool> _enviar(Future<Sesion> Function() accion) async {
    state = state.copyWith(cargando: true);
    try {
      final sesion = await accion();
      if (!ref.mounted) return false;
      state = AuthState(
        isAuthenticated: true,
        role: rolDesdeCodigo(sesion.rol),
        usuario: sesion.usuario,
        restaurando: false,
      );
      return true;
    } catch (error) {
      if (!ref.mounted) return false;
      state = AuthState(restaurando: false, error: mensajeDeError(error));
      return false;
    }
  }
}

/// Traduce una excepción al texto que la pantalla muestra (HEUR-2, HEUR-9).
///
/// [ApiException] ya trae el mensaje redactado por el backend más la siguiente acción
/// sugerida; cualquier otro fallo (error de parseo, de red sin clasificar) cae en un
/// texto genérico en vez de filtrar detalles técnicos al usuario.
String mensajeDeError(Object error) => switch (error) {
  ApiException(:final texto) => texto,
  _ => 'Ocurrió un problema inesperado. Inténtalo de nuevo.',
};

/// Convierte el código de rol del backend en [AppRole].
AppRole rolDesdeCodigo(String? codigo) {
  for (final rol in AppRole.values) {
    if (rol.name == codigo) return rol;
  }
  return AppRole.cliente;
}
