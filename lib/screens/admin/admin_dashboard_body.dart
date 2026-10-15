import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/credits_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_teacher_slots_screen.dart';
import 'admin_widgets.dart';

/// A1 — Dashboard global de l'établissement (vue Admin).
/// Branché sur Supabase via [EstablishmentService].
class AdminDashboardBody extends StatefulWidget {
  const AdminDashboardBody({super.key});

  @override
  State<AdminDashboardBody> createState() => _AdminDashboardBodyState();
}

class _AdminDashboardBodyState extends State<AdminDashboardBody> {
  EstablishmentStats? _stats;
  List<RecentPublication> _recentPubs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    final svc = context.read<EstablishmentService>();
    final creditsSvc = context.read<CreditsService>();
    final stats = await svc.computeStats();
    final pubs = await svc.loadRecentPublications(hours: 24);
    // Michel : refresh pool + quotas pour que le solde du pool s'affiche
    // correctement dans _CreditsQuickCard.
    await Future.wait([
      creditsSvc.refreshWallet(),
      creditsSvc.refreshTeacherQuotas(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _recentPubs = pubs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final estab = context.watch<EstablishmentService>();
    final school = estab.currentEstablishment;
    final me = estab.currentMember;

    if (school == null) {
      return _NoEstablishmentState(onRetry: () => estab.refresh());
    }

    final stats = _stats ?? EstablishmentStats.empty();
    final activeCount = estab.members.where((m) => m.isActive).length;
    final teacherCount = estab.members.where((m) => m.isTeacher).length;
    final gradedRatioPct = (stats.gradedRatio * 100).round();

    return RefreshIndicator(
      color: AppColors.adminPrimary,
      onRefresh: () async {
        await estab.refresh();
        await _loadStats();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ━━━━━━ HEADER ÉTABLISSEMENT ━━━━━━
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.adminGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TABLEAU DE BORD',
                        style: AppFonts.mono(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        school.name,
                        style: AppFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Administrateur · ${me?.displayNameOrEmail ?? "-"}',
                        style: AppFonts.sans(
                          fontSize: 11,
                          color: AppColors.adminPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ━━━━━━ KPIs ━━━━━━
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                AdminKpiCard(
                  kpi: AdminKpi(
                    label: 'PROFS ACTIFS',
                    value: '$activeCount',
                    sub: '/${estab.members.length}',
                    deltaText: '$teacherCount enseignant${teacherCount > 1 ? "s" : ""}',
                    isPositive: true,
                  ),
                  color: AppColors.adminPrimary,
                ),
                AdminKpiCard(
                  kpi: AdminKpi(
                    label: 'COPIES TOTALES',
                    value: '${stats.totalCopies}',
                    sub: '',
                    deltaText: stats.totalCopies == 0
                        ? 'Aucune copie pour l\'instant'
                        : 'Tous enseignants',
                    isPositive: true,
                  ),
                  color: AppColors.primaryLight,
                ),
                AdminKpiCard(
                  kpi: AdminKpi(
                    label: 'CORRIGÉES',
                    value: '${stats.gradedCopies}',
                    sub:
                        stats.totalCopies > 0 ? ' · $gradedRatioPct%' : '',
                    deltaText:
                        stats.totalCopies > 0 ? 'sur ${stats.totalCopies}' : '—',
                    isPositive: true,
                  ),
                  color: AppColors.profPrimary,
                ),
                AdminKpiCard(
                  kpi: AdminKpi(
                    label: 'COPIES SIGNALÉES',
                    value: '${stats.flaggedCopies}',
                    sub: '',
                    deltaText: stats.flaggedCopies == 0
                        ? 'Aucun signalement'
                        : 'À examiner',
                    isPositive: stats.flaggedCopies == 0,
                  ),
                  color: stats.flaggedCopies == 0
                      ? AppColors.profPrimary
                      : AppColors.warning,
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ━━━━━━ ALERTES (calculées sur les vraies données) ━━━━━━
            Text(
              'ALERTES',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            ..._computeAlerts(estab, stats).map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdminAlertCard(alert: a),
              ),
            ),

            // ━━━━━━ CRÉDITS ÉTABLISSEMENT ━━━━━━
            // Michel : affiche le solde du pool + accès à la gestion.
            const SizedBox(height: 18),
            _CreditsQuickCard(
              // Michel : "Gérer / Attribuer" ouvre l'écran des profs
              // (AdminTeacherSlotsScreen) où l'admin voit la liste, ajoute
              // des profs, et attribue les crédits par tap sur chaque prof.
              onManage: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminTeacherSlotsScreen(),
                ),
              ),
            ),

            // ━━━━━━ NOTIFICATIONS : profs qui ont envoyé des notes ━━━━━━
            if (_recentPubs.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    'NOTES REÇUES (24h)',
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_recentPubs.fold<int>(0, (a, b) => a + b.count)} notes',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.profPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._recentPubs.map((pub) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecentPubCard(pub: pub),
                  )),
            ],

            const SizedBox(height: 18),

            // ━━━━━━ ENSEIGNANTS ACTIFS ━━━━━━
            Text(
              'ENSEIGNANTS',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            if (estab.members.where((m) => m.isTeacher).isEmpty)
              _EmptyTeachersHint()
            else
              Builder(
                builder: (context) {
                  // Michel : dedup par user_id — si l'API renvoie 2 rows
                  // pour le même user (bug historique), on ne montre qu'une
                  // chip. Le fix DB est dans 20260903000005 mais on garde
                  // le filet côté client.
                  final seen = <String>{};
                  final teachers = estab.members
                      .where((m) => m.isTeacher)
                      .where((m) => seen.add(m.userId))
                      .toList();
                  return SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: teachers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final teacher = teachers[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border:
                                Border.all(color: AppColors.borderSubtle),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: teacher.isActive
                                      ? AppColors.profPrimary
                                      : AppColors.textMuted,
                                  shape: BoxShape.circle,
                                  boxShadow: teacher.isActive
                                      ? [
                                          BoxShadow(
                                            color: AppColors.profPrimary,
                                            blurRadius: 5,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                teacher.displayNameOrEmail,
                                style: AppFonts.sans(
                                  fontSize: 11,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),

            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                        AppColors.adminPrimary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Alertes calculées dynamiquement depuis les vraies données.
  List<AdminAlert> _computeAlerts(
      EstablishmentService svc, EstablishmentStats stats) {
    final alerts = <AdminAlert>[];

    if (stats.flaggedCopies > 0) {
      alerts.add(AdminAlert(
        severity: AdminAlertSeverity.warning,
        message:
            '${stats.flaggedCopies} copie${stats.flaggedCopies > 1 ? "s" : ""} signalée${stats.flaggedCopies > 1 ? "s" : ""} (hors-sujet ou illisibles).',
      ));
    }

    final pendingInv = svc.pendingInvitations.where((i) => i.isPending);
    if (pendingInv.isNotEmpty) {
      alerts.add(AdminAlert(
        severity: AdminAlertSeverity.info,
        message:
            '${pendingInv.length} invitation${pendingInv.length > 1 ? "s" : ""} en attente d\'acceptation.',
      ));
    }

    if (svc.members.where((m) => m.isTeacher).isEmpty) {
      alerts.add(const AdminAlert(
        severity: AdminAlertSeverity.info,
        message:
            'Aucun enseignant pour l\'instant. Allez dans "Enseignants" pour en inviter.',
      ));
    }

    if (alerts.isEmpty) {
      alerts.add(const AdminAlert(
        severity: AdminAlertSeverity.info,
        message: 'Aucune alerte. Tout est sous contrôle.',
      ));
    }

    return alerts;
  }
}

class _NoEstablishmentState extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoEstablishmentState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.adminGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Créez votre école',
              style: AppFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Donnez un nom à votre établissement. Vous pourrez ensuite '
              'inviter vos enseignants et leur attribuer des crédits.',
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.adminGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => _openCreateSchoolSheet(context, onRetry),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 14),
                    child: Text(
                      '+ CRÉER MON ÉCOLE',
                      style: AppFonts.mono(
                        fontSize: 11,
                        color: Colors.white,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Réessayer',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateSchoolSheet(BuildContext context, VoidCallback onDone) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateSchoolSheet(onDone: onDone),
    );
  }
}

/// Michel : formulaire minimal pour qu'un admin fraîchement inscrit crée
/// son école (nom + ville). Après création, l'onRetry recharge le dashboard.
class _CreateSchoolSheet extends StatefulWidget {
  final VoidCallback onDone;
  const _CreateSchoolSheet({required this.onDone});

  @override
  State<_CreateSchoolSheet> createState() => _CreateSchoolSheetState();
}

class _CreateSchoolSheetState extends State<_CreateSchoolSheet> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<EstablishmentService>().createEstablishment(
            name: _name.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Créer mon école',
                style: AppFonts.fraunces(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Ces infos peuvent être modifiées plus tard.',
              style: AppFonts.sans(
                  fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            Text('NOM DE L\'ÉCOLE',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 1.4,
                )),
            const SizedBox(height: 6),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ex : Lycée Kaba',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nom requis' : null,
            ),
            const SizedBox(height: 14),
            Text('VILLE (OPTIONNEL)',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 1.4,
                )),
            const SizedBox(height: 6),
            TextFormField(
              controller: _city,
              decoration: InputDecoration(
                hintText: 'Ex : Conakry',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.adminGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: _saving ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'CRÉER L\'ÉCOLE',
                              style: AppFonts.mono(
                                fontSize: 11,
                                color: Colors.white,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTeachersHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.adminPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.adminPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1_outlined,
              size: 18, color: AppColors.adminPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aucun enseignant. Invitez-en depuis l\'onglet Enseignants.',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.adminPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte "X notes envoyées par M. Untel" — affichée dans le dashboard pour
/// que l'admin sache qui a publié quand.
class _RecentPubCard extends StatelessWidget {
  final RecentPublication pub;
  const _RecentPubCard({required this.pub});

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.profPrimary.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.profPrimary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.upload_rounded,
              color: AppColors.profPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pub.teacherName,
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pub.count} note${pub.count > 1 ? "s" : ""} envoyée${pub.count > 1 ? "s" : ""} au casier · ${_relativeTime(pub.lastPublishedAt)}',
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.profPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.profPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '+${pub.count}',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.profPrimary,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte dashboard admin — SOLDE POOL visible + accès direct à la gestion.
/// Michel : le solde doit apparaître clairement pour que l'admin sache
/// combien il a. Un seul bouton "Gérer" mène à l'écran complet
/// (liste profs + attribution). L'achat se fait hors de l'app (option B).
class _CreditsQuickCard extends StatelessWidget {
  final VoidCallback onManage;
  const _CreditsQuickCard({
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CreditsService>(
      builder: (context, svc, _) {
        // Michel : "dispos" = pool physique - crédits déjà engagés chez
        // les profs. C'est ce chiffre qui doit décroître à chaque attribution.
        final poolAvailable = svc.orgWallet.availableCredits;
        final poolEngaged = svc.orgWallet.engagedCredits;
        final poolPhysical = svc.orgWallet.totalCredits;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.adminPrimary.withValues(alpha: 0.18),
                AppColors.adminPrimary.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: AppColors.adminPrimary.withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.adminPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Crédits établissement',
                      style: AppFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.adminPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // SOLDE POOL DISPO en gros (déduction faite des quotas engagés)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$poolAvailable',
                    style: AppFonts.fraunces(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: AppColors.adminPrimary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    poolAvailable == 1 ? 'crédit dispo' : 'crédits dispos',
                    style: AppFonts.sans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                poolEngaged > 0
                    ? '$poolEngaged déjà engagés · $poolPhysical au total dans le pool'
                    : 'dans le pool à répartir entre vos enseignants',
                style: AppFonts.sans(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onManage,
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text('Gérer / Attribuer'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.adminPrimary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        textStyle: AppFonts.mono(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
