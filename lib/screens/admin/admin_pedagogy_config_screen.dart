import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// Écran de configuration pédagogique de l'établissement.
///
/// L'admin y saisit :
///   • Les dates des trimestres (ou semestres) de l'année scolaire
///   • Les coefficients par matière utilisés pour les moyennes
///
/// Tout est persisté dans `establishments.config` (JSONB).
class AdminPedagogyConfigScreen extends StatefulWidget {
  const AdminPedagogyConfigScreen({super.key});

  @override
  State<AdminPedagogyConfigScreen> createState() =>
      _AdminPedagogyConfigScreenState();
}

class _AdminPedagogyConfigScreenState
    extends State<AdminPedagogyConfigScreen> {
  late List<_TermDraft> _terms;
  late Map<String, double> _coefficients;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final svc = context.read<EstablishmentService>();
    final cfg = svc.currentEstablishment?.config ??
        const EstablishmentConfig();
    _terms = cfg.terms
        .map((t) => _TermDraft(
              name: t.name,
              start: t.start,
              end: t.end,
            ))
        .toList();
    _coefficients = Map<String, double>.from(cfg.coefficients);
  }

  Future<void> _save() async {
    // Validation
    for (final t in _terms) {
      if (t.name.trim().isEmpty) {
        _snack('Chaque période doit avoir un nom.');
        return;
      }
      if (!t.end.isAfter(t.start)) {
        _snack(
            'La fin de "${t.name}" doit être après son début.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final svc = context.read<EstablishmentService>();
      final newConfig = (svc.currentEstablishment?.config ??
              const EstablishmentConfig())
          .copyWith(
        terms: _terms
            .map((t) => AcademicTerm(
                  name: t.name.trim(),
                  start: t.start,
                  end: t.end,
                ))
            .toList(),
        coefficients: _coefficients,
      );
      await svc.updateConfig(newConfig);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration enregistrée.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addDefaultTerms() {
    // Année scolaire qui contient la date actuelle.
    final now = DateTime.now();
    final yearStart = now.month >= 9 ? now.year : now.year - 1;
    setState(() {
      _terms = [
        _TermDraft(
          name: 'Trimestre 1',
          start: DateTime(yearStart, 9, 15),
          end: DateTime(yearStart, 12, 20),
        ),
        _TermDraft(
          name: 'Trimestre 2',
          start: DateTime(yearStart + 1, 1, 5),
          end: DateTime(yearStart + 1, 3, 28),
        ),
        _TermDraft(
          name: 'Trimestre 3',
          start: DateTime(yearStart + 1, 4, 13),
          end: DateTime(yearStart + 1, 6, 30),
        ),
      ];
    });
  }

  Future<void> _addTerm() async {
    final last = _terms.isNotEmpty ? _terms.last.end : DateTime.now();
    setState(() {
      _terms.add(_TermDraft(
        name: 'Période ${_terms.length + 1}',
        start: last.add(const Duration(days: 1)),
        end: last.add(const Duration(days: 90)),
      ));
    });
  }

  void _removeTerm(int i) {
    setState(() => _terms.removeAt(i));
  }

  Future<void> _addSubject() async {
    final name = await _showSubjectDialog();
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _coefficients[name.trim()] = 1.0;
    });
  }

  Future<String?> _showSubjectDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Nouvelle matière',
          style: AppFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ex : Mathématiques',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(
              'Ajouter',
              style: TextStyle(color: AppColors.adminPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBg,
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    AdminBackButton(
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text(
                      'PARAMÈTRES',
                      style: AppFonts.mono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configuration pédagogique',
                      style: AppFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dates des trimestres et coefficients par matière.',
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ━━━━━━ TRIMESTRES ━━━━━━
                    _sectionHeader(
                      label: 'TRIMESTRES / SEMESTRES',
                      action: _terms.isEmpty
                          ? TextButton.icon(
                              onPressed: _addDefaultTerms,
                              icon: const Icon(
                                Icons.auto_awesome_outlined,
                                size: 14,
                              ),
                              label: Text(
                                'Auto',
                                style: AppFonts.mono(
                                  fontSize: 10,
                                  color: AppColors.adminPrimary,
                                  letterSpacing: 1,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                    if (_terms.isEmpty)
                      _emptyCard(
                        message:
                            'Aucune période définie. Saisissez vos trimestres ou cliquez "Auto" pour la structure standard (T1 : sept-déc · T2 : jan-mars · T3 : avr-juin).',
                      )
                    else
                      ..._terms.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TermEditor(
                            term: t,
                            onChanged: () => setState(() {}),
                            onRemove: () => _removeTerm(i),
                          ),
                        );
                      }),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _addTerm,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.adminPrimary
                              .withValues(alpha: 0.35),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: AppColors.adminPrimary,
                      ),
                      label: Text(
                        'AJOUTER UNE PÉRIODE',
                        style: AppFonts.mono(
                          fontSize: 11,
                          color: AppColors.adminPrimary,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ━━━━━━ COEFFICIENTS ━━━━━━
                    _sectionHeader(label: 'COEFFICIENTS PAR MATIÈRE'),
                    const SizedBox(height: 10),
                    if (_coefficients.isEmpty)
                      _emptyCard(
                        message:
                            'Aucune matière configurée. Sans coefficient, les moyennes sont arithmétiques. Ajoutez vos matières et leurs poids.',
                      )
                    else
                      ..._coefficients.entries.toList().map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CoefficientRow(
                            subject: entry.key,
                            value: entry.value,
                            onChanged: (v) {
                              setState(() {
                                _coefficients[entry.key] = v;
                              });
                            },
                            onRemove: () {
                              setState(() {
                                _coefficients.remove(entry.key);
                              });
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _addSubject,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.adminPrimary
                              .withValues(alpha: 0.35),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: AppColors.adminPrimary,
                      ),
                      label: Text(
                        'AJOUTER UNE MATIÈRE',
                        style: AppFonts.mono(
                          fontSize: 11,
                          color: AppColors.adminPrimary,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                  ],
                ),
              ),
              // ━━━━━━ SAVE BUTTON ━━━━━━
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: AdminGradientButton(
                  label: _saving ? 'ENREGISTREMENT…' : 'ENREGISTRER',
                  icon: _saving ? null : Icons.check_rounded,
                  onTap: _saving ? () {} : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({required String label, Widget? action}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppFonts.mono(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _emptyCard({required String message}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: AppFonts.sans(
          fontSize: 12,
          color: AppColors.textMuted,
          height: 1.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal models / widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TermDraft {
  String name;
  DateTime start;
  DateTime end;
  _TermDraft({
    required this.name,
    required this.start,
    required this.end,
  });
}

class _TermEditor extends StatelessWidget {
  final _TermDraft term;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _TermEditor({
    required this.term,
    required this.onChanged,
    required this.onRemove,
  });

  String _fmt(DateTime d) {
    const m = [
      'janv', 'févr', 'mars', 'avr', 'mai', 'juin',
      'juil', 'août', 'sept', 'oct', 'nov', 'déc',
    ];
    return '${d.day.toString().padLeft(2, "0")} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate(
    BuildContext context, {
    required bool isStart,
  }) async {
    final initial = isStart ? term.start : term.end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.adminPrimary,
            onPrimary: Colors.white,
            surface: AppColors.card,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    if (isStart) {
      term.start = picked;
    } else {
      term.end = picked;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: term.name,
                  onChanged: (v) {
                    term.name = v;
                    onChanged();
                  },
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Nom de la période',
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _dateChip(
                  context,
                  label: 'Début',
                  value: _fmt(term.start),
                  onTap: () => _pickDate(context, isStart: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateChip(
                  context,
                  label: 'Fin',
                  value: _fmt(term.end),
                  onTap: () => _pickDate(context, isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateChip(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.adminPrimary.withValues(alpha: 0.08),
          border: Border.all(
            color: AppColors.adminPrimary.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 12,
              color: AppColors.adminPrimary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: AppFonts.mono(
                      fontSize: 8,
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    value,
                    style: AppFonts.sans(
                      fontSize: 11.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoefficientRow extends StatelessWidget {
  final String subject;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onRemove;

  const _CoefficientRow({
    required this.subject,
    required this.value,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subject,
              style: AppFonts.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: value > 0.5 ? () => onChanged(value - 0.5) : null,
            icon: const Icon(Icons.remove_rounded, size: 16),
            color: AppColors.adminPrimary,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
          Container(
            width: 44,
            alignment: Alignment.center,
            child: Text(
              value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.adminPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: value < 10 ? () => onChanged(value + 0.5) : null,
            icon: const Icon(Icons.add_rounded, size: 16),
            color: AppColors.adminPrimary,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: AppColors.danger,
            ),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
