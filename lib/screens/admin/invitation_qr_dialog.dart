import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';

/// Dialog qui affiche un QR code pour une invitation enseignant.
///
/// L'admin réunit ses profs en salle des profs, ouvre ce dialog, et chaque
/// prof scanne avec son téléphone. Le QR encode `correctis://invite?token=XXX`
/// donc le scan ouvre directement l'app Correctis sur l'écran d'acceptation.
///
/// Utilisation :
///   showDialog(
///     context: context,
///     builder: (_) => InvitationQrDialog(
///       token: invitation.token,
///       email: invitation.email,
///       establishmentName: 'Lycée Ibn Khaldoun',
///     ),
///   );
class InvitationQrDialog extends StatelessWidget {
  final String token;
  final String email;
  final String establishmentName;

  const InvitationQrDialog({
    super.key,
    required this.token,
    required this.email,
    required this.establishmentName,
  });

  String get _link => 'correctis://invite?token=$token';

  String _shareMessage() {
    return 'Bonjour,\n\n'
        'Vous êtes invité à rejoindre $establishmentName sur Correctis.\n\n'
        'COMMENT REJOINDRE :\n'
        '1. Installez Correctis depuis le Play Store\n'
        '2. Ouvrez l\'app et appuyez sur "J\'ai un code d\'invitation"\n'
        '3. Collez ce code :\n\n'
        '$token\n\n'
        'L\'invitation est valable 48h.';
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lien copié.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share() async {
    await Share.share(
      _shareMessage(),
      subject: 'Invitation Correctis — $establishmentName',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.adminPrimary.withValues(alpha: 0.08),
              AppColors.card,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: AppColors.adminGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'INVITATION',
                    style: AppFonts.mono(
                      fontSize: 9.5,
                      color: Colors.white,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              establishmentName,
              style: AppFonts.fraunces(
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              'pour $email',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.adminPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),

            // QR Code dans un cadre blanc (les QR codes doivent être sur
            // fond clair pour scanner correctement)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.adminPrimary.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: QrImageView(
                data: _link,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF6D28D9), // purple admin
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0F0E1B),
                ),
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 14),

            // Texte d'instruction
            Text(
              'L\'enseignant scanne ce code avec son téléphone — '
              'l\'app Correctis s\'ouvrira sur l\'écran d\'acceptation.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'L\'app Correctis doit déjà être installée.',
              textAlign: TextAlign.center,
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            // Token visible en clair sous le QR (fallback si le scan ne
            // marche pas — le prof peut lire et coller dans "J'ai un code")
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.adminPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'OU CODE À RECOPIER',
                    style: AppFonts.mono(
                      fontSize: 8.5,
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    token,
                    textAlign: TextAlign.center,
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.adminPrimary,
                      letterSpacing: 0.3,
                    ).copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyLink(context),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: Text(
                      'COPIER',
                      style: AppFonts.mono(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.adminPrimary,
                      side: BorderSide(
                        color:
                            AppColors.adminPrimary.withValues(alpha: 0.4),
                      ),
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: Text(
                      'PARTAGER',
                      style: AppFonts.mono(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppColors.adminPrimary,
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Fermer',
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
