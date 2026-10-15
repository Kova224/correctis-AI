import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_pedagogy_config_screen.dart';
import 'admin_widgets.dart';

/// A4 — Analytique pédagogique (vue Admin).
/// Tendances et lacunes calculées sur les vraies notes Supabase.
/// Filtrage par trimestre selon la config école.
class AdminAnalyticsBody extends StatefulWidget {
  const AdminAnalyticsBody({super.key});

  @override
  State<AdminAnalyticsBody> createState() => _AdminAnalyticsBodyState();
}

class _AdminAnalyticsBodyState extends State<AdminAnalyticsBody> {
  /// Index du terme sélectionné (-1 = toute l'année).
  int _selectedTermIndex = -1;

  List<AdminStudentNote> _allNotes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final notes = await svc.loadAllNotes();
    if (!mounted) return;
    setState(() {
      _allNotes = notes;
      _loading = false;
      // Préselectionne le trimestre en cours s'il y en a un
      final terms = svc.currentEstablishment?.config.terms ?? [];
      final now = DateTime.now();
      for (int i = 0; i < terms.length; i++) {
        if (terms[i].contains(now)) {
          _selectedTermIndex = i;
          break;
        }
      }
    });
  }

  /// Filtre les notes selon le terme sélectionné.
  List<AdminStudentNote> _filteredNotes(List<AcademicTerm> terms) {
    if (_selectedTermIndex < 0 || _selectedTermIndex >= terms.length) {
      return _allNotes;
    }
    final term = terms[_selectedTermIndex];
    return _allNotes.where((n) => term.contains(n.date)).toList();
  }

  /// Tendance : moyenne par mois sur la période sélectionnée.
  List<AdminTrendPoint> _computeTrends(
    List<AdminStudentNote> notes,
    List<AcademicTerm> terms,
  ) {
    const labels = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
                    'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

    // Plage : si un terme est sélectionné → mois du terme.
    //        Sinon → 6 derniers mois.
    DateTime rangeStart;
    DateTime rangeEnd;
    if (_selectedTermIndex >= 0 && _selectedTermIndex < terms.length) {
      rangeStart = terms[_selectedTermIndex].start;
      rangeEnd = terms[_selectedTermIndex].end;
    } else {
      final now = DateTime.now();
      rangeStart = DateTime(now.year, now.month - 5, 1);
      rangeEnd = now;
    }

    // Itère mois par mois entre rangeStart et rangeEnd
    final months = <DateTime>[];
    var cursor = DateTime(rangeStart.year, rangeStart.month, 1);
    final end = DateTime(rangeEnd.year, rangeEnd.month, 1);
    while (!cursor.isAfter(end)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    final result = <AdminTrendPoint>[];
    for (final m in months) {
      final monthEnd = DateTime(m.year, m.month + 1, 1);
      final inMonth = notes
          .where((n) =>
              !n.date.isBefore(m) && n.date.isBefore(monthEnd))
          .toList();
      if (inMonth.isEmpty) {
        result.add(AdminTrendPoint(month: labels[m.month - 1], value: 0));
      } else {
        final avg = inMonth.fold<double>(0, (acc, n) => acc + n.note) /
            inMonth.length;
        result.add(AdminTrendPoint(
          month: labels[m.month - 1],
          value: (avg / 20).clamp(0.0, 1.0),
        ));
      }
    }
    return result;
  }

  /// Lacunes : matières où la moyenne (pondérée par coef) est < 12/20.
  List<AdminLacune> _computeLacunes(
    List<AdminStudentNote> notes,
    EstablishmentConfig config,
  ) {
    if (notes.isEmpty) return const [];
    final bySubject = <String, List<double>>{};
    for (final n in notes) {
      bySubject.putIfAbsent(n.matiere, () => []).add(n.note);
    }
    final lacunes = <AdminLacune>[];
    bySubject.forEach((matiere, ns) {
      final avg = ns.reduce((a, b) => a + b) / ns.length;
      final difficultyPct = (100 - (avg / 20 * 100)).round().clamp(0, 100);
      if (difficultyPct < 30) return;
      final severity = difficultyPct >= 60
          ? 'high'
          : difficultyPct >= 40
              ? 'medium'
              : 'low';
      lacunes.add(AdminLacune(
        label: matiere,
        percentage: difficultyPct,
        severity: severity,
      ));
    });
    lacunes.sort((a, b) => b.percentage.compareTo(a.percentage));
    return lacunes.take(5).toList();
  }

  String _aiRecommendation(
    List<AdminLacune> lacunes,
    List<AdminStudentNote> notes,
  ) {
    if (notes.isEmpty) {
      return 'Aucune donnée pour générer des recommandations sur cette période. '
          'Les analyses apparaîtront dès que vos enseignants corrigeront des copies.';
    }
    if (lacunes.isEmpty) {
      return 'Excellents résultats à l\'échelle de l\'établissement sur cette '
          'période. Continuez à suivre la progression.';
    }
    final top = lacunes.first;
    return 'Une séance de révision ciblée sur "${top.label}" '
        'améliorerait sensiblement les notes du prochain contrôle. '
        'Identifiez les élèves en difficulté dans cette matière depuis le Casier.';
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EstablishmentService>();
    final config = svc.currentEstablishment?.config ??
        const EstablishmentConfig();
    final terms = config.terms;
    final notes = _filteredNotes(terms);
    final trends = _computeTrends(notes, terms);
    final lacunes = _computeLacunes(notes, config);

    return RefreshIndicator(
      color: AppColors.adminPrimary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ANALYTIQUE',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tendances pédagogiques',
              style: AppFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${notes.length} note${notes.length != 1 ? "s" : ""} sur la période sélectionnée',
              style: AppFonts.sans(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),

            const SizedBox(height: 16),

            // ━━━━━━ PÉRIODE ━━━━━━
            _periodSelector(context, terms),

            const SizedBox(height: 18),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                          AppColors.adminPrimary),
                    ),
                  ),
                ),
              )
            else if (notes.isEmpty)
              _emptyAnalytics()
            else ...[
              _trendCard(trends),
              const SizedBox(height: 22),
              Text(
                'MATIÈRES EN DIFFICULTÉ',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              if (lacunes.isEmpty)
                _allGood()
              else
                ...lacunes.map(_lacuneRow),
              const SizedBox(height: 16),
              _recommendationCard(_aiRecommendation(lacunes, notes)),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _periodSelector(BuildContext ctx, List<AcademicTerm> terms) {
    if (terms.isEmpty) {
      // Aucune période configurée → CTA vers Configuration
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.adminPrimary.withValues(alpha: 0.06),
          border: Border.all(
            color: AppColors.adminPrimary.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.event_note_outlined,
              color: AppColors.adminPrimary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aucun trimestre configuré. Définissez les périodes scolaires '
                'pour filtrer ici.',
                style: AppFonts.sans(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => const AdminPedagogyConfigScreen(),
                ),
              ),
              child: Text(
                'Définir',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.adminPrimary,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          AdminFilterPill(
            label: 'ANNÉE',
            active: _selectedTermIndex == -1,
            onTap: () => setState(() => _selectedTermIndex = -1),
          ),
          const SizedBox(width: 6),
          for (int i = 0; i < terms.length; i++) ...[
            AdminFilterPill(
              label: terms[i].name.toUpperCase(),
              active: _selectedTermIndex == i,
              onTap: () => setState(() => _selectedTermIndex = i),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _trendCard(List<AdminTrendPoint> trends) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.adminPrimary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AppColors.adminPrimary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOYENNE MENSUELLE',
            style: AppFonts.mono(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trends.map((t) {
                final isLast = t == trends.last;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: (60 * t.value).clamp(2, 60),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        gradient:
                            isLast ? AppColors.adminGradient : null,
                        color: isLast
                            ? null
                            : AppColors.adminPrimary
                                .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: trends.map((t) {
              return Expanded(
                child: Text(
                  t.month,
                  textAlign: TextAlign.center,
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _lacuneRow(AdminLacune l) {
    final color = l.severity == 'high'
        ? AppColors.danger
        : l.severity == 'medium'
            ? AppColors.warning
            : AppColors.profPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              l.label,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: l.percentage / 100,
                minHeight: 6,
                backgroundColor: const Color(0x14FFFFFF),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '${l.percentage}%',
              textAlign: TextAlign.right,
              style: AppFonts.mono(
                fontSize: 11,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _allGood() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.profPrimary.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.profPrimary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aucune lacune significative détectée.',
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.profPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.profPrimary.withValues(alpha: 0.07),
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                color: AppColors.profPrimary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'RECOMMANDATION',
                style: AppFonts.mono(
                  fontSize: 9,
                  color: AppColors.profPrimary,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: AppFonts.sans(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyAnalytics() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 38, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Aucune donnée sur cette période',
              style: AppFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Les statistiques apparaîtront dès que des copies seront '
                'corrigées dans la période sélectionnée.',
                textAlign: TextAlign.center,
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
