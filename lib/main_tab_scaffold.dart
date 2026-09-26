import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'challenge_response_dialog.dart';
import 'home_screen.dart';
import 'acca_hub_screen.dart';
import 'league_table_tab.dart';
import 'stats_screen.dart';
import 'live_accumulator_screen.dart';
import 'main.dart'; // for AccaColors

class MainTabScaffold extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const MainTabScaffold({super.key, required this.appState, required this.teamId});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int currentIndex = 0;
  final Map<int, int> refreshTokens = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0};

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingChallenges());
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final pending = widget.appState.consumePendingTabNavigation();
    if (pending != null && mounted) {
      setState(() => currentIndex = pending.clamp(0, 4));
    }
  }

  Future<void> _checkPendingChallenges() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    if (member?.id == null || !mounted) return;
    final pending = await FirestoreService.instance.fetchPendingAcceptanceChallengesForMember(
      teamId: widget.teamId,
      memberId: member!.id!,
    );
    for (final challenge in pending) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => ChallengeResponseDialog(challenge: challenge),
      );
    }
  }

  void _select(int i) {
    setState(() {
      currentIndex = i;
      refreshTokens[i] = (refreshTokens[i] ?? 0) + 1;
    });
  }

  void goToTab(int index) {
    setState(() => currentIndex = index);
  }

  static const _items = [
    (Icons.home, 'Home'),
    (Icons.sports_soccer, 'Hub'),
    (Icons.scoreboard, 'League'),
    (Icons.bar_chart, 'Form'),
    (Icons.live_tv, 'Live'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeScreen(appState: widget.appState, teamId: widget.teamId, onNavigateToTab: goToTab, refreshToken: refreshTokens[0]!),
      AccaHubScreen(appState: widget.appState, teamId: widget.teamId),
      LeagueTableTab(appState: widget.appState, teamId: widget.teamId, refreshToken: refreshTokens[2]!),
      StatsScreen(appState: widget.appState, teamId: widget.teamId, refreshToken: refreshTokens[3]!),
      _LiveTab(appState: widget.appState, teamId: widget.teamId, refreshToken: refreshTokens[4]!),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: tabs),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 60,
          color: AccaColors.primary,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => _select(i),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: currentIndex == i ? AccaColors.gold : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_items[i].$1, color: currentIndex == i ? AccaColors.gold : Colors.white70, size: 24),
                          const SizedBox(height: 2),
                          Text(
                            _items[i].$2,
                            style: TextStyle(
                              fontSize: 11,
                              color: currentIndex == i ? AccaColors.gold : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper so LiveAccumulatorScreen (which just renders whatever
/// GameWeek? it's given) gets a live-refreshed active gameweek at the
/// bottom-nav level, the same way every other tab loads its own data.
class _LiveTab extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final int refreshToken;
  const _LiveTab({required this.appState, required this.teamId, required this.refreshToken});

  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  GameWeek? gameWeek;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant _LiveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.refreshToken != widget.refreshToken) {
      load();
    }
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final gw = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (mounted) {
      setState(() {
        gameWeek = gw;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(backgroundColor: AccaColors.background, body: Center(child: CircularProgressIndicator()));
    }
    return LiveAccumulatorScreen(appState: widget.appState, gameWeek: gameWeek);
  }
}