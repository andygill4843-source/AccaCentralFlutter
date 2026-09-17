import 'package:flutter/material.dart';
import 'dart:math';
import 'firestore_service.dart';
import 'models.dart';
import 'scoring_engine.dart';
import 'tournament_bracket_engine.dart';
import 'tournament_participant_picker_screen.dart';
import 'main.dart'; // for AccaColors

enum _SelectionMethod { random, leagueTable, manual }

class CreateTournamentScreen extends StatefulWidget {
  final String teamId;
  const CreateTournamentScreen({super.key, required this.teamId});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameController = TextEditingController();
  List<Member> members = [];
  int maxRounds = 0;
  int rounds = 1;
  DateTime? drawDateTime;
  _SelectionMethod selectionMethod = _SelectionMethod.random;
  List<String>? manualSelection; // set once the picker screen returns a result
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final loadedMembers = await FirestoreService.instance.fetchMembers(widget.teamId);
    final calculatedMax = TournamentBracketEngine.maxRounds(loadedMembers.length);
    if (!mounted) return;
    setState(() {
      members = loadedMembers;
      maxRounds = calculatedMax;
      rounds = calculatedMax; // default to using everyone — no selection method needed
      isLoading = false;
    });
  }

  bool get needsSelectionMethod => rounds < maxRounds;
  int get requiredParticipantCount => 1 << rounds; // 2^rounds

  String _formatDateTime(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> pickDrawDateTime() async {
    final initial = drawDateTime ?? DateTime.now().add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;
    setState(() {
      drawDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> pickManualParticipants() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => TournamentParticipantPickerScreen(
          members: members,
          requiredCount: requiredParticipantCount,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => manualSelection = result);
    }
  }

  /// Best performers first — reuses the same ordering the League Table
  /// tab itself shows, so "based on the league table" means exactly what
  /// it says: the top N by current standing.
  Future<List<String>> _leagueTableTopN(int n) async {
    final team = await FirestoreService.instance.fetchTeam(widget.teamId);
    final season = team?.season ?? '';
    final allLegs = await FirestoreService.instance.fetchLegs(widget.teamId);
    final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
    final seasonGameWeekIds = gameWeeks.where((g) => g.season == season).map((g) => g.id).toSet();
    final seasonLegs = allLegs.where((l) => seasonGameWeekIds.contains(l.gameWeekId)).toList();
    final challenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: season);
    final table = ScoringEngine.buildLeagueTable(members: members, legs: seasonLegs, challenges: challenges);
    return table.take(n).map((e) => e.memberId).toList();
  }

  Future<void> submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Enter a tournament name.');
      return;
    }
    if (drawDateTime == null) {
      setState(() => errorMessage = 'Set a draw date and time.');
      return;
    }
    if (needsSelectionMethod && selectionMethod == _SelectionMethod.manual && manualSelection == null) {
      setState(() => errorMessage = 'Choose the $requiredParticipantCount participants first.');
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    try {
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      List<String>? participantIds;

      if (needsSelectionMethod) {
        switch (selectionMethod) {
          case _SelectionMethod.random:
            final shuffled = [for (final m in members) if (m.id != null) m.id!]..shuffle(Random());
            participantIds = shuffled.take(requiredParticipantCount).toList();
            break;
          case _SelectionMethod.leagueTable:
            participantIds = await _leagueTableTopN(requiredParticipantCount);
            break;
          case _SelectionMethod.manual:
            participantIds = manualSelection;
            break;
        }
      }
      // rounds == maxRounds: participantIds stays null — everyone plays,
      // same as the original single-tournament behaviour.

      final tournament = Tournament(
        teamId: widget.teamId,
        season: team?.season ?? '',
        name: _nameController.text.trim(),
        drawDateTime: drawDateTime!,
        mainBracketSize: requiredParticipantCount,
        participantMemberIds: participantIds,
        createdAt: DateTime.now(),
      );
      await FirestoreService.instance.createTournament(tournament);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Tournament'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : maxRounds < 1
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Need at least 2 members on the team to set up a tournament.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Tournament name',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Rounds', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Up to $maxRounds for a team of ${members.length}.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: rounds,
                        decoration: const InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
                        dropdownColor: Colors.white,
                        items: [
                          for (var r = 1; r <= maxRounds; r++)
                            DropdownMenuItem(
                              value: r,
                              child: Text('$r (${1 << r} participants — ${tournamentRoundLabel(1 << r)} start)', style: const TextStyle(color: Colors.black)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            rounds = v;
                            manualSelection = null; // required count may have changed
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      ListTile(
                        tileColor: AccaColors.surface,
                        title: const Text('Draw date & time'),
                        subtitle: Text(drawDateTime == null ? 'Not set' : _formatDateTime(drawDateTime!)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: pickDrawDateTime,
                      ),
                      if (needsSelectionMethod) ...[
                        const SizedBox(height: 24),
                        Text(
                          'This uses $requiredParticipantCount of your ${members.length} members. How should they be chosen?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                         RadioGroup<_SelectionMethod>(
                          groupValue: selectionMethod,
                          onChanged: (v) => setState(() => selectionMethod = v!),
                          child: Column(
                            children: const [
                              RadioListTile<_SelectionMethod>(
                                value: _SelectionMethod.random,
                                title: Text('Random', style: TextStyle(color: Colors.white)),
                                activeColor: AccaColors.gold,
                              ),
                              RadioListTile<_SelectionMethod>(
                                value: _SelectionMethod.leagueTable,
                                title: Text('Best performers (league table)', style: TextStyle(color: Colors.white)),
                                activeColor: AccaColors.gold,
                              ),
                              RadioListTile<_SelectionMethod>(
                                value: _SelectionMethod.manual,
                                title: Text('Choose specific members', style: TextStyle(color: Colors.white)),
                                activeColor: AccaColors.gold,
                              ),
                            ],
                          ),
                        ),
                        if (selectionMethod == _SelectionMethod.manual) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: pickManualParticipants,
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: AccaColors.gold), foregroundColor: AccaColors.gold),
                            child: Text(
                              manualSelection == null
                                  ? 'Choose $requiredParticipantCount members'
                                  : '${manualSelection!.length} members selected — tap to change',
                            ),
                          ),
                        ],
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(errorMessage!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: isSubmitting ? null : submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Create tournament', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
    );
  }
}