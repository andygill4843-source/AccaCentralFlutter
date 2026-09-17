import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'tournament_view.dart';

/// Swipeable pages across every tournament for a season, with dot
/// indicators when there's more than one. Used both by TournamentScreen
/// (wrapped in its own Scaffold/AppBar) and embedded directly inside
/// LeagueTableTab's Cup toggle.
class TournamentPager extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final String season;
  /// Called whenever the loaded list changes, so an embedding screen
  /// (e.g. TournamentScreen, for its AppBar title) can react.
  final void Function(List<Tournament> tournaments, int currentPage)? onTournamentsChanged;
  const TournamentPager({
    super.key,
    required this.appState,
    required this.teamId,
    required this.season,
    this.onTournamentsChanged,
  });

  @override
  State<TournamentPager> createState() => TournamentPagerState();
}

class TournamentPagerState extends State<TournamentPager> {
  List<Tournament> tournaments = [];
  bool isLoading = true;
  int currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TournamentPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.season != widget.season) {
      load();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Public so an embedding screen can force a refresh (e.g. after
  /// creating a new tournament).
  Future<void> load() async {
    setState(() => isLoading = true);
    final loaded = await FirestoreService.instance.fetchTournaments(
      teamId: widget.teamId,
      season: widget.season,
    );
    // Newest first — a freshly created tournament should be the one
    // whoever's looking lands on and immediately sees.
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      tournaments = loaded;
      currentPage = 0;
      isLoading = false;
    });
    widget.onTournamentsChanged?.call(tournaments, currentPage);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (tournaments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('No tournaments set up this season.', style: TextStyle(color: Colors.white70))),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tournaments.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < tournaments.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: currentPage == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: currentPage == i ? AccaColors.gold : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Sized explicitly rather than Expanded — this widget is meant to
        // sit inside another scrollable body (LeagueTableTab's toggle, or
        // TournamentScreen's own layout) rather than fill a Scaffold on
        // its own.
        SizedBox(
          height: 640,
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => currentPage = i);
              widget.onTournamentsChanged?.call(tournaments, currentPage);
            },
            children: [
              for (final t in tournaments)
                SingleChildScrollView(
                  child: TournamentView(
                    appState: widget.appState,
                    teamId: widget.teamId,
                    tournament: t,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}