import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/login_view.dart';
import 'views/home_view.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza Firebase con tolleranza d'errore (non blocca mai l'avvio della UI)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initializeApp notice: $e');
  }

  // Inizializza notifiche push Firebase e canali di sistema
  try {
    await PushNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('PushNotificationService initialize notice: $e');
  }

  bool isLoggedIn = false;
  try {
    final initialUser = await ApiService().tryAutoLogin();
    isLoggedIn = initialUser != null;
    if (isLoggedIn) {
      unawaited(PushNotificationService.instance.syncCurrentDeviceToken());
    }
  } catch (e) {
    debugPrint('AutoLogin notice: $e');
  }

  runApp(FantaEventiApp(isLoggedIn: isLoggedIn));
}

class FantaEventiApp extends StatelessWidget {
  final bool isLoggedIn;
  const FantaEventiApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    const primaryGold = Color(0xFFFACC15);
    const secondaryPurple = Color(0xFF9333EA);
    const darkBackground = Color(0xFF0F172A);
    const darkSurface = Color(0xFF1E293B);

    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      title: 'FantaEventi',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBackground,
        primaryColor: primaryGold,
        colorScheme: const ColorScheme.dark(
          primary: primaryGold,
          secondary: secondaryPurple,
          surface: darkSurface,
          onPrimary: Color(0xFF0F172A),
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: darkSurface,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: isLoggedIn ? const HomeView() : const LoginView(),
    );
  }
}
