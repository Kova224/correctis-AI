/// Feature flags globaux de l'application.
///
/// Mode pratique pour activer/désactiver des fonctionnalités sans toucher au
/// code métier. Toute modification d'un flag ici doit faire l'objet d'un
/// nouveau build (les flags sont compilés en const).
library;

/// REMPLACÉ — l'ancien freemium "3 corrections gratuites" est remplacé par
/// le pack Découverte (3 copies à vie par compte) attribué automatiquement
/// au signup via un trigger SQL.
///
/// Le nouveau système : à l'inscription, un trigger Postgres attribue 3
/// crédits Découverte (lot expirant à J+30). L'app utilise désormais
/// `CreditsService.reserveCredit()` qui se base sur le wallet réel.
///
/// Ces deux flags sont laissés à `false` pour ne pas casser les écrans qui
/// les référencent encore (la condition `if (kFreemiumEnabled)` court-circuite
/// l'ancienne logique). Ils seront supprimés au Sprint 5.
const bool kFreemiumEnabled = false;
const int kFreemiumLimit = 3;
