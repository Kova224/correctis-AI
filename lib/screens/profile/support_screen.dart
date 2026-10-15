import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.dart';
import '../../theme/app_theme.dart';

/// Écran de support / contact (H.1).
///
/// Propose 3 canaux :
///   - Email (mailto: support@correctis.app)
///   - WhatsApp (wa.me/<numero>)
///   - Formulaire local (préparé pour Edge Function `submit-support-ticket`)
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const String _supportEmail = 'support@correctis.app';
  // Numéro WhatsApp en E.164 sans le '+' (format Tunisie : 216...)
  static const String _supportWhatsappE164 = '21655555555';

  final _messageCtl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageCtl.dispose();
    super.dispose();
  }

  Future<void> _openEmail() async {
    final s = S.read(context);
    final subject = Uri.encodeComponent('Support Correctis');
    final uri = Uri.parse('mailto:$_supportEmail?subject=$subject');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await Clipboard.setData(
            const ClipboardData(text: _supportEmail));
        _toast('${s.supportEmailLabel} — copié dans le presse-papiers');
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: _supportEmail));
      _toast('${s.supportEmailLabel} — copié dans le presse-papiers');
    }
  }

  Future<void> _openWhatsApp() async {
    final s = S.read(context);
    final text = Uri.encodeComponent(
        'Bonjour, j\'ai besoin d\'aide avec l\'application Correctis.');
    final uri =
        Uri.parse('https://wa.me/$_supportWhatsappE164?text=$text');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _toast('WhatsApp introuvable : ${s.supportWhatsappLabel}');
      }
    } catch (_) {
      _toast('WhatsApp introuvable : ${s.supportWhatsappLabel}');
    }
  }

  Future<void> _sendForm() async {
    final s = S.read(context);
    if (_messageCtl.text.trim().isEmpty) {
      _toast(s.supportFormHint);
      return;
    }
    setState(() => _sending = true);
    try {
      // Pour MVP : on ouvre mailto pré-rempli avec le message tapé.
      // Plus tard : Edge Function `submit-support-ticket` qui enregistre
      // en DB + notifie l'admin Correctis par email.
      final subject = Uri.encodeComponent('Support Correctis - Demande');
      final body = Uri.encodeComponent(_messageCtl.text.trim());
      final uri =
          Uri.parse('mailto:$_supportEmail?subject=$subject&body=$body');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _messageCtl.clear();
      if (mounted) _toast(s.supportSent);
    } catch (e) {
      _toast('Erreur : $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          s.support,
          style: AppFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUPPORT',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.supportTitle,
              style: AppFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.supportSubtitle,
              style: AppFonts.sans(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 22),

            // ━━━ Email ━━━
            _SupportCard(
              icon: Icons.mail_outline_rounded,
              iconColor: AppColors.primaryLight,
              title: s.supportEmail,
              value: s.supportEmailLabel,
              onTap: _openEmail,
            ),
            const SizedBox(height: 10),

            // ━━━ WhatsApp ━━━
            _SupportCard(
              icon: Icons.chat_outlined,
              iconColor: AppColors.profPrimary,
              title: s.supportWhatsapp,
              value: s.supportWhatsappLabel,
              onTap: _openWhatsApp,
            ),

            const SizedBox(height: 26),

            // ━━━ Formulaire ━━━
            Text(
              s.supportForm.toUpperCase(),
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageCtl,
              maxLines: 6,
              minLines: 4,
              maxLength: 1000,
              style: AppFonts.sans(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: s.supportFormHint,
                hintStyle: AppFonts.sans(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide:
                      const BorderSide(color: AppColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide:
                      const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _sendForm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  s.send.toUpperCase(),
                  style: AppFonts.mono(
                    fontSize: 11,
                    color: Colors.white,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SupportCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onTap,
  });

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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppFonts.sans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppFonts.mono(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
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
