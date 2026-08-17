import 'package:flutter/material.dart';
import 'app_state.dart';

class SplashScreen extends StatelessWidget {
  final AppState appState;

  const SplashScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => appState.resolveAuthState(),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/splash_1708.png', fit: BoxFit.cover),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Text(
                'Tap to continue',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}