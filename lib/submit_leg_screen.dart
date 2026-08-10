import 'package:flutter/material.dart';
import 'odds_api_service.dart';
import 'pick_outcome_screen.dart';
import 'main.dart'; // for AccaColors

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
  State<SubmitLegScreen> createState() => _SubmitLegScreenState();
}

class _SubmitLegScreenState extends State<SubmitLegScreen> {
  SoccerLeague selectedLeague = SoccerLeague.premierLeague;
  List<OddsEvent> events = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadEvents();
  }

  Future<void> loadEvents() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final allEvents = await OddsApiService.instance.fetchOdds(league: selectedLeague);
      final filtered = allEvents
          .where((e) => e.commenceTime.isAfter(widget.windowStart) && e.commenceTime.isBefore(widget.windowEnd))
          .toList();
      setState(() {
        events = filtered;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Couldn't load fixtures/odds.";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick your leg'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<SoccerLeague>(
              value: selectedLeague,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: SoccerLeague.values
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.displayName)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => selectedLeague = value);
                loadEvents();
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
                    : events.isEmpty
                        ? const Center(child: Text('No upcoming fixtures found for this competition and gameweek window.'))
                        : ListView.builder(
                            itemCount: events.length,
                            itemBuilder: (context, index) {
                              final event = events[index];
                              return ListTile(
                                title: Text('${event.homeTeam} vs ${event.awayTeam}'),
                                subtitle: Text(formatDateTime(event.commenceTime)),
                                onTap: () async {
                                  final submitted = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => PickOutcomeScreen(
                                        event: event,
                                        league: selectedLeague,
                                        gameWeekId: widget.gameWeekId,
                                        memberId: widget.memberId,
                                        teamId: widget.teamId,
                                      ),
                                    ),
                                  );
                                  if (submitted == true && mounted) {
                                    Navigator.of(context).pop(true);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  String formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}