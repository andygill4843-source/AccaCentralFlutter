import 'package:flutter/material.dart';
import 'api_football_service.dart';
import 'pick_outcome_screen.dart';
import 'models.dart';
import 'fixture_card.dart';
import 'main.dart';

class SubmitLegScreen extends StatefulWidget {
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String? tournamentMatchId;
  final bool isSecondaryTournamentLeg;
  final List<BetType>? allowedBetTypes;

  const SubmitLegScreen({
    super.key,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    required this.windowStart,
    required this.windowEnd,
    this.tournamentMatchId,
    this.isSecondaryTournamentLeg = false,
    this.allowedBetTypes,
  });

  @override
  State<SubmitLegScreen> createState() => _SubmitLegScreenState();
}

class _SubmitLegScreenState extends State<SubmitLegScreen> {
  static const Map<String, String> _leagueOptions = {
    'soccer_epl':               'Premier League',
    'soccer_efl_champ':         'Championship',
    'soccer_england_league1':   'League One',
    'soccer_england_league2':   'League Two',
    'apifootball_only_national_league': 'National League',
    'soccer_italy_serie_a':     'Serie A',
    'soccer_spain_la_liga':     'La Liga',
    'soccer_france_ligue_one':  'Ligue 1',
    'soccer_germany_bundesliga': 'Bundesliga',
    'soccer_netherlands_eredivisie': 'Eredivisie',
  };

  static const List<String> _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String selectedLeague = 'soccer_epl';
  List<ApiFootballFixture> fixtures = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadFixtures();
  }

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

      final filtered = loaded.where((f) =>
        f.kickoff.isAfter(now) &&
        !f.kickoff.isBefore(widget.windowStart) &&
        !f.kickoff.isAfter(widget.windowEnd) &&
        !f.isUnavailableForSelection
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

  /// Two-line date/time for the header's centre — replaces the score
  /// box shown on the live screen, since this fixture hasn't kicked off.
  Widget _kickoffCenter(ApiFootballFixture f) {
    final local = f.kickoff.toLocal();
    final dateStr = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        fixtureStatusChip(dateStr),
        const SizedBox(height: 6),
        Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    final submitted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => PickOutcomeScreen(
                          fixture: fixture,
                          leagueKey: selectedLeague,
                          gameWeekId: widget.gameWeekId,
                          memberId: widget.memberId,
                          teamId: widget.teamId,
                          tournamentMatchId: widget.tournamentMatchId,
                          isSecondaryTournamentLeg: widget.isSecondaryTournamentLeg,
                          allowedBetTypes: widget.allowedBetTypes,
                        ),
                      ),
                    );
                    if (submitted == true && mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: FixtureHeaderCard(
                    fixtureId: fixture.id,
                    homeLogo: fixture.homeLogo,
                    awayLogo: fixture.awayLogo,
                    homeName: fixture.homeTeam,
                    awayName: fixture.awayTeam,
                    isLive: false,
                    roundAllCorners: true,
                    centerContent: _kickoffCenter(fixture),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}