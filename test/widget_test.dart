import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presence_scolaire/main.dart';

void main() {
  testWidgets('dashboard opens in French and navigation shows claims', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Yasmine 👋'), findsOneWidget);
    expect(find.text('Taux de présence'), findsOneWidget);

    await tester.tap(find.text('Réclamations').first);
    await tester.pumpAndSettle();

    expect(find.text('Mes réclamations'), findsOneWidget);
    expect(find.text('Contester une absence'), findsNothing);

    await tester.tap(find.byTooltip('Changer de profil démo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enseignant').last);
    await tester.pumpAndSettle();

    expect(find.text('Espace enseignant'), findsOneWidget);
    expect(find.text('Validations'), findsOneWidget);

    await tester.tap(find.text('Validations'));
    await tester.pumpAndSettle();
    expect(find.text('Validation des présences'), findsOneWidget);

    await tester.tap(find.byTooltip('Valider la présence').first);
    await tester.pumpAndSettle();
    expect(find.text('La présence a été validée.'), findsOneWidget);
  });
}
