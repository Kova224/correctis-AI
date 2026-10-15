import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/credits.dart';
import '../../services/credits_service.dart';
import '../../theme/app_theme.dart';

/// Écran "Mes Crédits" (cf. maquette EduCorrect — écran C1).
///
/// Affiche :
///   - Solde global (l'achat se fait hors de l'app depuis l'option B —
///     règle Google Play : aucun bouton ni lien d'achat dans l'app)
///   - Lots actifs en FIFO (lot le plus proche d'expiration en haut)
///   - Activité récente (achats, corrections, remboursements)
class MyCreditsScreen extends StatefulWidget {
  const MyCreditsScreen({super.key});

  @override
  State<MyCreditsScreen> createState() => _MyCreditsScreenState();
}

class _MyCreditsScreenState extends State<MyCreditsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final svc = context.read<CreditsService>();
    await Future.wait([
      svc.refreshWallet(),
      svc.refreshLots(),
      svc.refreshHistory(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CreditsService>();
    final wallet = svc.wallet;
    final lots = svc.lots.where((l) => l.isActive).toList();
    final history = svc.history;

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
              'Mes crédits',
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'SOLDE ET HISTORIQUE',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.profPrimary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ━━━ CARTE SOLDE ━━━
            _BalanceCard(
              wallet: wallet,
              loading: svc.loadingWallet,
            ),

            // Michel : le pool école (total acheté par admin) n'est PAS
            // visible au prof. Le prof voit uniquement son quota individuel.

            // ━━━ QUOTA INDIVIDUEL (attribué par l'admin) ━━━
            if (svc.myTeacherQuota != null) ...[
              const SizedBox(height: 12),
              _MyQuotaCard(quota: svc.myTeacherQuota!),
            ],

            const SizedBox(height: 18),

            // ━━━ LOTS ACTIFS (FIFO) ━━━
            Text(
              'LOTS ACTIFS · ORDRE D\'EXPIRATION (FIFO)',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            if (lots.isEmpty)
              _emptyLotsCard()
            else
              ...lots.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: _LotCard(lot: l),
                  )),

            const SizedBox(height: 20),

            // ━━━ ACTIVITÉ RÉCENTE ━━━
            Text(
              'ACTIVITÉ RÉCENTE',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.borderSubtle),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  'Aucune activité pour l\'instant.',
                  style: AppFonts.sans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              ...history.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _HistoryRow(txn: t),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _emptyLotsCard() {
    return Container(
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
            Icons.inbox_outlined,
            color: AppColors.textMuted,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'Aucun crédit actif',
            style: AppFonts.fraunces(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Vos crédits apparaîtront ici.',
            textAlign: TextAlign.center,
            style: AppFonts.sans(
              fontSize: 11.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CARTE SOLDE PRINCIPAL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _BalanceCard extends StatelessWidget {
  final CreditWallet wallet;
  final bool loading;
  const _BalanceCard({
    required this.wallet,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.profPrimary.withValues(alpha: 0.14),
            AppColors.profPrimary.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.profPrimary),
              ),
            )
          else
            Text(
              wallet.totalCredits.toString(),
              style: AppFonts.fraunces(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: AppColors.profPrimary,
                height: 1.0,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'crédits disponibles',
            style: AppFonts.sans(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '≈ ${wallet.totalCredits} copie${wallet.totalCredits != 1 ? "s" : ""} de 8 pages max à corriger',
            style: AppFonts.sans(
              fontSize: 10.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CARTE POOL ÉTABLISSEMENT (si applicable)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _OrgPoolCard extends StatelessWidget {
  final OrgCreditWallet orgWallet;
  const _OrgPoolCard({required this.orgWallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.adminPrimary.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.adminPrimary.withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.adminPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.account_balance_rounded,
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
                  'Pool établissement disponible',
                  style: AppFonts.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.adminPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${orgWallet.totalCredits} crédits accessibles via votre école',
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CARTE QUOTA INDIVIDUEL (attribué par l'admin)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _MyQuotaCard extends StatelessWidget {
  final MyTeacherQuota quota;
  const _MyQuotaCard({required this.quota});

  @override
  Widget build(BuildContext context) {
    final hasLimit = quota.hasLimit;
    final remaining = quota.remaining;
    final low = hasLimit && remaining <= 3;
    final blocked = hasLimit && remaining == 0;
    final color = blocked
        ? AppColors.danger
        : (low ? AppColors.warning : AppColors.profPrimary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  blocked
                      ? Icons.block_rounded
                      : Icons.person_outline_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mon quota individuel',
                      style: AppFonts.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quota.establishmentName,
                      style: AppFonts.sans(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasLimit)
                Text(
                  '$remaining / ${quota.limitTotal}',
                  style: AppFonts.fraunces(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                )
              else
                Text(
                  'Aucun crédit attribué',
                  style: AppFonts.mono(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
          if (hasLimit) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: quota.progressFraction,
                minHeight: 6,
                backgroundColor: AppColors.borderSubtle,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              blocked
                  ? 'Quota atteint. Contactez l\'admin pour recharger.'
                  : (low
                      ? 'Attention : plus que $remaining crédits.'
                      : '${quota.used} utilisés sur ${quota.limitTotal} attribués'),
              style: AppFonts.sans(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CARTE LOT (FIFO)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _LotCard extends StatelessWidget {
  final CreditLot lot;
  const _LotCard({required this.lot});

  @override
  Widget build(BuildContext context) {
    final urgent = lot.isUrgent;
    final days = lot.daysUntilExpiration;
    final expColor = urgent ? AppColors.danger : AppColors.profPrimary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: urgent
            ? AppColors.danger.withValues(alpha: 0.04)
            : AppColors.card,
        border: Border.all(
          color: urgent
              ? AppColors.danger.withValues(alpha: 0.35)
              : AppColors.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Pack ${lot.packName}',
                        style: AppFonts.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (lot.isDiscovery) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.profPrimary
                              .withValues(alpha: 0.14),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'OFFERT',
                          style: AppFonts.mono(
                            fontSize: 8,
                            color: AppColors.profPrimary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                urgent
                    ? '⚠ Expire dans $days j'
                    : 'Expire dans $days j',
                style: AppFonts.mono(
                  fontSize: 9,
                  color: expColor,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: lot.progressFraction,
              minHeight: 5,
              backgroundColor: const Color(0x14FFFFFF),
              valueColor: AlwaysStoppedAnimation(
                urgent ? AppColors.danger : AppColors.profPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${lot.creditsRemaining} restants sur ${lot.creditsTotal}'
            '${urgent ? " · consommés en priorité" : ""}',
            style: AppFonts.sans(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// LIGNE D'HISTORIQUE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _HistoryRow extends StatelessWidget {
  final CreditTransaction txn;
  const _HistoryRow({required this.txn});

  ({IconData icon, Color color, String title}) _theme() {
    if (txn.isPurchase) {
      return (
        icon: Icons.credit_card_rounded,
        color: AppColors.profPrimary,
        title: 'Achat ${txn.packName ?? "pack"}',
      );
    }
    if (txn.isDiscovery) {
      return (
        icon: Icons.card_giftcard_rounded,
        color: AppColors.profPrimary,
        title: 'Pack Découverte offert',
      );
    }
    if (txn.isRefund) {
      return (
        icon: Icons.refresh_rounded,
        color: AppColors.warning,
        title: 'Crédit remis en solde',
      );
    }
    if (txn.type == CreditTxnType.expire) {
      return (
        icon: Icons.hourglass_disabled_rounded,
        color: AppColors.textMuted,
        title: 'Crédits expirés',
      );
    }
    // reserve / consume
    return (
      icon: Icons.edit_note_rounded,
      color: AppColors.primary,
      title: 'Correction de copie',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme();
    final df = DateFormat('d MMM · HH:mm', 'fr_FR');
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(t.icon, color: t.color, size: 15),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: AppFonts.sans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  df.format(txn.createdAt.toLocal()) +
                      (txn.paymentMethod != null
                          ? ' · ${_methodLabel(txn.paymentMethod!)}'
                          : ''),
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (txn.paymentAmountGnf != null && txn.paymentAmountGnf! > 0)
                Text(
                  '${_formatFcfa(txn.paymentAmountGnf!)} GNF',
                  style: AppFonts.mono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (txn.paymentAmountFcfa != null &&
                  txn.paymentAmountFcfa! > 0)
                Text(
                  '${_formatFcfa(txn.paymentAmountFcfa!)} FCFA',
                  style: AppFonts.mono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Text(
                  txn.delta >= 0 ? '+${txn.delta}' : '${txn.delta}',
                  style: AppFonts.mono(
                    fontSize: 11,
                    color: txn.delta >= 0
                        ? AppColors.profPrimary
                        : AppColors.textPrimary,
                  ),
                ),
              if (txn.paymentStatus != null) ...[
                const SizedBox(height: 3),
                _StatusPill(status: txn.paymentStatus!),
              ] else if (txn.isRefund) ...[
                const SizedBox(height: 3),
                _StatusPill(status: 'refunded'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _methodLabel(String code) {
    switch (code) {
      case 'OM':
        return 'Orange Money';
      case 'MTN':
        return 'MTN MoMo';
      case 'WAVE':
        return 'Wave';
      case 'MOOV':
        return 'Moov Money';
      case 'AIRTEL':
        return 'Airtel Money';
      case 'FREE':
        return 'Free Money';
      case 'TMONEY':
        return 'T-Money';
      case 'CARD':
        return 'Carte bancaire';
      default:
        return code;
    }
  }

  String _formatFcfa(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'completed':
        bg = AppColors.profPrimary.withValues(alpha: 0.14);
        fg = AppColors.profPrimary;
        label = 'Réussi';
        break;
      case 'pending':
        bg = AppColors.warning.withValues(alpha: 0.14);
        fg = AppColors.warning;
        label = 'En cours';
        break;
      case 'failed':
        bg = AppColors.danger.withValues(alpha: 0.14);
        fg = AppColors.danger;
        label = 'Échoué';
        break;
      case 'refunded':
        bg = AppColors.warning.withValues(alpha: 0.14);
        fg = AppColors.warning;
        label = 'Remboursé';
        break;
      default:
        bg = AppColors.textMuted.withValues(alpha: 0.14);
        fg = AppColors.textMuted;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppFonts.mono(
          fontSize: 8,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FOOTER — règles métier visibles pour l'utilisateur
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RulesFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rules = [
      ('🪙', '1 crédit = 1 copie corrigée par l\'IA, jusqu\'à 8 pages'),
      ('📄', 'Copie plus longue : 9–17 p. = 2 crédits, 18–25 p. = 3, 26–34 p. = 4…'),
      ('📸', 'Le scan seul ne consomme pas de crédit : seul « Lancer la correction » débite'),
      ('🔄', 'Échec technique : crédits remis en solde'),
      ('✍️', 'Validation des zones illisibles incluse (aucun crédit en plus)'),
      ('⏳', 'Crédits valables 30 jours après l\'achat'),
      ('📊', 'Consommation FIFO (lot le plus proche d\'expiration en premier)'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMMENT ÇA MARCHE',
            style: AppFonts.mono(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          ...rules.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: AppFonts.sans(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
