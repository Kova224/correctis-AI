import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import 'admin_widgets.dart';

/// Écran d'acceptation d'une invitation enseignant.
///
/// Atterrissage du deep-link `correctis://invite?token=XXX`.
/// Flux :
///   1. Si l'utilisateur n'est pas connecté → invite à se connecter/créer
///      un compte avec le même email que celui de l'invitation, puis on
///      reviendra ici.
///   2. Si connecté → appel à `EstablishmentService.acceptInvitation(token)`.
///   3. Succès → message + navigation vers Home.
class AcceptInvitationScreen extends StatefulWidget {
  final String token;
  const AcceptInvitationScreen({super.key, required this.token});

  @override
  State<AcceptInvitationScreen> createState() =>
      _AcceptInvitationScreenState();
}

enum _Step { loading, mustLogin, ready, accepting, success, error }

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  _Step _step = _Step.loading;
  String? _errorMessage;
  InvitationInfo? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    // 1. Charge les infos publiques de l'invitation (email + nom école)
    final svc = context.read<EstablishmentService>();
    final info = await svc.lookupInvitationInfo(widget.token);
    if (!mounted) return;

    if (info == null) {
      setState(() {
        _step = _Step.error;
        _errorMessage =
            'Cette invitation est introuvable. Vérifiez le lien.';
      });
      return;
    }
    if (info.expired) {
      setState(() {
        _step = _Step.error;
        _info = info;
        _errorMessage = 'Invitation expirée (>48h). '
            'Demandez à l\'administrateur de vous en envoyer une nouvelle.';
      });
      return;
    }
    if (info.accepted) {
      setState(() {
        _step = _Step.error;
        _info = info;
        _errorMessage =
            'Invitation déjà acceptée. Connectez-vous normalement.';
      });
      return;
    }

    setState(() => _info = info);

    // 2. Vérifie l'état de connexion
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() => _step = _Step.mustLogin);
    } else {
      setState(() => _step = _Step.ready);
    }
  }

  Future<void> _accept() async {
    setState(() {
      _step = _Step.accepting;
      _errorMessage = null;
    });
    try {
      await context
          .read<EstablishmentService>()
          .acceptInvitation(widget.token);
      if (!mounted) return;
      setState(() => _step = _Step.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _goToLogin() async {
    // Pousse le LoginScreen avec l'email pré-rempli. Quand l'user se
    // connecte (auth state change), `DeepLinkService` déclenche
    // automatiquement la reprise de l'invitation.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(prefilledEmail: _info?.email),
      ),
    );
  }

  Future<void> _goToRegister() async {
    // Push direct vers Register avec l'email pré-rempli ET verrouillé
    // (l'enseignant ne peut pas le modifier — il doit utiliser l'adresse
    // exacte de l'invitation).
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          prefilledEmail: _info?.email,
          emailLocked: true,
        ),
      ),
    );
  }

  void _close() {
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                Row(
                  children: [
                    AdminBackButton(
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(child: Center(child: _buildBody())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.loading:
        return const _Loading();
      case _Step.ready:
        return _Card(
          gradient: AppColors.adminGradient,
          icon: Icons.mark_email_read_outlined,
          eyebrow: 'INVITATION REÇUE',
          title: _info?.establishmentName ?? 'Rejoindre l\'établissement',
          message:
              'Vous avez été invité à rejoindre cet établissement sur Correctis. '
              'En acceptant, vous pourrez corriger des copies au nom de cet '
              'établissement.\n\nL\'administrateur aura accès aux notes de vos '
              'examens (jamais à vos copies sans votre accord).',
          primaryLabel: 'ACCEPTER',
          primaryIcon: Icons.check_rounded,
          onPrimary: _accept,
          secondaryLabel: 'Plus tard',
          onSecondary: _close,
        );
      case _Step.mustLogin:
        return _Card(
          gradient: AppColors.adminGradient,
          icon: Icons.lock_outline_rounded,
          eyebrow: 'CONNEXION REQUISE',
          title: _info?.establishmentName ?? 'Connectez-vous',
          message:
              'Invitation pour : ${_info?.email ?? "—"}\n\n'
              'Pour accepter cette invitation, connectez-vous à Correctis '
              'avec cette adresse email exactement. Si vous n\'avez pas '
              'encore de compte, créez-en un (l\'email sera pré-rempli).',
          primaryLabel: 'SE CONNECTER',
          primaryIcon: Icons.login_rounded,
          onPrimary: _goToLogin,
          secondaryLabel: 'Créer un compte',
          onSecondary: _goToRegister,
        );
      case _Step.accepting:
        return const _Loading(message: 'Validation en cours…');
      case _Step.success:
        final estab = context.read<EstablishmentService>();
        return _Card(
          gradient: const LinearGradient(
            colors: [Color(0xFF059669), Color(0xFF0891B2)],
          ),
          icon: Icons.celebration_outlined,
          eyebrow: 'BIENVENUE',
          title: estab.currentEstablishment?.name ?? 'Établissement rejoint',
          message:
              'Vous faites maintenant partie de cet établissement. Vos copies '
              'corrigées seront visibles par l\'administrateur (notes '
              'uniquement, dans le respect de votre travail pédagogique).',
          primaryLabel: 'COMMENCER',
          primaryIcon: Icons.arrow_forward_rounded,
          onPrimary: _close,
        );
      case _Step.error:
        return _Card(
          gradient: const LinearGradient(
            colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
          ),
          icon: Icons.error_outline_rounded,
          eyebrow: 'IMPOSSIBLE D\'ACCEPTER',
          title: 'Invitation non valide',
          message: _errorMessage ??
              'Une erreur est survenue. Vérifiez que le lien n\'est pas '
                  'expiré (48h) et qu\'il n\'a pas déjà été utilisé.',
          primaryLabel: 'RÉESSAYER',
          primaryIcon: Icons.refresh_rounded,
          onPrimary: _accept,
          secondaryLabel: 'Fermer',
          onSecondary: _close,
        );
    }
  }
}

class _Loading extends StatelessWidget {
  final String? message;
  const _Loading({this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation(AppColors.adminPrimary),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: AppFonts.sans(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Gradient gradient;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _Card({
    required this.gradient,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.adminPrimary.withValues(alpha: 0.3),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            eyebrow,
            style: AppFonts.mono(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppFonts.fraunces(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppFonts.sans(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AdminGradientButton(
              label: primaryLabel,
              icon: primaryIcon,
              onTap: onPrimary,
            ),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onSecondary,
              child: Text(
                secondaryLabel!,
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
