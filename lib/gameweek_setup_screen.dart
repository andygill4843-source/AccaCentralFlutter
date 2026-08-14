import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors

class GameWeekSetupScreen extends StatefulWidget {
  final AppState appState;

  const GameWeekSetupScreen({super.key, required this.appState});

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

  @override
  void initState() {
    super.initState();
    suggestNextWeekNumber();
    loadCurrentSeason();
    loadActiveGameWeek();
    loadManagerStatus();
  }

  Future<void> loadManagerStatus() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    final userId = widget.appState.currentUser?.id;
    if (teamId == null || userId == null) return;
    final member = await FirestoreService.instance.fetchMember(teamId: teamId, userId: userId);
    if (mounted) setState(() => isManager = member?.role == MemberRole.manager);
  }

  Future<void> loadCurrentSeason() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;
    final team = await FirestoreService.instance.fetchTeam(teamId);
    if (mounted) setState(() => currentSeason = team?.season);
  }

  Future<void> loadActiveGameWeek() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(teamId);
    if (mounted) setState(() => activeGameWeek = gameWeek);
  }

  Future<void> suggestNextWeekNumber() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;
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
    );
    if (time == null) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => setter(combined));
  }

  Future<void> create() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;

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

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> endCurrentGameWeek() async {
    if (activeGameWeek == null || activeGameWeek!.id == null) return;
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End gameweek?'),
        content: Text('This ends Week ${activeGameWeek!.weekNumber}. Selections will close.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End gameweek')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirestoreService.instance.settleGameWeek(teamId: teamId, gameWeekId: activeGameWeek!.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gameweek ended.')));
      }
      loadActiveGameWeek();
      suggestNextWeekNumber();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error ending gameweek: ${e.toString()}')));
      }
    }
  }

  Future<void> endSeason() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final teamId = widget.appState.currentUser!.teamIds.first;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure you want to end the season?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${winner.displayName} will be crowned champion of ${team.season} with ${winner.totalBasePoints} points.'),
            const SizedBox(height: 16),
            TextField(
              controller: newSeasonController,
              decoration: const InputDecoration(labelText: 'New season name (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (newSeasonController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('End season'),
          ),
        ],
      ),
    );
    if (confirmed != true || newSeasonController.text.trim().isEmpty) return;

    try {
      await FirestoreService.instance.endSeason(
        teamId: teamId,
        currentSeason: team.season,
        newSeason: newSeasonController.text.trim(),
        winner: winner,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${winner.displayName} crowned champion of ${team.season}!')),
        );
        loadCurrentSeason();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error ending season: ${e.toString()}')));
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
                    OutlinedButton(
                      onPressed: endSeason,
                      child: const Text('Start new season'),
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active gameweek', style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
                          Text('Week ${activeGameWeek!.weekNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      OutlinedButton(
                        onPressed: endCurrentGameWeek,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('End current gameweek'),
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
              tileColor: Colors.white,
              title: const Text('First kickoff'),
              subtitle: Text(formatDateTime(startDate)),
              onTap: () => pickDateField(() => startDate, (d) => startDate = d),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: Colors.white,
              title: const Text('Last match window ends'),
              subtitle: Text(formatDateTime(endDate)),
              onTap: () => pickDateField(() => endDate, (d) => endDate = d),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: Colors.white,
              title: const Text('Selection deadline'),
              subtitle: Text(formatDateTime(deadline)),
              onTap: () => pickDateField(() => deadline, (d) => deadline = d),
            ),
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