import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../auth/login_screen.dart';

/// Affiche le bottom-sheet du profil avec toutes les options.
Future<void> showProfileSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ProfileSheet(),
  );
}

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final stats = _userStats(context, user.id);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    _ProfileHeader(user: user),
                    const SizedBox(height: 18),
                    _StatsRow(stats: stats),
                    const SizedBox(height: 24),
                    Text(
                      'Paramètres du compte',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.edit_outlined,
                      iconColor: AppColors.primary,
                      title: 'Modifier mon profil',
                      subtitle: 'Nom, école, téléphone',
                      onTap: () async {
                        Navigator.of(context).pop();
                        await Future.delayed(
                            const Duration(milliseconds: 200));
                        if (context.mounted) {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ));
                        }
                      },
                    ),
                    _ActionTile(
                      icon: Icons.lock_outline,
                      iconColor: AppColors.warning,
                      title: 'Changer le mot de passe',
                      subtitle: 'Mot de passe actuel + nouveau',
                      onTap: () async {
                        Navigator.of(context).pop();
                        await Future.delayed(
                            const Duration(milliseconds: 200));
                        if (context.mounted) {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen(),
                          ));
                        }
                      },
                    ),
                    _ActionTile(
                      icon: Icons.help_outline,
                      iconColor: AppColors.accent,
                      title: 'Aide & support',
                      subtitle: 'FAQ, contact',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bientôt disponible')),
                        );
                      },
                    ),
                    _ActionTile(
                      icon: Icons.info_outline,
                      iconColor: AppColors.textSecondary,
                      title: 'À propos',
                      subtitle: 'Correctis MVP v1.0',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Correctis',
                          applicationVersion: '1.0.0 (MVP)',
                          applicationIcon: const Icon(Icons.auto_awesome,
                              color: AppColors.primary, size: 36),
                          children: const [
                            SizedBox(height: 8),
                            Text(
                                'Application de correction automatique de copies par IA.'),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md)),
                            title: const Text('Se déconnecter ?'),
                            content: const Text(
                                'Vos données restent sauvegardées localement et seront disponibles à votre prochaine connexion.'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Annuler'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Déconnexion',
                                    style:
                                        TextStyle(color: AppColors.danger)),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await context.read<AuthService>().logout();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                              (_) => false,
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _UserStats _userStats(BuildContext context, String userId) {
    final examSvc = context.read<ExamService>();
    final exams = examSvc.examsForUser(userId);
    int copiesTotal = 0;
    int copiesGraded = 0;
    double sumGrades = 0;
    int countGraded = 0;
    double sumTotalPts = 0;
    for (final exam in exams) {
      final copies = examSvc.copiesFor(exam.id);
      copiesTotal += copies.length;
      final maxPts = exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;
      for (final c in copies) {
        if (c.status.name == 'graded') {
          copiesGraded++;
          sumGrades += c.totalScore;
          sumTotalPts += maxPts;
        }
      }
    }
    final avgPercent =
        sumTotalPts == 0 ? 0.0 : (sumGrades / sumTotalPts) * 100;
    return _UserStats(
      examsCount: exams.length,
      copiesTotal: copiesTotal,
      copiesGraded: copiesGraded,
      averagePercent: avgPercent,
    );
  }
}

