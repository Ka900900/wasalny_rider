import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:wasalny_rider/core/network/dio_client.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/features/home/home_screen.dart';
import 'package:wasalny_rider/features/auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;
  late final Animation<double> _glowPulse;

  late final Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _glowPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeInOutSine),
      ),
    );
    _controller.forward();
    _initializationFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    // ── 1. Firebase MUST be ready before anything else ──
    await _initFirebase();

    // ── 2. All services run in parallel with a timeout guard ──
    final List<Future<void>> tasks = [];

    if (!kIsWeb) {
      tasks.add(_timed('Crashlytics', _initCrashlytics()));
    }

    tasks.add(_timed('ErrorWidget', _initErrorWidget()));
    tasks.add(_timed('AuthToken', ApiService.instance.loadToken()));
    tasks.add(_timed('DioClient', Future(() => DioClient.instance.init())));

    // Ensure a minimum splash duration so the animation feels polished
    tasks.add(Future.delayed(const Duration(milliseconds: 1800)));

    await Future.wait(tasks);
  }

  /// Runs [future] with an 8-second timeout, logging start/finish time and
  /// any error. Errors and timeouts never abort the other initialisation
  /// tasks – we simply log and continue so the splash screen can proceed.
  Future<void> _timed(String name, Future<void> future) async {
    final stopwatch = Stopwatch()..start();
    logInfo('SplashScreen', '[init] $name ▶ started');
    try {
      await future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          logWarning(
            'SplashScreen',
            '[init] $name ⏱ TIMEOUT after '
                '${stopwatch.elapsed.inMilliseconds}ms',
          );
        },
      );
      logInfo(
        'SplashScreen',
        '[init] $name ✔ done in ${stopwatch.elapsed.inMilliseconds}ms',
      );
    } catch (e, stack) {
      logError(
        'SplashScreen',
        '[init] $name ❌ error after '
            '${stopwatch.elapsed.inMilliseconds}ms: $e',
        e,
        stack,
      );
    } finally {
      stopwatch.stop();
    }
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') {
        rethrow;
      }
    }
  }

  Future<void> _initCrashlytics() async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      originalOnError?.call(errorDetails);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  Future<void> _initErrorWidget() async {
    ErrorWidget.builder = (FlutterErrorDetails details) => Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF081014),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFF5A5F),
                size: 64,
              ),
              const SizedBox(height: 20),
              const Text(
                'حدث خطأ غير متوقع',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF7FAFC),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'يرجى إعادة المحاولة',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFC5D0D8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// After initialization completes, check authentication status and
  /// navigate to the appropriate screen.
  Future<void> _navigateBasedOnAuth() async {
    try {
      // First check if we have a stored JWT token
      if (!ApiService.instance.hasToken) {
        // No token stored — go to login
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
        return;
      }

      // We have a token — try to fetch the profile to verify it's still valid
      final data = await ApiService.instance.getProfile();
      if (!mounted) return;

      final role = data['role'] as String? ?? 'RIDER';
      logInfo('SplashScreen', '✅ Auto-login successful — role: $role');

      // Token is valid — go to home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
      );
    } catch (_) {
      // Token expired or network error — go to login
      logInfo('SplashScreen', 'Auto-login failed — redirecting to login');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // Initialization complete — trigger navigation
          // Use addPostFrameCallback to avoid building during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateBasedOnAuth();
          });
        }

        return _buildSplashScreen(context, snapshot);
      },
    );
  }

  Widget _buildSplashScreen(BuildContext context, AsyncSnapshot snapshot) {
    final hasError = snapshot.hasError;

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.7 + _glowPulse.value * 0.3,
                colors: [
                  AppColors.primary.withValues(alpha: 0.12 * _fadeIn.value),
                  AppColors.primaryBg,
                  AppColors.primaryBg,
                ],
              ),
            ),
            child: Opacity(
              opacity: _fadeIn.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated logo with glow
                    AnimatedBuilder(
                      animation: _glowPulse,
                      builder: (context, child) {
                        return Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryContainer,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.5 * _glowPulse.value,
                                ),
                                blurRadius: 80 * _glowPulse.value,
                                spreadRadius: 15 * _glowPulse.value,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.directions_car_rounded,
                              size: 56,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // App name
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.primaryGradient.createShader(bounds),
                      child: Text(
                        'Waslny',
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rider',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 64),
                    // Loading indicator or error content
                    hasError
                        ? Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'فشل في تهيئة التطبيق',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  // Re-trigger initialization
                                  setState(() {
                                    // Force rebuild
                                  });
                                },
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
