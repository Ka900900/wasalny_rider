import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/widgets/route_transitions.dart';
import 'package:wasalny_rider/features/splash/splash_screen.dart';
import 'package:wasalny_rider/features/auth/login_screen.dart';
import 'package:wasalny_rider/features/home/home_screen.dart';

/// [runApp] is called immediately without awaiting any async init.
/// All service initialisation is delegated to [SplashScreen] so the UI
/// appears instantly and the user sees a smooth branded experience while
/// the app warms up.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupLogging();
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
