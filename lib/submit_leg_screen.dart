import 'package:flutter/material.dart';
import 'api_football_service.dart';
import 'pick_outcome_screen.dart';
import 'main.dart';

class SubmitLegScreen extends StatefulWidget {
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String? tournamentMatchId;
  final bool isSecondaryTournamentLeg;

  const SubmitLegScreen({
    super.key,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    required this.windowStart,
    required this.windowEnd,
    this.tournamentMatchId,
    this.isSecondaryTournamentLeg = false,
  });

  @override
  State<SubmitLegScreen> createState() => _SubmitLegScreenState();
}

class _SubmitLegScreenState extends State<SubmitLegScreen> {
  // ── League options ────────────────────────────────────────────────────────
  // Keys are The Odds API league keys — these map to API Football IDs via
  // ApiFootballService.leagueIds, and are also passed to PickOutcomeScreen
  // so the orchestrator knows which Odds API endpoint to call.
  static const Map<String, String> _leagueOptions = {
    'soccer_epl':               'Premier League',
    'soccer_efl_champ':         'Championship',
    'soccer_england_league1':   'League One',
    'soccer_england_league2':   'League Two',
    'soccer_italy_serie_a':     'Serie A',
    'soccer_spain_la_liga':     'La Liga',
    'soccer_france_ligue_one':  'Ligue 1',
    'soccer_germany_bundesliga': 'Bundesliga',
  };

  static const List<String> _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  // ── State ─────────────────────────────────────────────────────────────────
  String selectedLeague = 'soccer_epl';
  List<ApiFootballFixture> fixtures = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadFixtures();
  }

  // ── Load fixtures ─────────────────────────────────────────────────────────

  Future<void> loadFixtures() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
        fixtures = [];
      });
    }

    final requestedLeague = selectedLeague;
    final apiLeagueId = ApiFootballService.leagueIds[requestedLeague];

    if (apiLeagueId == null) {
      if (mounted) {
        setState(() {
          errorMessage = 'Unknown league: $requestedLeague';
          isLoading = false;
        });
      }
      return;
    }

    try {
      final loaded = await ApiFootballService.instance.fetchFixtures(
        leagueId: apiLeagueId,
        from: widget.windowStart,
        to: widget.windowEnd,
      );

      final now = DateTime.now();

      // Filter to:
      //   1. Future only — can't pick a match that's already kicked off
      //   2. Within the gameweek window by TIME, not just by date — this
      //      prevents e.g. a 12:30 Saturday kick-off showing when the
      //      window doesn't open until 3pm Saturday.
      final filtered = loaded.where((f) =>
        f.kickoff.isAfter(now) &&
        !f.kickoff.isBefore(widget.windowStart) &&
        !f.kickoff.isAfter(widget.windowEnd)
      ).toList();

      if (!mounted || selectedLeague != requestedLeague) return;

      setState(() {
        fixtures = filtered;
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        fixtures = [];
        isLoading = false;
        errorMessage = "Couldn't load fixtures: $e";
      });
    }
  }

  Future<void> changeLeague(String value) async {
    if (value == selectedLeague) return;
    setState(() {
      selectedLeague = value;
      fixtures = [];
      errorMessage = null;
    });
    await loadFixtures();
  }

  // ── Group by day ──────────────────────────────────────────────────────────

  Map<DateTime, List<ApiFootballFixture>> _groupByDay(
    List<ApiFootballFixture> list,
  ) {
    final grouped = <DateTime, List<ApiFootballFixture>>{};
    for (final f in list) {
      final local = f.kickoff.toLocal();
      final dayKey = DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(dayKey, () => []).add(f);
    }
    for (final dayFixtures in grouped.values) {
      dayFixtures.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    }
    return grouped;
  }

  String _dayTitle(DateTime day) {
    final weekday = _weekdayNames[day.weekday - 1];
    final month = _monthNames[day.month - 1];
    return '$weekday, ${day.day} $month';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tournamentMatchId == null
              ? 'Pick your leg'
              : (widget.isSecondaryTournamentLeg
                  ? 'Pick your Secondary Leg'
                  : 'Pick your Primary Leg'),
        ),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Column(
        children: [
          // League selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('League',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedLeague,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AccaColors.gold, width: 1.5),
                    ),
                  ),
                  dropdownColor: Colors.white,
                  style: accaFieldTextStyle,
                  items: _leagueOptions.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: const TextStyle(color: Colors.black))))
                      .toList(),
                  onChanged:
                      isLoading ? null : (v) { if (v != null) changeLeague(v); },
                ),
              ],
            ),
          ),
          Expanded(child: _buildFixtureContent()),
        ],
      ),
    );
  }

  Widget _buildFixtureContent() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading fixtures...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: loadFixtures, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    if (fixtures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports_soccer, size: 48, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'No fixtures found in this window for '
                '${_leagueOptions[selectedLeague] ?? selectedLeague}.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Games may have already kicked off, or the window '
                'doesn\'t cover any fixtures for this league.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AccaColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: loadFixtures, child: const Text('Reload fixtures')),
            ],
          ),
        ),
      );
    }

    final grouped = _groupByDay(fixtures);
    final sortedDays = grouped.keys.toList()..sort();

    return ListView(
      children: [
        for (final day in sortedDays) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              _dayTitle(day),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AccaColors.gold),
            ),
          ),
          for (final fixture in grouped[day]!)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.sports_soccer, color: Colors.white),
                title: Text(
                  '${fixture.homeTeam} vs ${fixture.awayTeam}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(fixture.leagueName,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(_formatTime(fixture.kickoff)),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final submitted = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PickOutcomeScreen(
                        fixture: fixture,
                        leagueKey: selectedLeague, // Odds API key
                        gameWeekId: widget.gameWeekId,
                        memberId: widget.memberId,
                        teamId: widget.teamId,
                        tournamentMatchId: widget.tournamentMatchId,
                        isSecondaryTournamentLeg: widget.isSecondaryTournamentLeg,
                      ),
                    ),
                  );
                  if (submitted == true && mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
            ),
        ],
      ],
    );
  }
}