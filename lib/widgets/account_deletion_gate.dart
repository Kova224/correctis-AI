import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login_screen.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Affiche [child] (accueil prof ou admin), sauf si le compte a une
/// suppression en cours : on propose alors d'annuler la suppression ou de se
/// déconnecter. Utilisé après le splash et après la connexion.
///
/// Si la vérification échoue (réseau), on laisse passer : la suppression
/// reste prévue côté serveur et l'écran « Supprimer mon compte » permet
/// toujours de l'annuler.
class AccountDeletionGate extends StatefulWidget {
  final Widget child;
  const AccountDeletionGate({super.key, required this.child});

  @override
  State<AccountDeletionGate> createState() => _AccountDeletionGateState();
}

class _AccountDeletionGateState extends State<AccountDeletionGate> {
  DateTime? _scheduledFor;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final s = await AccountDeletionService.status();
    if (!mounted || s == null || !s.isPending) return;
    setState(() => _scheduledFor = s.scheduledFor);
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await AccountDeletionService.cancel();
      if (!mounted) return;
      setState(() => _scheduledFor = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Suppression annulée. Bon retour sur Correctis !'),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final when = _scheduledFor;
    if (when == null) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.schedule_outlined,
                  size: 48, color: AppColors.warning),
              const SizedBox(height: 16),
              Text(
                'Suppression du compte prévue',
                textAlign: TextAlign.center,
                style: AppFonts.fraunces(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Vous avez demandé la suppression de votre compte. Elle sera '
                'définitive le ${AccountDeletionService.formatDate(when)}.\n\n'
                'Vous pouvez encore l\'annuler et retrouver toutes vos données.',
                textAlign: TextAlign.center,
                style: AppFonts.sans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _cancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text(
                    _busy ? 'Annulation…' : 'Annuler la suppression',
                    style: AppFonts.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : _logout,
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
