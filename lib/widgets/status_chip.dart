import 'package:flutter/material.dart';

import '../models/copy.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final CopyStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      CopyStatus.graded => (AppColors.success, Icons.check_circle),
      CopyStatus.processing => (AppColors.warning, Icons.refresh),
      CopyStatus.pending => (AppColors.textMuted, Icons.hourglass_empty),
      CopyStatus.error => (AppColors.danger, Icons.error_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
