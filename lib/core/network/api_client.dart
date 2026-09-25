import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

/// Proveedor del almacenamiento seguro de sesión.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const TokenStorage();
});

/// Cliente HTTP base (dio) con interceptor de JWT.
final apiClientProvider = Provider<Dio>((ref) {
  final storage = ref.watch(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(AuthInterceptor(storage));
  return dio;
});