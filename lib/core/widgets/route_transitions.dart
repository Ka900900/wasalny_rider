import 'package:flutter/material.dart';

/// Custom page route with smooth transitions.
///
/// Usage:
/// ```dart
/// Navigator.push(context, RouteTransitions.slideUp(const NextScreen()));
/// ```
class RouteTransitions {
  /// Slide-up transition with fade.
  static Route<T> slideUp<T>(Widget page) {
    return _buildRoute<T>(
      page,
      transition: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  /// Fade transition (simple / lightweight).
  static Route<T> fade<T>(Widget page) {
    return _buildRoute<T>(
      page,
      transition: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  /// Scale-in transition.
  static Route<T> scaleIn<T>(Widget page) {
    return _buildRoute<T>(
      page,
      transition: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
    );
  }

  /// Slide-horizontal transition (left-to-right by default).
  static Route<T> slideHorizontal<T>(Widget page) {
    return _buildRoute<T>(
      page,
      transition: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.25, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  static Route<T> _buildRoute<T>(
    Widget page, {
    required Widget Function(
      BuildContext,
      Animation<double>,
      Animation<double>,
      Widget,
    )
    transition,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: transition,
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
    );
  }
}
