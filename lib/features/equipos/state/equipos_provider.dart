import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/state/retry.dart';
import '../../auth/auth_state.dart';
import '../data/equipos_repository.dart';

final equiposRepositoryProvider = Provider<EquiposRepository>(
  (ref) => EquiposRepository(ref.watch(apiClientProvider)),
);

// No conservar plantillas personales entre sesiones ni al abandonar la sección.
final equiposProvider = FutureProvider.autoDispose<List<Equipo>>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated || auth.role != AppRole.cliente) return [];
  return ref.watch(equiposRepositoryProvider).listar();
}, retry: sinReintento);

final equipoProvider = FutureProvider.autoDispose.family<Equipo, int>((
  ref,
  id,
) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated || auth.role != AppRole.cliente) {
    throw StateError('Se requiere sesión de cliente');
  }
  return ref.watch(equiposRepositoryProvider).detalle(id);
}, retry: sinReintento);
