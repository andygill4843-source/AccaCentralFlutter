import 'package:flutter/material.dart';
import 'app_state.dart';
import 'home_screen.dart';
import 'acca_hub_screen.dart';
import 'league_table_tab.dart';
import 'stats_screen.dart';
import 'awards_screen.dart';
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
    (Icons.bar_chart, 'Stats'),
    (Icons.military_tech, 'Awards'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeScreen(appState: widget.appState, teamId: widget.teamId, onNavigateToTab: goToTab, refreshToken: refreshTokens[0]!),
      AccaHubScreen(appState: widget.appState, teamId: widget.teamId),
      LeagueTableTab(teamId: widget.teamId, refreshToken: refreshTokens[2]!),
      StatsScreen(appState: widget.appState, teamId: widget.teamId),
      AwardsScreen(appState: widget.appState, teamId: widget.teamId),
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