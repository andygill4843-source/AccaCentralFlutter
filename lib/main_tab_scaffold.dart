import 'package:flutter/material.dart';
import 'app_state.dart';
import 'home_screen.dart';
import 'acca_hub_screen.dart';
import 'league_table_tab.dart';
import 'stats_screen.dart';
import 'awards_screen.dart';
import 'main.dart'; // for AccaColors
import 'profile_screen.dart';

class MainTabScaffold extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const MainTabScaffold({super.key, required this.appState, required this.teamId});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int currentIndex = 0;

  void goToTab(int index) {
    setState(() => currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeScreen(appState: widget.appState, teamId: widget.teamId, onNavigateToTab: goToTab),
      AccaHubScreen(appState: widget.appState, teamId: widget.teamId),
      LeagueTableTab(teamId: widget.teamId),
      StatsScreen(teamId: widget.teamId),
      AwardsScreen(appState: widget.appState, teamId: widget.teamId),
      ProfileScreen(appState: widget.appState, teamId: widget.teamId),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
        selectedItemColor: AccaColors.gold,
        unselectedItemColor: Colors.white70,
        backgroundColor: AccaColors.primary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_soccer), label: 'Acca Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.leaderboard), label: 'League'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.military_tech), label: 'Awards'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}