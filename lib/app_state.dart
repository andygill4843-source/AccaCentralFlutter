import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'models.dart';

enum AppScreen { splash, auth, teamSetup, main }

class AppState extends ChangeNotifier {
  AppScreen screen = AppScreen.splash;
  AppUser? currentUser;
  String? activeTeamId;

  static const _rememberMeKey = 'acca.rememberMe';

  Future<bool> get rememberMe async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
  }

  void switchActiveTeam(String teamId) {
    activeTeamId = teamId;
    notifyListeners();
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
      activeTeamId = user.teamIds.isNotEmpty ? user.teamIds.first : null;
      screen = user.teamIds.isEmpty ? AppScreen.teamSetup : AppScreen.main;
    } catch (_) {
      screen = AppScreen.auth;
    }
    notifyListeners();
  }

  void didLogIn(AppUser user) {
    currentUser = user;
    activeTeamId = user.teamIds.isNotEmpty ? user.teamIds.first : null;
    screen = user.teamIds.isEmpty ? AppScreen.teamSetup : AppScreen.main;
    notifyListeners();
  }

  void didJoinOrCreateTeam(AppUser updatedUser) {
    currentUser = updatedUser;
    // Only switch active team automatically if this was the very first team
    // (initial setup) — for an additional team joined/created later, the
    // caller decides whether to switch (see ProfileScreen).
    if (activeTeamId == null && updatedUser.teamIds.isNotEmpty) {
      activeTeamId = updatedUser.teamIds.first;
    }
    screen = AppScreen.main;
    notifyListeners();
  }

  Future<void> logOut() async {
    await AuthService.instance.signOut();
    currentUser = null;
    activeTeamId = null;
    await setRememberMe(false);
    screen = AppScreen.auth;
    notifyListeners();
  }
}