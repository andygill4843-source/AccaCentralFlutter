import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'main.dart'; // for AccaColors
import 'tournament_view.dart';

/// Thin Scaffold wrapper around TournamentView, for direct navigation
/// (e.g. Acca Hub's "Tournament" button). LeagueTableTab embeds
/// TournamentView directly instead, inside its own League/Cup toggle.
class TournamentScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  const TournamentScreen({super.key, required this.appState, required this.teamId});
  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  String? tournamentName;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final team = await FirestoreService.instance.fetchTeam(widget.teamId);
    final tournament = await FirestoreService.instance.fetchTournament(
      teamId: widget.teamId,
      season: team?.season ?? '',
    );
    if (mounted) setState(() => tournamentName = tournament?.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tournamentName ?? 'Tournament'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: SingleChildScrollView(
        child: TournamentView(appState: widget.appState, teamId: widget.teamId),
      ),
    );
  }
}