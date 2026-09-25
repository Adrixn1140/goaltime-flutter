import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth_state.dart';

/// Inicio de sesión y registro (`POST /api/login`, `POST /api/registro`).
///
/// Un solo formulario con dos modos en vez de dos pantallas: son los mismos campos, y el
/// usuario que se equivocó de botón no tiene que volver atrás a corregirlo.
///
/// HEUR-5: los requisitos de contraseña se muestran **antes** de enviar, porque
/// descubrir un "mínimo 8 caracteres" cuando el servidor responde `422` obliga a
/// recordarlos y volver a escribir la contraseña.
/// HEUR-1: el botón se bloquea y muestra progreso mientras se envía.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registro = false;
  bool _verPassword = false;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    // El router mueve al shell del rol en cuanto hay sesión, así que aquí lo único que
    // se dibuja es el error (HEUR-2: el mensaje del backend, ya redactado en español).
    ref.listen<AuthState>(authProvider, (previous, next) {
      final error = next.error;
      if (error == null || error == previous?.error) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error)));
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.sports_soccer, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('GoalTime', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Reserva tu cancha sintética',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 32),
                  if (_registro) ...[
                    TextFormField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: _validaNombre,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: _validaEmail,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: !_verPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => auth.cargando ? null : _enviar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      helperText: _registro ? 'Mínimo 8 caracteres' : null,
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: _verPassword ? 'Ocultar contraseña' : 'Ver contraseña',
                        icon: Icon(_verPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _verPassword = !_verPassword),
                      ),
                    ),
                    validator: _validaPassword,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: auth.cargando ? null : _enviar,
                    child: auth.cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_registro ? 'Crear cuenta' : 'Iniciar sesión'),
                  ),
                  TextButton(
                    onPressed: auth.cargando
                        ? null
                        : () {
                            ref.read(authProvider.notifier).limpiarError();
                            setState(() => _registro = !_registro);
                          },
                    child: Text(_registro
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Regístrate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(authProvider.notifier);
    if (_registro) {
      await notifier.register(
        nombre: _nombre.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } else {
      await notifier.login(email: _email.text.trim(), password: _password.text);
    }
  }

  String? _validaNombre(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.length < 3) return 'Escribe tu nombre completo';
    return null;
  }

  String? _validaEmail(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return 'Escribe tu correo';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(texto)) {
      return 'Ese correo no parece válido';
    }
    return null;
  }

  String? _validaPassword(String? valor) {
    final texto = valor ?? '';
    if (texto.isEmpty) return 'Escribe tu contraseña';
    if (_registro && texto.length < 8) return 'La contraseña necesita al menos 8 caracteres';
    return null;
  }
}
