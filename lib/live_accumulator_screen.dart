import 'dart:async';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'api_football_service.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';
import 'settlement_engine.dart';
import 'fixture_card.dart';

class LiveAccumulatorScreen extends StatefulWidget {
  final AppState appState;
  final GameWeek? gameWeek;
  const LiveAccumulatorScreen({super.key, required this.appState, this.gameWeek});
  @override
  State<LiveAccumulatorScreen> createState() => _LiveAccumulatorScreenState();
}

class _LiveAccumulatorScreenState extends State<LiveAccumulatorScreen> {
  List<AccumulatorLeg> legs = [];
  Map<int, ApiFootballFixture> fixtures = {};
  Map<int, List<ApiFootballEvent>> events = {};
  Map<String, String> memberNames = {};
  Member? currentMember;
  Map<int, LiveNotificationMute> mutePrefsByFixture = {};
  bool isLoading = true;
  String? errorMessage;
  Timer? pollTimer;

  bool get _isLocked => widget.gameWeek?.isLocked ?? false;

  List<_LegGroup> get legGroups {
    final groups = <String, _LegGroup>{};
    for (final leg in legs) {
      final key = '${leg.apiFootballFixtureId ?? leg.fixtureDescription}_${leg.selectionDescription}';
      if (groups.containsKey(key)) {
        groups[key]!.legs.add(leg);
      } else {
        groups[key] = _LegGroup(legs: [leg]);
      }
    }
    return groups.values.toList();
  }

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
    if (_isLocked) {
      loadLegs();
    } else {
      isLoading = false;
    }
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadLegs() async {
    final gameWeek = widget.gameWeek;
    if (gameWeek == null || gameWeek.id == null) {
      setState(() {
        errorMessage = 'No active gameweek.';
        isLoading = false;
      });
      return;
    }
    try {
      final allLegs = await FirestoreService.instance.fetchLegs(gameWeek.teamId);
      final members = await FirestoreService.instance.fetchMembers(gameWeek.teamId);
      final userId = widget.appState.currentUser?.id;
      Member? me;
      if (userId != null) {
        me = await FirestoreService.instance.fetchMember(teamId: gameWeek.teamId, userId: userId);
      }
      final scopedLegs = allLegs
          .where((l) => l.gameWeekId == gameWeek.id && !l.isSecondaryTournamentLeg)
          .toList();
      Map<int, LiveNotificationMute> mutes = {};
      if (me?.id != null) {
        final fixtureIds = scopedLegs.map((l) => l.apiFootballFixtureId).whereType<int>().toSet().toList();
        try {
          mutes = await FirestoreService.instance.fetchLiveNotificationMutesForMember(
            teamId: gameWeek.teamId,
            memberId: me!.id!,
            apiFootballFixtureIds: fixtureIds,
          );
        } catch (_) {
          // best-effort
        }
      }
      if (mounted) {
        setState(() {
          legs = scopedLegs;
          memberNames = {for (final m in members) if (m.id != null) m.id!: m.displayName};
          currentMember = me;
          mutePrefsByFixture = mutes;
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
    final fixtureIds = legs
        .where((l) => l.apiFootballFixtureId != null)
        .map((l) => l.apiFootballFixtureId!)
        .toSet();

    for (final fixtureId in fixtureIds) {
      try {
        final fixture = await ApiFootballService.instance.fetchFixture(fixtureId);
        if (fixture == null || !mounted) continue;
        setState(() => fixtures[fixtureId] = fixture);

        if (fixture.isLive || fixture.isFinished) {
          final fixtureEvents = await ApiFootballService.instance.fetchEvents(fixtureId);
          if (mounted) setState(() => events[fixtureId] = fixtureEvents);
        }
      } catch (_) {
        // best-effort
      }
    }
  }

  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => refreshFixtures());
  }

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

  Future<void> _showMuteSheet(int fixtureId) async {
    if (currentMember?.id == null || widget.gameWeek == null) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications for this match',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
              ),
              const SizedBox(height: 4),
              const Text(
                "Affects notifications about anyone's leg on this fixture, not just yours.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              for (final (key, label) in LiveNotificationMute.allCategories)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label, style: const TextStyle(color: Colors.black, fontSize: 14)),
                  value: !(mutePrefsByFixture[fixtureId]?.isMuted(key) ?? false),
                  activeThumbColor: AccaColors.gold,
                  onChanged: (receiving) async {
                    final muted = !receiving;
                    final existing = mutePrefsByFixture[fixtureId];
                    final updatedMap = Map<String, bool>.from(existing?.mutedCategories ?? {});
                    updatedMap[key] = muted;
                    final updated = LiveNotificationMute(
                      teamId: widget.gameWeek!.teamId,
                      memberId: currentMember!.id!,
                      apiFootballFixtureId: fixtureId,
                      mutedCategories: updatedMap,
                    );
                    setSheetState(() => mutePrefsByFixture[fixtureId] = updated);
                    setState(() => mutePrefsByFixture[fixtureId] = updated);
                    await FirestoreService.instance.setLiveNotificationMuteCategory(
                      teamId: widget.gameWeek!.teamId,
                      memberId: currentMember!.id!,
                      apiFootballFixtureId: fixtureId,
                      category: key,
                      muted: muted,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isLocked && !isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$winningLegsCount / ${legs.length}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: winningLegsCount == legs.length && legs.isNotEmpty ? AccaColors.gold : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      backgroundColor: AccaColors.background,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.gameWeek == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Currently no active gameweek', style: TextStyle(color: Colors.white70, fontSize: 15), textAlign: TextAlign.center),
        ),
      );
    }
    if (!_isLocked) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Gameweek selections underway. Live scores will show following selection',
            style: TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) return Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)));
    if (legs.isEmpty) {
      return const Center(child: Text('No legs submitted for this gameweek yet.', style: TextStyle(color: Colors.white70)));
    }
    final groups = legGroups;
    return RefreshIndicator(
      onRefresh: refreshFixtures,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _legGroupCard(groups[index]),
      ),
    );
  }

  Widget _liveCenter(ApiFootballFixture? fixture) {
    if (fixture == null) {
      return const Text('—', style: TextStyle(color: Colors.white54));
    }
    final String topLabel;
    if (fixture.isLive) {
      topLabel = fixture.halfLabel;
    } else if (fixture.isFinished) {
      topLabel = 'FT';
    } else {
      topLabel = fixture.statusLabel;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        fixtureStatusChip(topLabel),
        if (fixture.isLive && fixture.elapsed != null) ...[
          const SizedBox(height: 4),
          Text("${fixture.elapsed}'", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
        const SizedBox(height: 6),
        Text(fixture.scoreDisplay, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _legGroupCard(_LegGroup group) {
    final rep = group.legs.first;
    final fixtureId = rep.apiFootballFixtureId;
    final fixture = fixtureId != null ? fixtures[fixtureId] : null;
    final fixtureEvents = fixtureId != null ? (events[fixtureId] ?? []) : <ApiFootballEvent>[];

    final relevantEvents = fixtureEvents
        .where((e) => e.isGoal || e.isCard)
        .toList()
      ..sort((a, b) => b.elapsed.compareTo(a.elapsed));

    final isWinning = _isLegCurrentlyWinning(rep);
    final isSettled = _isLegSettled(rep);
    final hasAnyMute = fixtureId != null && (mutePrefsByFixture[fixtureId]?.mutedCategories.values.any((v) => v) ?? false);

    final homeName = fixture?.homeTeam ?? rep.fixtureDescription.split(' vs ').first;
    final awayName = fixture?.awayTeam ?? (rep.fixtureDescription.split(' vs ').length > 1 ? rep.fixtureDescription.split(' vs ')[1] : '');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSettled
              ? (isWinning ? AccaColors.win : AccaColors.loss)
              : AccaColors.gold,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FixtureHeaderCard(
            fixtureId: fixtureId ?? rep.fixtureDescription.hashCode,
            homeLogo: fixture?.homeLogo ?? '',
            awayLogo: fixture?.awayLogo ?? '',
            homeName: homeName,
            awayName: awayName,
            isLive: fixture?.isLive ?? false,
            centerContent: _liveCenter(fixture),
          ),
          FixtureCardFooter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rep.selectionDescription,
                              style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              decimalToFractional(rep.decimalOddsAtSelection),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      if (fixtureId != null && currentMember?.id != null)
                        IconButton(
                          icon: Icon(
                            hasAnyMute ? Icons.notifications_off : Icons.notifications_none,
                            color: Colors.black45,
                            size: 20,
                          ),
                          tooltip: 'Notification settings for this match',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showMuteSheet(fixtureId),
                        ),
                      const SizedBox(width: 8),
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
          ),
        ],
      ),
    );
  }
}

class _LegGroup {
  final List<AccumulatorLeg> legs;
  _LegGroup({required this.legs});
}