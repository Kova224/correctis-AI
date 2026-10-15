import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../services/admin_export_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// A7 — Casier d'un élève (toutes matières, vraies notes Supabase).
///
/// Le couple (studentName, studentRef) identifie l'élève de façon unique.
/// Si deux élèves portent le même nom mais ont des matricules différents,
/// ils sont traités comme deux casiers distincts.
class AdminStudentCasierScreen extends StatefulWidget {
  final String studentName;
  final String? studentRef; // matricule
  final String className;
  final String studentInitial;
  final String studentAvatarKey;

  const AdminStudentCasierScreen({
    super.key,
    required this.studentName,
    this.studentRef,
    required this.className,
    required this.studentInitial,
    required this.studentAvatarKey,
  });

  @override
  State<AdminStudentCasierScreen> createState() =>
      _AdminStudentCasierScreenState();
}

class _AdminStudentCasierScreenState extends State<AdminStudentCasierScreen> {
  /// Index du terme sélectionné (-1 = année complète).
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
    final all = await svc.notesForStudent(
      widget.studentName,
      studentRef: widget.studentRef,
    );
    if (!mounted) return;
    setState(() {
      _allNotes = all;
      _loading = false;
      // Préselectionne le terme en cours
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

  List<AdminStudentNote> _notesForCurrentTerm(List<AcademicTerm> terms) {
    if (_selectedTermIndex < 0 || _selectedTermIndex >= terms.length) {
      return _allNotes;
    }
    final term = terms[_selectedTermIndex];
    return _allNotes.where((n) => term.contains(n.date)).toList();
  }

  /// Groupe par matière et calcule la moyenne arithmétique.
  List<_SubjectAverage> _bySubject(List<AdminStudentNote> notes) {
    final groups = <String, List<AdminStudentNote>>{};
    for (final n in notes) {
      groups.putIfAbsent(n.matiere, () => []).add(n);
    }
    final result = <_SubjectAverage>[];
    groups.forEach((subject, ns) {
      final avg = ns.fold<double>(0, (acc, n) => acc + n.note) / ns.length;
      result.add(_SubjectAverage(
        name: subject,
        average: double.parse(avg.toStringAsFixed(2)),
        count: ns.length,
      ));
    });
    result.sort((a, b) => b.average.compareTo(a.average));
    return result;
  }

  /// Moyenne générale pondérée par les coefficients de l'école.
  double _moyenneGenerale(
    List<_SubjectAverage> subjects,
    EstablishmentConfig config,
  ) {
    if (subjects.isEmpty) return 0;
    double sumWeighted = 0;
    double sumCoefs = 0;
    for (final s in subjects) {
      final coef = config.coefficientFor(s.name);
      sumWeighted += s.average * coef;
      sumCoefs += coef;
    }
    if (sumCoefs == 0) return 0;
    return double.parse((sumWeighted / sumCoefs).toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EstablishmentService>();
    final config = svc.currentEstablishment?.config ??
        const EstablishmentConfig();
    final terms = config.terms;
    final notes = _notesForCurrentTerm(terms);
    final subjects = _bySubject(notes);
    final moyenne = _moyenneGenerale(subjects, config);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
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

              const SizedBox(height: 16),

              // ━━━━━━ STUDENT CARD ━━━━━━
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.adminPrimary.withValues(alpha: 0.12),
                        AppColors.primary.withValues(alpha: 0.06),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.adminPrimary
                          .withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    children: [
                      AdminAvatar(
                        initials: widget.studentInitial,
                        avatarKey: widget.studentAvatarKey,
                        size: 52,
                        withBorder: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.studentName,
                              style: AppFonts.fraunces(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  widget.className.toUpperCase(),
                                  style: AppFonts.mono(
                                    fontSize: 9.5,
                                    color: AppColors.textMuted,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                if (widget.studentRef?.trim().isNotEmpty == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.adminPrimary
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.pill),
                                    ),
                                    child: Text(
                                      'MAT. ${widget.studentRef}',
                                      style: AppFonts.mono(
                                        fontSize: 8.5,
                                        color: AppColors.adminPrimary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notes.isEmpty
                                  ? 'Aucune note'
                                  : '${notes.length} note${notes.length != 1 ? "s" : ""}'
                                      ' · ${subjects.length} matière${subjects.length != 1 ? "s" : ""}',
                              style: AppFonts.mono(
                                fontSize: 9.5,
                                color: AppColors.adminPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.adminPrimary
                              .withValues(alpha: 0.15),
                          border: Border.all(
                            color: AppColors.adminPrimary
                                .withValues(alpha: 0.35),
                          ),
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                        child: Column(
                          children: [
                            Text(
                              notes.isEmpty
                                  ? '—'
                                  : moyenne.toStringAsFixed(1),
                              style: AppFonts.fraunces(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.adminPrimary,
                              ),
                            ),
                            Text(
                              'MOYENNE',
                              style: AppFonts.mono(
                                fontSize: 8,
                                color: AppColors.textMuted,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (terms.isNotEmpty) ...[
                const SizedBox(height: 12),
                // ━━━━━━ TRIM TABS ━━━━━━
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    height: 30,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        AdminFilterPill(
                          label: 'ANNÉE',
                          active: _selectedTermIndex == -1,
                          onTap: () =>
                              setState(() => _selectedTermIndex = -1),
                        ),
                        const SizedBox(width: 6),
                        for (int i = 0; i < terms.length; i++) ...[
                          AdminFilterPill(
                            label: terms[i].name.toUpperCase(),
                            active: _selectedTermIndex == i,
                            onTap: () =>
                                setState(() => _selectedTermIndex = i),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ━━━━━━ MATIÈRES ━━━━━━
              Expanded(
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                                AppColors.adminPrimary),
                          ),
                        ),
                      )
                    : (notes.isEmpty
                        ? _emptyNotes()
                        : RefreshIndicator(
                            color: AppColors.adminPrimary,
                            onRefresh: _load,
                            child: ListView.separated(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  20, 0, 20, 16),
                              itemCount: subjects.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) => _SubjectRow(
                                s: subjects[i],
                                coefficient: config.coefficientFor(
                                    subjects[i].name),
                              ),
                            ),
                          )),
              ),

              if (notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    children: [
                      AdminGradientButton(
                        label: 'EXPORTER LE BULLETIN PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        onTap: () => _exportPdf(
                          notes,
                          terms.isNotEmpty && _selectedTermIndex >= 0
                              ? terms[_selectedTermIndex]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                          side: BorderSide(
                            color:
                                AppColors.adminPrimary.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        icon: const Icon(
                          Icons.grid_on_rounded,
                          size: 16,
                          color: AppColors.adminPrimary,
                        ),
                        label: Text(
                          'EXPORTER EN EXCEL',
                          style: AppFonts.mono(
                            fontSize: 10.5,
                            color: AppColors.adminPrimary,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => _exportExcel(
                          notes,
                          terms.isNotEmpty && _selectedTermIndex >= 0
                              ? terms[_selectedTermIndex]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportExcel(
    List<AdminStudentNote> notes,
    AcademicTerm? term,
  ) async {
    final svc = context.read<EstablishmentService>();
    final school = svc.currentEstablishment;
    if (school == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Génération du fichier Excel…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final exporter = AdminExportService();
      final file = await exporter.exportCasierExcel(
        establishment: school,
        notes: notes,
        term: term,
      );
      await exporter.shareFile(
        file,
        text: 'Notes de ${widget.studentName} — ${school.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Excel : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportPdf(
    List<AdminStudentNote> notes,
    AcademicTerm? term,
  ) async {
    final svc = context.read<EstablishmentService>();
    final school = svc.currentEstablishment;
    if (school == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Génération du bulletin…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final exporter = AdminExportService();
      final file = await exporter.exportStudentBulletin(
        establishment: school,
        studentName: widget.studentName,
        className: widget.className,
        notes: notes,
        term: term,
      );
      await exporter.shareFile(
        file,
        text: 'Bulletin de ${widget.studentName} — ${school.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _emptyNotes() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              'Aucune note pour cet élève',
              style: AppFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Les notes apparaîtront ici une fois\nles copies corrigées par les enseignants.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectAverage {
  final String name;
  final double average;
  final int count;
  const _SubjectAverage({
    required this.name,
    required this.average,
    required this.count,
  });
}

class _SubjectRow extends StatelessWidget {
  final _SubjectAverage s;
  final double coefficient;
  const _SubjectRow({required this.s, required this.coefficient});

  Color get _color {
    if (s.average >= 14) return AppColors.profPrimary;
    if (s.average >= 10) return AppColors.primaryLight;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.book_outlined,
              size: 18,
              color: _color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: AppFonts.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${s.count} note${s.count != 1 ? "s" : ""}',
                      style: AppFonts.mono(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (coefficient != 1.0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.adminPrimary
                              .withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'COEF ${coefficient.toStringAsFixed(coefficient == coefficient.roundToDouble() ? 0 : 1)}',
                          style: AppFonts.mono(
                            fontSize: 8,
                            color: AppColors.adminPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: (s.average / 20).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: const Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation(_color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.average.toStringAsFixed(1),
                style: AppFonts.fraunces(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              ),
              Text(
                '/20',
                style: AppFonts.sans(
                  fontSize: 9.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
