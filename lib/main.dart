import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app_state.dart';
import 'auth_screen.dart';
import 'team_setup_screen.dart';
import 'main_tab_scaffold.dart';
import 'splash_screen.dart';
import 'package:google_fonts/google_fonts.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AccaCentralApp());
}

// Champion Navy palette — same hex values as Colors.swift
class AccaColors {
  static const primary = Color(0xFF0D1117);
  static const secondary = Color(0xFF161B22);
  static const gold = Color(0xFF00E676); // brand green accent
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22); // cards, elevated panels
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8A8F98);
  static const win = Color(0xFF16A34A);
  static const loss = Color(0xFFDC2626);
}

InputDecoration accaFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always, // keeps the label pinned above the field, never overlapping
    labelStyle: const TextStyle(color: Colors.black87, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
    ),
  );
}

const accaFieldTextStyle = TextStyle(color: Colors.black, fontSize: 15);


class AccaCentralApp extends StatelessWidget {
  const AccaCentralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acca Central',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AccaColors.background,
        cardColor: AccaColors.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AccaColors.gold,
          brightness: Brightness.dark,
          primary: AccaColors.gold,
          surface: AccaColors.surface,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(
          const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
            titleLarge: TextStyle(color: Colors.white),
            titleMedium: TextStyle(color: Colors.white),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AccaColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final appState = AppState();

  @override
  void initState() {
    super.initState();
    appState.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    switch (appState.screen) {
      case AppScreen.splash:
        return SplashScreen(appState: appState);
      case AppScreen.auth:
        return AuthScreen(appState: appState, onAuthenticated: () {});
      case AppScreen.teamSetup:
  	return TeamSetupScreen(appState: appState, onTeamReady: () {});
      case AppScreen.main:
  return MainTabScaffold(appState: appState, teamId: appState.activeTeamId ?? appState.currentUser?.teamIds.first ?? '');
    }
  }
}

