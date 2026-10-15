import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../models/exam.dart';
import '../../models/notification.dart';
import '../../services/admin_export_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// E — Relevé d'un élève par type de contrôle (au lieu du bulletin moyenne).
///
/// Affiche, pour un élève donné, ses notes regroupées par type de contrôle
/// (DS, Examen, Bac blanc…). L'admin peut filtrer par un type spécifique.
class AdminStudentReleveScreen extends StatefulWidget {
  final String studentName;
  final String? studentRef;
  final String? initialControlType;

  const AdminStudentReleveScreen({
    super.key,
    required this.studentName,
    this.studentRef,
    this.initialControlType,
  });

  @override
  State<AdminStudentReleveScreen> createState() =>
      _AdminStudentReleveScreenState();
}

class _AdminStudentReleveScreenState
    extends State<AdminStudentReleveScreen> {
  String? _selectedType;
  // A6 (Sprint 5) : -1 = Toutes périodes, sinon index dans terms de l'école
  int _selectedTermIndex = -1;
  List<StudentReleveEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialControlType;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final list = await svc.loadStudentReleve(
      studentName: widget.studentName,
      studentRef: widget.studentRef,
      controlType: _selectedType,
    );
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  /// Types de contrôle présents dans les notes de l'élève.
  List<String> get _availableTypes {
    final set = <String>{};
    for (final e in _entries) {
      set.add(e.controlType);
    }
    return set.toList()..sort();
  }

  Color _noteColor(double note20) {
    if (note20 >= 14) return AppColors.profPrimary;
    if (note20 >= 10) return AppColors.primaryLight;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    // A6 : récupère les termes de l'école pour le filtre trimestre/semestre
    final estabSvc = context.watch<EstablishmentService>();
    final terms = estabSvc.currentEstablishment?.config.terms ?? [];

    // A6 : filtre les entries selon le terme sélectionné (période)
    final filteredByTerm = _selectedTermIndex < 0 || _selectedTermIndex >= terms.length
        ? _entries
        : _entries
            .where((e) =>
                e.publishedAt != null &&
                terms[_selectedTermIndex].contains(e.publishedAt!))
            .toList();

    // Groupement par type contrôle pour la vue "Tous"
    final byType = <String, List<StudentReleveEntry>>{};
    for (final e in filteredByTerm) {
      byType.putIfAbsent(e.controlType, () => []).add(e);
    }
    final types = byType.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.studentName,
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.studentRef?.isNotEmpty == true
                  ? 'Relevé — Mat. ${widget.studentRef}'
                  : 'Relevé par type de contrôle',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Exporter en Excel',
            icon: const Icon(Icons.grid_on_rounded),
            onPressed: () => _exportExcel(filteredByTerm, terms),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          // A6 — ━━━━━━ FILTRES TRIMESTRE / SEMESTRE ━━━━━━
          if (terms.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  AdminFilterPill(
                    label: 'Toute l\'année',
                    active: _selectedTermIndex < 0,
                    onTap: () => setState(() => _selectedTermIndex = -1),
                  ),
                  const SizedBox(width: 6),
                  for (int i = 0; i < terms.length; i++) ...[
                    AdminFilterPill(
                      label: '📅  ${terms[i].name}',
                      active: _selectedTermIndex == i,
                      onTap: () => setState(() => _selectedTermIndex = i),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          if (terms.isNotEmpty) const SizedBox(height: 6),
          // ━━━━━━ FILTRES TYPE CONTRÔLE ━━━━━━
          if (_availableTypes.isNotEmpty || _selectedType != null)
            SizedBox(
              height: 34,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  AdminFilterPill(
                    label: 'Tous',
                    active: _selectedType == null,
                    onTap: () {
                      setState(() => _selectedType = null);
                      _load();
                    },
                  ),
                  const SizedBox(width: 6),
                  for (final code in [
                    ..._availableTypes,
                    if (_selectedType != null &&
                        !_availableTypes.contains(_selectedType))
                      _selectedType!,
                  ]) ...[
                    AdminFilterPill(
                      label:
                          '${ControlType.fromCode(code).emoji} ${ControlType.fromCode(code).label}',
                      active: _selectedType == code,
                      onTap: () {
                        setState(() => _selectedType = code);
                        _load();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 12),

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
                : (filteredByTerm.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: AppColors.adminPrimary,
                        onRefresh: _load,
                        child: ListView(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              20, 0, 20, 20),
                          children: [
                            // Si filtre actif → vue plate
                            if (_selectedType != null)
                              ...filteredByTerm.map(_buildEntryTile)
                            else
                              // Sinon → groupement par type
                              for (final t in types) ...[
                                _SectionHeader(controlTypeCode: t),
                                const SizedBox(height: 6),
                                ...byType[t]!.map(_buildEntryTile),
                                const SizedBox(height: 14),
                              ],
                          ],
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  /// Michel — Export Excel du relevé de l'élève (respecte le filtre terme).
  Future<void> _exportExcel(
    List<StudentReleveEntry> entries,
    List<AcademicTerm> terms,
  ) async {
    final svc = context.read<EstablishmentService>();
    final school = svc.currentEstablishment;
    if (school == null) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune note à exporter.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Génération du fichier Excel…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final adminNotes = entries.map((e) {
        final note20 = e.totalPoints > 0
            ? (e.totalScore / e.totalPoints) * 20
            : 0.0;
        return AdminStudentNote(
          copyId: e.copyId,
          student: widget.studentName,
          studentRef: widget.studentRef,
          className: e.className ?? '—',
          matiere: e.examType != null
              ? ExamType.fromCode(e.examType).label
              : e.examTitle,
          teacher: e.teacherName,
          note: double.parse(note20.toStringAsFixed(2)),
          date: e.publishedAt ?? DateTime.now(),
          noteLevel: AdminStudentNote.levelFor(note20.toDouble()),
        );
      }).toList();

      final term = (_selectedTermIndex >= 0 && _selectedTermIndex < terms.length)
          ? terms[_selectedTermIndex]
          : null;

      final exporter = AdminExportService();
      final file = await exporter.exportCasierExcel(
        establishment: school,
        notes: adminNotes,
        term: term,
      );
      await exporter.shareFile(
        file,
        text: 'Relevé ${widget.studentName} — ${school.name}',
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export : $err'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildEntryTile(StudentReleveEntry e) {
    final note20 = e.totalPoints > 0
        ? (e.totalScore / e.totalPoints) * 20
        : 0.0;
    final color = _noteColor(note20.toDouble());
    final df = DateFormat('d MMM y', 'fr_FR');
    final ct = ControlType.fromCode(e.controlType);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                ct.emoji,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.examTitle,
                    style: AppFonts.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${e.className ?? "—"} · ${e.teacherName}'
                    '${e.publishedAt != null ? " · ${df.format(e.publishedAt!.toLocal())}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 60,
              child: Text(
                '${note20.toStringAsFixed(note20 == note20.roundToDouble() ? 0 : 1)}/20',
                textAlign: TextAlign.right,
                style: AppFonts.fraunces(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 36,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              'Aucune note',
              style: AppFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedType == null
                  ? 'Aucune note pour cet élève.'
                  : 'Aucune note pour ce type de contrôle.\nChoisissez « Tous » pour voir l\'ensemble.',
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

class _SectionHeader extends StatelessWidget {
  final String controlTypeCode;
  const _SectionHeader({required this.controlTypeCode});

  @override
  Widget build(BuildContext context) {
    final ct = ControlType.fromCode(controlTypeCode);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Text(
            ct.emoji,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            ct.label.toUpperCase(),
            style: AppFonts.mono(
              fontSize: 10,
              color: AppColors.adminPrimary,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(
              color: AppColors.borderSubtle,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}
