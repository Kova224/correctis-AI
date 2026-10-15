import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/credits_service.dart';
import '../services/establishment_service.dart';
import '../services/exam_service.dart';
import '../theme/app_theme.dart';

/// Pill cliquable qui affiche le nom de l'école active et ouvre un bottom
/// sheet pour basculer vers une autre école (si l'user en a plusieurs).
///
/// S'affiche uniquement si l'user est membre d'au moins une école.
class EstablishmentSwitcher extends StatelessWidget {
  const EstablishmentSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EstablishmentService>(
      builder: (context, estab, _) {
        if (!estab.hasEstablishment) return const SizedBox.shrink();
        final school = estab.currentEstablishment!;
        final canSwitch = estab.hasMultipleMemberships;

        return Material(
          color: AppColors.adminPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: canSwitch ? () => _openSwitcher(context, estab) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 12,
                    color: AppColors.adminPrimary,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      school.name.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.mono(
                        fontSize: 9,
                        color: AppColors.adminPrimary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (canSwitch) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 12,
                      color: AppColors.adminPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openSwitcher(BuildContext context, EstablishmentService estab) {
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
            Text(
              'Mes établissements',
              style: AppFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choisissez celui sur lequel vous voulez travailler.',
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            ...estab.myMemberships.map((m) {
              final isActive =
                  m.establishmentId == estab.currentEstablishment?.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isActive
                      ? AppColors.adminPrimary.withValues(alpha: 0.10)
                      : AppColors.card2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(AppRadius.md),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!isActive) {
                        // Capture les services AVANT le await (safe context)
                        final examSvc = context.read<ExamService>();
                        final creditsSvc = context.read<CreditsService>();
                        try {
                          await estab.switchActiveEstablishment(
                              m.establishmentId);
                          // Michel : après switch, recharger les
                          // examens et les crédits pour cloisonnement
                          // strict de l'école active.
                          await Future.wait([
                            examSvc.bootstrap(),
                            creditsSvc.bootstrap(),
                          ]);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Basculé sur ${m.establishmentName}'),
                              backgroundColor: AppColors.profPrimary,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erreur : $e'),
                              backgroundColor: AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isActive
                              ? AppColors.adminPrimary
                                  .withValues(alpha: 0.4)
                              : AppColors.borderSubtle,
                          width: isActive ? 1.5 : 1,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: AppColors.adminGradient,
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.account_balance_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.establishmentName,
                                  style: AppFonts.sans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    m.isAdmin
                                        ? 'Administrateur'
                                        : 'Enseignant',
                                    if (m.matiere?.isNotEmpty == true)
                                      m.matiere!,
                                    if (m.establishmentCity != null)
                                      m.establishmentCity!,
                                  ].join(' · '),
                                  style: AppFonts.sans(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                gradient: AppColors.adminGradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Pour rejoindre une autre école, demandez le lien d\'invitation à son admin.',
                textAlign: TextAlign.center,
                style: AppFonts.sans(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
