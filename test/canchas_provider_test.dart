import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/features/cliente/data/canchas_repository.dart';
import 'package:goaltime_flutter/features/cliente/data/models.dart';
import 'package:goaltime_flutter/features/cliente/state/canchas_provider.dart';

class _RepositorioControlado extends CanchasRepository {
  _RepositorioControlado() : super(Dio());

  int llamadas = 0;
  Completer<List<Cancha>>? pendiente;

  @override
  Future<List<Cancha>> listar() {
    llamadas++;
    return pendiente?.future ?? Future.value(<Cancha>[]);
  }
}

void main() {
  late _RepositorioControlado repo;
  late ProviderContainer container;

  setUp(() {
    repo = _RepositorioControlado();
    container = ProviderContainer(
      overrides: [canchasRepositoryProvider.overrideWithValue(repo)],
    );
  });
  tearDown(() => container.dispose());

  test('actualizaciones simultáneas comparten una sola petición', () async {
    await container.read(canchasProvider.future);
    repo.pendiente = Completer<List<Cancha>>();
    final notifier = container.read(canchasProvider.notifier);

    final primera = notifier.recargar();
    final segunda = notifier.recargar();
    expect(identical(primera, segunda), isTrue);
    expect(repo.llamadas, 2); // Carga inicial + una sola actualización.

    repo.pendiente!.complete(<Cancha>[]);
    await Future.wait([primera, segunda]);
    expect(container.read(canchasProvider).hasValue, isTrue);

    repo.pendiente = null;
    await notifier.recargar();
    expect(repo.llamadas, 3);
  });

  test('un error libera la petición y permite reintentar', () async {
    await container.read(canchasProvider.future);
    repo.pendiente = Completer<List<Cancha>>();
    final notifier = container.read(canchasProvider.notifier);
    final actualizacion = notifier.recargar();
    repo.pendiente!.completeError(Exception('Fallo de prueba'));
    await actualizacion;
    expect(container.read(canchasProvider).hasError, isTrue);

    repo.pendiente = null;
    await notifier.recargar();
    expect(repo.llamadas, 3);
    expect(container.read(canchasProvider).hasValue, isTrue);
  });

  test('invalidar el catálogo descarta una respuesta antigua', () async {
    await container.read(canchasProvider.future);
    final anterior = Completer<List<Cancha>>();
    repo.pendiente = anterior;
    final actualizacion = container.read(canchasProvider.notifier).recargar();

    repo.pendiente = null;
    container.invalidate(canchasProvider);
    await container.read(canchasProvider.future);
    anterior.completeError(Exception('Error de una petición antigua'));
    await actualizacion;
    expect(container.read(canchasProvider).hasValue, isTrue);
    expect(container.read(canchasProvider).hasError, isFalse);
  });
}
