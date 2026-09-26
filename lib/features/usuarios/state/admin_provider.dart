import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/state/retry.dart';
import '../data/admin_repository.dart';
import '../data/models.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Usuarios de la plataforma, con rol, estado y conteos.
///
/// Igual que las canchas del dueño, cada cambio vuelve a pedir la lista completa en vez
/// de parchear la fila: son pocas y el backend es la única fuente de la verdad. El
/// detalle que aquí importa es que el cambio de rol puede ser rechazado con un `422` que
/// explica qué hacer antes, y ese error tiene que llegar a la pantalla.
class UsuariosAdminNotifier extends AsyncNotifier<List<UsuarioAdmin>> {
  @override
  Future<List<UsuarioAdmin>> build() => ref.watch(adminRepositoryProvider).listarUsuarios();

  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  /// Cambia el rol y/o el estado activo de un usuario.
  ///
  /// Un rechazo del backend (el admin no se toca a sí mismo, o el dueño tiene canchas
  /// activas) sube como excepción con el mensaje tal cual, y la lista se refresca igual:
  /// si el cambio sí llegó a aplicarse, la fila tiene que reflejarlo.
  Future<UsuarioAdmin> cambiar(int usuarioId, {RolUsuario? rol, bool? activo}) async {
    final actualizado = await ref
        .read(adminRepositoryProvider)
        .cambiarRol(usuarioId, rol: rol, activo: activo);
    unawaited(_recargarEnSegundoPlano());
    return actualizado;
  }

  Future<void> _recargarEnSegundoPlano() async {
    try {
      await recargar();
    } on Object catch (error, pila) {
      debugPrint('No se pudo refrescar la lista de usuarios: $error');
      debugPrintStack(stackTrace: pila, maxFrames: 4);
    }
  }
}

final usuariosAdminProvider =
    AsyncNotifierProvider<UsuariosAdminNotifier, List<UsuarioAdmin>>(
      UsuariosAdminNotifier.new,
      retry: sinReintento,
    );

/// Reporte agregado. Es un `FutureProvider` y no un notifier porque nadie lo muta desde
/// la app: se vuelve a pedir con "deslizar para actualizar" o al invalidarlo tras un
/// cambio de rol, que puede alterar los conteos por rol.
final reporteProvider = FutureProvider<ReporteAdmin>(
  (ref) => ref.watch(adminRepositoryProvider).reporte(),
  retry: sinReintento,
);
