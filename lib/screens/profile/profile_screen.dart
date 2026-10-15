import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.dart';
import '../../models/copy.dart';
import '../../services/auth_service.dart';
import '../../services/establishment_service.dart';
import '../../services/exam_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_version_footer.dart';
import '../auth/login_screen.dart';
import '../admin/admin_home_screen.dart';
import 'delete_account_screen.dart';
import 'my_schools_screen.dart';
import '../../services/credits_service.dart';
import '../credits/my_credits_screen.dart';
import 'language_screen.dart';
import 'notifications_screen.dart';
import 'profile_sheet.dart' show EditProfileScreen, ChangePasswordScreen;
import 'support_screen.dart';

/// Écran Profil — V2 selon maquette P7.
///
/// Wrapper Scaffold de [ProfileBody]. Utilisé pour la navigation directe
/// (tap sur l'avatar du header → push). Affiche un bouton retour en haut.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        bottom: false,
        child: ProfileBody(showBackButton: true),
      ),
    );
  }
}

/// Contenu de l'écran Profil — réutilisable sans Scaffold (pour IndexedStack).
///
/// Paramètres :
///   - [showBackButton] : si true (ProfileScreen pushed), affiche un bouton retour
///     en haut à gauche. Sinon (embedded dans HomeScreen), pas de bouton.
class ProfileBody extends StatefulWidget {
  final bool showBackButton;
  const ProfileBody({super.key, this.showBackButton = false});

