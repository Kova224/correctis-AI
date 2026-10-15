import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

/// Footer version + build lu dynamiquement depuis pubspec.yaml au runtime.
///
/// Michel : jamais hardcoder — quand on bump pubspec + build, l'affichage
/// doit refléter la version installée automatiquement.
class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({super.key});

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String _label = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _label =
            'Correctis · v${info.version} · build ${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _label = 'Correctis');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_label.isEmpty) return const SizedBox(height: 12);
    return Center(
      child: Text(
        _label,
        style: AppFonts.mono(
          fontSize: 9,
          color: AppColors.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
