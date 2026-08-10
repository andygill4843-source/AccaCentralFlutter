import 'dart:async';
import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'sportmonks_service.dart';
import 'main.dart'; // for AccaColors

class LiveAccumulatorScreen extends StatefulWidget {
  final GameWeek gameWeek;

  const LiveAccumulatorScreen({super.key, required this.gameWeek});

  @override
  State<LiveAccumulatorScreen> createState() => _LiveAccumulatorScreenState();
}

class _LiveAccumulatorScreenState extends State<LiveAccumulatorScreen> {
  List<AccumulatorLeg> legs = [];
  Map<String, SportmonksFixture> fixtures = {}; // keyed by leg.id
  bool isLoading = true;
  String? errorMessage;
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    loadLegs();
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadLegs() async {
    if (widget.gameWeek.id == null) {
      setState(() {
        errorMessage = 'No active gameweek.';
        isLoading = false;
      });
      return;
    }
    try {
      final allLegs = await FirestoreService.instance.fetchLegs(widget.gameWeek.teamId);
      setState(() {
        legs = allLegs.where((l) => l.gameWeekId == widget.gameWeek.id).toList();
        isLoading = false;
      });
      await refreshFixtures();
      startPolling();
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> refreshFixtures() async {
    for (final leg in legs) {
      if (leg.id == null || leg.sportmonksFixtureId == null) continue;
      try {
        final fixture = await SportmonksService.instance.fetchFixture(leg.sportmonksFixtureId!);
        if (mounted) {
          setState(() => fixtures[leg.id!] = fixture);
        }
      } catch (_) {
        // best-effort — leave this leg showing "—" if the fetch fails
      }
    }
  }

  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => refreshFixtures());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : legs.isEmpty
                  ? const Center(child: Text('No legs submitted for this gameweek yet.'))
                  : ListView.separated(
                      itemCount: legs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final leg = legs[index];
                        final fixture = leg.id != null ? fixtures[leg.id!] : null;
                        return ListTile(
                          title: Text(leg.fixtureDescription, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: Text(leg.selectionDescription, style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
                          trailing: fixture != null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      fixture.homeGoals != null && fixture.awayGoals != null
                                          ? '${fixture.homeGoals} - ${fixture.awayGoals}'
                                          : 'vs',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      fixture.isLive
                                          ? 'Live'
                                          : fixture.isFinished
                                              ? 'Full time'
                                              : 'Kickoff soon',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: fixture.isLive
                                            ? AccaColors.gold
                                            : fixture.isFinished
                                                ? AccaColors.textSecondary
                                                : Colors.grey,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text('—', style: TextStyle(color: Colors.grey)),
                        );
                      },
                    ),
    );
  }
}