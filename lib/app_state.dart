import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'models.dart';

enum AppScreen { splash, auth, teamSetup, main }

class AppState extends ChangeNotifier {
  AppScreen screen = AppScreen.splash;
  AppUser? currentUser;

  static const _rememberMeKey = 'acca.rememberMe';

  Future<bool> get rememberMe async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
  }

  Future<void> resolveAuthState() async {
    final remember = await rememberMe;
    if (!remember) {
      await AuthService.instance.signOut();
    }

    final firebaseUser = AuthService.instance.currentFirebaseUser;
    if (firebaseUser == null) {
      screen = AppScreen.auth;
      notifyListeners();
      return;
    }

    try {
      final user = await AuthService.instance.fetchCurrentUserProfile(firebaseUser.uid);
      currentUser = user;
      screen = user.teamIds.isEmpty ? AppScreen.teamSetup : AppScreen.main;
    } catch (_) {
      screen = AppScreen.auth;
    }
    notifyListeners();
  }

  void didLogIn(AppUser user) {
    currentUser = user;
    screen = user.teamIds.isEmpty ? AppScreen.teamSetup : AppScreen.main;
    notifyListeners();
  }

  void didJoinOrCreateTeam(AppUser updatedUser) {
    currentUser = updatedUser;
    screen = AppScreen.main;
    notifyListeners();
  }

  Future<void> logOut() async {
    await AuthService.instance.signOut();
    currentUser = null;
    await setRememberMe(false);
    screen = AppScreen.auth;
    notifyListeners();
  }
}