import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/state/retry.dart';
import '../../auth/auth_state.dart';
import '../data/arbitros_repository.dart';

final arbitrosRepositoryProvider = Provider<ArbitrosRepository>(
  (ref) => ArbitrosRepository(ref.watch(apiClientProvider)),
);
typedef FiltroArbitros = ({String q, bool soloDisponibles});

final arbitrosProvider = FutureProvider.autoDispose
    .family<List<PerfilArbitro>, FiltroArbitros>((ref, filtro) {
      final auth = ref.watch(authProvider);
      if (!auth.isAuthenticated) return [];
      return ref
          .watch(arbitrosRepositoryProvider)
          .listar(q: filtro.q, soloDisponibles: filtro.soloDisponibles);
    }, retry: sinReintento);

final miPerfilArbitroProvider = FutureProvider.autoDispose<PerfilArbitro?>((
  ref,
) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated || auth.role != AppRole.arbitro) return null;
  return ref.watch(arbitrosRepositoryProvider).miPerfil();
}, retry: sinReintento);
