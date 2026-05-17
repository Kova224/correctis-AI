import 'package:flutter/material.dart';

/// Transitions de page personnalisées pour une fluidité plus douce
/// que la transition Material par défaut.
class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  FadeSlidePageRoute({required Widget page, RouteSettings? settings})
      : super(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              ),
            );
          },
        );
}

/// Transition fade simple — pour les écrans modaux, les remplacements.
class FadePageRoute<T> extends PageRouteBuilder<T> {
  FadePageRoute({required Widget page, RouteSettings? settings})
      : super(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        );
}

extension NavigatorFluidX on NavigatorState {
  Future<T?> pushFluid<T>(Widget page) =>
      push<T>(FadeSlidePageRoute<T>(page: page));

  Future<T?> pushReplacementFluid<T, TO>(Widget page, {TO? result}) =>
      pushReplacement<T, TO>(FadeSlidePageRoute<T>(page: page), result: result);
}
