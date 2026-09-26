import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/state/retry.dart';
import '../data/gestion_repository.dart';
import '../data/models.dart';

final gestionRepositoryProvider = Provider<GestionRepository>(
  (ref) => GestionRepository(ref.watch(apiClientProvider)),
);

/// Canchas del dueño, con su estado y su número de horarios.
///
/// Cada cambio (crear, editar, dar de baja) vuelve a pedir la lista en vez de parchear el
/// estado local: son pocas canchas y el backend es la única fuente de la verdad. El error
/// de una mutación sí sube a la pantalla —que muestra el mensaje del backend—, y la lista
/// se refresca igual para que no quede a medias si el cambio sí llegó a aplicarse.
class CanchasGestionNotifier extends AsyncNotifier<List<CanchaGestion>> {
  @override
  Future<List<CanchaGestion>> build() => ref.watch(gestionRepositoryProvider).listarCanchas();

  /// Recarga esperando a terminar, para que "deslizar para actualizar" no quite el
  /// indicador antes de tener los datos nuevos.
  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  Future<CanchaGestion> crear({required String nombre, required String ubicacion}) async {
    final creada = await ref
        .read(gestionRepositoryProvider)
        .crearCancha(nombre: nombre, ubicacion: ubicacion);
    unawaited(_recargarEnSegundoPlano());
    return creada;
  }

  Future<CanchaGestion> editar(
    int canchaId, {
    String? nombre,
    String? ubicacion,
    bool? activo,
  }) async {
    final editada = await ref.read(gestionRepositoryProvider).actualizarCancha(
      canchaId,
      nombre: nombre,
      ubicacion: ubicacion,
      activo: activo,
    );
    unawaited(_recargarEnSegundoPlano());
    return editada;
  }

  /// Da de baja una cancha con `DELETE`, que en el backend es baja lógica: responde `204`
  /// y la cancha sigue existiendo, con sus horarios y sus reservas.
  Future<void> bajar(int canchaId) async {
    await ref.read(gestionRepositoryProvider).bajarCancha(canchaId);
    unawaited(_recargarEnSegundoPlano());
  }

  /// Reactiva una cancha. No hay `DELETE` inverso en el contrato, así que es un `PATCH`
  /// con `activo: true`.
  Future<void> reactivar(int canchaId) async {
    await ref.read(gestionRepositoryProvider).actualizarCancha(canchaId, activo: true);
    unawaited(_recargarEnSegundoPlano());
  }

  Future<void> _recargarEnSegundoPlano() async {
    try {
      await recargar();
    } on Object catch (error) {
      debugPrint('No se pudo refrescar la lista de canchas: $error');
    }
  }
}

final canchasGestionProvider = AsyncNotifierProvider<CanchasGestionNotifier, List<CanchaGestion>>(
  CanchasGestionNotifier.new,
  retry: sinReintento,
);

/// Horarios de una cancha. El id entra por el constructor: en Riverpod 3 el `family` se
/// declara como `HorariosNotifier.new` y la factoría se lo pasa al notifier.
class HorariosNotifier extends AsyncNotifier<List<HorarioCancha>> {
  HorariosNotifier(this.canchaId);

  final int canchaId;

  @override
  Future<List<HorarioCancha>> build() =>
      ref.watch(gestionRepositoryProvider).listarHorarios(canchaId);

  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  Future<HorarioCancha> crear({
    required int dia,
    required String horaInicio,
    required String horaFin,
    required double tarifa,
  }) async {
    final creado = await ref.read(gestionRepositoryProvider).crearHorario(
      canchaId,
      dia: dia,
      horaInicio: horaInicio,
      horaFin: horaFin,
      tarifa: tarifa,
    );
    unawaited(_recargarEnSegundoPlano());
    return creado;
  }

  Future<HorarioCancha> editar(
    int horarioId, {
    int? dia,
    String? horaInicio,
    String? horaFin,
    double? tarifa,
  }) async {
    // El backend no deja cambiar día ni hora de un horario con reservas, y sí la tarifa
    // (`409` en el primer caso). La app no intenta adivinar si ese horario tiene
    // reservas —no tiene el dato—: manda el cambio y muestra el mensaje tal cual, que ya
    // explica qué se puede y qué no.
    final editado = await ref.read(gestionRepositoryProvider).actualizarHorario(
      canchaId,
      horarioId,
      dia: dia,
      horaInicio: horaInicio,
      horaFin: horaFin,
      tarifa: tarifa,
    );
    unawaited(_recargarEnSegundoPlano());
    return editado;
  }

  Future<void> borrar(int horarioId) async {
    await ref.read(gestionRepositoryProvider).borrarHorario(canchaId, horarioId);
    unawaited(_recargarEnSegundoPlano());
  }

  Future<void> _recargarEnSegundoPlano() async {
    try {
      await recargar();
    } on Object catch (error) {
      debugPrint('No se pudo refrescar la lista de horarios: $error');
    }
  }
}

final horariosProvider = AsyncNotifierProvider.family<HorariosNotifier, List<HorarioCancha>, int>(
  HorariosNotifier.new,
  retry: sinReintento,
);

/// Reservas de una cancha vista por el dueño.
class ReservasCanchaNotifier extends AsyncNotifier<List<ReservaGestion>> {
  ReservasCanchaNotifier(this.canchaId);

  final int canchaId;

  @override
  Future<List<ReservaGestion>> build() =>
      ref.watch(gestionRepositoryProvider).listarReservas(canchaId);

  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  /// Confirma o cancela una reserva y devuelve el estado que quedó.
  ///
  /// El `422` del backend (la reserva ya no está en el estado que permite la acción) se
  /// deja subir a la pantalla, que refresca la lista y muestra el mensaje: el dueño
  /// necesita ver el estado real, no un error genérico.
  Future<ReservaGestion> cambiarEstado(int reservaId, String accion) async {
    final actualizada = await ref
        .read(gestionRepositoryProvider)
        .cambiarEstadoReserva(reservaId, accion);
    unawaited(_recargarEnSegundoPlano());
    return actualizada;
  }

  Future<void> _recargarEnSegundoPlano() async {
    try {
      await recargar();
    } on Object catch (error) {
      debugPrint('No se pudo refrescar la lista de reservas: $error');
    }
  }
}

final reservasCanchaProvider =
    AsyncNotifierProvider.family<ReservasCanchaNotifier, List<ReservaGestion>, int>(
      ReservasCanchaNotifier.new,
      retry: sinReintento,
    );
