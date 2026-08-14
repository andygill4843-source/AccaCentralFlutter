import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
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

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    suggestNextWeekNumber();
  }

  Future<void> suggestNextWeekNumber() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;
    final existing = await FirestoreService.instance.fetchGameWeeks(teamId);
    if (existing.isNotEmpty) {
      setState(() {
        weekNumber = existing.map((g) => g.weekNumber).reduce((a, b) => a > b ? a : b) + 1;
      });
    }
  }

  Future<void> pickDate({required bool isStart}) async {
    final initial = isStart ? startDate : endDate;
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
    setState(() {
      if (isStart) {
        startDate = combined;
      } else {
        endDate = combined;
      }
    });
  }

  Future<void> create() async {
    final teamId = widget.appState.currentUser?.teamIds.first;
    if (teamId == null) return;

    if (!endDate.isAfter(startDate)) {
      setState(() => errorMessage = 'Deadline must be after the first kickoff.');
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
      final gameWeek = GameWeek(
        id: null,
        teamId: teamId,
        weekNumber: weekNumber,
        startDate: startDate,
        endDate: endDate,
        isSettled: false,
        createdAt: DateTime.now(),
      );
      await FirestoreService.instance.createGameWeek(gameWeek);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Gameweek'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              onTap: () => pickDate(isStart: true),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: Colors.white,
              title: const Text('Deadline / last match'),
              subtitle: Text(formatDateTime(endDate)),
              onTap: () => pickDate(isStart: false),
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