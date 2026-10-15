import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../admin/admin_home_screen.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  /// Email pré-rempli (utilisé quand on arrive depuis un lien d'invitation
  /// enseignant — l'email est figé sur celui de l'invitation pour éviter
  /// les erreurs).
  final String? prefilledEmail;
  final bool emailLocked;

  const RegisterScreen({
    super.key,
    this.prefilledEmail,
    this.emailLocked = false,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _loading = false;
  AccountType _accountType = AccountType.teacher;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.prefilledEmail ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final user = await context.read<AuthService>().register(
            email: _email.text.trim(),
            password: _password.text,
            displayName: _name.text.trim(),
            accountType: _accountType,
          );
      if (!mounted) return;
      // Michel spec §3 : admin → dashboard admin, prof → HomeScreen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => user.isAdminAccount
              ? const AdminHomeScreen()
              : const HomeScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
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
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: AppColors.card,
                      shape: const CircleBorder(
                        side: BorderSide(color: AppColors.borderSubtle),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
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
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Logo Correctis avec gradient
                  Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.logoGradient.createShader(bounds),
                      child: Text(
                        'CORRECTIS',
                        textAlign: TextAlign.center,
                        style: AppFonts.fraunces(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ).copyWith(letterSpacing: -1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Créer un compte',
                    textAlign: TextAlign.center,
                    style: AppFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rejoignez Correctis et corrigez\nvos copies en quelques secondes.',
                    textAlign: TextAlign.center,
                    style: AppFonts.sans(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Michel spec §3 : choix DÉFINITIF du type de compte
                  _AccountTypeSelector(
                    value: _accountType,
                    onChanged: widget.emailLocked
                        ? null // prof invité par une école → forcément teacher
                        : (v) => setState(() => _accountType = v),
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    hint: 'Votre nom complet',
                    controller: _name,
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nom requis' : null,
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    hint: 'email@exemple.com',
                    controller: _email,
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    readOnly: widget.emailLocked,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email requis';
                      if (!v.contains('@')) return 'Email invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    hint: 'Mot de passe (min. 6 caractères)',
                    controller: _password,
                    obscureText: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min. 6 caractères' : null,
                  ),
                  const SizedBox(height: 26),
                  // Bouton gradient vert (style login)
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.profGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.profPrimary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        onTap: _loading ? null : _register,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'CRÉER MON COMPTE',
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
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: RichText(
                        text: TextSpan(
                          text: 'Déjà un compte ? ',
                          style: AppFonts.sans(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                          children: [
                            TextSpan(
                              text: 'Se connecter',
                              style: AppFonts.sans(
                                fontSize: 13,
                                color: AppColors.profPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur "compte prof / compte admin" — Michel spec §3.
/// Choix définitif au signup. Si emailLocked (invitation prof), verrouillé
/// sur teacher.
class _AccountTypeSelector extends StatelessWidget {
  final AccountType value;
  final ValueChanged<AccountType>? onChanged;
  const _AccountTypeSelector({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'JE SUIS…',
          style: AppFonts.mono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TypePill(
                label: 'Enseignant',
                subtitle: 'je corrige des copies',
                icon: Icons.edit_note_rounded,
                selected: value == AccountType.teacher,
                accent: AppColors.profPrimary,
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(AccountType.teacher),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypePill(
                label: 'Administrateur',
                subtitle: 'je gère une école',
                icon: Icons.account_balance_rounded,
                selected: value == AccountType.admin,
                accent: AppColors.adminPrimary,
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(AccountType.admin),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ce choix est définitif : un compte admin ne peut pas corriger '
          'de copies, un compte prof ne peut pas gérer d\'école.',
          style: AppFonts.sans(
            fontSize: 10.5,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;
  const _TypePill({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : AppColors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? accent : AppColors.textMuted),
              const SizedBox(height: 6),
              Text(label,
                  style: AppFonts.fraunces(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? accent : AppColors.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
