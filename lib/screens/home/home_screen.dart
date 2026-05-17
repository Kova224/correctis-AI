import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/ranking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/activity_bar_chart.dart';
import '../../widgets/dashboard_stats_card.dart';
import '../../widgets/exam_card.dart';
import '../../widgets/greeting_banner.dart';
import '../../widgets/quick_actions_grid.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/score_line_chart.dart';
import '../../widgets/section_card.dart';
import '../../widgets/top_students_chart.dart';
import '../auth/login_screen.dart';
import '../chatbot/chatbot_sheet.dart';
import '../exam/create_exam_screen.dart';
import '../exam/exam_detail_screen.dart';
import '../profile/profile_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  bool _greetingShown = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final examSvc = context.watch<ExamService>();
    final user = auth.currentUser;
    if (user == null) {
      return const LoginScreen();
    }
    final exams = examSvc.examsForUser(user.id);

    // Affichage de la salutation chaleureuse une fois par session.
    if (!_greetingShown) {
      _greetingShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GreetingBanner.show(context, displayName: user.displayName);
      });
    }

    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 240,
            actions: [
              HeaderCircleAction(
                icon: Icons.smart_toy_outlined,
                tooltip: 'Correctis Chatbot',
                onPressed: () => showChatBotSheet(context),
              ),
              _HeaderAvatar(
                user: user,
                onTap: () => showProfileSheet(context),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bonjour,',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                ),
                Text(
                  user.displayName.isEmpty ? 'Professeur' : user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${exams.length} examen${exams.length > 1 ? 's' : ''} en cours',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => examSvc.bootstrap(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  // ===== Stats card =====
                  _SectionTitle(
                    icon: Icons.dashboard_rounded,
                    title: 'Vue d\'ensemble',
                  ),
                  const SizedBox(height: 10),
                  DashboardStatsCard(
                    stats: _computeStats(examSvc, user.id),
                  ),
                  const SizedBox(height: 22),
                  // ===== Quick actions grid =====
                  _SectionTitle(
                    icon: Icons.flash_on_rounded,
                    title: 'Actions rapides',
                  ),
                  const SizedBox(height: 10),
                  QuickActionsGrid(
                    actions: _buildQuickActions(context, exams.length),
                  ),
                  const SizedBox(height: 22),
                  // ===== Activité hebdomadaire (bar chart) =====
                  _SectionTitle(
                    icon: Icons.calendar_view_week_rounded,
                    title: 'Activité hebdomadaire',
                  ),
                  const SizedBox(height: 10),
                  ActivityBarChart(
                    days: _computeWeeklyActivity(examSvc, user.id),
                  ),
                  const SizedBox(height: 22),
                  // ===== Évolution des notes (line chart) =====
                  _SectionTitle(
                    icon: Icons.show_chart_rounded,
                    title: 'Évolution des moyennes',
                  ),
                  const SizedBox(height: 10),
                  ScoreLineChart(
                    points: _computeScorePoints(examSvc, user.id),
                  ),
                  const SizedBox(height: 22),
                  // ===== Top élèves =====
                  if (exams.isNotEmpty) ...[
                    _SectionTitle(
                      icon: Icons.emoji_events_rounded,
                      title: 'Meilleurs élèves',
                    ),
                    const SizedBox(height: 10),
                    _TopStudentsCard(examSvc: examSvc, userId: user.id),
                    const SizedBox(height: 22),
                  ],
                  // ===== Liste examens =====
                  if (exams.isEmpty)
                    _emptyState(context)
                  else ...[
                    _SectionTitle(
                      icon: Icons.assignment_outlined,
                      title: 'Mes examens',
                      trailingCount: exams.length,
                    ),
                    const SizedBox(height: 10),
                    ...exams.map((exam) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ExamCard(
                          exam: exam,
                          copies: examSvc.copiesFor(exam.id),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ExamDetailScreen(examId: exam.id),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateExamScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel examen'),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) async {
          if (i == 2) {
            // Profil → ouvre le bottom sheet et reste sur l'onglet précédent
            await showProfileSheet(context);
            return;
          }
          setState(() => _currentTab = i);
          if (i == 1 && exams.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExamDetailScreen(examId: exams.first.id),
              ),
            );
            // Réinitialise sur "Examens" après retour
            if (mounted) setState(() => _currentTab = 0);
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Examens',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Récents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Helpers : stats + actions rapides
  // ===========================================================================
  DashboardStats _computeStats(ExamService examSvc, String userId) {
    final exams = examSvc.examsForUser(userId);
    int total = 0, graded = 0;
    double sumScores = 0, sumMax = 0;
    for (final e in exams) {
      final maxPts = e.computedTotal == 0 ? e.totalPoints : e.computedTotal;
      final copies = examSvc.copiesFor(e.id);
      total += copies.length;
      for (final c in copies) {
        if (c.status == CopyStatus.graded) {
          graded++;
          sumScores += c.totalScore;
          sumMax += maxPts;
        }
      }
    }
    final avg = sumMax == 0 ? 0.0 : (sumScores / sumMax) * 100;
    return DashboardStats(
      examsCount: exams.length,
      copiesGraded: graded,
      copiesTotal: total,
      averagePercent: avg,
    );
  }

  /// Compte les copies corrigées et scannées pour chaque jour des 7 derniers jours.
  List<DayActivity> _computeWeeklyActivity(
      ExamService examSvc, String userId) {
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final now = DateTime.now();
    // Démarre lundi de cette semaine
    final monday = now.subtract(Duration(days: (now.weekday - 1) % 7));
    final mondayStart = DateTime(monday.year, monday.month, monday.day);

    final graded = List<int>.filled(7, 0);
    final scanned = List<int>.filled(7, 0);

    final exams = examSvc.examsForUser(userId);
    for (final e in exams) {
      for (final c in examSvc.copiesFor(e.id)) {
        // scan = createdAt
        final scanDay = _dayIndex(c.createdAt, mondayStart);
        if (scanDay != null) scanned[scanDay]++;
        // graded
        if (c.gradedAt != null) {
          final gradedDay = _dayIndex(c.gradedAt!, mondayStart);
          if (gradedDay != null) graded[gradedDay]++;
        }
      }
    }
    final todayIdx = (now.weekday - 1) % 7;
    return List.generate(
      7,
      (i) => DayActivity(
        label: labels[i],
        graded: graded[i],
        scanned: scanned[i],
        isToday: i == todayIdx,
      ),
    );
  }

  int? _dayIndex(DateTime date, DateTime mondayStart) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(mondayStart).inDays;
    if (diff < 0 || diff > 6) return null;
    return diff;
  }

  /// Moyenne en % par examen, ordonnée chronologiquement.
  List<ScorePoint> _computeScorePoints(ExamService examSvc, String userId) {
    final exams = examSvc.examsForUser(userId).reversed.toList();
    final pts = <ScorePoint>[];
    for (final e in exams) {
      final maxPts = e.computedTotal == 0 ? e.totalPoints : e.computedTotal;
      if (maxPts == 0) continue;
      final copies = examSvc
          .copiesFor(e.id)
          .where((c) => c.status == CopyStatus.graded)
          .toList();
      if (copies.isEmpty) continue;
      final avg = copies.fold<double>(0, (s, c) => s + c.totalScore) /
          copies.length;
      final percent = (avg / maxPts) * 100;
      // Label court : "Maths-12", on prend les 8 premiers caractères
      final label = e.title.length > 9 ? '${e.title.substring(0, 8)}…' : e.title;
      pts.add(ScorePoint(label: label, percent: percent));
    }
    return pts;
  }

  List<QuickAction> _buildQuickActions(BuildContext context, int examsCount) {
    return [
      QuickAction(
        icon: Icons.add_chart_rounded,
        label: 'Nouvel\nexamen',
        color: const Color(0xFFE0F7F6),
        iconColor: AppColors.accentDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateExamScreen()),
        ),
      ),
      QuickAction(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scanner\nune copie',
        color: const Color(0xFFE3E9FE),
        iconColor: AppColors.primary,
        badge: examsCount > 0 ? null : null,
        onTap: () => _openLatestExamForScan(context),
      ),
      QuickAction(
        icon: Icons.emoji_events_rounded,
        label: 'Classement\ndes élèves',
        color: const Color(0xFFFFF4DC),
        iconColor: const Color(0xFFE0A82E),
        onTap: () => _openLatestExamForRanking(context),
      ),
      QuickAction(
        icon: Icons.smart_toy_outlined,
        label: 'Correctis\nChatbot',
        color: const Color(0xFFEFE6FF),
        iconColor: const Color(0xFF7C4DFF),
        onTap: () => showChatBotSheet(context),
      ),
    ];
  }

  void _openLatestExamForScan(BuildContext context) {
    final svc = context.read<ExamService>();
    final user = context.read<AuthService>().currentUser!;
    final exams = svc.examsForUser(user.id);
    if (exams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Créez d\'abord un examen pour scanner des copies.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExamDetailScreen(examId: exams.first.id),
    ));
  }

  void _openLatestExamForRanking(BuildContext context) {
    final svc = context.read<ExamService>();
    final user = context.read<AuthService>().currentUser!;
    final exams = svc.examsForUser(user.id);
    if (exams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun examen pour générer un classement.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExamDetailScreen(examId: exams.first.id),
    ));
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_chart,
                  size: 56, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun examen pour le moment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Appuyez sur le bouton "+" en bas pour créer votre premier examen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titre de section uniforme avec icône à gauche et compteur optionnel à droite.
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? trailingCount;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.trailingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (trailingCount != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$trailingCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Carte dashboard : top 5 élèves toutes classes confondues.
/// Toggle entre "tous" et chaque classe individuellement.
class _TopStudentsCard extends StatefulWidget {
  final ExamService examSvc;
  final String userId;
  const _TopStudentsCard({required this.examSvc, required this.userId});

  @override
  State<_TopStudentsCard> createState() => _TopStudentsCardState();
}

class _TopStudentsCardState extends State<_TopStudentsCard> {
  String? _selectedClass; // null = toutes les classes

  @override
  Widget build(BuildContext context) {
    final exams = widget.examSvc.examsForUser(widget.userId);
    final copiesByExam = <String, List<StudentCopy>>{
      for (final e in exams) e.id: widget.examSvc.copiesFor(e.id)
    };
    final ranking = RankingService().rankByClass(
      exams: exams,
      copiesByExam: copiesByExam,
    );
    final classes = ranking.keys.toList()..sort();

    // Données pour le chart
    final List<TopStudentBar> bars;
    if (_selectedClass == null) {
      // Toutes classes : top 5 globaux
      final all = <TopStudentBar>[];
      ranking.forEach((cls, entries) {
        for (final e in entries) {
          all.add(TopStudentBar(
            name: e.studentName,
            percent: e.percent,
            score: e.score,
            maxScore: e.maxScore,
            className: cls,
          ));
        }
      });
      all.sort((a, b) => b.percent.compareTo(a.percent));
      bars = all.take(5).toList();
    } else {
      bars = (ranking[_selectedClass] ?? const [])
          .take(5)
          .map((e) => TopStudentBar(
                name: e.studentName,
                percent: e.percent,
                score: e.score,
                maxScore: e.maxScore,
                className: _selectedClass,
              ))
          .toList();
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.accentDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meilleurs élèves',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _selectedClass == null
                          ? 'Toutes classes confondues'
                          : 'Classe : $_selectedClass',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (classes.length > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ClassChip(
                    label: 'Toutes',
                    selected: _selectedClass == null,
                    onTap: () => setState(() => _selectedClass = null),
                  ),
                  ...classes.map((c) => _ClassChip(
                        label: c,
                        selected: _selectedClass == c,
                        onTap: () => setState(() => _selectedClass = c),
                      )),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TopStudentsChart(bars: bars),
        ],
      ),
    );
  }
}

class _ClassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ClassChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar cliquable du header — affiche la photo du prof ou ses initiales.
class _HeaderAvatar extends StatelessWidget {
  final dynamic user; // AppUser
  final VoidCallback onTap;
  const _HeaderAvatar({required this.user, required this.onTap});

  String get _initials {
    final name = user.displayName as String? ?? '';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoPath != null &&
        (user.photoPath as String).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: ClipOval(
              child: hasPhoto && File(user.photoPath as String).existsSync()
                  ? Image.file(File(user.photoPath as String),
                      fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        _initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
