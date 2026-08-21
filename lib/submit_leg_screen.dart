import 'package:flutter/material.dart';

import 'uk_odds_api_service.dart';
import 'pick_outcome_screen.dart';
import 'main.dart';

class SubmitLegScreen extends StatefulWidget {
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final DateTime windowStart;
  final DateTime windowEnd;

  const SubmitLegScreen({
    super.key,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    required this.windowStart,
    required this.windowEnd,
  });

  @override
  State<SubmitLegScreen> createState() =>
      _SubmitLegScreenState();
}

class _SubmitLegScreenState
    extends State<SubmitLegScreen> {

  // ============================================================
  // LEAGUES
  // ============================================================

  static const Map<String, String> _leagueOptions = {
    'english premier': 'Premier League',
    'english championship': 'Championship',
    'english league one': 'League One',
    'english league two': 'League Two',
    'fa cup': 'FA Cup',
    'champions league': 'Champions League',
    'la liga': 'La Liga',
    'serie a': 'Serie A',
    'bundesliga': 'Bundesliga',
    'ligue 1': 'Ligue 1',
  };



  // ============================================================
  // STATE
  // ============================================================

  String selectedLeague =
      'english premier';

  List<UkOddsFixtureSummary> events =
      <UkOddsFixtureSummary>[];

  bool isLoading = false;

  String? errorMessage;

  @override
  void initState() {
    super.initState();

    loadEvents();
  }

  // ============================================================
  // LOAD EVENTS
  // ============================================================

  Future<void> loadEvents() async {

    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;

        // Clear old results immediately.
        events = <UkOddsFixtureSummary>[];
      });
    }

    final requestedLeague =
        selectedLeague;

    debugPrint(
      '========================================',
    );

    debugPrint(
      'SUBMIT LEG - LOADING FIXTURES',
    );

    debugPrint(
      'Selected league: $requestedLeague',
    );

    debugPrint(
      'Window start: ${widget.windowStart}',
    );

    debugPrint(
      'Window end: ${widget.windowEnd}',
    );

    debugPrint(
      '========================================',
    );

    try {

      final loadedEvents =
          await UkOddsApiService.instance
              .fetchFixtures(
        from: widget.windowStart,
        to: widget.windowEnd,
        league: requestedLeague,
      );

      debugPrint(
        '========================================',
      );

      debugPrint(
        'SUBMIT LEG - EVENTS RECEIVED',
      );

      debugPrint(
        'Requested league: $requestedLeague',
      );

      debugPrint(
        'Number of events: ${loadedEvents.length}',
      );

      for (final event in loadedEvents) {
        debugPrint(
          'DISPLAY EVENT: '
          '${event.leagueName} | '
          '${event.homeTeam} vs '
          '${event.awayTeam}',
        );
      }

      debugPrint(
        '========================================',
      );

      if (!mounted) {
        return;
      }

      // Make absolutely sure the response belongs to the
      // currently selected league.
      //
      // This prevents a slower previous request from replacing
      // the results of a newer selection.

      if (selectedLeague != requestedLeague) {
        return;
      }

      setState(() {
        events = loadedEvents;
        isLoading = false;
        errorMessage = null;
      });

    } catch (e) {

      debugPrint(
        'SUBMIT LEG - ERROR: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        events = <UkOddsFixtureSummary>[];
        isLoading = false;
        errorMessage =
            "Couldn't load fixtures: $e";
      });
    }
  }

  // ============================================================
  // LEAGUE CHANGED
  // ============================================================

  Future<void> changeLeague(
    String value,
  ) async {

    if (value == selectedLeague) {
      return;
    }

    setState(() {
      selectedLeague = value;

      // Immediately remove the previous league's fixtures.
      events = <UkOddsFixtureSummary>[];

      errorMessage = null;
    });

    await loadEvents();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Pick your leg',
        ),
        backgroundColor:
            AccaColors.primary,
        foregroundColor:
            Colors.white,
      ),

      backgroundColor:
          AccaColors.background,

      body: Column(
        children: [

          // ======================================================
          // LEAGUE SELECTOR
          // ======================================================

          Padding(
            padding:
                const EdgeInsets.all(16),

            child:
                DropdownButtonFormField<String>(
                  
              initialValue: selectedLeague,
                  
              decoration: accaFieldDecoration('League'),
              
              dropdownColor: Colors.white,
          
              style: accaFieldTextStyle,

              items:
                  _leagueOptions.entries
                      .map(
                (
                  entry,
                ) {
                  return DropdownMenuItem<
                      String>(
                    value:
                        entry.key,
                    child:
                        Text(
                      entry.value,
                    ),
                  );
                },
              ).toList(),

              onChanged:
                  isLoading
                      ? null
                      : (
                          value,
                        ) {
                          if (value ==
                              null) {
                            return;
                          }

                          changeLeague(
                            value,
                          );
                        },
            ),
          ),

          // ======================================================
          // FIXTURES
          // ======================================================

          Expanded(
            child:
                _buildFixtureContent(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FIXTURE CONTENT
  // ============================================================

  Widget _buildFixtureContent() {

    if (isLoading) {

      return const Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [

            CircularProgressIndicator(),

            SizedBox(
              height: 16,
            ),

            Text(
              'Loading fixtures...',
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {

      return Center(
        child:
            Padding(
          padding:
              const EdgeInsets.all(24),

          child:
              Column(
            mainAxisSize:
                MainAxisSize.min,

            children: [

              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),

              const SizedBox(
                height: 16,
              ),

              Text(
                errorMessage!,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color: Colors.red,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              ElevatedButton(
                onPressed:
                    loadEvents,
                child:
                    const Text(
                  'Try again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (events.isEmpty) {

      return Center(
        child:
            Padding(
          padding:
              const EdgeInsets.all(24),

          child:
              Column(
            mainAxisSize:
                MainAxisSize.min,

            children: [

              const Icon(
                Icons.sports_soccer,
                size: 48,
              ),

              const SizedBox(
                height: 16,
              ),

              Text(
                'No fixtures found for '
                '${_leagueOptions[selectedLeague] ?? selectedLeague}.',
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  fontSize: 16,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              Text(
                'Check the selected gameweek window.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      AccaColors.textSecondary,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              ElevatedButton(
                onPressed:
                    loadEvents,
                child:
                    const Text(
                  'Reload fixtures',
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ==========================================================
    // FIXTURE LIST
    // ==========================================================

    return ListView.builder(

      itemCount:
          events.length,

      itemBuilder:
          (
        context,
        index,
      ) {

        final event =
            events[index];

        return Card(
          margin:
              const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 5,
          ),

          child:
              ListTile(

            leading:
                const Icon(
              Icons.sports_soccer,
              color:
                  AccaColors.primary,
            ),

            title:
                Text(
              '${event.homeTeam} vs '
              '${event.awayTeam}',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),

            subtitle:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                const SizedBox(
                  height: 4,
                ),

                Text(
                  event.leagueName,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  formatDateTime(
                    event.kickoffUtc,
                  ),
                ),
              ],
            ),

            trailing:
                const Icon(
              Icons.chevron_right,
            ),

            onTap:
                () async {

              final submitted =
                  await Navigator.of(
                context,
              ).push<bool>(
                MaterialPageRoute(
                  builder:
                      (_) =>
                          PickOutcomeScreen(
                    fixture:
                        event,

                    gameWeekId:
                        widget.gameWeekId,

                    memberId:
                        widget.memberId,

                    teamId:
                        widget.teamId,

                  ),
                ),
              );

              if (submitted ==
                      true &&
                  mounted) {

                Navigator.of(
                  context,
                ).pop(true);
              }
            },
          ),
        );
      },
    );
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String formatDateTime(
    DateTime dateTime,
  ) {

    final local =
        dateTime.toLocal();

    return
        '${local.day}/'
        '${local.month} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}