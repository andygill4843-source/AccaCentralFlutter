import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'tournament_pager.dart';
import 'create_tournament_screen.dart';

class TournamentScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  const TournamentScreen({super.key, required this.appState, required this.teamId});
  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  final GlobalKey<TournamentPagerState> _pagerKey = GlobalKey();
  bool isManager = false;
  String? season;
  String title = 'Tournament';

  @override
  void initState() {
    super.initState();
    loadManagerStatusAndSeason();
  }

  Future<void> loadManagerStatusAndSeason() async {
    final userId = widget.appState.currentUser?.id;
    if (userId != null) {
      final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      if (mounted) setState(() => isManager = member?.role == MemberRole.manager);
    }
    final team = await FirestoreService.instance.fetchTeam(widget.teamId);
    if (mounted) setState(() => season = team?.season ?? '');
  }

  Future<void> openCreateScreen() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateTournamentScreen(teamId: widget.teamId)),
    );
    if (created == true) _pagerKey.currentState?.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (isManager)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Set up a tournament',
              onPressed: openCreateScreen,
            ),
        ],
      ),
      backgroundColor: AccaColors.background,
      body: season == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: TournamentPager(
                key: _pagerKey,
                appState: widget.appState,
                teamId: widget.teamId,
                season: season!,
                onTournamentsChanged: (tournaments, currentPage) {
                  final newTitle = tournaments.isNotEmpty && currentPage < tournaments.length
                      ? tournaments[currentPage].name
                      : 'Tournament';
                  if (newTitle != title && mounted) setState(() => title = newTitle);
                },
              ),
            ),
    );
  }
}