import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors
import 'tournament_link_picker_screen.dart';

class GameWeekSetupScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  const GameWeekSetupScreen({super.key, required this.appState, required this.teamId});
  @override
  State<GameWeekSetupScreen> createState() => _GameWeekSetupScreenState();
}

class _GameWeekSetupScreenState extends State<GameWeekSetupScreen> {
  int weekNumber = 1;
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now().add(const Duration(days: 3));
  DateTime deadline = DateTime.now().add(const Duration(days: 3));
  bool isLoading = false;
  String? errorMessage;
  String? currentSeason;
  GameWeek? activeGameWeek;
  bool isManager = false;
  List<Tournament> availableTournaments = []; // in-progress rounds not yet attached to any gameweek
  Tournament? selectedTournamentForLink;

  @override
  void initState() {
    super.initState();
    suggestNextWeekNumber();
    loadCurrentSeason();
    loadActiveGameWeek();
    loadManagerStatus();
  }

  /// Firestore surfaces a manager-only rules rejection as a
  /// FirebaseException with code 'permission-denied' — swap that raw error
  /// for something a non-manager will actually understand. Anything else
  /// (network issues, etc.) falls back to the original message.
  String _friendlyError(Object error, String fallback) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Only manager profiles can update gameweeks.';
    }
    return fallback;
  }

  Future<void> loadManagerStatus() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    if (mounted) setState(() => isManager = member?.role == MemberRole.manager);
  }

  Future<void> loadCurrentSeason() async {
    final team = await FirestoreService.instance.fetchTeam(widget.teamId);
    if (!mounted) return;
    setState(() => currentSeason = team?.season);
    if (team != null) await loadAvailableTournamentRound(team.season);
  }

    /// Every in-progress tournament (there can now be several at once)
  /// whose CURRENT round hasn't already been attached to a different
  /// gameweek — each one is a candidate to link this new gameweek to.
  Future<void> loadAvailableTournamentRound(String season) async {
    final tournaments = await FirestoreService.instance.fetchTournaments(teamId: widget.teamId, season: season);
    final candidates = <Tournament>[];
    for (final t in tournaments) {
      if (t.status != TournamentStatus.inProgress || t.currentRoundSize == null || t.id == null) continue;
      final alreadyAttached = await FirestoreService.instance.isTournamentRoundAttached(
        teamId: widget.teamId,
        tournamentId: t.id!,
        roundSize: t.currentRoundSize!,
      );
      if (!alreadyAttached) candidates.add(t);
    }
    if (mounted) setState(() => availableTournaments = candidates);
  }

  Future<void> loadActiveGameWeek() async {
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (mounted) setState(() => activeGameWeek = gameWeek);
  }

  Future<void> suggestNextWeekNumber() async {
    final teamId = widget.teamId;
    final team = await FirestoreService.instance.fetchTeam(teamId);
    final existing = await FirestoreService.instance.fetchGameWeeks(teamId);
    final currentSeasonGameWeeks = existing.where((g) => g.season == team?.season).toList();
    setState(() {
      weekNumber = currentSeasonGameWeeks.isEmpty
          ? 1
          : currentSeasonGameWeeks.map((g) => g.weekNumber).reduce((a, b) => a > b ? a : b) + 1;
    });
  }

  Future<void> pickDateField(DateTime Function() getter, void Function(DateTime) setter) async {
    final initial = getter();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => setter(combined));
  }

  Future<void> create() async {
    final teamId = widget.teamId;
    if (!endDate.isAfter(startDate)) {
      setState(() => errorMessage = 'The last match window must end after the first kickoff.');
      return;
    }
    if (deadline.isAfter(endDate)) {
      setState(() => errorMessage = 'Selection deadline must not be after the last match window ends.');
      return;
    }
    if (startDate.isAfter(DateTime.now().add(const Duration(days: 14)))) {
      setState(() => errorMessage = "Gameweeks can only be set up within the next two weeks — bookmaker odds aren't posted further ahead than that.");
      return;
    }
    setState(() {
      errorMessage = null;
      isLoading = true;
    });
    try {
      final existing = await FirestoreService.instance.fetchGameWeeks(teamId);
      if (existing.any((g) => !g.isSettled)) {
        setState(() {
          isLoading = false;
          errorMessage = "There's already an active gameweek. End it before creating a new one.";
        });
        return;
      }
      final gameWeek = GameWeek(
        id: null,
        teamId: teamId,
        weekNumber: weekNumber,
        startDate: startDate,
        endDate: endDate,
        isSettled: false,
        createdAt: DateTime.now(),
        deadline: deadline,
        season: (await FirestoreService.instance.fetchTeam(teamId))?.season ?? '2026-27',
      );
      await FirestoreService.instance.createGameWeek(gameWeek);
            if (selectedTournamentForLink?.id != null && selectedTournamentForLink?.currentRoundSize != null) {
        final newGameWeek = await FirestoreService.instance.fetchActiveGameWeek(teamId);
        if (newGameWeek?.id != null) {
          await FirestoreService.instance.attachTournamentRoundToGameWeek(
            teamId: teamId,
            tournamentId: selectedTournamentForLink!.id!,
            roundSize: selectedTournamentForLink!.currentRoundSize!,
            gameWeekId: newGameWeek!.id!,
          );
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = _friendlyError(e, e.toString());
      });
    }
  }

  Future<void> endCurrentGameWeek() async {
    if (activeGameWeek == null || activeGameWeek!.id == null) return;
    final teamId = widget.teamId;
    final allSettled = await FirestoreService.instance.areAllLegsSettled(
      teamId: teamId,
      gameWeekId: activeGameWeek!.id!,
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End gameweek?'),
        content: Text(
          allSettled
              ? 'This ends Week ${activeGameWeek!.weekNumber}. Selections will close.'
              : 'Not all gameweek games have been settled. Please refer to the manual settlement tab. Continuing will mean not all gameweek results are correctly reflected in the output. Do you want to continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End gameweek')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirestoreService.instance.endActiveGameWeek(teamId: teamId, gameWeek: activeGameWeek!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gameweek ended.')));
      }
      loadActiveGameWeek();
      suggestNextWeekNumber();
    } catch (e) {
      if (mounted) {
        final message = _friendlyError(e, 'Error ending gameweek: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> editActiveGameWeekDeadline() async {
    if (activeGameWeek == null || activeGameWeek!.id == null) return;
    final initial = activeGameWeek!.deadline;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: activeGameWeek!.endDate,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null || !mounted) return;
    final newDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (newDeadline.isAfter(activeGameWeek!.endDate)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Deadline can't be after the last match window ends.")),
      );
      return;
    }
    try {
      await FirestoreService.instance.updateGameWeekDeadline(
        gameWeekId: activeGameWeek!.id!,
        newDeadline: newDeadline,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deadline updated.')));
      }
      loadActiveGameWeek();
    } catch (e) {
      if (mounted) {
        final message = _friendlyError(e, 'Error updating deadline: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> endSeason() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final teamId = widget.teamId;
    final team = await FirestoreService.instance.fetchTeam(teamId);
    if (team == null || !mounted) return;
    final members = await FirestoreService.instance.fetchMembers(teamId);
    final legs = await FirestoreService.instance.fetchLegs(teamId);
    final gameWeeks = await FirestoreService.instance.fetchGameWeeks(teamId);
    final currentSeasonGameWeekIds = gameWeeks.where((g) => g.season == team.season).map((g) => g.id).toSet();
    final currentSeasonLegs = legs.where((l) => currentSeasonGameWeekIds.contains(l.gameWeekId)).toList();
    final table = ScoringEngine.buildLeagueTable(members: members, legs: currentSeasonLegs);
    if (!mounted) return;
    if (table.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No league table data yet — nothing to crown a winner from.')),
      );
      return;
    }
    final winner = table.first;
    final newSeasonController = TextEditingController();
    int dialogMaxChallenges = 2;
    int dialogMaxPhysioSessions = 2;
    bool dialogSetupTournament = false;
    final dialogTournamentNameController = TextEditingController();
    DateTime? dialogTournamentDrawDateTime;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Are you sure you want to end the season?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${winner.displayName} will be crowned champion of ${team.season} with ${winner.totalBasePoints} points.'),
                const SizedBox(height: 16),
                TextField(
                  controller: newSeasonController,
                  decoration: const InputDecoration(labelText: 'New season name (required)'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: dialogMaxChallenges,
                  decoration: const InputDecoration(
                    labelText: 'Challenges per member this season',
                    prefixIcon: Icon(Icons.flash_on),
                  ),
                  items: [for (int i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => dialogMaxChallenges = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: dialogMaxPhysioSessions,
                  decoration: const InputDecoration(
                    labelText: 'Physio sessions per member this season',
                    prefixIcon: Icon(Icons.medical_services),
                  ),
                  items: [for (int i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => dialogMaxPhysioSessions = v);
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set up a knockout tournament this season?'),
                  value: dialogSetupTournament,
                  onChanged: (v) => setDialogState(() => dialogSetupTournament = v),
                ),
                if (dialogSetupTournament) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: dialogTournamentNameController,
                    decoration: const InputDecoration(labelText: 'Tournament name'),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dialogTournamentDrawDateTime == null
                          ? 'Set draw date & time'
                          : 'Draw: ${formatDateTime(dialogTournamentDrawDateTime!)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final initial = dialogTournamentDrawDateTime ?? DateTime.now().add(const Duration(days: 7));
                      final date = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(initial),
                        initialEntryMode: TimePickerEntryMode.input,
                      );
                      if (time == null) return;
                      setDialogState(() {
                        dialogTournamentDrawDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (newSeasonController.text.trim().isEmpty) return;
                if (dialogSetupTournament &&
                    (dialogTournamentNameController.text.trim().isEmpty || dialogTournamentDrawDateTime == null)) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('End season'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || newSeasonController.text.trim().isEmpty) return;
    final newSeasonName = newSeasonController.text.trim();
    try {
      // Generate season summaries for every member BEFORE the season
      // data changes — all current-season legs, gameweeks, and tournament
      // data must still be in place when this runs.
      final allLegs = await FirestoreService.instance.fetchLegs(teamId);
      final allGameWeeks = await FirestoreService.instance.fetchGameWeeks(teamId);
      final allChallenges = await FirestoreService.instance.fetchChallenges(teamId: teamId, season: team.season);
      final seasonGameWeekIds = allGameWeeks.where((g) => g.season == team.season).map((g) => g.id).toSet();
      final seasonLegs = allLegs.where((l) => seasonGameWeekIds.contains(l.gameWeekId)).toList();
      final seasonGameWeeks = allGameWeeks.where((g) => g.season == team.season).toList();
      final allMembers = await FirestoreService.instance.fetchMembers(teamId);
            // Fetch every tournament this season (a team can now run more than
      // one at once) along with its own matches, so no cup result gets
      // silently dropped just because it wasn't the first tournament
      // created.
      final seasonTournaments = await FirestoreService.instance.fetchTournaments(teamId: teamId, season: team.season);
      final tournamentsWithMatches = <({Tournament tournament, List<TournamentMatch> matches})>[];
      for (final t in seasonTournaments) {
        if (t.id == null) continue;
        final matches = await FirestoreService.instance.fetchTournamentMatches(teamId: teamId, tournamentId: t.id!);
        tournamentsWithMatches.add((tournament: t, matches: matches));
      }
      await FirestoreService.instance.generateSeasonSummaries(
        teamId: teamId,
        season: team.season,
        members: allMembers,
        legs: seasonLegs,
        gameWeeks: seasonGameWeeks,
        challenges: allChallenges,
        tournaments: tournamentsWithMatches,
      );
      await FirestoreService.instance.endSeason(
        teamId: teamId,
        currentSeason: team.season,
        newSeason: newSeasonName,
        winner: winner,
      );
      await FirestoreService.instance.createSeasonSettings(SeasonSettings(
        teamId: teamId,
        season: newSeasonName,
        maxChallengesPerMember: dialogMaxChallenges,
        maxPhysioSessionsPerMember: dialogMaxPhysioSessions,
        createdAt: DateTime.now(),
      ));
      if (dialogSetupTournament && dialogTournamentDrawDateTime != null) {
        await FirestoreService.instance.createTournament(Tournament(
          teamId: teamId,
          season: newSeasonName,
          name: dialogTournamentNameController.text.trim(),
          drawDateTime: dialogTournamentDrawDateTime!,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${winner.displayName} crowned champion of ${team.season}!')),
        );
        loadCurrentSeason();
        suggestNextWeekNumber();
      }
    } catch (e) {
      if (mounted) {
        final message = _friendlyError(e, 'Error ending season: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  String formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gameweek Manager'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current season', style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
                        Text(currentSeason ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: endSeason,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AccaColors.gold),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Start new season', style: TextStyle(fontSize: 12)),
                          ),
                  ],
                ),
              ),
            ),
            if (isManager && activeGameWeek != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Active gameweek', style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
                                Text('Week ${activeGameWeek!.weekNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: endCurrentGameWeek,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('End current gameweek', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Deadline: ${formatDateTime(activeGameWeek!.deadline)}', style: const TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: editActiveGameWeekDeadline,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AccaColors.gold),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Edit', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Week $weekNumber', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: weekNumber > 1 ? () => setState(() => weekNumber--) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => weekNumber++),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            ListTile(
              tileColor: AccaColors.surface,
              title: const Text('First kickoff'),
              subtitle: Text(formatDateTime(startDate)),
              onTap: () => pickDateField(() => startDate, (d) => startDate = d),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: AccaColors.surface,
              title: const Text('Latest kickoff'),
              subtitle: Text(formatDateTime(endDate)),
              onTap: () => pickDateField(() => endDate, (d) => endDate = d),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: AccaColors.surface,
              title: const Text('Selection deadline'),
              subtitle: Text(formatDateTime(deadline)),
              onTap: () => pickDateField(() => deadline, (d) => deadline = d),
            ),
            if (availableTournaments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ListTile(
                tileColor: AccaColors.surface,
                title: const Text('Part of a tournament round?'),
                subtitle: Text(
                  selectedTournamentForLink == null
                      ? 'No'
                      : '${selectedTournamentForLink!.name} (${tournamentRoundLabel(selectedTournamentForLink!.currentRoundSize!)})',
                ),
                onTap: () async {
                  final result = await Navigator.of(context).push<TournamentLinkChoice>(
                    MaterialPageRoute(
                      builder: (_) => TournamentLinkPickerScreen(
                        options: availableTournaments,
                        current: selectedTournamentForLink,
                      ),
                    ),
                  );
                  if (result != null) {
                    setState(() => selectedTournamentForLink = result.tournament);
                  }
                },
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AccaColors.gold,
                foregroundColor: AccaColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create gameweek'),
            ),
          ],
        ),
      ),
    );
  }
}