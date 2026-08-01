import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/widgets/route_transitions.dart';
import 'package:wasalny_rider/features/splash/splash_screen.dart';
import 'package:wasalny_rider/features/auth/login_screen.dart';
import 'package:wasalny_rider/features/auth/forgot_password_screen.dart';
import 'package:wasalny_rider/features/auth/register_screen.dart';
import 'package:wasalny_rider/features/auth/reset_password_screen.dart';
import 'package:wasalny_rider/features/home/home_screen.dart';
import 'package:wasalny_rider/features/notifications/notifications_screen.dart';
import 'package:wasalny_rider/features/profile/profile_screen.dart';
import 'package:wasalny_rider/features/trip/active_trip_screen.dart';
import 'package:wasalny_rider/features/trip/trip_history_screen.dart';
import 'package:wasalny_rider/features/trip/trip_rating_screen.dart';

/// [runApp] is called only after Firebase has been initialised in `main()`,
/// so any service that touches Firebase (e.g. [AuthService] → `FirebaseAuth`)
/// never hits the `[core/no-app] No Firebase App '[DEFAULT]' has been created`
/// error.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLogging();
  try {
    // No `firebase_options.dart` in this project — use the config bundled in
    // the native resources (google-services.json / GoogleService-Info.plist).
    await Firebase.initializeApp();
  } catch (e, stack) {
    // Never let a Firebase failure stop the app: log it and continue so the
    // splash screen and email/password login can still work.
    logError('main', 'Firebase initialization failed', e, stack);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waslny Rider',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      // Arabic is the primary UI language (RTL layout).
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: '/splash',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  /// Central route generator with animated transitions.
  static Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/splash':
        return RouteTransitions.fade(const SplashScreen());
      case '/login':
        return RouteTransitions.slideUp(const LoginScreen());
      case '/forgot-password':
        return RouteTransitions.slideUp(const ForgotPasswordScreen());
      case '/reset-password':
        return RouteTransitions.slideUp(
          ResetPasswordScreen(email: settings.arguments as String?),
        );
      case '/home':
        return RouteTransitions.slideHorizontal(const RiderHomeScreen());
      case '/register':
        return RouteTransitions.slideUp(const RegisterScreen());
      case '/active-trip':
        return RouteTransitions.slideHorizontal(
          ActiveTripScreen(args: settings.arguments as ActiveTripArgs?),
        );
      case '/rating':
        return RouteTransitions.slideUp(
          TripRatingScreen(args: settings.arguments as TripRatingArgs?),
        );
      case '/history':
        return RouteTransitions.slideHorizontal(const TripHistoryScreen());
      case '/notifications':
        return RouteTransitions.slideHorizontal(const NotificationsScreen());
      case '/profile':
        return RouteTransitions.slideHorizontal(const ProfileScreen());
      default:
        return RouteTransitions.fade(const SplashScreen());
    }
  }
}