  @override
  State<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<ProfileBody> {
  final _picker = ImagePicker();
  bool _pickingPhoto = false;

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _pickingPhoto = true);
    try {
      final XFile? f = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 600,
      );
      if (f != null && mounted) {
        await context.read<AuthService>().updateProfile(photoPath: f.path);
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _showPhotoOptions() async {
    final user = context.read<AuthService>().currentUser;
    final hasPhoto = user?.photoPath != null && user!.photoPath!.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.profPrimary),
              title: Text(
                'Prendre une photo',
                style: AppFonts.sans(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: AppColors.profPrimary),
              title: Text(
                'Choisir depuis la galerie',
                style: AppFonts.sans(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                title: Text(
                  'Retirer la photo',
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.danger,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (mounted) {
                    await context
                        .read<AuthService>()
                        .updateProfile(photoPath: '');
                  }
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
    final auth = context.watch<AuthService>();
    final examSvc = context.watch<ExamService>();
    final user = auth.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    final stats = _computeStats(examSvc, user.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
              // ━━━━━━ BACK BUTTON (uniquement si pushed via avatar) ━━━━━━
              if (widget.showBackButton)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: AppColors.card,
                    shape: const CircleBorder(
                      side: BorderSide(color: AppColors.borderSubtle),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),

              // ━━━━━━ HEADER : avatar + nom + école + matières ━━━━━━
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    // Avatar tappable pour changer la photo
                    Stack(
                      children: [
                        _ProfileAvatar(
                          user: user,
                          size: 72,
                          loading: _pickingPhoto,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap:
                                _pickingPhoto ? null : _showPhotoOptions,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                gradient: AppColors.profGradient,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.voidBg,
                                  width: 2.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user.displayName.isEmpty
                          ? 'Professeur'
                          : user.displayName,
                      style: AppFonts.fraunces(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.school?.isNotEmpty == true
                          ? user.school!
                          : 'École non renseignée',
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        _MatierePill(label: 'Enseignant'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ━━━━━━ CARTE MES CRÉDITS (pay-as-you-go, grille v5) ━━━━━━
              // Pas d'abonnement : le prof solo achète des packs de crédits.
              // Les profs rattachés à une école consomment le quota que
              // l'admin leur attribue (visible dans « Mes crédits »).
              Consumer<EstablishmentService>(
                builder: (context, estab, _) {
                  if (estab.hasEstablishment) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _CreditsCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyCreditsScreen(),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ━━━━━━ 3 STATS CARDS ━━━━━━
              Row(
                children: [
                  Expanded(
                    child: _MiniStatCard(
                      value: '${stats.examsCount}',
                      label: 'EXAMENS',
                      color: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStatCard(
                      value: '${stats.copiesGraded}',
                      label: 'COPIES',
                      color: AppColors.profPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStatCard(
                      value: stats.averagePercent.isNaN ||
                              stats.copiesGraded == 0
                          ? '—'
                          : '${stats.averagePercent.toStringAsFixed(0)}%',
                      label: 'MOYENNE',
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ━━━━━━ PARAMÈTRES ━━━━━━
              Text(
                'PARAMÈTRES',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              _SettingRow(
                icon: Icons.person_outline,
                label: 'Modifier mon profil',
                subtitle: 'Nom, école, téléphone',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EditProfileScreen(),
                  ),
                ),
              ),
              _SettingRow(
                icon: Icons.lock_outline,
                label: auth.isOAuthOnlyAccount
                    ? 'Définir un mot de passe'
                    : 'Changer le mot de passe',
                subtitle: auth.isOAuthOnlyAccount
                    ? 'Permet aussi le login email/password'
                    : 'Nouveau mot de passe',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
              ),
              // Section Mes Crédits (Pay-as-you-go).
              // Pour les profs rattachés à une école, on indique le pool
              // établissement disponible en complément.
              Consumer<CreditsService>(
                builder: (context, credits, _) {
                  final total = credits.wallet.totalCredits;
                  final pool = credits.orgWallet.totalCredits;
                  final subtitle = pool > 0
                      ? '$total perso · $pool pool établissement'
                      : '$total crédit${total != 1 ? "s" : ""} disponible${total != 1 ? "s" : ""}';
                  return _SettingRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Mes crédits',
                    subtitle: subtitle,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyCreditsScreen(),
                      ),
                    ),
                  );
                },
              ),
              _SettingRow(
                icon: Icons.notifications_outlined,
                label: S.of(context).notifications,
                subtitle: S.of(context).pick(
                  'Préférences de notifications',
                  'Notification preferences',
                  'تفضيلات الإشعارات',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              // ━━━━━━ MES ÉCOLES ━━━━━━
              // Écran de gestion des écoles rattachées (nouveau flow Michel :
              // Joindre une école via email + identifiant).
              _SettingRow(
                icon: Icons.account_balance_rounded,
                label: 'Mes écoles',
                subtitle: 'Rejoindre, basculer entre vos écoles',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MySchoolsScreen(),
                  ),
                ),
              ),

              // ━━━━━━ VUE ADMIN ÉTABLISSEMENT ━━━━━━
              // Carte visible UNIQUEMENT pour les administrateurs.
              // Le widget _AdminEstablishmentTile fait un refresh silencieux
              // au build pour rattraper un bootstrap incomplet.
              const _AdminEstablishmentTile(),
              Consumer<LocaleService>(
                builder: (context, localeSvc, _) => _SettingRow(
                  icon: Icons.language_outlined,
                  label: S.of(context).language,
                  subtitle:
                      '${localeSvc.current.flag} ${localeSvc.current.label}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LanguageScreen(),
                    ),
                  ),
                ),
              ),

              _SettingRow(
                icon: Icons.support_agent_outlined,
                label: S.of(context).support,
                subtitle: S.of(context).pick(
                  'Email, WhatsApp ou formulaire',
                  'Email, WhatsApp or form',
                  'البريد الإلكتروني، واتساب أو نموذج',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ━━━━━━ DÉCONNEXION ━━━━━━
              _SettingRow(
                icon: Icons.logout,
                label: S.of(context).logout,
                subtitle: '',
                danger: true,
                onTap: () => _confirmLogout(context),
              ),

              // ━━━━━━ SUPPRESSION DU COMPTE (exigence Google Play) ━━━━━━
              _SettingRow(
                icon: Icons.person_remove_outlined,
                label: S.of(context).pick(
                  'Supprimer mon compte',
                  'Delete my account',
                  'حذف حسابي',
                ),
                subtitle: S.of(context).pick(
                  'Suppression définitive après 30 jours',
                  'Permanent after 30 days',
                  'حذف نهائي بعد 30 يومًا',
                ),
                danger: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeleteAccountScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 30),

          // Version footer — lu dynamiquement depuis pubspec au runtime
          const AppVersionFooter(),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
            'Vos données restent sauvegardées et seront disponibles à votre prochaine connexion.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Déconnexion',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  _ProfileStats _computeStats(ExamService examSvc, String userId) {
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
    return _ProfileStats(
      examsCount: exams.length,
      copiesGraded: graded,
      copiesTotal: total,
      averagePercent: avg,
    );
  }
}

class _ProfileStats {
  final int examsCount;
  final int copiesGraded;
  final int copiesTotal;
  final double averagePercent;
  const _ProfileStats({
    required this.examsCount,
    required this.copiesGraded,
    required this.copiesTotal,
    required this.averagePercent,
  });
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COMPOSANTS LOCAUX
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Avatar circulaire avec dégradé vert et bordure subtile.
class _ProfileAvatar extends StatelessWidget {
  final dynamic user;
  final double size;
  final bool loading;
  const _ProfileAvatar({
    required this.user,
    this.size = 72,
    this.loading = false,
  });

  String get _initials {
    final name = (user.displayName as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget? _renderPhoto(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    return Image.file(file, fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = user.photoPath as String?;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.profGradient,
        border: Border.all(
          color: AppColors.profPrimary.withValues(alpha: 0.3),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            : (_renderPhoto(photoPath) ??
                Center(
                  child: Text(
                    _initials,
                    style: AppFonts.sans(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )),
      ),
    );
  }
}

class _MatierePill extends StatelessWidget {
  final String label;
  const _MatierePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppFonts.mono(
          fontSize: 10,
          color: AppColors.primaryLight,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Carte « Mes crédits » : solde du wallet + prochaine expiration.
/// Remplace l'ancienne carte « Mon abonnement » (EduCorrect est en
/// pay-as-you-go sans abonnement — grille tarifaire v5).
class _CreditsCard extends StatelessWidget {
  final VoidCallback onTap;
  const _CreditsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<CreditsService>().wallet;
    final total = wallet.totalCredits;
    final next = wallet.nextExpiration;
    final String subtitle;
    if (total <= 0) {
      subtitle = 'Aucun crédit disponible pour le moment.';
    } else {
      final exp = next == null
          ? ''
          : ' · expire le ${next.day.toString().padLeft(2, '0')}/'
              '${next.month.toString().padLeft(2, '0')}';
      subtitle = '1 crédit = 1 copie jusqu\'à 8 pages$exp';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.profPrimary.withValues(alpha: 0.1),
                AppColors.profDeep.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(
              color: AppColors.profPrimary.withValues(alpha: 0.25),
            ),
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'MES CRÉDITS',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Détails',
                    style: AppFonts.sans(
                      fontSize: 11,
                      color: AppColors.profPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$total crédit${total > 1 ? 's' : ''}',
                style: AppFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.profPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite carte stat — utilisée dans la rangée de 3 (Examens / Copies / Moyenne).
class _MiniStatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _MiniStatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppFonts.fraunces(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppFonts.mono(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne de paramètre — icône + label + sous-titre + chevron / toggle.
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final bool disabled;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.danger = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? AppColors.danger
        : disabled
            ? AppColors.textMuted
            : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: disabled ? null : onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppFonts.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppFonts.sans(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!danger)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte "Vue Admin Établissement" affichée uniquement si le user est admin
/// d'un établissement. Déclenche un refresh silencieux d'EstablishmentService
/// à l'init pour rattraper un bootstrap incomplet (par exemple bootstrap
/// terminé avant que la session Supabase soit complètement restaurée).
class _AdminEstablishmentTile extends StatefulWidget {
  const _AdminEstablishmentTile();

  @override
  State<_AdminEstablishmentTile> createState() =>
      _AdminEstablishmentTileState();
}

class _AdminEstablishmentTileState extends State<_AdminEstablishmentTile> {
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_refreshed || !mounted) return;
      _refreshed = true;
      try {
        await context.read<EstablishmentService>().refresh();
      } catch (_) {}
    });
  }

  Future<void> _retryRefresh(BuildContext context) async {
    final svc = context.read<EstablishmentService>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vérification du rôle…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await svc.refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            svc.isAdmin
                ? '✓ Vous êtes admin de ${svc.currentEstablishment?.name}.'
                : svc.hasEstablishment
                    ? 'Vous êtes enseignant de ${svc.currentEstablishment?.name}.'
                    : 'Aucun établissement associé à ce compte.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
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
    // Michel spec §3 : étanchéité stricte des rôles. Un compte prof ne peut
    // JAMAIS voir de dashboard admin — cette carte est désactivée. Les
    // comptes admin sont routés directement vers AdminHomeScreen depuis le
    // login/splash.
    return const SizedBox.shrink();
    // ignore: dead_code
    return Consumer<EstablishmentService>(
      builder: (context, estab, _) {
        if (!estab.isAdmin) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminHomeScreen(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.adminPrimary.withValues(alpha: 0.12),
                      AppColors.primary.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.adminPrimary.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: AppColors.adminGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vue Admin Établissement',
                            style: AppFonts.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.adminPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            estab.currentEstablishment?.name
                                    .toUpperCase() ??
                                'ADMINISTRATEUR',
                            style: AppFonts.mono(
                              fontSize: 9,
                              color: AppColors.textMuted,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.adminPrimary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

