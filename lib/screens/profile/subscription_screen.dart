import 'package:flutter/material.dart';

import '../credits/my_credits_screen.dart';

/// ANCIEN écran « Mon abonnement » — supprimé avec la grille tarifaire v5.
///
/// EduCorrect fonctionne en pay-as-you-go (packs de crédits CinetPay, sans
/// abonnement). Ce widget n'est plus référencé dans l'app ; il redirige vers
/// « Mes crédits » au cas où un ancien lien y mènerait encore. Le fichier
/// peut être supprimé.
@Deprecated('Utiliser MyCreditsScreen (pay-as-you-go, grille v5)')
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => const MyCreditsScreen();
}
