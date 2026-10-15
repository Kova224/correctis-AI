import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../models/notification.dart';
import '../../services/admin_export_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_search_student_screen.dart';
import 'admin_widgets.dart';

/// A3 — Casier numérique central (vue Admin), navigation hiérarchique :
///   Niveau 1 : liste des profs qui ont envoyé des notes
///   Niveau 2 : leurs classes
///   Niveau 3 : notes regroupées par type de contrôle (DS, Examen, Bac blanc…)
class AdminCasierBody extends StatefulWidget {
  const AdminCasierBody({super.key});

  @override
  State<AdminCasierBody> createState() => _AdminCasierBodyState();
}

class _AdminCasierBodyState extends State<AdminCasierBody> {
  List<TeacherCasierSummary> _teachers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final list = await svc.loadCasierByTeacher();
    if (!mounted) return;
    setState(() {
      _teachers = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ━━━━━━ HEADER ━━━━━━
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CASIER NUMÉRIQUE',
                      style: AppFonts.mono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Notes par enseignant',
                      style: AppFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_teachers.length} enseignant${_teachers.length != 1 ? "s" : ""} '
                      'ayant envoyé des notes',
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: AppColors.adminPrimary.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminSearchStudentScreen(),
                    ),
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.adminPrimary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_search_rounded,
                      color: AppColors.adminPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

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
              : (_teachers.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      color: AppColors.adminPrimary,
                      onRefresh: _load,
                      child: ListView.separated(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            20, 0, 20, 20),
                        itemCount: _teachers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = _teachers[i];
                          return _TeacherTile(
                            teacher: t,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    _TeacherClassesScreen(teacher: t),
                              ),
                            ),
                          );
                        },
                      ),
                    )),
        ),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_open_outlined,
              size: 38,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune note dans le casier',
              style: AppFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Les copies envoyées par vos enseignants\napparaîtront ici, regroupées par prof.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Actualiser',
                style: AppFonts.mono(
                  fontSize: 11,
                  color: AppColors.adminPrimary,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile niveau 1 : un enseignant
// ─────────────────────────────────────────────────────────────────────────────
class _TeacherTile extends StatelessWidget {
  final TeacherCasierSummary teacher;
  final VoidCallback onTap;
  const _TeacherTile({required this.teacher, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = teacher.teacherName.isNotEmpty
        ? teacher.teacherName[0].toUpperCase()
        : 'E';
    final lastDate = teacher.lastPublishedAt;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.15),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: AppFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.adminPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher.teacherName,
                      style: AppFonts.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${teacher.notesCount} note${teacher.notesCount != 1 ? "s" : ""} · '
                      '${teacher.classesCount} classe${teacher.classesCount != 1 ? "s" : ""}',
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (lastDate != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Dernier envoi ${DateFormat('d MMM y', 'fr_FR').format(lastDate.toLocal())}',
                        style: AppFonts.mono(
                          fontSize: 9.5,
                          color: AppColors.adminPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Niveau 2 : classes d'un enseignant
// ─────────────────────────────────────────────────────────────────────────────
class _TeacherClassesScreen extends StatefulWidget {
  final TeacherCasierSummary teacher;
  const _TeacherClassesScreen({required this.teacher});

  @override
  State<_TeacherClassesScreen> createState() =>
      _TeacherClassesScreenState();
}

class _TeacherClassesScreenState extends State<_TeacherClassesScreen> {
  List<TeacherClassSummary> _classes = const [];
  bool _loading = true;
  // Michel : true = récent → ancien (défaut) ; false = ancien → récent ; null = A-Z
  bool? _sortRecentDesc = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final list = await svc.loadTeacherClasses(widget.teacher.teacherUserId);
    if (!mounted) return;
    setState(() {
      _classes = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              widget.teacher.teacherName,
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Ses classes',
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
            onPressed: _exportAllTeacherNotesExcel,
          ),
          IconButton(
            tooltip: 'Exporter en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportAllTeacherNotesPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.adminPrimary),
                ),
              ),
            )
          : (_classes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Aucune classe trouvée pour cet enseignant.',
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Michel — toggle tri (Récent / Ancien / A-Z)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            'Trier :',
                            style: AppFonts.mono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _sortChip(
                            label: '↓ Récent',
                            active: _sortRecentDesc == true,
                            onTap: () => setState(() => _sortRecentDesc = true),
                          ),
                          const SizedBox(width: 6),
                          _sortChip(
                            label: '↑ Ancien',
                            active: _sortRecentDesc == false,
                            onTap: () => setState(() => _sortRecentDesc = false),
                          ),
                          const SizedBox(width: 6),
                          _sortChip(
                            label: 'A → Z',
                            active: _sortRecentDesc == null,
                            onTap: () => setState(() => _sortRecentDesc = null),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.adminPrimary,
                        onRefresh: _load,
                        child: ListView.separated(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding:
                              const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          itemCount: _sortedClasses.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = _sortedClasses[i];
                            return _ClassTile(
                              cls: c,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _ClassControlTypesScreen(
                                    teacher: widget.teacher,
                                    cls: c,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                )),
    );
  }

  /// Michel — Liste des classes triées selon `_sortRecentDesc`.
  List<TeacherClassSummary> get _sortedClasses {
    final sorted = List<TeacherClassSummary>.from(_classes);
    if (_sortRecentDesc == null) {
      // Tri alphabétique
      sorted.sort((a, b) => a.className.compareTo(b.className));
    } else {
      // Tri par date de dernière note publiée
      sorted.sort((a, b) {
        final da = a.lastPublishedAt;
        final db = b.lastPublishedAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return _sortRecentDesc == true
            ? db.compareTo(da) // récent → ancien
            : da.compareTo(db); // ancien → récent
      });
    }
    return sorted;
  }

  Widget _sortChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.adminPrimary.withValues(alpha: 0.14)
              : AppColors.card,
          border: Border.all(
            color: active
                ? AppColors.adminPrimary.withValues(alpha: 0.4)
                : AppColors.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: AppFonts.mono(
            fontSize: 10,
            color: active
                ? AppColors.adminPrimary
                : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  /// Récupère toutes les notes du prof (toutes classes confondues)
  /// et déclenche l'export.
  Future<List<AdminStudentNote>> _teacherNotes() async {
    final svc = context.read<EstablishmentService>();
    final all = await svc.loadAllNotes();
    final target = widget.teacher.teacherName.trim().toLowerCase();
    return all.where((n) => n.teacher.trim().toLowerCase() == target).toList();
  }

  Future<void> _exportAllTeacherNotesExcel() async {
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
      final notes = await _teacherNotes();
      if (notes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune note à exporter.')),
        );
        return;
      }
      final exporter = AdminExportService();
      final file = await exporter.exportCasierExcel(
        establishment: school,
        notes: notes,
      );
      await exporter.shareFile(
        file,
        text: 'Notes de ${widget.teacher.teacherName} — ${school.name}',
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

  Future<void> _exportAllTeacherNotesPdf() async {
    final svc = context.read<EstablishmentService>();
    final school = svc.currentEstablishment;
    if (school == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Génération du fichier PDF…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final notes = await _teacherNotes();
      if (notes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune note à exporter.')),
        );
        return;
      }
      // Pour un rapport prof, on utilise le bulletin sur "l'ensemble des notes"
      // en passant le nom du prof comme "student" fictif (contexte de rapport).
      final exporter = AdminExportService();
      final file = await exporter.exportStudentBulletin(
        establishment: school,
        studentName: 'Rapport ${widget.teacher.teacherName}',
        className: 'Toutes classes',
        notes: notes,
      );
      await exporter.shareFile(
        file,
        text: 'Rapport ${widget.teacher.teacherName} — ${school.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export PDF : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _ClassTile extends StatelessWidget {
  final TeacherClassSummary cls;
  final VoidCallback onTap;
  const _ClassTile({required this.cls, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.class_outlined,
                  color: AppColors.adminPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cls.className,
                      style: AppFonts.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cls.notesCount} note${cls.notesCount != 1 ? "s" : ""} · '
                      '${cls.controlTypes.length} type${cls.controlTypes.length != 1 ? "s" : ""}',
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Niveau 3 : types de contrôle d'une classe d'un prof + notes
// ─────────────────────────────────────────────────────────────────────────────
class _ClassControlTypesScreen extends StatefulWidget {
  final TeacherCasierSummary teacher;
  final TeacherClassSummary cls;
  const _ClassControlTypesScreen({
    required this.teacher,
    required this.cls,
  });

  @override
  State<_ClassControlTypesScreen> createState() =>
      _ClassControlTypesScreenState();
}

class _ClassControlTypesScreenState
    extends State<_ClassControlTypesScreen> {
  String? _selectedType; // null = tous

  List<ClassNoteEntry> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final list = await svc.loadClassNotes(
      teacherUserId: widget.teacher.teacherUserId,
      className: widget.cls.className,
      controlType: _selectedType,
    );
    if (!mounted) return;
    setState(() {
      _notes = list;
      _loading = false;
    });
  }

  Color _noteColor(double note20) {
    if (note20 >= 14) return AppColors.profPrimary;
    if (note20 >= 10) return AppColors.primaryLight;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final allTypes = ['Tous', ...widget.cls.controlTypes];

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
              '${widget.teacher.teacherName} · ${widget.cls.className}',
              style: AppFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Notes par type de contrôle',
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
            onPressed: _exportClassNotesExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: allTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final code = allTypes[i];
                final isAll = code == 'Tous';
                final label = isAll
                    ? 'Tous'
                    : '${ControlType.fromCode(code).emoji} ${ControlType.fromCode(code).label}';
                final active = (_selectedType == null && isAll) ||
                    _selectedType == code;
                return AdminFilterPill(
                  label: label,
                  active: active,
                  onTap: () {
                    setState(() {
                      _selectedType = isAll ? null : code;
                    });
                    _load();
                  },
                );
              },
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
                : (_notes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'Aucune note pour ce filtre.',
                            style: AppFonts.sans(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.adminPrimary,
                        onRefresh: _load,
                        child: ListView.separated(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              20, 0, 20, 20),
                          itemCount: _notes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final n = _notes[i];
                            final note20 = n.totalPoints > 0
                                ? (n.totalScore / n.totalPoints) * 20
                                : 0;
                            final color = _noteColor(note20.toDouble());
                            final ct = ControlType.fromCode(n.controlType);

                            return Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(
                                    AppRadius.md),
                                border: Border.all(
                                    color: AppColors.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                n.studentName,
                                                style: AppFonts.sans(
                                                  fontSize: 12.5,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (n.studentRef?.isNotEmpty ==
                                                true) ...[
                                              const SizedBox(width: 4),
                                              Text(
                                                n.studentRef!,
                                                style: AppFonts.mono(
                                                  fontSize: 9,
                                                  color:
                                                      AppColors.adminPrimary,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          '${ct.emoji} ${ct.label} · ${n.examTitle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppFonts.sans(
                                            fontSize: 10,
                                            color: AppColors.textMuted,
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
                            );
                          },
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  /// Michel — Export Excel des notes de cette classe (avec filtre type
  /// contrôle actif si sélectionné).
  Future<void> _exportClassNotesExcel() async {
    final svc = context.read<EstablishmentService>();
    final school = svc.currentEstablishment;
    if (school == null) return;
    if (_notes.isEmpty) {
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
      // Convertit ClassNoteEntry → AdminStudentNote pour réutiliser l'exporter
      final adminNotes = _notes.map((n) {
        final note20 = n.totalPoints > 0
            ? (n.totalScore / n.totalPoints) * 20
            : 0.0;
        return AdminStudentNote(
          copyId: n.copyId,
          student: n.studentName,
          studentRef: n.studentRef,
          className: widget.cls.className,
          matiere: n.examType != null
              ? ExamType.fromCode(n.examType).label
              : n.examTitle,
          teacher: widget.teacher.teacherName,
          note: double.parse(note20.toStringAsFixed(2)),
          date: n.publishedAt ?? DateTime.now(),
          noteLevel: AdminStudentNote.levelFor(note20.toDouble()),
        );
      }).toList();

      final exporter = AdminExportService();
      final file = await exporter.exportCasierExcel(
        establishment: school,
        notes: adminNotes,
      );
      await exporter.shareFile(
        file,
        text:
            'Notes ${widget.teacher.teacherName} · ${widget.cls.className} — ${school.name}',
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
}
