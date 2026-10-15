import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/notification.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';

/// Boîte de réception des notifications côté prof (lecture seule).
class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState
    extends State<NotificationsInboxScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await context.read<EstablishmentService>().loadMyNotifications();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EstablishmentService>();
    final notifs = svc.myNotifications;

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
              'Messages de vos établissements',
              style: AppFonts.mono(
                fontSize: 9.5,
                color: AppColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
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
                      AlwaysStoppedAnimation(AppColors.profPrimary),
                ),
              ),
            )
          : (notifs.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppColors.profPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: notifs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = notifs[i];
                      return _InboxTile(
                        notification: n,
                        onOpen: () => _openDetails(n),
                      );
                    },
                  ),
                )),
    );
  }

  Future<void> _openDetails(AppNotification n) async {
    if (!n.isRead) {
      await context
          .read<EstablishmentService>()
          .markNotificationRead(n.id);
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(notification: n),
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
              Icons.notifications_off_outlined,
              size: 42,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune notification',
              style: AppFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Les messages envoyés par l\'administration\nde vos établissements arriveront ici.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onOpen;
  const _InboxTile({required this.notification, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM · HH:mm', 'fr_FR');
    final isUnread = !notification.isRead;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isUnread
                  ? AppColors.profPrimary.withValues(alpha: 0.35)
                  : AppColors.borderSubtle,
              width: isUnread ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.profPrimary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      notification.title,
                      style: AppFonts.fraunces(
                        fontSize: 14.5,
                        fontWeight:
                            isUnread ? FontWeight.w700 : FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 4),
              Text(
                notification.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_rounded,
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${notification.establishmentName ?? "—"} · ${notification.authorName ?? "Admin"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.mono(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationDetailSheet extends StatelessWidget {
  final AppNotification notification;
  const _NotificationDetailSheet({required this.notification});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEEE d MMMM y · HH:mm', 'fr_FR');
    return Container(
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
              const SizedBox(height: 16),
              Text(
                'MESSAGE DE L\'ÉCOLE',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                notification.title,
                style: AppFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_rounded,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${notification.establishmentName ?? "—"} · ${notification.authorName ?? "Admin"}',
                      style: AppFonts.sans(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                df.format(notification.createdAt.toLocal()),
                style: AppFonts.mono(
                  fontSize: 9.5,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const Divider(height: 28, color: AppColors.borderSubtle),
              SelectableText(
                notification.body,
                style: AppFonts.sans(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'FERMER',
                    style: AppFonts.mono(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
