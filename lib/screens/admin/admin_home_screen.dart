import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'admin_analytics_body.dart';
import 'admin_casier_body.dart';
import 'admin_credits_screen.dart';
import 'admin_dashboard_body.dart';
import 'admin_notifications_screen.dart';
import 'admin_settings_body.dart';
import 'admin_teachers_body.dart';
import 'admin_widgets.dart';

/// AdminHomeScreen — wrapper avec bottom nav violet et IndexedStack.
///
/// Selon la maquette V2, l'admin a 5 onglets :
///   📊 Dashboard · 👥 Profs · ✦ FAB (invite) · 🗂️ Casier · ⚙️ Paramètres
///
/// + écrans pushable : Analytics (depuis Dashboard alerte) et Recherche élève.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.4,
            colors: [Color(0xFF120A2E), AppColors.voidBg],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header — back vers Vue Prof + badge "ADMIN" + bouton de
              // bascule rapide vers la vue prof (utile car un admin peut
              // aussi enseigner / créer des examens).
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop())
                      AdminBackButton(
                        onTap: () => Navigator.maybePop(context),
                      ),
                    const Spacer(),
                    // Pill "Vue Prof" pour basculer (texte court)
                    if (Navigator.of(context).canPop())
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Material(
                          color: AppColors.profPrimary
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            onTap: () => Navigator.maybePop(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 12,
                                    color: AppColors.profPrimary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'VUE PROF',
                                    style: AppFonts.mono(
                                      fontSize: 9,
                                      color: AppColors.profPrimary,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Bouton "Crédits" — accès rapide au pool établissement
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Material(
                        color: AppColors.adminPrimary
                            .withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminCreditsScreen(),
                            ),
                          ),
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 16,
                              color: AppColors.adminPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Cloche notifications admin (compose / liste envois)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Material(
                        color: AppColors.adminPrimary
                            .withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AdminNotificationsScreen(),
                            ),
                          ),
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.notifications_outlined,
                              size: 16,
                              color: AppColors.adminPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppColors.adminGradient,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ADMIN',
                            style: AppFonts.mono(
                              fontSize: 9,
                              color: Colors.white,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body switch
              Expanded(
                child: IndexedStack(
                  index: _currentTab,
                  children: const [
                    AdminDashboardBody(),
                    AdminTeachersBody(),
                    SizedBox.shrink(), // FAB — placeholder
                    AdminCasierBody(),
                    AdminAnalyticsBody(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ━━━━━━ BOTTOM NAV ADMIN (violet) ━━━━━━
      bottomNavigationBar: _AdminBottomNav(
        currentIndex: _currentTab,
        onTap: (i) {
          if (i == 2) {
            // FAB central → Settings (raccourci)
            _openSettings();
            return;
          }
          setState(() => _currentTab = i);
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _AdminSettingsScreen(),
      ),
    );
  }
}

/// Wrapper Scaffold pour les Settings (poussé depuis FAB central).
class _AdminSettingsScreen extends StatelessWidget {
  const _AdminSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.4,
            colors: [Color(0xFF120A2E), AppColors.voidBg],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    AdminBackButton(
                        onTap: () => Navigator.maybePop(context)),
                  ],
                ),
              ),
              const Expanded(child: AdminSettingsBody()),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BOTTOM NAV ADMIN (violet, FAB central paramètres)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _AdminBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _AdminBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.voidBg,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.dashboard_outlined,
                label: 'Tableau',
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.people_outline_rounded,
                label: 'Profs',
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _CenterFab(onTap: () => onTap(2)),
              _NavItem(
                icon: Icons.folder_open_outlined,
                label: 'Casier',
                active: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.show_chart_rounded,
                label: 'Analytique',
                active: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.adminPrimary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppFonts.mono(
                fontSize: 9,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterFab extends StatelessWidget {
  final VoidCallback onTap;
  const _CenterFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: AppColors.adminGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.adminPrimary.withValues(alpha: 0.5),
                blurRadius: 22,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Center(
                child: Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
