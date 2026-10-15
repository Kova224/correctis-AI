import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_deletion_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'support_screen.dart';

/// Écran « Supprimer mon compte » (exigence Google Play).
///
/// Explique ce qui est supprimé / conservé, demande de retaper l'e-mail du
/// compte, puis enregistre la demande (suppression définitive dans 30 jours)
/// et déconnecte l'utilisateur.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _emailCtrl = TextEditingController();
  AccountDeletionStatus? _status;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AccountDeletionService.status();
    if (!mounted) return;
    setState(() {
      _status = s ?? const AccountDeletionStatus();
      _loading = false;
    });
  }

  String get _accountEmail =>
      context.read<AuthService>().currentUser?.email.trim().toLowerCase() ?? '';

  bool get _emailMatches =>
      _accountEmail.isNotEmpty &&
      _emailCtrl.text.trim().toLowerCase() == _accountEmail;

  Future<void> _submit() async {
    if (!_emailMatches || _submitting) return;
    setState(() => _submitting = true);
    try {
      final when = await AccountDeletionService.request();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Suppression enregistrée'),
          content: Text(
            'Votre compte sera supprimé définitivement le '
            '${AccountDeletionService.formatDate(when)}.\n\n'
            'Vous allez être déconnecté. Si vous changez d\'avis d\'ici là, '
            'reconnectez-vous et choisissez « Annuler la suppression ».',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await context.read<AuthService>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AccountDeletionService.messageFor(null)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelPending() async {
    setState(() => _submitting = true);
    try {
      await AccountDeletionService.cancel();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Suppression annulée. Votre compte est conservé.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annulation impossible pour le moment. Réessayez.'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'Supprimer mon compte',
          style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: _buildContent(),
              ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final s = _status ?? const AccountDeletionStatus();

    if (s.isPending) {
      return [
        _infoCard(
          icon: Icons.schedule_outlined,
          color: AppColors.warning,
          title: 'Suppression déjà demandée',
          body: 'Votre compte sera supprimé définitivement le '
              '${AccountDeletionService.formatDate(s.scheduledFor!)}.',
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Annuler la suppression',
          onPressed: _submitting ? null : _cancelPending,
        ),
      ];
    }

    if (s.isBlocked) {
      return [
        _infoCard(
          icon: Icons.block_outlined,
          color: AppColors.warning,
          title: 'Suppression impossible pour l\'instant',
          body: AccountDeletionService.messageFor(s.blocker),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Contacter le support',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SupportScreen()),
          ),
        ),
      ];
    }

    return [
      Text(
        'Vous pouvez supprimer votre compte Correctis et vos données. '
        'La suppression devient définitive 30 jours après votre demande : '
        'd\'ici là, il suffit de vous reconnecter pour l\'annuler.',
        style: AppFonts.sans(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 18),
      _section('Ce qui sera supprimé', AppColors.danger, [
        'Votre profil : nom, e-mail, téléphone, photo',
        'Les photos des copies et des sujets que vous avez envoyées',
        'Vos examens, copies et notes personnels (hors école)',
        'Vos crédits non utilisés : ils seront perdus',
      ]),
      const SizedBox(height: 14),
      _section('Ce qui est conservé', AppColors.info, [
        if (s.inSchool)
          'Les examens et notes que vous avez faits pour votre école restent '
              'à l\'école (sans les photos des copies)',
        'Vos paiements, sans lien avec votre identité, '
            'pour les obligations comptables',
      ]),
      const SizedBox(height: 22),
      Text(
        'Pour confirmer, tapez l\'adresse e-mail de votre compte :',
        style: AppFonts.sans(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        style: AppFonts.sans(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'votre@email.com',
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.borderSubtle),
          ),
        ),
      ),
      const SizedBox(height: 20),
      _primaryButton(
        label: _submitting ? 'Envoi…' : 'Supprimer mon compte',
        danger: true,
        onPressed: _emailMatches && !_submitting ? _submit : null,
      ),
    ];
  }

  Widget _section(String title, Color color, List<String> lines) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppFonts.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l,
                      style: AppFonts.sans(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppFonts.sans(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: danger ? AppColors.danger : AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: Text(
          label,
          style: AppFonts.sans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
