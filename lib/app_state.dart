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
  /// Set when the app is opened via an accacentral://join?code=XXXX deep
  /// link. The RootScreen notices this via notifyListeners() and opens
  /// TeamSetupScreen with the code pre-filled. Cleared by
  /// consumeInviteCode() once the screen has consumed it.
  String? pendingInviteCode;

  static const _rememberMeKey = 'acca.rememberMe';

  Future<bool> get rememberMe async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
  }

  /// Set when a notification tap should switch the main tab bar — consumed
  /// by MainTabScaffold in its build cycle via consumePendingTabNavigation().
  int? _pendingTabIndex;

  void requestTabNavigation(int index) {
    _pendingTabIndex = index;
    notifyListeners();
  }

  /// Returns and clears the pending tab index — called by MainTabScaffold
  /// so it only switches once, not on every subsequent rebuild.
  int? consumePendingTabNavigation() {
    final index = _pendingTabIndex;
    _pendingTabIndex = null;
    return index;
  }

  void switchActiveTeam(String teamId) {
    activeTeamId = teamId;
    notifyListeners();
  }

  /// Called by RootScreen whenever the app receives an incoming URL.
  /// Parses the invite code and stores it — the UI reacts via the
  /// notifyListeners() call.
  void handleDeepLink(Uri uri) {
    if (uri.scheme == 'accacentral' && uri.host == 'join') {
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        pendingInviteCode = code.toUpperCase();
        notifyListeners();
      }
    }
  }

  /// Called once TeamSetupScreen has read pendingInviteCode and pre-filled
  /// the field — clears the value so it isn't re-applied on rebuild.
  void consumeInviteCode() {
    pendingInviteCode = null;
    // No notifyListeners() — no UI change needed, just a housekeeping clear.
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