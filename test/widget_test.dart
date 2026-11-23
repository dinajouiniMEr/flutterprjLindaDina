import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presence_scolaire/main.dart';

void main() {
  testWidgets('app starts in demo mode without Supabase', (tester) async {
    await tester.pumpWidget(const AttendanceApp(supabaseEnabled: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bonjour Dina Jouini'), findsOneWidget);
    expect(find.text('Mon emploi du temps'), findsOneWidget);
  });

  testWidgets('dashboard opens in French and navigation shows claims', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Dina Jouini 👋'), findsOneWidget);
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
    expect(find.text('Mme Linda Wadaa'), findsWidgets);

    await tester.tap(find.text('Validations'));
    await tester.pumpAndSettle();
    expect(find.text('Validation des présences'), findsOneWidget);
    expect(find.text('Dina Jouini'), findsOneWidget);

    await tester.tap(find.byTooltip('Valider la présence').first);
    await tester.pumpAndSettle();
    expect(find.text('La présence a été validée.'), findsOneWidget);
  });

  testWidgets('search filters sessions, claims and attendance', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('search_field'));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'Réseaux');
    await tester.pumpAndSettle();
    expect(find.text('Réseaux informatiques'), findsWidgets);
    expect(find.text('Algorithmique avancée'), findsNothing);
    expect(find.text('Bases de données'), findsNothing);
    expect(find.text('Développement mobile'), findsNothing);

    await tester.tap(find.byTooltip('Effacer la recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Algorithmique avancée'), findsWidgets);

    await tester.enterText(field, 'Linda');
    await tester.pumpAndSettle();
    expect(find.text('Algorithmique avancée'), findsWidgets);
    expect(find.text('Bases de données'), findsWidgets);

    await tester.enterText(field, 'Salle B12');
    await tester.pumpAndSettle();
    expect(find.text('Algorithmique avancée'), findsWidgets);
    expect(find.text('Réseaux informatiques'), findsNothing);
  });

  testWidgets('student can declare attendance and submit a claim', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Actions sur la séance').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Déclarer ma présence'));
    await tester.pumpAndSettle();
    expect(
      find.text('Votre présence a été déclarée à l’enseignant.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Nouvelle réclamation').first);
    await tester.pumpAndSettle();
    expect(find.text('Contester une absence'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Détails de la réclamation'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Expliquez votre demande',
      ),
      'Retard du bus',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.text('Votre réclamation a été transmise.'), findsOneWidget);

    await tester.tap(find.text('Réclamations').first);
    await tester.pumpAndSettle();
    expect(find.text('Retard du bus'), findsOneWidget);
  });

  testWidgets('teacher can accept a claim', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Changer de profil démo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enseignant').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Réclamations').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accepter').first);
    await tester.pumpAndSettle();

    expect(find.text('La réclamation a été acceptée.'), findsOneWidget);
    expect(find.text('Acceptée'), findsWidgets);
  });

  testWidgets('search shows an empty state when nothing matches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('search_field')), 'inexistant');
    await tester.pumpAndSettle();

    expect(find.text('Aucune séance à afficher'), findsOneWidget);
    expect(find.text('Aucune déclaration'), findsNothing);
  });

  testWidgets('demo mode AI asks for a key and a PDF', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Actions sur la séance').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Résumé IA du cours'));
    await tester.pumpAndSettle();

    expect(
      find.text('Clé Google AI Studio (gratuite)'),
      findsOneWidget,
    );
    expect(find.text('Choisir un PDF'), findsOneWidget);
    expect(find.text('Aucun PDF sélectionné'), findsOneWidget);
  });

  testWidgets('mobile layout exposes the search field', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardGate()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search_field')), findsNothing);
    await tester.tap(find.byTooltip('Rechercher'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search_field')), 'Bases');
    await tester.pumpAndSettle();
    expect(find.text('Bases de données'), findsWidgets);
    expect(find.text('Algorithmique avancée'), findsNothing);

    await tester.tap(find.byTooltip('Masquer la recherche'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search_field')), findsNothing);
  });
}