// =============================================================================
// HEADER avec avatar
// =============================================================================
class _ProfileHeader extends StatefulWidget {
  final dynamic user; // AppUser
  const _ProfileHeader({required this.user});

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _picking = false;

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _picking = true);
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 600,
      );
      if (f != null && mounted) {
        await context.read<AuthService>().updateProfile(photoPath: f.path);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _showPhotoOptions() async {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: AppColors.primary),
              title: const Text('Choisir depuis la galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (widget.user.photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                title: const Text('Retirer la photo',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () async {
                  Navigator.pop(context);
                  await context
                      .read<AuthService>()
                      .updateProfile(photoPath: '');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            _Avatar(
              photoPath: user.photoPath,
              displayName: user.displayName,
              size: 96,
              loading: _picking,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _showPhotoOptions,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          user.displayName.isEmpty ? 'Professeur' : user.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          user.email,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (user.school != null && user.school.toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            user.school,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoPath;
  final String displayName;
  final double size;
  final bool loading;
  const _Avatar({
    required this.photoPath,
    required this.displayName,
    this.size = 80,
    this.loading = false,
  });

  String get _initials {
    final parts = displayName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Retourne l'Image (file ou network) ou null si pas affichable.
  Widget? _renderPhoto() {
    final p = photoPath;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) {
      return Image.network(p, fit: BoxFit.cover);
    }
    final file = File(p);
    if (!file.existsSync()) return null;
    return Image.file(file, fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null && photoPath!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : (hasPhoto && _renderPhoto() != null
                ? _renderPhoto()!
                : Center(
                    child: Text(
                      _initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )),
      ),
    );
  }
}

// =============================================================================
// STATS
// =============================================================================
class _UserStats {
  final int examsCount;
  final int copiesTotal;
  final int copiesGraded;
  final double averagePercent;
  const _UserStats({
    required this.examsCount,
    required this.copiesTotal,
    required this.copiesGraded,
    required this.averagePercent,
  });
}

class _StatsRow extends StatelessWidget {
  final _UserStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _StatCard(
                icon: Icons.assignment_outlined,
                label: 'Examens',
                value: '${stats.examsCount}')),
        const SizedBox(width: 10),
        Expanded(
            child: _StatCard(
                icon: Icons.fact_check_outlined,
                label: 'Corrigées',
                value: '${stats.copiesGraded}/${stats.copiesTotal}')),
        const SizedBox(width: 10),
        Expanded(
            child: _StatCard(
                icon: Icons.show_chart,
                label: 'Moyenne',
                value: stats.averagePercent.isNaN ||
                        stats.averagePercent == 0
                    ? '—'
                    : '${stats.averagePercent.toStringAsFixed(0)} %')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TILE D'ACTION
// =============================================================================
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ÉCRAN MODIFIER PROFIL
// =============================================================================
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _school;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().currentUser!;
    _name = TextEditingController(text: u.displayName);
    _email = TextEditingController(text: u.email);
    _phone = TextEditingController(text: u.phone ?? '');
    _school = TextEditingController(text: u.school ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthService>().updateProfile(
            displayName: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            school: _school.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil mis à jour'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier mon profil'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CustomTextField(
              label: 'Nom complet *',
              hint: 'Ex : Jean Dupont',
              controller: _name,
              prefixIcon: Icons.person_outline,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nom requis' : null,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'Email *',
              hint: 'email@exemple.com',
              controller: _email,
              prefixIcon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email requis';
                if (!v.contains('@')) return 'Email invalide';
                return null;
              },
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'Téléphone',
              hint: '+221 77 000 00 00',
              controller: _phone,
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'École / Établissement',
              hint: 'Ex : Lycée Blaise Diagne',
              controller: _school,
              prefixIcon: Icons.school_outlined,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ÉCRAN CHANGER MOT DE PASSE
// =============================================================================
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _newPwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPwd.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les deux mots de passe ne correspondent pas.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AuthService>().changePassword(
            currentPassword: _current.text,
            newPassword: _newPwd.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mot de passe modifié'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Changer le mot de passe'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CustomTextField(
              label: 'Mot de passe actuel',
              hint: '••••••••',
              controller: _current,
              prefixIcon: Icons.lock_outline,
              obscureText: true,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'Nouveau mot de passe',
              hint: 'Min. 4 caractères',
              controller: _newPwd,
              prefixIcon: Icons.vpn_key_outlined,
              obscureText: true,
              validator: (v) =>
                  v == null || v.length < 4 ? 'Min. 4 caractères' : null,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'Confirmer',
              hint: 'Retapez le nouveau mot de passe',
              controller: _confirm,
              prefixIcon: Icons.vpn_key_outlined,
              obscureText: true,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Mettre à jour',
              icon: Icons.check,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
