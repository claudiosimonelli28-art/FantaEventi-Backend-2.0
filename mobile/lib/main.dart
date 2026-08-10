import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/login_view.dart';
import 'views/home_view.dart';
import 'services/api_service.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialUser = await ApiService().tryAutoLogin();
  runApp(FantaEventiApp(isLoggedIn: initialUser != null));
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
      home: isLoggedIn ? const HomeView() : const LoginView(),
    );
  }
}
