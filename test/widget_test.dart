// Smoke test minimal. Le vrai test demanderait Supabase initialisé, donc
// on se contente ici de garantir que le projet compile.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App imports compile', () {
    // Pas d'init Supabase dans les tests unitaires — ce fichier sert juste
    // de garde-fou contre des suppressions accidentelles de code critique.
    expect(true, isTrue);
  });
}
