import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/credits.dart';
import '../../services/credits_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';

/// Écran admin "Crédits Établissement" (cf. maquette EduCorrect — écran A1).
///
/// Affiche :
///   - Pool mutualisé (barre violette) + jauge / pack actuel / expiration
///   - Liste des profs avec leur quota individuel (avec édition au tap)
///   (Option B : l'achat de packs se fait hors de l'app — règle Google Play.)
class AdminCreditsScreen extends StatefulWidget {
  const AdminCreditsScreen({super.key});

  @override
  State<AdminCreditsScreen> createState() => _AdminCreditsScreenState();
}

class _AdminCreditsScreenState extends State<AdminCreditsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = context.read<CreditsService>();
    await Future.wait([
      svc.refreshWallet(),
      svc.refreshTeacherQuotas(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CreditsService>();
    final estab = context.watch<EstablishmentService>();
    final orgWallet = svc.orgWallet;
    final quotas = svc.teacherQuotas;
    final schoolName = estab.currentEstablishment?.name ?? 'Mon établissement';

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
              'Crédits établissement',
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              schoolName.toUpperCase(),
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.adminPrimary,
                letterSpacing: 1.4,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.adminPrimary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            _OrgBalanceCard(wallet: orgWallet, loading: svc.loadingWallet),
            const SizedBox(height: 10),

            // Bouton principal — attribution rapide à un prof
            _AttributeCreditsButton(
              enabled: orgWallet.totalCredits > 0 && quotas.isNotEmpty,
              onTap: () => _openAttributionSheet(),
            ),
            const SizedBox(height: 14),

            // Bannière "Comment ça marche" pour clarifier le partage
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.adminPrimary.withValues(alpha: 0.06),
                border: Border.all(
                  color: AppColors.adminPrimary.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppColors.adminPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Attribuez à chaque enseignant le nombre de crédits '
                      'qu\'il peut consommer. Une fois épuisés, il ne pourra '
                      'plus corriger tant que vous ne lui en donnez pas de nouveaux.',
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'CRÉDITS PAR ENSEIGNANT',
                  style: AppFonts.mono(
                    fontSize: 9.5,
                    color: AppColors.textMuted,
                    letterSpacing: 1.6,
                  ),
                ),
                const Spacer(),
                Text(
                  '${quotas.length} prof${quotas.length != 1 ? "s" : ""}',
                  style: AppFonts.mono(
                    fontSize: 9.5,
                    color: AppColors.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (quotas.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.borderSubtle),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.person_off_outlined,
                      color: AppColors.textMuted,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aucun enseignant rattaché',
                      style: AppFonts.fraunces(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invitez des profs depuis l\'onglet « Profs ».',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...quotas.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TeacherQuotaRow(
                    quota: q,
                    onEdit: () => _editQuota(q),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editQuota(TeacherQuota q) async {
    final ctl = TextEditingController(
      text: q.limitTotal > 0 ? q.limitTotal.toString() : '',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Quota de ${q.displayName}',
          style: AppFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Définissez le nombre maximal de crédits que ce prof peut consommer sur le pool établissement (1 crédit = 1 copie jusqu\'à 8 pages).',
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '0 = aucune limite individuelle (dans la limite du pool global).',
              style: AppFonts.sans(
                fontSize: 11,
                color: AppColors.textMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limite (en crédits)',
                hintText: 'ex : 300',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Déjà consommé : ${q.used} crédits',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v == null || v < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Saisissez un nombre positif.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(ctx, v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.adminPrimary,
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    try {
      await context
          .read<CreditsService>()
          .updateTeacherQuota(q.userId, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 0
                ? 'Quota retiré pour ${q.displayName}.'
                : 'Quota de ${q.displayName} : $result crédits.',
          ),
          backgroundColor: AppColors.adminPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Bottom sheet : "Attribuer des crédits à un enseignant".
  /// Flow demandé par Michel :
  ///   1. Admin sélectionne un prof dans la liste
  ///   2. Saisit le nombre de crédits à AJOUTER (pas remplacer)
  ///   3. Envoie → le quota du prof augmente
  Future<void> _openAttributionSheet() async {
    final svc = context.read<CreditsService>();
    final quotas = List<TeacherQuota>.from(svc.teacherQuotas);
    if (quotas.isEmpty) return;

    TeacherQuota? selected = quotas.first;
    final ctl = TextEditingController();

    final result = await showModalBottomSheet<_AttributionResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Attribuer des crédits',
                    style: AppFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ces crédits s\'ajouteront au quota actuel de l\'enseignant.',
                    style: AppFonts.sans(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 1. Sélection prof
                  Text(
                    'ENSEIGNANT',
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(color: AppColors.borderSubtle),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: ButtonTheme(
                        alignedDropdown: true,
                        child: DropdownButton<TeacherQuota>(
                          value: selected,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          items: quotas
                              .map((q) => DropdownMenuItem(
                                    value: q,
                                    child: Text(
                                      q.hasLimit
                                          ? '${q.displayName} · ${q.used}/${q.limitTotal}'
                                          : q.displayName,
                                      style: AppFonts.sans(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setModalState(() => selected = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Nombre à attribuer
                  Text(
                    'CRÉDITS À ATTRIBUER',
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ctl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: AppFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.adminPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'ex : 10',
                      hintStyle: AppFonts.fraunces(
                        fontSize: 22,
                        color: AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide:
                            const BorderSide(color: AppColors.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (selected != null && selected!.hasLimit)
                    Text(
                      'Actuellement : ${selected!.used} utilisés sur '
                      '${selected!.limitTotal} · reste ${selected!.limitTotal - selected!.used}',
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    )
                  else
                    Text(
                      'Aucun quota défini pour l\'instant.',
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // 3. Bouton Envoyer
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: AppColors.adminGradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        onTap: () {
                          final n = int.tryParse(ctl.text.trim());
                          if (n == null || n <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Saisissez un nombre positif de crédits.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          if (selected == null) return;
                          Navigator.pop(
                            ctx,
                            _AttributionResult(
                              quota: selected!,
                              addAmount: n,
                            ),
                          );
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.send_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ENVOYER',
                                style: AppFonts.mono(
                                  fontSize: 12,
                                  color: Colors.white,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Annuler',
                        style: AppFonts.sans(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    // Additionne au quota existant
    final newTotal = result.quota.limitTotal + result.addAmount;
    try {
      await context
          .read<CreditsService>()
          .updateTeacherQuota(result.quota.userId, newTotal);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '+${result.addAmount} crédits attribués à ${result.quota.displayName}. '
            'Total : ${result.quota.used}/$newTotal.',
          ),
          backgroundColor: AppColors.adminPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Résultat interne du bottom sheet d'attribution.
class _AttributionResult {
  final TeacherQuota quota;
  final int addAmount;
  const _AttributionResult({required this.quota, required this.addAmount});
}

/// Bouton principal "Attribuer des crédits à un enseignant".
class _AttributeCreditsButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AttributeCreditsButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.adminPrimary.withValues(alpha: 0.12),
            border: Border.all(
              color: AppColors.adminPrimary.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.adminPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attribuer des crédits',
                          style: AppFonts.sans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.adminPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sélectionnez un prof et saisissez le nombre',
                          style: AppFonts.sans(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.adminPrimary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CARTE POOL ÉTABLISSEMENT
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _OrgBalanceCard extends StatelessWidget {
  final OrgCreditWallet wallet;
  final bool loading;
  const _OrgBalanceCard({required this.wallet, required this.loading});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMMM y', 'fr_FR');
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.adminPrimary.withValues(alpha: 0.14),
            AppColors.adminPrimary.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: AppColors.adminPrimary.withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (loading)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.adminPrimary),
                  ),
                )
              else
                Text(
                  _formatInt(wallet.totalCredits),
                  style: AppFonts.fraunces(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.adminPrimary,
                    height: 1.0,
                  ),
                ),
              const Spacer(),
              if (wallet.activePackTotal != null)
                Text(
                  '/ ${_formatInt(wallet.activePackTotal!)} crédits',
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (wallet.activePackTotal != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: wallet.progressFraction,
                minHeight: 6,
                backgroundColor: const Color(0x14FFFFFF),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.adminPrimary),
              ),
            ),
          const SizedBox(height: 6),
          if (wallet.activePackName != null && wallet.nextExpiration != null)
            Text(
              'Pack ${wallet.activePackName} · expire le ${df.format(wallet.nextExpiration!.toLocal())}',
              style: AppFonts.sans(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            )
          else
            Text(
              wallet.isEmpty
                  ? 'Aucun pack actif pour le moment.'
                  : '${wallet.activeLotsCount} lot${wallet.activeLotsCount != 1 ? "s" : ""} actif${wallet.activeLotsCount != 1 ? "s" : ""}',
              style: AppFonts.sans(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  static String _formatInt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// LIGNE QUOTA PROF
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _TeacherQuotaRow extends StatelessWidget {
  final TeacherQuota quota;
  final VoidCallback onEdit;
  const _TeacherQuotaRow({required this.quota, required this.onEdit});

  String get _initials {
    final parts = quota.displayName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color _barColor() {
    if (quota.blocked) return AppColors.danger;
    if (quota.progressFraction >= 0.75) return AppColors.warning;
    return AppColors.profPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final blocked = quota.blocked;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: blocked
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : AppColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6D28D9), Color(0xFFA78BFA)],
                  ),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: AppFonts.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quota.displayName,
                      style: AppFonts.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (quota.matiere != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        quota.matiere!,
                        style: AppFonts.mono(
                          fontSize: 9.5,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    if (quota.hasLimit) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: quota.progressFraction,
                          minHeight: 4,
                          backgroundColor:
                              const Color(0x14FFFFFF),
                          valueColor:
                              AlwaysStoppedAnimation(_barColor()),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (quota.hasLimit)
                    Text(
                      '${quota.used}/${quota.limitTotal}',
                      style: AppFonts.mono(
                        fontSize: 10.5,
                        color: blocked
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      ),
                    )
                  else
                    Text(
                      '∞',
                      style: AppFonts.mono(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (blocked) ...[
                    const SizedBox(height: 2),
                    Text(
                      'QUOTA ATTEINT',
                      style: AppFonts.mono(
                        fontSize: 7.5,
                        color: AppColors.danger,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      'MODIFIER',
                      style: AppFonts.mono(
                        fontSize: 7.5,
                        color: AppColors.adminPrimary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
