import 'dart:async';
import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'api_football_service.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';
import 'settlement_engine.dart';

class LiveAccumulatorScreen extends StatefulWidget {
  final GameWeek gameWeek;
  const LiveAccumulatorScreen({super.key, required this.gameWeek});
  @override
  State<LiveAccumulatorScreen> createState() => _LiveAccumulatorScreenState();
}

class _LiveAccumulatorScreenState extends State<LiveAccumulatorScreen> {
  List<AccumulatorLeg> legs = [];
  // fixtureId → live fixture data
  Map<int, ApiFootballFixture> fixtures = {};
  // fixtureId → events list
  Map<int, List<ApiFootballEvent>> events = {};
  // memberId → displayName, for showing names instead of raw IDs.
  Map<String, String> memberNames = {};
  bool isLoading = true;
  String? errorMessage;
  Timer? pollTimer;

  // Deduplicated view: groups legs with the same selection into one card.
  List<_LegGroup> get legGroups {
    final groups = <String, _LegGroup>{};
    for (final leg in legs) {
      // Key: fixture + selection — same fixture, different bet types are separate.
      final key = '${leg.apiFootballFixtureId ?? leg.fixtureDescription}_${leg.selectionDescription}';
      if (groups.containsKey(key)) {
        groups[key]!.legs.add(leg);
      } else {
        groups[key] = _LegGroup(legs: [leg]);
      }
    }
    return groups.values.toList();
  }

  // Count of legs currently on track to win.
  int get winningLegsCount {
    int count = 0;
    for (final leg in legs) {
      if (_isLegCurrentlyWinning(leg)) count++;
    }
    return count;
  }

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
      final members = await FirestoreService.instance.fetchMembers(widget.gameWeek.teamId);
      if (mounted) {
        setState(() {
          legs = allLegs
              .where((l) => l.gameWeekId == widget.gameWeek.id && !l.isSecondaryTournamentLeg)
              .toList();
          memberNames = {for (final m in members) if (m.id != null) m.id!: m.displayName};
          isLoading = false;
        });
      }
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
    // Collect unique API Football fixture IDs from legs.
    final fixtureIds = legs
        .where((l) => l.apiFootballFixtureId != null)
        .map((l) => l.apiFootballFixtureId!)
        .toSet();

    for (final fixtureId in fixtureIds) {
      try {
        final fixture = await ApiFootballService.instance.fetchFixture(fixtureId);
        if (fixture == null || !mounted) continue;
        setState(() => fixtures[fixtureId] = fixture);

        // Fetch events for fixtures that are live or just finished.
        if (fixture.isLive || fixture.isFinished) {
          final fixtureEvents = await ApiFootballService.instance.fetchEvents(fixtureId);
          if (mounted) setState(() => events[fixtureId] = fixtureEvents);
        }
      } catch (_) {
        // best-effort
      }
    }

    // Legs without an API Football fixture ID have no live data — they
    // will show "—" for the score, which is handled in the card builder.
  }

  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => refreshFixtures());
  }

  // ── Settlement determination (mirrors settleLegs.js logic) ──────────────

  bool _isLegCurrentlyWinning(AccumulatorLeg leg) {
    if (leg.outcome == LegOutcome.won) return true;
    if (leg.outcome == LegOutcome.lost) return false;
    final fixtureId = leg.apiFootballFixtureId;
    if (fixtureId == null) return false;
    final fixture = fixtures[fixtureId];
    if (fixture == null) return false;
    if (fixture.isNotStarted) return false;
    return SettlementEngine.isCurrentlyWinning(leg: leg, fixture: fixture);
  }

  bool _isLegSettled(AccumulatorLeg leg) =>
      leg.outcome == LegOutcome.won || leg.outcome == LegOutcome.lost;

  @override
  Widget build(BuildContext context) {
    final groups = legGroups;
    final total = legs.length;
    final winning = winningLegsCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$winning / $total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: winning == total && total > 0 ? AccaColors.gold : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : legs.isEmpty
                  ? const Center(
                      child: Text('No legs submitted for this gameweek yet.',
                          style: TextStyle(color: Colors.white70)),
                    )
                  : RefreshIndicator(
                      onRefresh: refreshFixtures,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _legGroupCard(groups[index]),
                      ),
                    ),
    );
  }

  Widget _legGroupCard(_LegGroup group) {
    final rep = group.legs.first; // representative leg for fixture data
    final fixtureId = rep.apiFootballFixtureId;
    final fixture = fixtureId != null ? fixtures[fixtureId] : null;
    final fixtureEvents = fixtureId != null ? (events[fixtureId] ?? []) : <ApiFootballEvent>[];

    // Filter events to only goal and card events, newest first.
    final relevantEvents = fixtureEvents
        .where((e) => e.isGoal || e.isCard)
        .toList()
      ..sort((a, b) => b.elapsed.compareTo(a.elapsed));

    final isWinning = _isLegCurrentlyWinning(rep);
    final isSettled = _isLegSettled(rep);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSettled
              ? (isWinning ? AccaColors.win : AccaColors.loss)
              : AccaColors.gold,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: fixture + score + status
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rep.fixtureDescription,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rep.selectionDescription,
                        style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        decimalToFractional(rep.decimalOddsAtSelection),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Score + status
                if (fixture != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fixture.scoreDisplay,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _statusChip(fixture),
                    ],
                  )
                else
                  const Text('—', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                // Tick / cross
                Icon(
                  isSettled
                      ? (isWinning ? Icons.check_circle : Icons.cancel)
                      : (isWinning ? Icons.check_circle_outline : Icons.radio_button_unchecked),
                  color: isWinning
                      ? (isSettled ? AccaColors.win : Colors.green)
                      : (isSettled ? AccaColors.loss : Colors.grey),
                  size: 28,
                ),
              ],
            ),
          ),
          // Who picked this leg (when deduplicated across members)
          if (group.legs.length > 1 || true) // always show member names
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final leg in group.legs)
                    Chip(
                      label: Text(
                        memberNames[leg.memberId] ?? 'Unknown',
                        style: const TextStyle(fontSize: 11),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AccaColors.surface,
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                ],
              ),
            ),
          // Latest match event only.
          if (relevantEvents.isNotEmpty) ...[
            const Divider(height: 1, color: Colors.black12),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                relevantEvents.first.displayText,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _statusChip(ApiFootballFixture fixture) {
    final Color color;
    if (fixture.isFinished) {
      color = AccaColors.loss; // red
    } else if (fixture.isLive) {
      color = AccaColors.win; // green
    } else {
      color = Colors.white; // white for kick-off soon
    }
    final label = fixture.statusLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fixture.isNotStarted ? Colors.black : color,
        ),
      ),
    );
  }
}

// ── Helper classes ──────────────────────────────────────────────────────────

class _LegGroup {
  final List<AccumulatorLeg> legs;
  _LegGroup({required this.legs});
}