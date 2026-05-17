import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/copy.dart';
import '../models/exam.dart';
import '../theme/app_theme.dart';

class ExamCard extends StatelessWidget {
  final Exam exam;
  final List<StudentCopy> copies;
  final VoidCallback? onTap;

  const ExamCard({
    super.key,
    required this.exam,
    required this.copies,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final graded = copies.where((c) => c.status == CopyStatus.graded).length;
    final pending = copies.where((c) => c.status != CopyStatus.graded).length;
    final progress = copies.isEmpty ? 0.0 : graded / copies.length;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.description_outlined,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (exam.className?.isNotEmpty == true)
                              exam.className!,
                            DateFormat('d MMM yyyy', 'fr_FR')
                                .format(exam.updatedAt),
                          ].join(' • '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statBadge(
                    icon: Icons.check_circle_outline,
                    label: '$graded corrigée${graded > 1 ? 's' : ''}',
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  _statBadge(
                    icon: Icons.hourglass_empty,
                    label: '$pending en attente',
                    color: AppColors.warning,
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)} %',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: progress,
                  backgroundColor: AppColors.surfaceMuted,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
