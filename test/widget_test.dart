// =============================================================================
// NOTITIA PoC - Widget Test
// Test de base pour vérifier que l'application se lance correctement
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:notitia/main.dart';

void main() {
  testWidgets('Notitia app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NotitiaApp());
    await tester.pumpAndSettle();

    // Vérification de la marque
    expect(find.text('NOTITIA'), findsOneWidget);

    // Vérification de la barre de navigation
    expect(find.text('CAPTURE'), findsOneWidget);
    expect(find.text('HISTORIQUE'), findsOneWidget);
    expect(find.text('RECHERCHE'), findsOneWidget);
  });
}
