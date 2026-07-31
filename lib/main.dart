import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/widgets/route_transitions.dart';
import 'package:wasalny_rider/features/splash/splash_screen.dart';
import 'package:wasalny_rider/features/auth/login_screen.dart';
import 'package:wasalny_rider/features/home/home_screen.dart';

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
    logError('main', 'Firebase initialization failed', e, stack);
    rethrow;
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
      case '/home':
        return RouteTransitions.slideHorizontal(const RiderHomeScreen());
      default:
        return RouteTransitions.fade(const SplashScreen());
    }
  }
}
