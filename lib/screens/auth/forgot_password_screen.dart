import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';

/// Réinitialisation du mot de passe — V2 dark mode style maquette.
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
          const SnackBar(
            content: Text('Aucun compte trouvé avec cet email.'),
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
          content:
              Text('✓ Mot de passe réinitialisé. Vous pouvez vous connecter.'),
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
      backgroundColor: AppColors.voidBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.5,
            colors: [Color(0xFF0A1F3E), AppColors.voidBg],
            stops: [0.0, 0.7],
          ),
        ),
        child: SafeArea(
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
          child: _BackButton(onTap: () => Navigator.of(context).pop()),
        ),
        const SizedBox(height: 40),
        // Icône + titre
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.profGradient,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.profPrimary.withValues(alpha: 0.4),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.lock_reset_rounded,
                color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Mot de passe oublié',
          textAlign: TextAlign.center,
          style: AppFonts.fraunces(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Entrez l\'email associé à votre compte.\nVous pourrez ensuite définir un nouveau mot de passe.',
          textAlign: TextAlign.center,
          style: AppFonts.sans(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _emailFormKey,
          child: CustomTextField(
            hint: 'email@exemple.com',
            controller: _email,
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
        _GradientButton(
          label: 'VÉRIFIER L\'EMAIL',
          loading: _loading,
          onTap: _submitEmail,
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Retour à la connexion',
              style: AppFonts.sans(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
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
          child: _BackButton(onTap: () => setState(() => _step = 0)),
        ),
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.profGradient,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.profPrimary.withValues(alpha: 0.4),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.vpn_key_rounded,
                color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Nouveau mot de passe',
          textAlign: TextAlign.center,
          style: AppFonts.fraunces(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Compte : ${_email.text}',
          textAlign: TextAlign.center,
          style: AppFonts.mono(
            fontSize: 11,
            color: AppColors.primaryLight,
            letterSpacing: 0.5,
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
                obscureText: true,
                prefixIcon: Icons.lock_outline,
                validator: (v) =>
                    v == null || v.length < 4 ? 'Min. 4 caractères' : null,
              ),
              const SizedBox(height: 14),
              CustomTextField(
                hint: 'Confirmer',
                controller: _confirm,
                obscureText: true,
                prefixIcon: Icons.lock_outline,
                validator: (v) =>
                    v == null || v.length < 4 ? 'Min. 4 caractères' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _GradientButton(
          label: 'RÉINITIALISER',
          loading: _loading,
          onTap: _submitPassword,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Composants partagés
// ─────────────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.profGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      label,
                      style: AppFonts.mono(
                        fontSize: 12,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
