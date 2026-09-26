import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';
import 'profile_screen.dart';
import 'place_challenge_screen.dart';
import 'package:collection/collection.dart';
import 'notifications_screen.dart';
import 'api_football_service.dart';
import 'fixture_card.dart';
import 'leg_scout_confidence.dart';
import 'news_feed_widget.dart';
import 'submit_leg_screen.dart';
import 'current_leg_screen.dart';

class _MemberGameWeekPerformance {
  final String memberId;
  final String displayName;
  final int basePoints;
  final double weightedPoints;
  final int? positionDelta;
  _MemberGameWeekPerformance({
    required this.memberId,
    required this.displayName,
    required this.basePoints,
    required this.weightedPoints,
    this.positionDelta,
  });
}

class _NewsFeedEntry {
  final DateTime timestamp;
  final String text;
  const _NewsFeedEntry({required this.timestamp, required this.text});
}

/// Pre-lock summary for one distinct fixture with at least one
/// selection on it — deliberately carries NO bet details, only who's
/// picked this game and how many.
class _FixtureSelectionSummary {
  final int? fixtureId;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final bool isLive;
  final DateTime? kickoff;
  final List<Member> selectedBy;
  const _FixtureSelectionSummary({
    required this.fixtureId,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.isLive,
    required this.kickoff,
    required this.selectedBy,
  });
}

/// Post-lock card group — legs sharing the same fixture AND bet type.
/// Within the card, legs are further split into "selection rows" by
/// their EXACT pick (selectionDescription) so two genuinely different
/// picks of the same bet type are never shown as if they were the same
/// selection.
class _FixtureBetTypeGroup {
  final int? fixtureId;
  final String fixtureDescription;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final bool isLive;
  final ApiFootballFixture? fixture;
  final List<AccumulatorLeg> legs;
  const _FixtureBetTypeGroup({
    required this.fixtureId,
    required this.fixtureDescription,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.isLive,
    required this.fixture,
    required this.legs,
  });

  Map<String, List<AccumulatorLeg>> get bySelection {
    final map = <String, List<AccumulatorLeg>>{};
    for (final leg in legs) {
      map.putIfAbsent(leg.selectionDescription, () => []).add(leg);
    }
    return map;
  }
}

class HomeScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final void Function(int tabIndex) onNavigateToTab;
  final int refreshToken;
  const HomeScreen({super.key, required this.appState, required this.teamId, required this.onNavigateToTab, this.refreshToken = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isLoading = true;
  String? errorMessage;
  GameWeek? activeGameWeek;
  int? nextWeekNumber;
  DateTime? nextDeadline;
  bool hasActiveGameWeek = false;
  bool hasChallengedThisWeek = false;
  Member? currentMember;
  List<Member> members = [];
  List<AccumulatorLeg> activeWeekLegs = [];
  Map<int, ApiFootballFixture> weekFixtures = {};
  List<NewsArticle> latestNews = [];
  List<_NewsFeedEntry> accaNewsFeed = [];
  List<LeagueTableEntry> fullTable = [];
  LeagueTableEntry? myEntry;
  int? pointsOffThird;
  List<_MemberGameWeekPerformance> lastGameweekPerformance = [];
  int myOutstandingFines = 0;
  List<Fine> squadActivityFines = [];
  List<Challenge> squadActivityChallenges = [];
  int myChallengesRemaining = 2;
  int unreadNotifications = 0;
  List<PhysioSession> squadActivityPhysioSessions = [];
  List<Reaction> activeWeekReactions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  List<_MemberGameWeekPerformance> get biggestPositionShiftsUp {
    final risers = lastGameweekPerformance.where((p) => (p.positionDelta ?? 0) > 0).toList();
    if (risers.isEmpty) return [];
    final maxDelta = risers.map((p) => p.positionDelta!).reduce((a, b) => a > b ? a : b);
    final tied = risers.where((p) => p.positionDelta == maxDelta).toList()..shuffle();
    return tied.take(2).toList();
  }

  List<_MemberGameWeekPerformance> get biggestPositionShiftsDown {
    final fallers = lastGameweekPerformance.where((p) => (p.positionDelta ?? 0) < 0).toList();
    if (fallers.isEmpty) return [];
    final minDelta = fallers.map((p) => p.positionDelta!).reduce((a, b) => a < b ? a : b);
    final tied = fallers.where((p) => p.positionDelta == minDelta).toList()..shuffle();
    return tied.take(2).toList();
  }

  bool get _hasKickedOff => activeWeekLegs.any((l) => !l.kickoff.isAfter(DateTime.now()));

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.refreshToken != widget.refreshToken) {
      load();
    }
  }

  Future<void> nudge(Member member) async {
    if (member.id == null) return;
    final recent = await FirestoreService.instance.fetchNotifications(
      teamId: widget.teamId,
      memberId: member.id!,
    );
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    final alreadyNudged = recent.any(
      (n) => n.type == NotificationType.nudge && n.createdAt.isAfter(oneHourAgo),
    );
    if (alreadyNudged) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} was already nudged in the last hour.')),
        );
      }
      return;
    }
    await FirestoreService.instance.sendNotification(
      teamId: widget.teamId,
      recipientMemberIds: [member.id!],
      type: NotificationType.nudge,
      title: '🫵 Nudge! 🫵',
      body: '${currentMember?.displayName ?? 'A teammate'} nudged you to pick your leg before the deadline.',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nudge sent to ${member.displayName}.')));
    }
  }

  Future<void> _openSelection(Member member, AccumulatorLeg? existingLeg) async {
    final gameWeek = activeGameWeek;
    if (gameWeek?.id == null || member.id == null) return;
    if (existingLeg != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CurrentLegScreen(
            leg: existingLeg,
            gameWeekId: gameWeek!.id!,
            memberId: member.id!,
            teamId: widget.teamId,
            windowStart: gameWeek.startDate,
            windowEnd: gameWeek.endDate,
            allowedBetTypes: gameWeek.managerSpecialBetTypes,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubmitLegScreen(
            gameWeekId: gameWeek!.id!,
            memberId: member.id!,
            teamId: widget.teamId,
            windowStart: gameWeek.startDate,
            windowEnd: gameWeek.endDate,
            allowedBetTypes: gameWeek.managerSpecialBetTypes,
          ),
        ),
      );
    }
    load();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final userId = widget.appState.currentUser?.id;
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
      final loadedMembers = await FirestoreService.instance.fetchMembers(widget.teamId);
      final allLegs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      final fines = await FirestoreService.instance.fetchFines(widget.teamId);
      final physioSessions = await FirestoreService.instance.fetchPhysioSessions(widget.teamId);
      Member? me;
      if (userId != null) {
        try {
          me = loadedMembers.firstWhere((m) => m.userId == userId);
        } catch (_) {
          me = null;
        }
      }
      final challenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: team?.season ?? '');
      final seasonSettings = await FirestoreService.instance.fetchSeasonSettings(teamId: widget.teamId, season: team?.season ?? '');
      final maxChallenges = seasonSettings?.maxChallengesPerMember ?? 2;
      final myLosses = me?.id != null
          ? challenges.where((c) => c.challengerMemberId == me!.id && c.status == ChallengeStatus.resolved && c.challengerWon == false).length
          : 0;
      final remaining = (maxChallenges - myLosses).clamp(0, maxChallenges);
      final challengedThisWeek = me?.id != null && gameWeek?.id != null
          ? challenges.any((c) => c.challengerMemberId == me!.id && c.gameWeekId == gameWeek!.id)
          : false;
      final unreadCount = me?.id != null
          ? await FirestoreService.instance.fetchUnreadNotificationCount(teamId: widget.teamId, memberId: me!.id!)
          : 0;
      final currentSeasonGameWeeks = gameWeeks.where((g) => g.season == team?.season).toList();
      final currentSeasonGameWeekIds = currentSeasonGameWeeks.map((g) => g.id).toSet();
      final currentSeasonLegs = allLegs.where((l) => currentSeasonGameWeekIds.contains(l.gameWeekId)).toList();
      final table = ScoringEngine.buildLeagueTable(members: loadedMembers, legs: currentSeasonLegs, challenges: challenges);
      LeagueTableEntry? mine;
      int? offThird;
      if (me?.id != null) {
        try {
          mine = table.firstWhere((e) => e.memberId == me!.id);
          if (table.length >= 3) {
            offThird = table[2].totalBasePoints - mine.totalBasePoints;
          }
        } catch (_) {
          mine = null;
        }
      }
      final settledWeeks = currentSeasonGameWeeks.where((g) => !g.startDate.isAfter(DateTime.now())).toList()
        ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
      List<_MemberGameWeekPerformance> performance = [];
      List<Fine> activityFines = [];
      List<PhysioSession> activityPhysioSessions = [];
      List<Challenge> activityChallenges = [];
      if (settledWeeks.isNotEmpty) {
        final lastWeek = settledWeeks.last;
        final lastWeekLegs = allLegs.where((l) => l.gameWeekId == lastWeek.id).toList();
        final Map<String, int> baseByMember = {};
        final Map<String, double> weightedByMember = {};
        for (final leg in lastWeekLegs.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost)) {
          baseByMember[leg.memberId] = (baseByMember[leg.memberId] ?? 0) + leg.basePoints;
          weightedByMember[leg.memberId] = (weightedByMember[leg.memberId] ?? 0) + leg.weightedPoints;
        }
        final Map<String, int> positionDeltaByMember = {};
        if (settledWeeks.length >= 2) {
          final previousGameWeekIds = settledWeeks.where((g) => g.weekNumber < lastWeek.weekNumber).map((g) => g.id).toSet();
          final previousLegs = currentSeasonLegs.where((l) => previousGameWeekIds.contains(l.gameWeekId)).toList();
          final previousChallenges = challenges.where((c) => previousGameWeekIds.contains(c.gameWeekId)).toList();
          final previousEntries = ScoringEngine.buildLeagueTable(members: loadedMembers, legs: previousLegs, challenges: previousChallenges);
          final Map<String, int> previousPosition = {
            for (int i = 0; i < previousEntries.length; i++) previousEntries[i].memberId: i + 1,
          };
          final Map<String, int> currentPosition = {
            for (int i = 0; i < table.length; i++) table[i].memberId: i + 1,
          };
          for (final member in loadedMembers) {
            if (member.id == null) continue;
            final prevPos = previousPosition[member.id];
            final currPos = currentPosition[member.id];
            if (prevPos != null && currPos != null) {
              positionDeltaByMember[member.id!] = prevPos - currPos;
            }
          }
        }
        performance = [
          for (final member in loadedMembers)
            if (member.id != null)
              _MemberGameWeekPerformance(
                memberId: member.id!,
                displayName: member.displayName,
                basePoints: baseByMember[member.id!] ?? 0,
                weightedPoints: weightedByMember[member.id!] ?? 0,
                positionDelta: positionDeltaByMember[member.id!],
              ),
        ]..sort((a, b) => b.basePoints != a.basePoints ? b.basePoints.compareTo(a.basePoints) : b.weightedPoints.compareTo(a.weightedPoints));
        final windowStart = lastWeek.startDate;
        activityFines = fines.where((f) => f.createdAt.isAfter(windowStart)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        activityChallenges = challenges.where((c) => c.createdAt.isAfter(windowStart)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        activityPhysioSessions = physioSessions.where((p) => p.usedAt.isAfter(windowStart)).toList()
          ..sort((a, b) => b.usedAt.compareTo(a.usedAt));
      }
      final myFineCount = me?.id != null
          ? fines.where((f) => f.memberId == me!.id && f.countsTowardTally).length
          : 0;

      List<AccumulatorLeg> weekLegs = [];
      List<Reaction> weekReactions = [];
      Map<int, ApiFootballFixture> fixtureMap = {};
      List<NewsArticle> news = [];
      List<_NewsFeedEntry> newsFeed = [];

      if (gameWeek?.id != null) {
        weekLegs = allLegs.where((l) => l.gameWeekId == gameWeek!.id && !l.isSecondaryTournamentLeg).toList();
        weekReactions = await FirestoreService.instance.fetchReactionsForGameWeek(
          teamId: widget.teamId,
          gameWeekId: gameWeek!.id!,
        );

        final uniqueFixtureIds = weekLegs.map((l) => l.apiFootballFixtureId).whereType<int>().toSet();
        for (final fid in uniqueFixtureIds) {
          try {
            final f = await ApiFootballService.instance.fetchFixture(fid);
            if (f != null) fixtureMap[fid] = f;
          } catch (_) {
            // best-effort
          }
        }

        final isLocked = gameWeek.isLocked;
        final hasKickedOffNow = weekLegs.any((l) => !l.kickoff.isAfter(DateTime.now()));

        if (!isLocked) {
          try {
            news = await FirestoreService.instance.fetchLatestFootballNews();
          } catch (_) {
            // best-effort
          }
        } else if (hasKickedOffNow) {
          try {
            final rawEvents = await FirestoreService.instance.fetchLiveMatchEventsForFixtures(
              teamId: widget.teamId,
              apiFootballFixtureIds: uniqueFixtureIds.toList(),
            );
            for (final raw in rawEvents) {
              final type = raw['type'] as String? ?? '';
              final detail = raw['detail'] as String? ?? '';
              final teamName = raw['teamName'] as String? ?? '';
              final playerName = raw['playerName'] as String?;
              final ts = (raw['processedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now();
              String emoji;
              String text;
              switch (type) {
                case 'Goal':
                  emoji = '⚽';
                  text = '$emoji $teamName${playerName != null ? ' — $playerName' : ''} — $detail';
                  break;
                case 'Card':
                  emoji = detail.toLowerCase().contains('red') ? '🟥' : '🟨';
                  text = '$emoji $teamName${playerName != null ? ' — $playerName' : ''} — $detail';
                  break;
                case 'subst':
                  emoji = '🔄';
                  text = '$emoji $teamName — Substitution';
                  break;
                case 'HalfTime':
                  text = '⏸️ Half Time';
                  break;
                case 'FullTime':
                  text = '🏁 Full Time';
                  break;
                case 'Var':
                  text = '🚫 $teamName — Goal Disallowed';
                  break;
                default:
                  text = detail;
              }
              newsFeed.add(_NewsFeedEntry(timestamp: ts, text: text));
            }
            for (final leg in weekLegs) {
              if (leg.settledAt == null || leg.outcome == LegOutcome.pending) continue;
              final memberName = loadedMembers.firstWhereOrNull((m) => m.id == leg.memberId)?.displayName ?? 'Someone';
              final resultEmoji = leg.outcome == LegOutcome.won ? '✅' : '❌';
              newsFeed.add(_NewsFeedEntry(
                timestamp: leg.settledAt!,
                text: '$resultEmoji $memberName — ${leg.selectionDescription} ${leg.outcome == LegOutcome.won ? 'WON' : 'LOST'}',
              ));
            }
            newsFeed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          } catch (_) {
            // best-effort
          }
        }
      }

      if (mounted) {
        setState(() {
          activeGameWeek = gameWeek;
          hasActiveGameWeek = gameWeek != null;
          nextWeekNumber = gameWeek?.weekNumber;
          nextDeadline = gameWeek?.deadline;
          currentMember = me;
          members = loadedMembers;
          activeWeekLegs = weekLegs;
          weekFixtures = fixtureMap;
          latestNews = news;
          accaNewsFeed = newsFeed;
          activeWeekReactions = weekReactions;
          fullTable = table;
          myEntry = mine;
          pointsOffThird = offThird;
          lastGameweekPerformance = performance;
          myOutstandingFines = myFineCount;
          squadActivityFines = activityFines;
          squadActivityChallenges = activityChallenges;
          myChallengesRemaining = remaining;
          hasChallengedThisWeek = challengedThisWeek;
          unreadNotifications = unreadCount;
          squadActivityPhysioSessions = activityPhysioSessions;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/images/logo_horizontal.png', height: 32, fit: BoxFit.contain),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$unreadNotifications'),
              isLabelVisible: unreadNotifications > 0,
              child: Icon(Icons.notifications_outlined, color: unreadNotifications > 0 ? AccaColors.gold : Colors.white),
            ),
            onPressed: currentMember?.id == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NotificationsScreen(teamId: widget.teamId, memberId: currentMember!.id!, appState: widget.appState)),
                    );
                    load();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(appState: widget.appState, teamId: widget.teamId)),
            ),
          ),
        ],
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AccaColors.gold, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.black87, size: 18),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasActiveGameWeek ? 'Gameweek $nextWeekNumber' : 'No active gameweek',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                                ),
                                if (hasActiveGameWeek && nextDeadline != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Deadline: ${_formatDate(nextDeadline!)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _statusBox(),
                    ],
                  ),
                ),
    );
  }

  Widget _statusBox() {
    if (!hasActiveGameWeek) return _noActiveGameWeekSummary();
    final isLocked = activeGameWeek?.isLocked ?? false;
    if (!isLocked) return _selectionsBox();
    if (_hasKickedOff) return _inPlayBox();
    return _lockedNotStartedBox();
  }

  // ============================================================
  // STATE 2 — active gameweek, not locked.
  // Fixture summary tiles (no bet detail) + Outstanding/Confirmed
  // member lists + news feed.
  // ============================================================

  List<_FixtureSelectionSummary> get _fixtureSelectionSummaries {
    final byFixture = <String, List<AccumulatorLeg>>{};
    for (final leg in activeWeekLegs) {
      final key = (leg.apiFootballFixtureId ?? leg.fixtureDescription).toString();
      byFixture.putIfAbsent(key, () => []).add(leg);
    }
    final summaries = <_FixtureSelectionSummary>[];
    for (final entry in byFixture.entries) {
      final legs = entry.value;
      final rep = legs.first;
      final fixture = rep.apiFootballFixtureId != null ? weekFixtures[rep.apiFootballFixtureId] : null;
      final parts = rep.fixtureDescription.split(' vs ');
      final memberIds = legs.map((l) => l.memberId).toSet();
      final selectedByMembers = members.where((m) => memberIds.contains(m.id)).toList();
      summaries.add(_FixtureSelectionSummary(
        fixtureId: rep.apiFootballFixtureId,
        homeName: fixture?.homeTeam ?? (parts.isNotEmpty ? parts.first : rep.fixtureDescription),
        awayName: fixture?.awayTeam ?? (parts.length > 1 ? parts[1] : ''),
        homeLogo: fixture?.homeLogo ?? '',
        awayLogo: fixture?.awayLogo ?? '',
        isLive: fixture?.isLive ?? false,
        kickoff: fixture?.kickoff ?? rep.kickoff,
        selectedBy: selectedByMembers,
      ));
    }
    summaries.sort((a, b) => (a.kickoff ?? DateTime(2100)).compareTo(b.kickoff ?? DateTime(2100)));
    return summaries;
  }

  Widget _selectionsBox() {
    final eligibleMembers = members.where((m) => m.id != null).toList();
    final submittedCount = activeWeekLegs.map((l) => l.memberId).toSet().length;
    final outstanding = eligibleMembers.where((m) => !activeWeekLegs.any((l) => l.memberId == m.id)).toList();
    final confirmed = eligibleMembers.where((m) => activeWeekLegs.any((l) => l.memberId == m.id)).toList();
    final deadline = activeGameWeek?.deadline;
    final within24h = deadline != null && deadline.isAfter(DateTime.now()) && deadline.difference(DateTime.now()).inHours <= 24;
    final summaries = _fixtureSelectionSummaries;

    return Column(
      children: [
        _yourAccaCard(submittedCount, eligibleMembers.length),
        const SizedBox(height: 16),
        for (final summary in summaries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _fixtureSummaryTile(summary, eligibleMembers.length),
          ),
        if (summaries.isNotEmpty) const SizedBox(height: 8),
        if (outstanding.isNotEmpty) ...[
          _sectionHeader('OUTSTANDING'),
          const SizedBox(height: 8),
          for (final member in outstanding)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _memberStatusRow(member, null, within24h),
            ),
          const SizedBox(height: 12),
        ],
        if (confirmed.isNotEmpty) ...[
          _sectionHeader('SELECTION CONFIRMED'),
          const SizedBox(height: 8),
          for (final member in confirmed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _memberStatusRow(member, activeWeekLegs.firstWhereOrNull((l) => l.memberId == member.id), within24h),
            ),
        ],
        if (latestNews.isNotEmpty) ...[
          const SizedBox(height: 8),
          NewsFeedWidget(articles: latestNews),
        ],
      ],
    );
  }

  Widget _yourAccaCard(int submittedCount, int totalMembers) {
    final progress = totalMembers == 0 ? 0.0 : (submittedCount / totalMembers).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: AccaColors.gold, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Acca', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                const SizedBox(height: 2),
                Text('$submittedCount / $totalMembers legs selected', style: const TextStyle(color: AccaColors.win, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.black12,
                    valueColor: const AlwaysStoppedAnimation(AccaColors.win),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.black26),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  /// Pre-lock fixture tile — crests, fixture info, "X/Y selected" count,
  /// and a row of chips naming who's picked this game. Deliberately
  /// carries NO bet detail.
  Widget _fixtureSummaryTile(_FixtureSelectionSummary summary, int totalMembers) {
    return GestureDetector(
      onTap: () => _showSelectedByDialog(summary),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AccaColors.gold, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FixtureHeaderCard(
              fixtureId: summary.fixtureId ?? '${summary.homeName}${summary.awayName}'.hashCode,
              homeLogo: summary.homeLogo,
              awayLogo: summary.awayLogo,
              homeName: summary.homeName,
              awayName: summary.awayName,
              isLive: summary.isLive,
              centerContent: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AccaColors.win.withValues(alpha: 0.2), border: Border.all(color: AccaColors.win), borderRadius: BorderRadius.circular(20)),
                child: Text('${summary.selectedBy.length}/$totalMembers selected', style: const TextStyle(color: AccaColors.win, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            FixtureCardFooter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final m in summary.selectedBy)
                            Chip(
                              label: Text(m.displayName, style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AccaColors.surface,
                              labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSelectedByDialog(_FixtureSelectionSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${summary.homeName} vs ${summary.awayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: summary.selectedBy.map((m) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(m.displayName, style: const TextStyle(fontSize: 15)),
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  /// One row in the Outstanding/Confirmed lists — name, and either a
  /// Make Selection / Revise Selection button (self) or a Nudge button
  /// (outstanding teammate), plus kudos reactions once confirmed.
  Widget _memberStatusRow(Member member, AccumulatorLeg? leg, bool within24hOfDeadline) {
    final isSelf = member.id == currentMember?.id;
    final isConfirmed = leg != null;
    final legReactions = leg != null ? activeWeekReactions.where((r) => r.legId == leg.id).toList() : <Reaction>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AccaColors.gold, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isConfirmed ? Icons.check_circle : Icons.hourglass_empty, color: isConfirmed ? AccaColors.win : Colors.black38, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(member.displayName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600))),
              if (isSelf)
                ElevatedButton(
                  onPressed: () => _openSelection(member, leg),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConfirmed ? Colors.orange : AccaColors.win,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Text(isConfirmed ? 'Revise Selection' : 'Make Selection', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                )
              else if (!isConfirmed && within24hOfDeadline)
                OutlinedButton(
                  onPressed: () => nudge(member),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: AccaColors.gold), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                  child: const Text('Nudge', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (isConfirmed) ...[
            const SizedBox(height: 8),
            Row(children: [for (final emoji in const ['👍', '❤️', '😂']) ...[_emojiChip(leg, emoji, legReactions, isOwnLeg: isSelf), const SizedBox(width: 6)]]),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // STATE 3 — locked, nothing kicked off.
  // ============================================================
  Widget _lockedNotStartedBox() {
    final groups = _postLockGroups();
    return Column(
      children: [
        if (activeGameWeek?.combinedOdds != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                children: [
                  const TextSpan(text: 'Accumulator odds: '),
                  TextSpan(text: combinedOddsToFractional(activeGameWeek!.combinedOdds!), style: const TextStyle(color: AccaColors.win)),
                ],
              ),
            ),
          ),
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _groupedSelectionCard(group),
          ),
      ],
    );
  }

  // ============================================================
  // STATE 4 — locked, in play.
  // ============================================================
  Widget _inPlayBox() {
    final groups = _postLockGroups();
    return Column(
      children: [
        if (accaNewsFeed.isNotEmpty) ...[
          _accaNewsFeedCard(),
          const SizedBox(height: 16),
        ],
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _groupedSelectionCard(group),
          ),
      ],
    );
  }

  /// Groups this gameweek's legs by (fixture, bet type) for the card
  /// container, per the explicit "grouped where bet type and fixture
  /// match" instruction — actual distinct selections within a group are
  /// rendered as separate labelled rows via group.bySelection, so two
  /// different picks of the same bet type (e.g. Over 1.5 vs Over 2.5)
  /// are never shown as if they were identical.
  List<_FixtureBetTypeGroup> _postLockGroups() {
    final byKey = <String, List<AccumulatorLeg>>{};
    for (final leg in activeWeekLegs) {
      final key = '${leg.apiFootballFixtureId ?? leg.fixtureDescription}_${leg.betType}';
      byKey.putIfAbsent(key, () => []).add(leg);
    }
    final groups = <_FixtureBetTypeGroup>[];
    for (final legs in byKey.values) {
      final rep = legs.first;
      final fixture = rep.apiFootballFixtureId != null ? weekFixtures[rep.apiFootballFixtureId] : null;
      final parts = rep.fixtureDescription.split(' vs ');
      groups.add(_FixtureBetTypeGroup(
        fixtureId: rep.apiFootballFixtureId,
        fixtureDescription: rep.fixtureDescription,
        homeName: fixture?.homeTeam ?? (parts.isNotEmpty ? parts.first : rep.fixtureDescription),
        awayName: fixture?.awayTeam ?? (parts.length > 1 ? parts[1] : ''),
        homeLogo: fixture?.homeLogo ?? '',
        awayLogo: fixture?.awayLogo ?? '',
        isLive: fixture?.isLive ?? false,
        fixture: fixture,
        legs: legs,
      ));
    }
    groups.sort((a, b) => (a.legs.first.kickoff).compareTo(b.legs.first.kickoff));
    return groups;
  }

  Widget _groupedSelectionCard(_FixtureBetTypeGroup group) {
    final bySelection = group.bySelection;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AccaColors.gold, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FixtureHeaderCard(
            fixtureId: group.fixtureId ?? group.fixtureDescription.hashCode,
            homeLogo: group.homeLogo,
            awayLogo: group.awayLogo,
            homeName: group.homeName,
            awayName: group.awayName,
            isLive: group.isLive,
            centerContent: group.fixture != null
                ? Text(group.fixture!.statusLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))
                : const Text('vs', style: TextStyle(color: Colors.white70)),
          ),
          FixtureCardFooter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in bySelection.entries) ...[
                  _selectionRow(entry.key, entry.value),
                  if (entry.key != bySelection.keys.last) const Divider(height: 1, color: Colors.black12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionRow(String selectionDescription, List<AccumulatorLeg> legs) {
    final rep = legs.first;
    final challengeableLegs = legs.where((l) =>
        l.memberId != currentMember?.id &&
        DateTime.now().isBefore(l.kickoff) &&
        myChallengesRemaining > 0 &&
        !hasChallengedThisWeek).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selectionDescription, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ScoutConfidenceBadge(leg: rep),
                    ScoutProbabilityBadge(leg: rep),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final leg in legs) _selectionMemberChip(leg)],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
                child: Text(decimalToFractional(rep.decimalOddsAtSelection), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
              ),
              if (challengeableLegs.isNotEmpty) const SizedBox(height: 10),
              for (final leg in challengeableLegs) ...[
                _bigChallengeButton(leg),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigChallengeButton(AccumulatorLeg leg) {
    final displayName = members.firstWhereOrNull((m) => m.id == leg.memberId)?.displayName ?? 'Unknown';
    return ElevatedButton(
      onPressed: () async {
        final myLeg = activeWeekLegs.where((l) => l.memberId == currentMember?.id).firstOrNull;
        final placed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PlaceChallengeScreen(
              teamId: widget.teamId,
              season: activeGameWeek?.season ?? '',
              gameWeek: activeGameWeek!,
              challengedLeg: leg,
              challengedMemberName: displayName,
              challenger: currentMember!,
              challengerLeg: myLeg,
              challengesRemaining: myChallengesRemaining,
              alreadyChallengedThisWeek: hasChallengedThisWeek,
            ),
          ),
        );
        if (placed == true) load();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AccaColors.win,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: const Text('Challenge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _selectionMemberChip(AccumulatorLeg leg) {
    final member = members.firstWhereOrNull((m) => m.id == leg.memberId);
    final displayName = member?.displayName ?? 'Unknown';
    final isSelf = leg.memberId == currentMember?.id;
    final legReactions = leg.id != null ? activeWeekReactions.where((r) => r.legId == leg.id).toList() : <Reaction>[];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: AccaColors.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          for (final emoji in const ['👍', '❤️', '😂']) ...[
            _emojiChip(leg, emoji, legReactions, isOwnLeg: isSelf),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }

  Widget _accaNewsFeedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A24), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.rss_feed, color: AccaColors.gold, size: 18),
              SizedBox(width: 6),
              Text('ACCA NEWS FEED', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in accaNewsFeed.take(15))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(entry.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  void _showReactors(BuildContext context, String emoji, List<Reaction> legReactions) {
    final reactors = legReactions.where((r) => r.emoji == emoji).map((r) => r.reactorName).toList();
    if (reactors.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$emoji Reactions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reactors.map((name) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(name, style: const TextStyle(fontSize: 15)),
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _react(AccumulatorLeg? leg, String emoji) async {
    if (currentMember?.id == null || leg?.id == null) return;
    await FirestoreService.instance.toggleReaction(
      teamId: widget.teamId,
      legId: leg!.id!,
      gameWeekId: leg.gameWeekId,
      reactorMemberId: currentMember!.id!,
      reactorName: currentMember!.displayName,
      recipientMemberId: leg.memberId,
      emoji: emoji,
    );
    load();
  }

  Widget _emojiChip(AccumulatorLeg? leg, String emoji, List<Reaction> legReactions, {bool isOwnLeg = false}) {
    final count = legReactions.where((r) => r.emoji == emoji).length;
    final myReaction = legReactions.any(
      (r) => r.emoji == emoji && r.reactorMemberId == currentMember?.id,
    );
    return GestureDetector(
      onTap: () {
        if (isOwnLeg) {
          _showReactors(context, emoji, legReactions);
        } else {
          _react(leg, emoji);
        }
      },
      onLongPress: () => _showReactors(context, emoji, legReactions),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: myReaction ? AccaColors.gold.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: myReaction ? AccaColors.gold : Colors.black26,
            width: myReaction ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text('$count', style: const TextStyle(fontSize: 10, color: Colors.black87)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lastGameweekRow(_MemberGameWeekPerformance p) {
    Widget deltaWidget;
    if (p.positionDelta == null || p.positionDelta == 0) {
      deltaWidget = const Text('—', style: TextStyle(fontSize: 12, color: Colors.black54));
    } else if (p.positionDelta! > 0) {
      deltaWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward, size: 13, color: AccaColors.win),
          Text(' ${p.positionDelta}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AccaColors.win)),
        ],
      );
    } else {
      deltaWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward, size: 13, color: AccaColors.loss),
          Text(' ${p.positionDelta!.abs()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AccaColors.loss)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(p.displayName, style: const TextStyle(color: Colors.black))),
          Text('${p.basePoints} pts', style: const TextStyle(color: Colors.black87, fontSize: 13)),
          const SizedBox(width: 10),
          deltaWidget,
        ],
      ),
    );
  }

  List<Widget> _squadActivityContent() {
    final upShifts = biggestPositionShiftsUp;
    final downShifts = biggestPositionShiftsDown;
    if (squadActivityFines.isEmpty && squadActivityChallenges.isEmpty && squadActivityPhysioSessions.isEmpty && upShifts.isEmpty && downShifts.isEmpty) {
      return [const Text('Nothing recent.', style: TextStyle(color: Colors.black87))];
    }
    return [
      for (final fine in squadActivityFines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${fine.memberName} fined — ${fine.fineType.displayName}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      for (final challenge in squadActivityChallenges)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${challenge.challengerName} challenged ${challenge.challengedName}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      for (final session in squadActivityPhysioSessions)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${session.memberName} booked a physio session — points protected', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      for (final shift in upShifts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${shift.displayName} climbed ${shift.positionDelta} places', style: const TextStyle(fontSize: 12, color: AccaColors.win)),
        ),
      for (final shift in downShifts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${shift.displayName} dropped ${shift.positionDelta!.abs()} places', style: const TextStyle(fontSize: 12, color: AccaColors.loss)),
        ),
    ];
  }

  Widget _noActiveGameWeekSummary() {
    final top3 = fullTable.take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [Icon(Icons.emoji_events, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Title Race', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          if (top3.isEmpty)
            const Text('No data yet.', style: TextStyle(color: Colors.black87))
          else
            for (int i = 0; i < top3.length; i++)
              Text('${i + 1}. ${top3[i].displayName} — ${top3[i].totalBasePoints} pts', style: const TextStyle(color: Colors.black)),
          if (myEntry != null && pointsOffThird != null) ...[
            const SizedBox(height: 6),
            Text(
              pointsOffThird! > 0
                  ? 'You are $pointsOffThird points off 3rd place.'
                  : pointsOffThird! < 0
                      ? 'You are ${pointsOffThird!.abs()} points clear of 3rd place.'
                      : 'You\'re level with 3rd place.',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
            ),
          ],
          const Divider(height: 28),
          Row(children: const [Icon(Icons.bar_chart, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Last Gameweek', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          if (lastGameweekPerformance.isEmpty)
            const Text('No settled gameweeks yet.', style: TextStyle(color: Colors.black87))
          else
            for (final p in lastGameweekPerformance) _lastGameweekRow(p),
          const Divider(height: 28),
          Row(children: const [Icon(Icons.gavel, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Your Fines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          Text('$myOutstandingFines outstanding fine${myOutstandingFines == 1 ? '' : 's'}.', style: const TextStyle(color: Colors.black)),
          const Divider(height: 28),
          Row(children: const [Icon(Icons.campaign, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Squad Activity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          ..._squadActivityContent(),
        ],
      ),
    );
  }
}