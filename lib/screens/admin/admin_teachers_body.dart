import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/establishment.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import 'admin_teacher_slots_screen.dart';
import 'admin_widgets.dart';
import 'invitation_qr_dialog.dart';

/// A2 — Gestion enseignants (vue Admin).
/// Branché sur Supabase via [EstablishmentService].
class AdminTeachersBody extends StatefulWidget {
  const AdminTeachersBody({super.key});

  @override
  State<AdminTeachersBody> createState() => _AdminTeachersBodyState();
}

class _AdminTeachersBodyState extends State<AdminTeachersBody> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showInviteDialog() {
    final emailCtrl = TextEditingController();
    final matiereCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool sending = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.adminPrimary.withValues(alpha: 0.08),
                  AppColors.card,
                ],
              ),
            ),
            padding: const EdgeInsets.all(22),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.adminGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.adminPrimary
                              .withValues(alpha: 0.4),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.email_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Inviter un enseignant',
                    style: AppFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.adminPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Un lien d\'invitation valable 48 heures sera envoyé par email.',
                    textAlign: TextAlign.center,
                    style: AppFonts.sans(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: emailCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    style: AppFonts.sans(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Email requis';
                      if (!s.contains('@') || !s.contains('.')) {
                        return 'Email invalide';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: 'email@enseignant.com',
                      hintStyle: AppFonts.sans(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                      prefixIcon: const Icon(
                        Icons.mail_outline,
                        size: 18,
                        color: AppColors.adminPrimary,
                      ),
                      filled: true,
                      fillColor: AppColors.card2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(
                            color: AppColors.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: matiereCtrl,
                    style: AppFonts.sans(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Matière (optionnel)',
                      hintStyle: AppFonts.sans(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                      prefixIcon: const Icon(
                        Icons.book_outlined,
                        size: 18,
                        color: AppColors.adminPrimary,
                      ),
                      filled: true,
                      fillColor: AppColors.card2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(
                            color: AppColors.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: AdminGradientButton(
                      label: sending
                          ? 'ENVOI EN COURS…'
                          : 'ENVOYER L\'INVITATION',
                      icon: sending ? null : Icons.send_rounded,
                      onTap: sending
                          ? () {}
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setStateDialog(() => sending = true);
                              final svc =
                                  context.read<EstablishmentService>();
                              final emailTarget = emailCtrl.text.trim();
                              try {
                                final result = await svc.inviteTeacher(
                                  email: emailTarget,
                                  matiere:
                                      matiereCtrl.text.trim().isEmpty
                                          ? null
                                          : matiereCtrl.text.trim(),
                                );
                                if (!dialogCtx.mounted) return;
                                Navigator.of(dialogCtx).pop();
                                // Propose toujours le partage manuel du
                                // lien — utile que l'email soit passé ou
                                // non (Resend en mode test bloque souvent
                                // les destinataires non vérifiés).
                                final estabName =
                                    svc.currentEstablishment?.name ??
                                        'l\'établissement';
                                final link =
                                    'correctis://invite?token=${result.invitation.token}';
                                final msg = 'Bonjour,\n\n'
                                    'Vous êtes invité à rejoindre $estabName sur Correctis '
                                    '(correction de copies par IA).\n\n'
                                    'COMMENT REJOINDRE :\n'
                                    '1. Installez Correctis depuis le Play Store\n'
                                    '2. Ouvrez l\'app et appuyez sur "J\'ai un code d\'invitation"\n'
                                    '3. Collez ce code :\n\n'
                                    '${result.invitation.token}\n\n'
                                    'L\'invitation est valable 48h.';
                                if (!context.mounted) return;
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.card,
                                    title: Text(
                                      result.emailResult.ok
                                          ? 'Invitation envoyée'
                                          : 'Invitation créée',
                                      style: AppFonts.fraunces(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          result.emailResult.ok
                                              ? 'Email envoyé à $emailTarget (vérifiez les spams si non reçu).'
                                              : 'L\'email n\'a pas pu être envoyé automatiquement (${result.emailResult.errorMessage ?? "raison inconnue"}).',
                                          style: AppFonts.sans(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Vous pouvez aussi partager le lien manuellement (WhatsApp, SMS).',
                                          style: AppFonts.sans(
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                InvitationQrDialog(
                                              token:
                                                  result.invitation.token,
                                              email: result
                                                  .invitation.email,
                                              establishmentName:
                                                  estabName,
                                            ),
                                          );
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.qr_code_2_rounded,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text('QR Code'),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                              ClipboardData(text: link));
                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content:
                                                  Text('Lien copié.'),
                                              behavior: SnackBarBehavior
                                                  .floating,
                                            ),
                                          );
                                        },
                                        child: const Text('Copier'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          await Share.share(
                                            msg,
                                            subject:
                                                'Invitation Correctis — $estabName',
                                          );
                                        },
                                        child: Text(
                                          'Partager',
                                          style: TextStyle(
                                            color: AppColors.adminPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx),
                                        child: const Text('Fermer'),
                                      ),
                                    ],
                                  ),
                                );
                              } catch (e) {
                                // L'insert DB lui-même a échoué (RLS, réseau…)
                                if (!dialogCtx.mounted) return;
                                setStateDialog(() => sending = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erreur création invitation : $e',
                                    ),
                                    backgroundColor: AppColors.danger,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: sending
                        ? null
                        : () => Navigator.of(dialogCtx).pop(),
                    child: Text(
                      'Annuler',
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.textMuted,
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

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EstablishmentService>();
    final query = _searchCtrl.text.trim().toLowerCase();
    // Michel : dedup par user_id (filet client — fix DB dans migration
    // 20260903000005 pour get_my_establishment_members).
    final _seen = <String>{};
    final all = svc.members
        .where((m) => m.isTeacher)
        .where((m) => _seen.add(m.userId))
        .toList();
    final filtered = all.where((m) {
      if (query.isEmpty) return true;
      return m.displayNameOrEmail.toLowerCase().contains(query) ||
          (m.matiere ?? '').toLowerCase().contains(query) ||
          (m.email ?? '').toLowerCase().contains(query);
    }).toList();
    final activeCount = all.where((m) => m.isActive).length;
    final pendingInv =
        svc.pendingInvitations.where((i) => i.isPending).toList();

    return Column(
      children: [
        // ━━━━━━ HEADER ━━━━━━
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GESTION',
                          style: AppFonts.mono(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enseignants',
                          style: AppFonts.fraunces(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${all.length} membre${all.length != 1 ? "s" : ""} · '
                          '$activeCount actif${activeCount != 1 ? "s" : ""}'
                          '${pendingInv.isNotEmpty ? " · ${pendingInv.length} en attente" : ""}',
                          style: AppFonts.sans(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: AppFonts.sans(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Rechercher un enseignant…',
                  hintStyle: AppFonts.sans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
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
                        color: AppColors.adminPrimary, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ━━━━━━ LISTE ━━━━━━
        Expanded(
          child: RefreshIndicator(
            color: AppColors.adminPrimary,
            onRefresh: () => svc.refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              itemCount:
                  filtered.length + pendingInv.length + 1, // +1 = invite card
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                // Teachers
                if (i < filtered.length) {
                  return _TeacherRow(member: filtered[i]);
                }
                // Invitations en attente
                final invIndex = i - filtered.length;
                if (invIndex < pendingInv.length) {
                  return _PendingInvitationRow(invitation: pendingInv[invIndex]);
                }
                // Retour Michel : nouveau flow — la carte ouvre le nouvel
                // écran de gestion des slots profs (CRUD complet + matières).
                return _InviteCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminTeacherSlotsScreen(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TeacherRow extends StatelessWidget {
  final EstablishmentMember member;
  const _TeacherRow({required this.member});

  String get _avatarKey {
    const keys = ['blue', 'green', 'purple', 'amber'];
    return keys[member.userId.hashCode.abs() % keys.length];
  }

  Future<void> _suspend(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Suspendre ${member.displayNameOrEmail} ?',
          style: AppFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Cet enseignant ne pourra plus envoyer de notes au casier de '
          'votre école. Vous pourrez le réactiver à tout moment. '
          'Ses notes déjà publiées restent dans le casier.',
          style: AppFonts.sans(
            fontSize: 12.5,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Suspendre',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<EstablishmentService>().suspendMember(member.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enseignant suspendu.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _unsuspend(BuildContext context) async {
    try {
      await context.read<EstablishmentService>().unsuspendMember(member.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enseignant réactivé.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
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
    final subtitle = [
      if (member.matiere?.isNotEmpty == true) member.matiere!,
      if (member.classes.isNotEmpty) member.classes.join(', '),
      if (member.email?.isNotEmpty == true) member.email!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: member.isActive ? 1 : 0.5,
            child: AdminAvatar(
              initials: member.initials,
              avatarKey: _avatarKey,
              size: 44,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayNameOrEmail,
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: member.isActive
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isEmpty ? 'Enseignant' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: member.isActive
                  ? AppColors.profPrimary.withValues(alpha: 0.12)
                  : AppColors.textMuted.withValues(alpha: 0.12),
              border: Border.all(
                color: member.isActive
                    ? AppColors.profPrimary.withValues(alpha: 0.3)
                    : AppColors.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              member.isActive ? 'ACTIF' : 'SUSPENDU',
              style: AppFonts.mono(
                fontSize: 8.5,
                letterSpacing: 1,
                color: member.isActive
                    ? AppColors.profPrimary
                    : AppColors.textMuted,
              ),
            ),
          ),
          // Menu kebab : suspendre / réactiver
          if (!member.isAdmin)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
              color: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: const BorderSide(color: AppColors.borderSubtle),
              ),
              onSelected: (v) {
                if (v == 'suspend') _suspend(context);
                if (v == 'unsuspend') _unsuspend(context);
              },
              itemBuilder: (_) => [
                if (member.isActive)
                  PopupMenuItem(
                    value: 'suspend',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Suspendre',
                          style: AppFonts.sans(
                            fontSize: 12,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  PopupMenuItem(
                    value: 'unsuspend',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: AppColors.profPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Réactiver',
                          style: AppFonts.sans(
                            fontSize: 12,
                            color: AppColors.profPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PendingInvitationRow extends StatelessWidget {
  final EstablishmentInvitation invitation;
  const _PendingInvitationRow({required this.invitation});

  /// Construit le lien d'invitation à partager (deep-link Correctis).
  String _inviteLink() => 'correctis://invite?token=${invitation.token}';

  void _showQr(BuildContext context) {
    final svc = context.read<EstablishmentService>();
    final estabName =
        svc.currentEstablishment?.name ?? 'l\'établissement';
    showDialog<void>(
      context: context,
      builder: (_) => InvitationQrDialog(
        token: invitation.token,
        email: invitation.email,
        establishmentName: estabName,
      ),
    );
  }

  /// Message clé en main que l'admin peut coller dans WhatsApp/SMS.
  String _shareMessage(String establishmentName) {
    return 'Bonjour,\n\n'
        'Vous êtes invité à rejoindre $establishmentName sur Correctis '
        '(correction de copies par IA).\n\n'
        'COMMENT REJOINDRE :\n'
        '1. Installez Correctis depuis le Play Store\n'
        '2. Ouvrez l\'app et appuyez sur "J\'ai un code d\'invitation" '
        '(sur l\'écran de connexion)\n'
        '3. Collez ce code :\n\n'
        '${invitation.token}\n\n'
        'L\'invitation est valable 48h. À très vite !';
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _inviteLink()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Lien copié. Collez-le dans WhatsApp / SMS pour l\'enseignant.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _shareLink(BuildContext context) async {
    final svc = context.read<EstablishmentService>();
    final establishmentName =
        svc.currentEstablishment?.name ?? 'l\'établissement';
    await Share.share(
      _shareMessage(establishmentName),
      subject: 'Invitation Correctis — $establishmentName',
    );
  }

  Future<void> _resend(BuildContext context) async {
    final svc = context.read<EstablishmentService>();
    try {
      final r = await svc.resendInvitationEmail(invitation.id);
      if (!context.mounted) return;
      if (r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Email renvoyé à ${invitation.email}. Vérifiez les spams.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Échec du renvoi : ${r.errorMessage ?? "raison inconnue"}'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Annuler l\'invitation ?',
          style: AppFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Le lien envoyé à ${invitation.email} ne sera plus valable.',
          style: AppFonts.sans(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Annuler',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await context
          .read<EstablishmentService>()
          .cancelInvitation(invitation.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation annulée.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
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
    final hoursLeft = invitation.expiresAt
        .difference(DateTime.now())
        .inHours
        .clamp(0, 48);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.hourglass_top_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'En attente · expire dans ${hoursLeft}h'
                  '${invitation.matiere != null ? " · ${invitation.matiere}" : ""}',
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          // Boutons d'action visibles directement (gain UX vs menu caché)
          IconButton(
            tooltip: 'QR code (présentiel)',
            onPressed: () => _showQr(context),
            icon: Icon(
              Icons.qr_code_2_rounded,
              color: AppColors.warning,
              size: 22,
            ),
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            tooltip: 'Partager le lien (WhatsApp, SMS…)',
            onPressed: () => _shareLink(context),
            icon: Icon(
              Icons.share_outlined,
              color: AppColors.warning,
              size: 20,
            ),
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            padding: EdgeInsets.zero,
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: AppColors.warning,
              size: 20,
            ),
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
            onSelected: (v) {
              if (v == 'copy') _copyLink(context);
              if (v == 'resend') _resend(context);
              if (v == 'cancel') _cancel(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text('Copier le lien',
                        style: AppFonts.sans(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'resend',
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, size: 16),
                    const SizedBox(width: 8),
                    Text('Renvoyer l\'email',
                        style: AppFonts.sans(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'cancel',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 16, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Annuler l\'invitation',
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final VoidCallback onTap;
  const _InviteCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.adminPrimary.withValues(alpha: 0.04),
            border: Border.all(
              color: AppColors.adminPrimary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      AppColors.adminPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: AppColors.adminPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Inviter un enseignant',
                style: AppFonts.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.adminPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Lien sécurisé valable 48h',
                style: AppFonts.sans(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
