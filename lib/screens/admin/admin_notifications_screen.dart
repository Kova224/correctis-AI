import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../models/notification.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';

/// G — Admin compose / consulte les notifications envoyées aux profs.
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends State<AdminNotificationsScreen> {
  bool _loading = true;
  List<AppNotification> _sent = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = context.read<EstablishmentService>();
    final list = await svc.loadSentNotifications();
    if (!mounted) return;
    setState(() {
      _sent = list;
      _loading = false;
    });
  }

  Future<void> _openCompose() async {
    final svc = context.read<EstablishmentService>();
    final teachers = svc.members
        .where((m) => m.isTeacher && m.isActive)
        .toList();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeNotificationSheet(teachers: teachers),
    );
    if (sent == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Notifications',
              style: AppFonts.fraunces(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Messages envoyés aux enseignants',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.adminPrimary,
        foregroundColor: Colors.white,
        onPressed: _openCompose,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(
          'Nouveau message',
          style: AppFonts.mono(
            fontSize: 11,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.adminPrimary),
                ),
              ),
            )
          : (_sent.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppColors.adminPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: _sent.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = _sent[i];
                      return _SentTile(notification: n);
                    },
                  ),
                )),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.campaign_outlined,
              size: 42,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucun message envoyé',
              style: AppFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vos communications aux enseignants\napparaîtront ici.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCompose,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.adminPrimary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Composer un message',
                style: AppFonts.mono(
                  fontSize: 11,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SentTile extends StatelessWidget {
  final AppNotification notification;
  const _SentTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM y · HH:mm', 'fr_FR');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: notification.isBroadcast
                      ? AppColors.adminPrimary.withValues(alpha: 0.12)
                      : AppColors.primaryLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  notification.isBroadcast
                      ? 'TOUS LES PROFS'
                      : '${notification.targets!.length} CIBLÉ${notification.targets!.length > 1 ? "S" : ""}',
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: notification.isBroadcast
                        ? AppColors.adminPrimary
                        : AppColors.primaryLight,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                df.format(notification.createdAt.toLocal()),
                style: AppFonts.mono(
                  fontSize: 9.5,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notification.title,
            style: AppFonts.fraunces(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            notification.body,
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.done_all_rounded,
                size: 13,
                color: AppColors.profPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                '${notification.readCount ?? 0} / ${notification.totalRecipients ?? 0} lu${(notification.readCount ?? 0) > 1 ? "s" : ""}',
                style: AppFonts.mono(
                  fontSize: 9.5,
                  color: AppColors.profPrimary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet "Composer un message"
// ─────────────────────────────────────────────────────────────────────────────
class _ComposeNotificationSheet extends StatefulWidget {
  final List<EstablishmentMember> teachers;
  const _ComposeNotificationSheet({required this.teachers});

  @override
  State<_ComposeNotificationSheet> createState() =>
      _ComposeNotificationSheetState();
}

class _ComposeNotificationSheetState
    extends State<_ComposeNotificationSheet> {
  final _titleCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  final Set<String> _selected = {};
  bool _broadcast = true;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleCtl.text.trim().isEmpty || _bodyCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Titre et message obligatoires.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_broadcast && _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez au moins un destinataire.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<EstablishmentService>().sendNotification(
            title: _titleCtl.text.trim(),
            body: _bodyCtl.text.trim(),
            targets: _broadcast ? null : _selected.toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _broadcast
                ? 'Message envoyé à tous les enseignants.'
                : 'Message envoyé à ${_selected.length} enseignant${_selected.length > 1 ? "s" : ""}.',
          ),
          backgroundColor: AppColors.profPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'NOUVEAU MESSAGE',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'À vos enseignants',
                  style: AppFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),

                // Sélecteur destinataires
                Row(
                  children: [
                    Expanded(
                      child: _DestPill(
                        label: 'Tous les profs',
                        active: _broadcast,
                        onTap: () =>
                            setState(() => _broadcast = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DestPill(
                        label: 'Sélectionner',
                        active: !_broadcast,
                        onTap: () =>
                            setState(() => _broadcast = false),
                      ),
                    ),
                  ],
                ),
                if (!_broadcast) ...[
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderSubtle),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: widget.teachers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'Aucun enseignant à cibler.',
                              style: AppFonts.sans(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: widget.teachers.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppColors.borderSubtle,
                            ),
                            itemBuilder: (_, i) {
                              final t = widget.teachers[i];
                              final name = t.displayName ??
                                  t.email ??
                                  'Enseignant';
                              final checked =
                                  _selected.contains(t.userId);
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(t.userId);
                                    } else {
                                      _selected.remove(t.userId);
                                    }
                                  });
                                },
                                title: Text(
                                  name,
                                  style: AppFonts.sans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: t.matiere != null
                                    ? Text(
                                        t.matiere!,
                                        style: AppFonts.sans(
                                          fontSize: 10.5,
                                          color: AppColors.textMuted,
                                        ),
                                      )
                                    : null,
                                activeColor: AppColors.adminPrimary,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            },
                          ),
                  ),
                ],

                const SizedBox(height: 16),
                _labelField('TITRE'),
                TextField(
                  controller: _titleCtl,
                  maxLength: 80,
                  style: AppFonts.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: _decoration('Réunion pédagogique, rappel…'),
                ),
                const SizedBox(height: 8),
                _labelField('MESSAGE'),
                TextField(
                  controller: _bodyCtl,
                  maxLines: 6,
                  minLines: 4,
                  maxLength: 1000,
                  style: AppFonts.sans(
                    fontSize: 13,
                    height: 1.45,
                  ),
                  decoration: _decoration(
                      'Détails que vos enseignants doivent connaître…'),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          side: const BorderSide(
                              color: AppColors.borderSubtle),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: Text(
                          'ANNULER',
                          style: AppFonts.mono(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.adminPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                'ENVOYER',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelField(String l) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          l,
          style: AppFonts.mono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 1.6,
          ),
        ),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppFonts.sans(
          fontSize: 12.5,
          color: AppColors.textMuted,
        ),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(
              color: AppColors.adminPrimary, width: 1.5),
        ),
      );
}

class _DestPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DestPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppColors.adminPrimary
          : AppColors.adminPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active
                  ? AppColors.adminPrimary
                  : AppColors.adminPrimary.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: AppFonts.mono(
              fontSize: 10.5,
              color: active ? Colors.white : AppColors.adminPrimary,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
