import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goaltime_flutter/core/app.dart';

void main() {
  testWidgets('La app arranca y muestra la pantalla de login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.text('GoalTime'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}