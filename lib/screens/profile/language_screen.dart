import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../admin/admin_widgets.dart';

/// Écran de sélection de la langue de l'application.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminBackButton(
                    onTap: () => Navigator.maybePop(context)),
                const SizedBox(height: 18),
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
                  'Langue de l\'application',
                  style: AppFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Le changement est immédiat.',
                  style: AppFonts.sans(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Consumer<LocaleService>(
                  builder: (context, svc, _) => Column(
                    children: AppLanguage.values.map((lang) {
                      final isActive = svc.current == lang;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.card,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                            onTap: () => svc.setLanguage(lang),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.primary
                                          .withValues(alpha: 0.35)
                                      : AppColors.borderSubtle,
                                  width: isActive ? 1.5 : 1,
                                ),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    lang.flag,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lang.label,
                                          style: AppFonts.sans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          lang.code.toUpperCase(),
                                          style: AppFonts.mono(
                                            fontSize: 9,
                                            color: AppColors.textMuted,
                                            letterSpacing: 1.4,
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
                                        gradient:
                                            AppColors.adminGradient,
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
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
