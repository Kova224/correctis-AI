import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'accept_invitation_screen.dart';
import 'admin_widgets.dart';

/// Écran pour coller manuellement un code/lien d'invitation enseignant.
///
/// Utile quand le lien `correctis://invite?token=...` n'est pas cliquable
/// (cas WhatsApp/SMS où les schémas custom n'ouvrent pas d'app).
/// L'enseignant copie le token ou le lien complet depuis le message, ouvre
/// Correctis, va sur cet écran, colle, et valide.
class PasteInvitationTokenScreen extends StatefulWidget {
  const PasteInvitationTokenScreen({super.key});

  @override
  State<PasteInvitationTokenScreen> createState() =>
      _PasteInvitationTokenScreenState();
}

class _PasteInvitationTokenScreenState
    extends State<PasteInvitationTokenScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Extrait le token à partir d'un texte qui peut être :
  /// - Le token brut : `1ab2fa5a664c75dffe9a43c7c0982733a9aefa5927c5ad88`
  /// - Le lien complet : `correctis://invite?token=1ab2fa5a...`
  /// - Un lien web futur : `https://correctis.app/invite?token=1ab2fa5a...`
  String _extractToken(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return '';
    // Cherche `token=...` dans la chaîne
    final tokenMatch = RegExp(r'token=([a-zA-Z0-9]+)').firstMatch(cleaned);
    if (tokenMatch != null) return tokenMatch.group(1) ?? '';
    // Sinon on suppose que c'est le token brut (alphanumeric)
    if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(cleaned)) return cleaned;
    return '';
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _ctrl.text = data.text!);
    }
  }

  Future<void> _validate() async {
    final token = _extractToken(_ctrl.text);
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code ou lien invalide.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    // Vérification rapide que l'invitation existe avant de pousser l'écran.
    try {
      final info = await context
          .read<EstablishmentService>()
          .lookupInvitationInfo(token);
      if (!mounted) return;
      setState(() => _loading = false);
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Aucune invitation ne correspond à ce code. Vérifiez-le.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Pousse vers l'écran d'acceptation classique
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AcceptInvitationScreen(token: token),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminBackButton(
                    onTap: () => Navigator.maybePop(context)),
                const SizedBox(height: 20),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppColors.adminGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.adminPrimary
                            .withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'INVITATION',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saisir un code d\'invitation',
                  style: AppFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Collez ici le lien ou le code que l\'administrateur '
                  'de votre école vous a envoyé (WhatsApp, SMS, email…). '
                  'Vous pouvez coller le message entier — on extraira '
                  'automatiquement le code.',
                  style: AppFonts.sans(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _ctrl,
                  maxLines: 5,
                  minLines: 3,
                  style: AppFonts.mono(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'correctis://invite?token=…',
                    hintStyle: AppFonts.mono(
                      fontSize: 12,
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor:
                        AppColors.adminPrimary.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide(
                        color:
                            AppColors.adminPrimary.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide(
                        color:
                            AppColors.adminPrimary.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                      borderSide: const BorderSide(
                          color: AppColors.adminPrimary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _paste,
                    icon: const Icon(
                      Icons.content_paste_rounded,
                      size: 16,
                      color: AppColors.adminPrimary,
                    ),
                    label: Text(
                      'COLLER DEPUIS LE PRESSE-PAPIER',
                      style: AppFonts.mono(
                        fontSize: 10,
                        color: AppColors.adminPrimary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                AdminGradientButton(
                  label: _loading ? 'VÉRIFICATION…' : 'VALIDER',
                  icon: _loading ? null : Icons.arrow_forward_rounded,
                  onTap: _loading ? () {} : _validate,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
