import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'models.dart';
import 'notification_service.dart';

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

  void _captureNotificationToken() {
    final userId = currentUser?.id;
    if (userId != null) {
      NotificationService.instance.initAndSaveToken(userId);
    }
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
      _captureNotificationToken();
    } catch (_) {
      screen = AppScreen.auth;
    }
    notifyListeners();
  }

  void didLogIn(AppUser user) {
    currentUser = user;
    activeTeamId = user.teamIds.isNotEmpty ? user.teamIds.first : null;
    screen = user.teamIds.isEmpty ? AppScreen.teamSetup : AppScreen.main;
    _captureNotificationToken();
    notifyListeners();
  }

  void didJoinOrCreateTeam(AppUser updatedUser) {
    currentUser = updatedUser;
    if (activeTeamId == null && updatedUser.teamIds.isNotEmpty) {
      activeTeamId = updatedUser.teamIds.first;
    }
    screen = AppScreen.main;
    _captureNotificationToken();
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