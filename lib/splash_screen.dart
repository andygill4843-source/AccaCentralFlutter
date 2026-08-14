import 'package:flutter/material.dart';
import 'app_state.dart';
import 'main.dart'; // for AccaColors

class SplashScreen extends StatelessWidget {
  final AppState appState;

  const SplashScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => appState.resolveAuthState(),
      child: Scaffold(
        backgroundColor: AccaColors.primary,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Acca Central',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'One Team. One Acca. One Champion.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 15),
                ),
                const SizedBox(height: 60),
                Text(
                  'Tap to continue',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}