import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/credits.dart';
import '../../models/exam.dart';
import '../../services/credits_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';

/// Nouveau flow d'invitation (retour Michel) — CRUD complet des comptes prof.
///
/// L'admin crée un slot avec :
///   - email école (attribué par l'école — peut différer de l'email perso)
///   - identifiant unique (choisi par l'admin, ex: LYC-MK-001)
///   - nom du prof
///   - matières attribuées (le prof ne pourra corriger que ces matières)
///
/// L'admin partage email + identifiant au prof (WhatsApp/SMS/verbal).
/// Le prof va dans son profil → "Mes écoles" → "+ Joindre une école".
class AdminTeacherSlotsScreen extends StatefulWidget {
  const AdminTeacherSlotsScreen({super.key});

  @override
  State<AdminTeacherSlotsScreen> createState() =>
      _AdminTeacherSlotsScreenState();
}

class _AdminTeacherSlotsScreenState extends State<AdminTeacherSlotsScreen> {
  List<TeacherSlot> _slots = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await context.read<EstablishmentService>().loadTeacherSlots();
    // Michel : rafraîchit quotas + pool pour afficher reçu/utilisé/restant
    // à côté de chaque prof et le pool dispo cohérent après attribution.
    await Future.wait([
      context.read<CreditsService>().refreshTeacherQuotas(),
      context.read<CreditsService>().refreshWallet(),
    ]);
    if (!mounted) return;
    setState(() {
      _slots = list;
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
              'Comptes enseignants',
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_slots.length} compte${_slots.length != 1 ? "s" : ""}',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.adminPrimary),
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColors.adminPrimary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  // Bandeau explicatif
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          AppColors.adminPrimary.withValues(alpha: 0.06),
                      border: Border.all(
                        color: AppColors.adminPrimary
                            .withValues(alpha: 0.22),
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
                            'Créez un compte pour chaque enseignant : email + identifiant unique. '
                            'Communiquez ces 2 valeurs au prof, qui utilisera "Mes écoles" pour rejoindre.',
                            style: AppFonts.sans(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_slots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Column(
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded,
                              size: 40, color: AppColors.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            'Aucun compte créé',
                            style: AppFonts.fraunces(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cliquez sur "Créer un compte prof" ci-dessous.',
                            style: AppFonts.sans(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Consumer<CreditsService>(
                      builder: (context, credits, _) => Column(
                        children: _slots.map((s) {
                          TeacherQuota? q;
                          if (s.isClaimed) {
                            try {
                              q = credits.teacherQuotas.firstWhere(
                                (x) => x.userId == s.claimedByUserId,
                              );
                            } catch (_) {}
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SlotCard(
                              slot: s,
                              quota: q,
                              onShareCredentials: () =>
                                  _shareCredentials(s),
                              onEdit: () => _openEditSheet(s),
                              onToggleSuspend: () => _toggleSuspend(s),
                              onDelete: () => _confirmDelete(s),
                              onAttributeCredits: s.isClaimed
                                  ? () => _openAttributeCreditsDialog(s)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Ink(
              decoration: BoxDecoration(
                gradient: AppColors.adminGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.adminPrimary.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => _openCreateSheet(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_add_alt_1_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '+ CRÉER UN COMPTE PROF',
                        style: AppFonts.mono(
                          fontSize: 11,
                          color: Colors.white,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareCredentials(TeacherSlot s) async {
    final msg =
        'Bienvenue sur Correctis ! Voici tes accès pour rejoindre l\'école :\n\n'
        'Email école : ${s.schoolEmail}\n'
        'Identifiant : ${s.joinCode}\n\n'
        'Ouvre l\'app → Profil → Mes écoles → "+ Joindre une école" et '
        'saisis ces 2 valeurs.';
    await Share.share(msg);
  }

  Future<void> _openCreateSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SlotFormSheet(),
    );
    if (saved == true) await _load();
  }

  Future<void> _openEditSheet(TeacherSlot slot) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SlotFormSheet(existing: slot),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggleSuspend(TeacherSlot s) async {
    final newStatus = s.status == 'suspended'
        ? (s.claimedByUserId != null ? 'claimed' : 'pending')
        : 'suspended';
    try {
      await context.read<EstablishmentService>().toggleSlotStatus(
            slotId: s.slotId,
            newStatus: newStatus,
          );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'suspended'
                ? '${s.teacherName} suspendu.'
                : '${s.teacherName} réactivé.',
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
        ),
      );
    }
  }

  /// Attribue N crédits en plus au prof qui a rejoint ce slot.
  /// Si le pool n'a pas assez, on l'indique (l'achat se fait hors de l'app).
  Future<void> _openAttributeCreditsDialog(TeacherSlot slot) async {
    final creditsSvc = context.read<CreditsService>();
    // Attend d'avoir les quotas à jour
    await creditsSvc.refreshTeacherQuotas();
    await creditsSvc.refreshWallet();

    if (!mounted) return;

    // Trouve le quota actuel du prof
    TeacherQuota? current;
    try {
      current = creditsSvc.teacherQuotas
          .firstWhere((q) => q.userId == slot.claimedByUserId);
    } catch (_) {
      current = null;
    }
    final currentLimit = current?.limitTotal ?? 0;
    final currentUsed = current?.used ?? 0;
    // Michel : c'est le dispo qui compte (pool physique - engagés)
    final poolAvailable = creditsSvc.orgWallet.availableCredits;
    final poolEngaged = creditsSvc.orgWallet.engagedCredits;

    final ctl = TextEditingController();

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Attribuer à ${slot.teacherName}',
          style: AppFonts.fraunces(
              fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogInfoRow(
                    'Reçu (quota)',
                    '$currentLimit',
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(height: 4),
                  _dialogInfoRow(
                    'Utilisés',
                    '$currentUsed',
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  _dialogInfoRow(
                    'Restant',
                    '${(currentLimit - currentUsed).clamp(0, currentLimit)}',
                    color: AppColors.profPrimary,
                  ),
                  const Divider(height: 12),
                  _dialogInfoRow(
                    'Pool dispo',
                    '$poolAvailable',
                    color: AppColors.adminPrimary,
                  ),
                  const SizedBox(height: 4),
                  _dialogInfoRow(
                    'Déjà engagés',
                    '$poolEngaged',
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'CRÉDITS À AJOUTER',
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.adminPrimary,
            ),
            onPressed: () {
              final n = int.tryParse(ctl.text.trim());
              if (n == null || n <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Saisis un nombre positif.')),
                );
                return;
              }
              Navigator.pop(ctx, n);
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    // Vérifie que le pool DISPO (physique - engagés) a assez de crédits.
    if (result > poolAvailable) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Pool insuffisant',
              style: AppFonts.fraunces(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          content: Text(
            'Il ne vous reste que $poolAvailable crédits disponibles dans '
            'le pool ($poolEngaged déjà engagés chez vos profs). Vous '
            'voulez en attribuer $result.',
            style: AppFonts.sans(fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    // Attribution ADDITIVE : ajoute result au quota existant et engage
    // ces crédits côté pool (via la nouvelle RPC).
    try {
      await creditsSvc.attributeCreditsToTeacher(
          slot.claimedByUserId!, result);
      if (!mounted) return;
      final newTotal = currentLimit + result;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '+$result crédits attribués à ${slot.teacherName}. Quota : $currentUsed/$newTotal.'),
          backgroundColor: AppColors.adminPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Widget _dialogInfoRow(String label, String value, {required Color color}) {
    return Row(
      children: [
        Text(
          label,
          style: AppFonts.sans(fontSize: 11.5, color: AppColors.textMuted),
        ),
        const Spacer(),
        Text(
          value,
          style: AppFonts.mono(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(TeacherSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Supprimer le compte ${s.teacherName} ?',
            style: AppFonts.fraunces(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          s.isClaimed
              ? 'Le prof perdra l\'accès à cette école. Les notes déjà '
                  'publiées restent dans le casier selon la règle 3 jours.'
              : 'Ce compte en attente sera définitivement supprimé.',
          style: AppFonts.sans(fontSize: 12, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<EstablishmentService>()
          .deleteTeacherSlot(s.slotId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
// CARD SLOT PROF
// ══════════════════════════════════════════════════════════════════════════

/// Trio de pills "Reçu · Utilisé · Restant" pour un prof donné.
/// Si le quota est null (jamais attribué), affiche juste "Aucun crédit
/// attribué" — l'admin comprend qu'il faut cliquer sur "Attribuer".
class _QuotaChips extends StatelessWidget {
  final TeacherQuota? quota;
  const _QuotaChips({required this.quota});

  @override
  Widget build(BuildContext context) {
    if (quota == null || quota!.limitTotal == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 13, color: AppColors.warning),
            const SizedBox(width: 6),
            Text(
              'Aucun crédit attribué',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.warning,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      );
    }
    final q = quota!;
    final remaining = (q.limitTotal - q.used).clamp(0, q.limitTotal);
    return Row(
      children: [
        Expanded(
          child: _QuotaChip(
            label: 'REÇU',
            value: '${q.limitTotal}',
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuotaChip(
            label: 'UTILISÉ',
            value: '${q.used}',
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuotaChip(
            label: 'RESTANT',
            value: '$remaining',
            color: AppColors.profPrimary,
          ),
        ),
      ],
    );
  }
}

class _QuotaChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _QuotaChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.mono(
              fontSize: 8.5,
              color: color.withValues(alpha: 0.85),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final TeacherSlot slot;
  final TeacherQuota? quota; // null si slot pending ou sans quota attribué
  final VoidCallback onShareCredentials;
  final VoidCallback onEdit;
  final VoidCallback onToggleSuspend;
  final VoidCallback onDelete;
  final VoidCallback? onAttributeCredits; // null si slot pas encore claimed
  const _SlotCard({
    required this.slot,
    required this.onShareCredentials,
    required this.onEdit,
    required this.onToggleSuspend,
    required this.onDelete,
    this.quota,
    this.onAttributeCredits,
  });

  @override
  Widget build(BuildContext context) {
    final initials = slot.teacherName.isNotEmpty
        ? slot.teacherName[0].toUpperCase()
        : '?';
    Color statusColor;
    String statusLabel;
    switch (slot.status) {
      case 'claimed':
        statusColor = AppColors.profPrimary;
        statusLabel = 'ACTIF';
        break;
      case 'suspended':
        statusColor = AppColors.danger;
        statusLabel = 'SUSPENDU';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'EN ATTENTE';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
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
                      slot.teacherName,
                      style: AppFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slot.schoolEmail,
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: statusColor,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Identifiant + copier
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.borderSubtle),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  slot.joinCode,
                  style: AppFonts.mono(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                iconSize: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: slot.joinCode));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Identifiant ${slot.joinCode} copié.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded,
                    color: AppColors.textMuted),
                tooltip: 'Copier l\'identifiant',
              ),
              const Spacer(),
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: onShareCredentials,
                icon: const Icon(Icons.ios_share_rounded,
                    color: AppColors.adminPrimary),
                tooltip: 'Envoyer par WhatsApp / SMS',
              ),
            ],
          ),

          if (slot.matieres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: slot.matieres.map((code) {
                final t = ExamType.fromCode(code);
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        AppColors.profPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${t.emoji} ${t.label}',
                    style: AppFonts.sans(
                      fontSize: 10,
                      color: AppColors.profPrimary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Michel : reçu / utilisé / restant en un coup d'œil.
          if (slot.isClaimed) ...[
            const SizedBox(height: 10),
            _QuotaChips(quota: quota),
          ],

          // Michel : bouton "Attribuer crédits" bien visible sur les slots
          // déjà rejoints par un prof (claimed). Pour un slot pending, pas
          // d'attribution possible (le prof n'est pas encore là).
          if (slot.isClaimed && onAttributeCredits != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAttributeCredits,
                icon: const Icon(Icons.card_giftcard_rounded, size: 15),
                label: const Text('Attribuer des crédits'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.adminPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: AppFonts.mono(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.adminPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Éditer'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onToggleSuspend,
                style: TextButton.styleFrom(
                  foregroundColor: slot.isSuspended
                      ? AppColors.profPrimary
                      : AppColors.warning,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                    slot.isSuspended ? 'Réactiver' : 'Suspendre'),
              ),
              const Spacer(),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// FORM SHEET : CRÉER / ÉDITER UN SLOT
// ══════════════════════════════════════════════════════════════════════════

class _SlotFormSheet extends StatefulWidget {
  final TeacherSlot? existing;
  const _SlotFormSheet({this.existing});

  @override
  State<_SlotFormSheet> createState() => _SlotFormSheetState();
}

class _SlotFormSheetState extends State<_SlotFormSheet> {
  late final TextEditingController _emailCtl;
  late final TextEditingController _codeCtl;
  late final TextEditingController _nameCtl;
  late Set<String> _selectedMatieres;
  bool _submitting = false;
  String? _errorMsg;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _emailCtl = TextEditingController(text: widget.existing?.schoolEmail ?? '');
    _codeCtl = TextEditingController(text: widget.existing?.joinCode ?? '');
    _nameCtl = TextEditingController(text: widget.existing?.teacherName ?? '');
    _selectedMatieres = {...?widget.existing?.matieres};
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _codeCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtl.text.trim();
    final code = _codeCtl.text.trim();
    final name = _nameCtl.text.trim();
    if (email.isEmpty || code.isEmpty || name.isEmpty) {
      setState(() => _errorMsg =
          'Email, identifiant et nom sont obligatoires.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });
    try {
      final svc = context.read<EstablishmentService>();
      if (_isEdit) {
        await svc.updateTeacherSlot(
          slotId: widget.existing!.slotId,
          teacherName: name,
          matieres: _selectedMatieres.toList(),
          schoolEmail: email,
          joinCode: code,
        );
      } else {
        await svc.createTeacherSlot(
          schoolEmail: email,
          joinCode: code,
          teacherName: name,
          matieres: _selectedMatieres.toList(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMsg = 'Erreur : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 14),
            Text(
              _isEdit ? 'Éditer le compte' : 'Créer un compte prof',
              style: AppFonts.fraunces(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _isEdit
                  ? 'Modifie l\'email, l\'identifiant, le nom ou les matières attribuées.'
                  : 'Ces infos seront communiquées au prof pour qu\'il rejoigne l\'école.',
              style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4),
            ),
            const SizedBox(height: 18),
            _label('NOM DU PROF'),
            _textField(_nameCtl, hint: 'ex : Michael Kova'),
            const SizedBox(height: 12),
            _label('EMAIL ÉCOLE'),
            _textField(
              _emailCtl,
              hint: 'ex : math.michel@lycee-cote.fr',
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _label('IDENTIFIANT UNIQUE'),
            TextField(
              controller: _codeCtl,
              textCapitalization: TextCapitalization.characters,
              style: AppFonts.mono(
                fontSize: 15,
                color: AppColors.textPrimary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'ex : LYC-MK-001',
                hintStyle: AppFonts.mono(
                    fontSize: 15, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide:
                      const BorderSide(color: AppColors.borderSubtle),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choisis un code unique dans ton école — c\'est ce que le prof '
              'saisira pour rejoindre.',
              style: AppFonts.sans(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  height: 1.35),
            ),
            const SizedBox(height: 14),
            _label('MATIÈRES ATTRIBUÉES'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ExamType.values.map((t) {
                final selected = _selectedMatieres.contains(t.code);
                return InkWell(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedMatieres.remove(t.code);
                    } else {
                      _selectedMatieres.add(t.code);
                    }
                  }),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.profPrimary.withValues(alpha: 0.14)
                          : AppColors.card,
                      border: Border.all(
                        color: selected
                            ? AppColors.profPrimary.withValues(alpha: 0.5)
                            : AppColors.borderSubtle,
                      ),
                      borderRadius:
                          BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${t.emoji} ${t.label}',
                          style: AppFonts.sans(
                            fontSize: 11.5,
                            color: selected
                                ? AppColors.profPrimary
                                : AppColors.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.check_rounded,
                              color: AppColors.profPrimary, size: 12),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text(
              'Le prof ne pourra corriger que les copies de ces matières '
              'dans cette école.',
              style: AppFonts.sans(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  height: 1.35),
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.30)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  _errorMsg!,
                  style: AppFonts.sans(
                      fontSize: 11.5, color: AppColors.textPrimary),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: AppColors.adminGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: _submitting ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              _isEdit
                                  ? 'ENREGISTRER'
                                  : '+ CRÉER LE COMPTE',
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
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Annuler',
                  style: AppFonts.sans(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: AppFonts.mono(
        fontSize: 10,
        color: AppColors.textMuted,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _textField(
    TextEditingController ctl, {
    required String hint,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctl,
      keyboardType: keyboard,
      style: AppFonts.sans(fontSize: 13.5, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppFonts.sans(fontSize: 12.5, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
      ),
    );
  }
}
