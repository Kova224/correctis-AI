import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';

/// Réinitialisation du mot de passe — flux en 2 étapes :
/// 1) saisir l'email du compte
/// 2) saisir un nouveau mot de passe (mode démo, sans email réel)
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _passFormKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _newPwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final exists =
          await context.read<AuthService>().emailExists(_email.text.trim());
      if (!mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Aucun compte trouvé avec cet email.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() => _step = 1);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPassword() async {
    if (!_passFormKey.currentState!.validate()) return;
    if (_newPwd.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les deux mots de passe ne correspondent pas.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().resetPassword(
            email: _email.text.trim(),
            newPassword: _newPwd.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Mot de passe réinitialisé. Vous pouvez vous connecter.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.1, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _step == 0 ? _buildEmailStep() : _buildPasswordStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      key: const ValueKey('step-email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.lock_reset_rounded,
                color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Mot de passe oublié',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Entrez l\'email associé à votre compte. Vous pourrez ensuite définir un nouveau mot de passe.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _emailFormKey,
          child: CustomTextField(
            hint: 'email@exemple.com',
            controller: _email,
            light: true,
            prefixIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitEmail(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email requis';
              if (!v.contains('@')) return 'Email invalide';
              return null;
            },
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Vérifier l\'email',
          icon: Icons.arrow_forward_rounded,
          loading: _loading,
          onPressed: _submitEmail,
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Retour à la connexion',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey('step-pwd'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.vpn_key_rounded,
                color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Nouveau mot de passe',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Compte : ${_email.text}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _passFormKey,
          child: Column(
            children: [
              CustomTextField(
                hint: 'Nouveau mot de passe',
                controller: _newPwd,
                light: true,
                obscureText: true,
                prefixIcon: Icons.lock_outline,
                validator: (v) =>
                    v == null || v.length < 4 ? 'Min. 4 caractères' : null,
              ),
              const SizedBox(height: 14),
              CustomTextField(
                hint: 'Confirmer',
                controller: _confirm,
                light: true,
                obscureText: true,
                prefixIcon: Icons.lock_outline,
                validator: (v) =>
                    v == null || v.length < 4 ? 'Min. 4 caractères' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Réinitialiser',
          icon: Icons.check_rounded,
          loading: _loading,
          onPressed: _submitPassword,
        ),
      ],
    );
  }
}
