import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.dart';
import '../../models/copy.dart';
import '../../models/credits.dart';
import '../../models/exam.dart';
import '../../services/auth_service.dart';
import '../../services/credits_service.dart';
import '../../services/establishment_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../chatbot/chatbot_sheet.dart';
import '../credits/my_credits_screen.dart';
import '../exam/create_exam_screen.dart';
import '../exam/exam_detail_screen.dart';
import '../profile/notifications_inbox_screen.dart';
import '../profile/profile_screen.dart';
import 'accueil_body.dart';
import 'results_body.dart';

/// Écran d'accueil — V2 selon maquette Michel (P1 : Mes Examens).
///
/// Layout :
///   [Status bar]
///   [Greeting "Bonjour" mono + Nom Fraunces + École + Plan badge]
///   [Section "MES EXAMENS RÉCENTS"]
///   [Liste cartes examens]
///   [Bouton "+ Créer un examen" pleine largeur vert dégradé]
///   [Bottom tab bar : 📋 Examens · 📸 Scanner · ✦ FAB · 📊 Résultats · 👤 Profil]
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  final TextEditingController _searchCtl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Charge l'inbox notifications (badge non lu visible dans le header).
      if (!mounted) return;
      context.read<EstablishmentService>().loadMyNotifications();
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final examSvc = context.watch<ExamService>();
    context.watch<EstablishmentService>(); // rebuild on membership change
    final s = S.of(context);
    final user = auth.currentUser;
    if (user == null) {
      return const LoginScreen();
    }
    // Michel (spec §5/§6) : plus de concept "école active". Le prof voit
    // TOUS ses examens (solo + toutes ses écoles) ; le tri/regroupement par
    // catégorie est fait au niveau UI (section §8 spec).
    final allExams = examSvc.examsForUser(user.id);
    final q = _searchQuery.trim().toLowerCase();
    final exams = q.isEmpty
        ? allExams
        : allExams.where((e) {
            final t = e.title.toLowerCase();
            final c = (e.className ?? '').toLowerCase();
            return t.contains(q) || c.contains(q);
          }).toList();

    // Body actuel selon l'onglet sélectionné — IndexedStack pour navigation
    // persistante (la bottom nav reste affichée, le switch est instantané).
    final accueilBody = AccueilBody(
      onStart: () => setState(() => _currentTab = 1),
    );
    final dashboardBody =
        _buildDashboardBody(context, user, examSvc, exams, allExams, s);
    final scannerBody = _buildPlaceholder(
      icon: Icons.qr_code_scanner_rounded,
      title: s.tabScanner,
      subtitle: s.pick(
        'Sélectionnez un examen pour scanner ses copies.',
        'Pick an exam to scan its papers.',
        'اختر امتحانًا لمسح أوراقه.',
      ),
      onAction: () => setState(() => _currentTab = 1),
      actionLabel: s.myRecentExams,
    );
    final resultsBody = _buildPlaceholder(
      icon: Icons.bar_chart_rounded,
      title: s.tabResults,
      subtitle: s.pick(
        'Sélectionnez un examen pour voir ses résultats détaillés.',
        'Pick an exam to view detailed results.',
        'اختر امتحانًا لعرض النتائج المفصلة.',
      ),
      onAction: () => setState(() => _currentTab = 1),
      actionLabel: s.myRecentExams,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.4,
            colors: [
              Color(0xFF091F3A),
              AppColors.voidBg,
            ],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _currentTab,
            children: [
              accueilBody, // 0 = Accueil (landing chaleureux, par défaut)
              dashboardBody, // 1 = Examens
              scannerBody, // 2 = Scanner placeholder
              const SizedBox.shrink(), // 3 = FAB (jamais affiché)
              const ResultsBody(), // 4 = Résultats analytiques (A7)
              const ProfileBody(), // 5 = Profil (style maquette)
            ],
          ),
        ),
      ),

      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      // BOTTOM NAV — 5 onglets + FAB central (style maquette)
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      bottomNavigationBar: _CorrectisBottomNav(
        currentIndex: _currentTab,
        onTap: (i) {
          if (i == 3) {
            // FAB central → créer un examen (push vrai écran)
            _openCreateExam(context);
            return;
          }
          // Tous les autres tabs (0, 1, 2, 4, 5) → switch interne IndexedStack
          setState(() => _currentTab = i);
        },
      ),
    );
  }

  /// Builder du body du dashboard (onglet "Examens").
  Widget _buildDashboardBody(
    BuildContext context,
    dynamic user,
    ExamService examSvc,
    List<Exam> exams,
    List<Exam> allExams,
    S s,
  ) {
    return RefreshIndicator(
            color: AppColors.profPrimary,
            backgroundColor: AppColors.card,
            onRefresh: () async => examSvc.bootstrap(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              children: [
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // GREETING + ACTIONS RAPIDES (chatbot, profil)
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.hello,
                            style: AppFonts.mono(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.displayName.isEmpty
                                ? s.teacher
                                : user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.fraunces(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.school?.isNotEmpty == true
                                ? user.school!
                                : s.schoolNotSet,
                            style: AppFonts.sans(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Michel : plus de switcher école active — chaque
                          // examen sait déjà à quelle école il appartient
                          // (choix fait à la création). Le regroupement par
                          // catégorie se fait dans la section examens.
                          // Badge crédits dynamique (Pay-as-you-go).
                          // Affiche le solde personnel + indication pool éta-
                          // blissement le cas échéant. Cliquable → MyCredits.
                          Consumer<CreditsService>(
                            builder: (context, credits, _) {
                              final total = credits.wallet.totalCredits;
                              final pool = credits.orgWallet.totalCredits;
                              // Audit 15/10/2026 : un prof d'école corrige
                              // les examens de l'école avec le quota donné
                              // par l'admin, pas avec son solde perso → on
                              // affiche les deux.
                              final schoolQuotas = credits
                                  .myTeacherQuotasAllSchools
                                  .where((q) => q.hasLimit)
                                  .toList();
                              final schoolRemaining = schoolQuotas.fold<int>(
                                  0, (sum, q) => sum + q.remaining);
                              final String label;
                              if (schoolQuotas.isNotEmpty) {
                                label = schoolQuotas.length == 1
                                    ? 'École : $schoolRemaining crédit${schoolRemaining != 1 ? "s" : ""} · perso : $total'
                                    : 'Écoles : $schoolRemaining crédits · perso : $total';
                              } else if (pool > 0) {
                                label = '$total crédits · pool : $pool';
                              } else {
                                label = total > 0
                                    ? '$total crédit${total != 1 ? "s" : ""} disponibles'
                                    : 'Aucun crédit disponible';
                              }
                              return _PlanBadge(
                                label: label,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MyCreditsScreen(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CircleIcon(
                      icon: Icons.smart_toy_outlined,
                      tooltip: 'Correctis Chatbot',
                      onTap: () => showChatBotSheet(context),
                    ),
                    const SizedBox(width: 8),
                    _NotificationsBell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const NotificationsInboxScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeaderAvatar(
                      user: user,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION "MES EXAMENS RÉCENTS" + BARRE DE RECHERCHE
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Text(
                  s.myRecentExams,
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),

                // Barre de recherche (affichée seulement s'il y a au moins
                // quelques examens à filtrer)
                if (allExams.length >= 3) ...[
                  _ExamSearchBar(
                    controller: _searchCtl,
                    hint: s.searchExam,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    onClear: () {
                      _searchCtl.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                if (allExams.isEmpty)
                  _EmptyStateCard(
                    onCreate: () => _openCreateExam(context),
                  )
                else if (exams.isEmpty)
                  _NoSearchMatchCard(
                    query: _searchQuery,
                    onClear: () {
                      _searchCtl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                else
                  // Michel (spec §6) : regroupement par catégorie
                  // Section "Personnel (solo)" + une section par école
                  // (nom + solde de crédits) + liste des examens.
                  ..._buildGroupedExams(context, exams, examSvc),

                const SizedBox(height: 12),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // BOUTON CRÉER (gradient vert prof)
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _GradientButton(
                  label: s.createExam,
                  gradient: AppColors.profGradient,
                  onTap: () => _openCreateExam(context),
                ),
              ],
            ),
          );
  }

  /// Michel (spec §6) : regroupe les examens par catégorie.
  ///
  /// - "Personnel (solo)" : examens sans establishmentId
  /// - Une section par école : examens dont establishmentId == cette école,
  ///   avec le nom de l'école + solde de crédits attribués au prof.
  ///
  /// Chaque section a un header pill avec le nom + le solde.
  List<Widget> _buildGroupedExams(
    BuildContext context,
    List<Exam> exams,
    ExamService examSvc,
  ) {
    // Split solo vs école
    final soloExams = exams.where((e) => e.establishmentId == null).toList();
    // Groupe par establishmentId
    final byEstab = <String, List<Exam>>{};
    for (final e in exams) {
      if (e.establishmentId == null) continue;
      byEstab.putIfAbsent(e.establishmentId!, () => []).add(e);
    }

    final estabSvc = context.read<EstablishmentService>();
    final creditsSvc = context.watch<CreditsService>();
    final memberships = estabSvc.myMemberships;

    final widgets = <Widget>[];

    // Section Solo
    if (soloExams.isNotEmpty) {
      widgets.add(_SectionHeader(
        label: 'PERSONNEL (SOLO)',
        subtitle: '${soloExams.length} examen${soloExams.length > 1 ? "s" : ""}',
        color: AppColors.textMuted,
      ));
      widgets.add(const SizedBox(height: 8));
      widgets.addAll(soloExams.map((exam) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ExamCard(
              exam: exam,
              copies: examSvc.copiesFor(exam.id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExamDetailScreen(examId: exam.id),
                ),
              ),
            ),
          )));
      widgets.add(const SizedBox(height: 16));
    }

    // Sections par école (ordre : nom école)
    final estabIds = byEstab.keys.toList()
      ..sort((a, b) {
        final na = memberships
            .firstWhere((m) => m.establishmentId == a,
                orElse: () => MembershipSummary(
                    membershipId: '',
                    establishmentId: a,
                    establishmentName: 'ZZZ',
                    role: 'teacher',
                    matieres: const [],
                    classes: const [],
                    isActive: true,
                    joinedAt: DateTime.now()))
            .establishmentName;
        final nb = memberships
            .firstWhere((m) => m.establishmentId == b,
                orElse: () => MembershipSummary(
                    membershipId: '',
                    establishmentId: b,
                    establishmentName: 'ZZZ',
                    role: 'teacher',
                    matieres: const [],
                    classes: const [],
                    isActive: true,
                    joinedAt: DateTime.now()))
            .establishmentName;
        return na.compareTo(nb);
      });

    for (final estabId in estabIds) {
      final estabExams = byEstab[estabId]!;
      final membership = memberships.firstWhere(
        (m) => m.establishmentId == estabId,
        orElse: () => MembershipSummary(
          membershipId: '',
          establishmentId: estabId,
          establishmentName: 'École',
          role: 'teacher',
          matieres: const [],
          classes: const [],
          isActive: true,
          joinedAt: DateTime.now(),
        ),
      );
      MyTeacherQuota? quota;
      try {
        quota = creditsSvc.myTeacherQuotasAllSchools
            .firstWhere((q) => q.establishmentId == estabId);
      } catch (_) {
        quota = null;
      }
      final subtitle = quota != null && quota.hasLimit
          ? '${estabExams.length} examen${estabExams.length > 1 ? "s" : ""} · ${quota.remaining}/${quota.limitTotal} crédits'
          : '${estabExams.length} examen${estabExams.length > 1 ? "s" : ""}';
      widgets.add(_SectionHeader(
        label: '🏛️  ${membership.establishmentName.toUpperCase()}',
        subtitle: subtitle,
        color: AppColors.adminPrimary,
      ));
      widgets.add(const SizedBox(height: 8));
      widgets.addAll(estabExams.map((exam) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ExamCard(
              exam: exam,
              copies: examSvc.copiesFor(exam.id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExamDetailScreen(examId: exam.id),
                ),
              ),
            ),
          )));
      widgets.add(const SizedBox(height: 16));
    }

    return widgets;
  }

  /// Placeholder simple pour les onglets pas encore branchés (Scanner, Résultats).
  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onAction,
    required String actionLabel,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.profPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 36, color: AppColors.profPrimary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: AppFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// Ouvre l'écran "Créer un examen". Pas de limite à la création :
  /// les crédits sont débités au lancement de chaque correction (grille v5).
  void _openCreateExam(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateExamScreen()),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COMPOSANTS LOCAUX
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Badge plan / crédits (vert prof translucide) — style maquette P1.
class _PlanBadge extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PlanBadge({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.profPrimary.withValues(alpha: 0.1),
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            size: 11,
            color: AppColors.profPrimary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppFonts.mono(
              fontSize: 10,
              color: AppColors.profPrimary,
              letterSpacing: 1,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 12,
              color: AppColors.profPrimary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: pill,
    );
  }
}

/// Header de section pour le regroupement Mes examens (Solo / par école).
/// Michel (spec §6) : nom de la catégorie + solde crédits.
class _SectionHeader extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppFonts.mono(
                fontSize: 10.5,
                color: color,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: AppFonts.mono(
              fontSize: 10,
              color: color.withValues(alpha: 0.85),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte examen — style P1 maquette : icon coloré + titre + meta + status badge.
class _ExamCard extends StatelessWidget {
  final Exam exam;
  final List<StudentCopy> copies;
  final VoidCallback onTap;

  const _ExamCard({
    required this.exam,
    required this.copies,
    required this.onTap,
  });

  ({Color bg, Color fg, IconData icon, String status, Color statusBg, Color statusFg})
      _theme() {
    final total = copies.length;
    final graded = copies.where((c) => c.status == CopyStatus.graded).length;
    if (total == 0) {
      // Nouvel examen
      return (
        bg: AppColors.primary.withValues(alpha: 0.12),
        fg: AppColors.primary,
        icon: Icons.note_add_outlined,
        status: 'Nouveau',
        statusBg: AppColors.primary.withValues(alpha: 0.1),
        statusFg: AppColors.primaryLight,
      );
    }
    if (graded < total) {
      // En cours
      return (
        bg: AppColors.warning.withValues(alpha: 0.1),
        fg: AppColors.warning,
        icon: Icons.hourglass_top_outlined,
        status: 'En cours',
        statusBg: AppColors.warning.withValues(alpha: 0.1),
        statusFg: AppColors.warning,
      );
    }
    // Tout corrigé
    return (
      bg: AppColors.profPrimary.withValues(alpha: 0.1),
      fg: AppColors.profPrimary,
      icon: Icons.check_circle_outline,
      status: '✓ Corrigé',
      statusBg: AppColors.profPrimary.withValues(alpha: 0.1),
      statusFg: AppColors.profPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme();
    final dateLabel = _formatDate(exam.createdAt);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon coloré
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(t.icon, color: t.fg, size: 20),
              ),
              const SizedBox(width: 12),
              // Titre + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateLabel · ${copies.length} élève${copies.length > 1 ? 's' : ''}',
                      style: AppFonts.sans(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.statusBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  t.status,
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: t.statusFg,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime utc) {
    final d = utc.toLocal();
    const months = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// Barre de recherche sur la liste d'examens (titre + classe).
class _ExamSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hint;

  const _ExamSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppFonts.sans(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppFonts.sans(
          fontSize: 12.5,
          color: AppColors.textMuted.withValues(alpha: 0.7),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textMuted,
                onPressed: onClear,
                splashRadius: 18,
              ),
        filled: true,
        fillColor: AppColors.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(
              color: AppColors.profPrimary, width: 1.4),
        ),
      ),
    );
  }
}

/// Carte « aucun résultat » pour la recherche d'examens.
class _NoSearchMatchCard extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _NoSearchMatchCard({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textMuted,
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            'Aucun examen pour « $query »',
            textAlign: TextAlign.center,
            style: AppFonts.sans(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onClear,
            child: Text(
              'EFFACER LA RECHERCHE',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.profPrimary,
                letterSpacing: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// État vide — invitation à créer le premier examen.
class _EmptyStateCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyStateCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.profPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(Icons.add_chart_rounded,
                color: AppColors.profPrimary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun examen',
            style: AppFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Créez votre premier examen pour\ncommencer à corriger des copies.',
            textAlign: TextAlign.center,
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton plein largeur avec dégradé (style maquette).
class _GradientButton extends StatelessWidget {
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                label,
                style: AppFonts.mono(
                  fontSize: 12,
                  color: Colors.white,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cloche notifications avec badge "non lu" rouge.
class _NotificationsBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationsBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread =
        context.watch<EstablishmentService>().unreadNotificationsCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.card,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.borderSubtle),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.notifications_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: unread < 10
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius:
                    unread < 10 ? null : BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.voidBg,
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: AppFonts.mono(
                  fontSize: 8.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Petit bouton circulaire icon-only — pour les actions du greeting.
class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _CircleIcon({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Avatar cliquable du header — photo prof ou initiales.
class _HeaderAvatar extends StatelessWidget {
  final dynamic user; // AppUser
  final VoidCallback onTap;
  const _HeaderAvatar({required this.user, required this.onTap});

  String get _initials {
    final name = user.displayName as String? ?? '';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = user.photoPath as String?;
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: ClipOval(
            child: _renderHeaderPhoto(photoPath) ??
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.profGradient,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: AppFonts.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Widget? _renderHeaderPhoto(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    return Image.file(file, fit: BoxFit.cover);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BOTTOM NAV — 5 onglets + FAB central style maquette
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Bottom nav style maquette P1 : 4 items texte + FAB central lumineux vert.
class _CorrectisBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CorrectisBottomNav({
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
                icon: Icons.home_rounded,
                label: S.of(context).tabHome,
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.assignment_outlined,
                label: S.of(context).tabExams,
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // FAB central lumineux — création rapide
              _CenterFab(onTap: () => onTap(3)),
              _NavItem(
                icon: Icons.bar_chart_rounded,
                label: S.of(context).tabResults,
                active: currentIndex == 4,
                onTap: () => onTap(4),
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: S.of(context).tabProfile,
                active: currentIndex == 5,
                onTap: () => onTap(5),
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
    final color = active ? AppColors.profPrimary : AppColors.textMuted;
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

/// Bouton FAB central lumineux (gradient vert + halo).
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
            gradient: AppColors.profGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.profPrimary.withValues(alpha: 0.5),
                blurRadius: 22,
                spreadRadius: 0,
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
                child: Icon(Icons.auto_awesome,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
