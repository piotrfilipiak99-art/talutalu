import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_storage.dart';

void _applySystemChrome(bool isDark) {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: isDark ? AppColors.darkBg : AppColors.lightBg,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.instance.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _applySystemChrome(AppStorage.instance.darkMode.value);
  runApp(const TalutaluApp());
}

class TalutaluApp extends StatefulWidget {
  const TalutaluApp({super.key});

  @override
  State<TalutaluApp> createState() => _TalutaluAppState();
}

class _TalutaluAppState extends State<TalutaluApp> {
  @override
  void initState() {
    super.initState();
    AppStorage.instance.darkMode.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppStorage.instance.darkMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    _applySystemChrome(AppStorage.instance.darkMode.value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talutalu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(AppStorage.instance.darkMode.value),
      initialRoute: '/splash',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/splash':
            return _fadeRoute(const SplashScreen());
          case '/onboarding':
            return _slideRoute(const OnboardingScreen());
          case '/auth':
            return _slideRoute(const AuthScreen());
          case '/home':
            return _fadeRoute(const HomeScreen());
          default:
            return _fadeRoute(const SplashScreen());
        }
      },
    );
  }

  PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (context, animation, _) => page,
        transitionDuration: const Duration(milliseconds: 700),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (context, animation, _) => page,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (context, animation, _, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position:
                Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      );
}
