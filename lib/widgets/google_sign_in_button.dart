import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'google_g_logo.dart';

/// Bouton "Continuer avec Google" stylé selon les guidelines Google :
/// fond blanc, ombre subtile, logo G officiel à gauche, texte centré.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  const GoogleSignInButton({
    super.key,
    this.onPressed,
    this.loading = false,
    this.label = 'Continuer avec Google',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF4285F4)),
                    ),
                  )
                else
                  const GoogleGLogo(size: 22),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF3C4043),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
