import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_models.dart';
import 'admin_student_releve_screen.dart';
import 'admin_widgets.dart';

/// A6 — Recherche élève par nom/classe/matière.
/// Indexe les vraies copies de l'établissement.
class AdminSearchStudentScreen extends StatefulWidget {
  const AdminSearchStudentScreen({super.key});

  @override
  State<AdminSearchStudentScreen> createState() =>
      _AdminSearchStudentScreenState();
}

class _AdminSearchStudentScreenState extends State<AdminSearchStudentScreen> {
  final _nameCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _classChip = '';
  String _matiereChip = '';
  String _controlTypeChip = ''; // code de ControlType ou ''

  List<AdminStudentNote> _allNotes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIndex());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIndex() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final notes = await svc.loadAllNotes();
    if (!mounted) return;
    setState(() {
      _allNotes = notes;
      _loading = false;
    });
  }

  /// Liste unique des classes présentes dans le casier.
  List<String> get _classes {
    final set = <String>{};
    for (final n in _allNotes) {
      if (n.className.isNotEmpty && n.className != '—') {
        set.add(n.className);
      }
    }
    return set.toList()..sort();
  }

  /// Liste unique des matières présentes.
  List<String> get _matieres {
    final set = <String>{};
    for (final n in _allNotes) {
      if (n.matiere.isNotEmpty && n.matiere != '—') {
        set.add(n.matiere);
      }
    }
    return set.toList()..sort();
  }

  /// Élèves récemment notés (dédup par couple nom + matricule).
  /// Deux élèves homonymes mais de matricules distincts apparaissent
  /// comme deux entrées séparées.
  List<_StudentRef> get _recent {
    final seen = <String>{};
    final result = <_StudentRef>[];
    for (final n in _allNotes) {
      if (seen.contains(n.studentKey)) continue;
      seen.add(n.studentKey);
      final initial =
          n.student.isNotEmpty ? n.student[0].toUpperCase() : '?';
      final keys = ['blue', 'green', 'purple', 'amber'];
      final hashSource = n.studentKey;
      final key = keys[hashSource.hashCode.abs() % keys.length];
      result.add(_StudentRef(
        name: n.student,
        ref: n.studentRef,
        className: n.className,
        initial: initial,
        avatarKey: key,
      ));
      if (result.length >= 8) break;
    }
    return result;
  }

  void _openStudentCasier(BuildContext context, String name, String? ref,
      String className, String initial, String avatarKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminStudentReleveScreen(
          studentName: name,
          studentRef: ref,
          initialControlType:
              _controlTypeChip.isNotEmpty ? _controlTypeChip : null,
        ),
      ),
    );
  }

  void _runSearch() {
    final name = _nameCtrl.text.trim();
    final ref = _refCtrl.text.trim();
    if (name.isEmpty && ref.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saisissez un nom ou un matricule.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Cherche dans l'index local. Si matricule fourni → match exact.
    final qName = name.toLowerCase();
    final qRef = ref.toLowerCase();
    final matches = _allNotes.where((n) {
      if (qName.isNotEmpty && !n.student.toLowerCase().contains(qName)) {
        return false;
      }
      if (qRef.isNotEmpty &&
          (n.studentRef ?? '').toLowerCase() != qRef) {
        return false;
      }
      if (_classChip.isNotEmpty && n.className != _classChip) return false;
      if (_matiereChip.isNotEmpty && n.matiere != _matiereChip) {
        return false;
      }
      return true;
    }).toList();

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aucun élève trouvé '
            '${name.isNotEmpty ? "pour \"$name\"" : ""}'
            '${name.isNotEmpty && ref.isNotEmpty ? " · " : ""}'
            '${ref.isNotEmpty ? "matricule \"$ref\"" : ""}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Dédoublonne les matches par couple nom+matricule
    final uniqueKeys = <String>{};
    final uniqueStudents = <AdminStudentNote>[];
    for (final m in matches) {
      if (uniqueKeys.add(m.studentKey)) uniqueStudents.add(m);
    }

    // Si on a plusieurs élèves distincts (homonymes sans matricule de
    // désambiguïsation), on affiche un sélecteur pour que l'admin choisisse.
    if (uniqueStudents.length > 1) {
      _showDisambiguationSheet(uniqueStudents);
      return;
    }

    final first = uniqueStudents.first;
    final initial = first.student.isNotEmpty
        ? first.student[0].toUpperCase()
        : '?';
    final keys = ['blue', 'green', 'purple', 'amber'];
    final key = keys[first.studentKey.hashCode.abs() % keys.length];
    _openStudentCasier(
      context,
      first.student,
      first.studentRef,
      first.className,
      initial,
      key,
    );
  }

  /// Affiche un bottom sheet pour choisir parmi plusieurs élèves homonymes.
  void _showDisambiguationSheet(List<AdminStudentNote> students) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plusieurs élèves trouvés',
              style: AppFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choisissez le bon (le matricule distingue les homonymes).',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            ...students.map((s) {
              final initial = s.student.isNotEmpty
                  ? s.student[0].toUpperCase()
                  : '?';
              final keys = ['blue', 'green', 'purple', 'amber'];
              final key = keys[s.studentKey.hashCode.abs() % keys.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openStudentCasier(
                        context,
                        s.student,
                        s.studentRef,
                        s.className,
                        initial,
                        key,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: AppColors.borderSubtle),
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          AdminAvatar(
                            initials: initial,
                            avatarKey: key,
                            size: 36,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.student,
                                  style: AppFonts.sans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${s.className} · '
                                  '${s.studentRef?.isNotEmpty == true ? "Mat. ${s.studentRef}" : "Pas de matricule"}',
                                  style: AppFonts.mono(
                                    fontSize: 9.5,
                                    color: AppColors.textMuted,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminBackButton(
                    onTap: () => Navigator.maybePop(context)),

                const SizedBox(height: 16),

                Text(
                  'CASIER',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rechercher un élève',
                  style: AppFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loading
                      ? 'Chargement du casier…'
                      : '${_allNotes.length} note${_allNotes.length != 1 ? "s" : ""} indexée${_allNotes.length != 1 ? "s" : ""}',
                  style: AppFonts.sans(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),

                const SizedBox(height: 22),

                // ━━━━━━ INPUT NOM ━━━━━━
                Text(
                  'NOM DE L\'ÉLÈVE',
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: AppColors.adminPrimary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  onSubmitted: (_) => _runSearch(),
                  style: AppFonts.sans(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: _searchInputDecoration(
                    hint: 'Ex : Ali Mansouri',
                    icon: Icons.search_rounded,
                  ),
                ),

                const SizedBox(height: 12),

                // ━━━━━━ INPUT MATRICULE ━━━━━━
                Text(
                  'MATRICULE (recommandé si homonymes)',
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: AppColors.adminPrimary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _refCtrl,
                  onSubmitted: (_) => _runSearch(),
                  style: AppFonts.sans(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: _searchInputDecoration(
                    hint: 'Ex : 12345',
                    icon: Icons.badge_outlined,
                  ),
                ),

                const SizedBox(height: 18),

                if (_classes.isNotEmpty) ...[
                  Text(
                    'CLASSE (optionnel)',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.adminPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _classes
                        .map((c) => AdminFilterPill(
                              label: c,
                              active: _classChip == c,
                              onTap: () => setState(
                                () => _classChip = _classChip == c ? '' : c,
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],

                if (_matieres.isNotEmpty) ...[
                  Text(
                    'MATIÈRE (optionnel)',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.adminPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _matieres
                        .map((m) => AdminFilterPill(
                              label: m,
                              active: _matiereChip == m,
                              onTap: () => setState(
                                () => _matiereChip =
                                    _matiereChip == m ? '' : m,
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],

                Text(
                  'TYPE DE CONTRÔLE (optionnel)',
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: AppColors.adminPrimary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ControlType.values.map((ct) {
                    final active = _controlTypeChip == ct.code;
                    return AdminFilterPill(
                      label: '${ct.emoji} ${ct.label}',
                      active: active,
                      onTap: () => setState(
                        () => _controlTypeChip = active ? '' : ct.code,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                AdminGradientButton(
                  label: 'RECHERCHER',
                  icon: Icons.search_rounded,
                  onTap: _runSearch,
                ),

                const SizedBox(height: 28),

                // ━━━━━━ RÉCENTS ━━━━━━
                Text(
                  'NOTÉS RÉCEMMENT',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
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
                  )
                else if (_recent.isEmpty)
                  _emptyRecent()
                else
                  ..._recent.map((r) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: AppColors.card,
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          onTap: () => _openStudentCasier(
                            context,
                            r.name,
                            r.ref,
                            r.className,
                            r.initial,
                            r.avatarKey,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.borderSubtle),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: Row(
                              children: [
                                AdminAvatar(
                                  initials: r.initial,
                                  avatarKey: r.avatarKey,
                                  size: 36,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.name,
                                        style: AppFonts.sans(
                                          fontSize: 12.5,
                                          fontWeight:
                                              FontWeight.w500,
                                          color:
                                              AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${r.className.toUpperCase()}'
                                        '${r.ref?.isNotEmpty == true ? "  ·  MAT. ${r.ref}" : ""}',
                                        style: AppFonts.mono(
                                          fontSize: 9,
                                          color: AppColors.textMuted,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.textMuted,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _searchInputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppFonts.sans(
        fontSize: 13,
        color: AppColors.textMuted.withValues(alpha: 0.4),
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: AppColors.adminPrimary,
      ),
      filled: true,
      fillColor: AppColors.adminPrimary.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(
          color: AppColors.adminPrimary.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(
          color: AppColors.adminPrimary.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(
            color: AppColors.adminPrimary, width: 1.5),
      ),
    );
  }

  Widget _emptyRecent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Icon(Icons.history_rounded,
              size: 24, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            'Aucun élève noté pour l\'instant',
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentRef {
  final String name;
  final String? ref;
  final String className;
  final String initial;
  final String avatarKey;
  const _StudentRef({
    required this.name,
    this.ref,
    required this.className,
    required this.initial,
    required this.avatarKey,
  });
}
