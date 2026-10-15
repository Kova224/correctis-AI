import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../admin/admin_home_screen.dart';
import '../home/home_screen.dart';

/// Michel : affiché après un Google Sign-In quand le compte n'a pas encore
/// choisi Enseignant / Administrateur. Bloque tant que le choix n'est pas
/// fait — impossible de revenir en arrière (le compte doit être qualifié).
class AccountTypePickerScreen extends StatefulWidget {
  const AccountTypePickerScreen({super.key});

  @override
  State<AccountTypePickerScreen> createState() =>
      _AccountTypePickerScreenState();
}

class _AccountTypePickerScreenState extends State<AccountTypePickerScreen> {
  AccountType _selected = AccountType.teacher;
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await context.read<AuthService>().confirmAccountType(_selected);
      if (!mounted) return;
      // pushAndRemoveUntil : plus rien dans la pile, évite le pop "VUE PROF"
      // qui s'affichait quand la LoginScreen restait sous la stack.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => _selected == AccountType.admin
              ? const AdminHomeScreen()
              : const HomeScreen(),
        ),
        (r) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.logoGradient.createShader(bounds),
                      child: Text(
                        'CORRECTIS',
                        textAlign: TextAlign.center,
                        style: AppFonts.fraunces(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ).copyWith(letterSpacing: -1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Bienvenue !',
                    textAlign: TextAlign.center,
                    style: AppFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Avant de continuer, dites-nous qui vous êtes.\n'
                    'Ce choix est définitif.',
                    textAlign: TextAlign.center,
                    style: AppFonts.sans(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _TypePill(
                    label: 'Enseignant',
                    subtitle: 'Je corrige des copies pour ma classe.',
                    icon: Icons.edit_note_rounded,
                    selected: _selected == AccountType.teacher,
                    accent: AppColors.profPrimary,
                    onTap: () =>
                        setState(() => _selected = AccountType.teacher),
                  ),
                  const SizedBox(height: 12),
                  _TypePill(
                    label: 'Administrateur',
                    subtitle: 'Je gère une école et ses enseignants.',
                    icon: Icons.account_balance_rounded,
                    selected: _selected == AccountType.admin,
                    accent: AppColors.adminPrimary,
                    onTap: () =>
                        setState(() => _selected = AccountType.admin),
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: _selected == AccountType.admin
                          ? AppColors.adminGradient
                          : AppColors.profGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        onTap: _saving ? null : _confirm,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'CONTINUER',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
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
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : AppColors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? accent : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
