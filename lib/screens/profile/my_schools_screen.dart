import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';

/// Écran "Mes écoles" — accessible depuis le profil du prof.
///
/// Michel (spec §5) : purement informatif. Plus de notion d'"école active".
/// Chaque examen sait déjà à quelle école il appartient (choix à la création).
///
/// Liste toutes les écoles où le prof est rattaché avec :
///   - Nom + ville de l'école
///   - Rôle (Admin / Enseignant)
///   - Badge de statut : Active / Suspendue
///   - Bouton "Quitter" (soft leave — le prof se retire volontairement)
///
/// Bouton en bas : "+ Joindre une école" ouvre le formulaire
/// email école + identifiant.
class MySchoolsScreen extends StatefulWidget {
  const MySchoolsScreen({super.key});

  @override
  State<MySchoolsScreen> createState() => _MySchoolsScreenState();
}

class _MySchoolsScreenState extends State<MySchoolsScreen> {
  @override
  Widget build(BuildContext context) {
    final estab = context.watch<EstablishmentService>();
    final memberships = estab.myMemberships;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mes écoles',
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${memberships.length} école${memberships.length != 1 ? "s" : ""}',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          if (memberships.isEmpty)
            _emptyState()
          else
            ...memberships.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SchoolCard(
                    membership: m,
                    onLeave: () => _confirmLeave(m),
                  ),
                )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Ink(
              decoration: BoxDecoration(
                gradient: AppColors.profGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.profPrimary.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: _openJoinSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.school_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+ JOINDRE UNE ÉCOLE',
                        style: AppFonts.mono(
                          fontSize: 11,
                          color: Colors.white,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.profPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.school_outlined,
              color: AppColors.profPrimary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Vous n\'êtes rattaché à aucune école',
            style: AppFonts.fraunces(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Demandez à l\'admin d\'une école de vous créer un compte : '
            'il vous transmettra un email école et un identifiant unique.',
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(MembershipSummary m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Quitter ${m.establishmentName} ?',
            style: AppFonts.fraunces(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Vous ne pourrez plus consulter les copies ni les crédits de '
          'cette école. L\'admin peut vous réinviter à tout moment.',
          style: AppFonts.sans(fontSize: 12, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<EstablishmentService>()
          .leaveSchool(m.establishmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vous avez quitté ${m.establishmentName}.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _openJoinSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _JoinSchoolSheet(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// CARD ÉCOLE
// ══════════════════════════════════════════════════════════════════════════

class _SchoolCard extends StatelessWidget {
  final MembershipSummary membership;
  final VoidCallback onLeave;

  const _SchoolCard({
    required this.membership,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final suspended = !membership.isActive;
    final borderColor = suspended
        ? AppColors.danger.withValues(alpha: 0.30)
        : AppColors.borderSubtle;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (membership.isAdmin
                          ? AppColors.adminPrimary
                          : AppColors.profPrimary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.account_balance_rounded,
                  color: membership.isAdmin
                      ? AppColors.adminPrimary
                      : AppColors.profPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.establishmentName,
                      style: AppFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (membership.establishmentCity != null &&
                        membership.establishmentCity!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        membership.establishmentCity!,
                        style: AppFonts.sans(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _RoleBadge(role: membership.role),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (suspended)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SUSPENDU',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.danger,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              if (!suspended)
                TextButton(
                  onPressed: onLeave,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(
                    'Quitter',
                    style: AppFonts.sans(fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});
  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    final label = isAdmin ? 'ADMIN' : 'PROF';
    final color = isAdmin ? AppColors.adminPrimary : AppColors.profPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppFonts.mono(
          fontSize: 9,
          color: color,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET : JOINDRE UNE ÉCOLE
// ══════════════════════════════════════════════════════════════════════════

class _JoinSchoolSheet extends StatefulWidget {
  const _JoinSchoolSheet();

  @override
  State<_JoinSchoolSheet> createState() => _JoinSchoolSheetState();
}

class _JoinSchoolSheetState extends State<_JoinSchoolSheet> {
  final _emailCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtl.text.trim();
    final code = _codeCtl.text.trim();
    if (email.isEmpty || code.isEmpty) {
      setState(
          () => _errorMsg = 'Saisis l\'email école et l\'identifiant.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });
    final result = await context
        .read<EstablishmentService>()
        .joinSchool(schoolEmail: email, joinCode: code);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.profPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _submitting = false;
        _errorMsg = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Joindre une école',
            style: AppFonts.fraunces(
                fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'L\'admin de l\'école vous a communiqué un email école + un '
            'identifiant unique. Saisis-les pour rejoindre.',
            style: AppFonts.sans(
                fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          Text(
            'EMAIL ÉCOLE',
            style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 1.4),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            style: AppFonts.sans(
                fontSize: 13.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'ex : math.michel@lycee-cote.fr',
              hintStyle: AppFonts.sans(
                  fontSize: 12.5, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide:
                    const BorderSide(color: AppColors.borderSubtle),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'IDENTIFIANT',
            style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 1.4),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _codeCtl,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            style: AppFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.adminPrimary,
            ).copyWith(letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: 'ex : LYC-MK-001',
              hintStyle: AppFonts.mono(
                  fontSize: 15, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide:
                    const BorderSide(color: AppColors.borderSubtle),
              ),
            ),
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.30)),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: AppFonts.sans(
                          fontSize: 11.5, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Ink(
              decoration: BoxDecoration(
                gradient: AppColors.profGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: _submitting ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Colors.white)),
                          )
                        : Text(
                            'REJOINDRE L\'ÉCOLE',
                            style: AppFonts.mono(
                              fontSize: 11,
                              color: Colors.white,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annuler',
                style: AppFonts.sans(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
