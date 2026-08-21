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
import 'submission_gauge.dart';


class _MemberGameWeekPerformance {
  final String memberId;
  final String displayName;
  final int basePoints;
  final double weightedPoints;
  final int? positionDelta; // positive = climbed, negative = dropped, null = no prior data to compare
  _MemberGameWeekPerformance({
    required this.memberId,
    required this.displayName,
    required this.basePoints,
    required this.weightedPoints,
    this.positionDelta,
  });
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

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.refreshToken != widget.refreshToken) {
      load();
    }
  }

  Future<void> nudge(Member member) async {
    if (member.id == null) return;
    await FirestoreService.instance.sendNotification(
      teamId: widget.teamId,
      recipientMemberIds: [member.id!],
      type: NotificationType.nudge,
      title: 'Nudge!',
      body: '${currentMember?.displayName ?? 'A teammate'} nudged you to pick your leg before the deadline.',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nudge sent to ${member.displayName}.')));
    }
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
            offThird = table[2].totalBasePoints - mine.totalBasePoints; // positive = behind, negative = clear
          }
        } catch (_) {
          mine = null;
        }
      }

      // Biggest weighted-points winner from the most recently SETTLED gameweek.
            // Per-member points + position swing from the most recently SETTLED gameweek,
      // and everything (fines/challenges) that's happened since it started.
      final settledWeeks = currentSeasonGameWeeks.where((g) => g.isSettled).toList()
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
          final previousEntries = ScoringEngine.buildLeagueTable(members: loadedMembers, legs: previousLegs, challenges: challenges);
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
      if (gameWeek?.id != null) {
        weekLegs = allLegs.where((l) => l.gameWeekId == gameWeek!.id).toList();
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
                      MaterialPageRoute(builder: (_) => NotificationsScreen(teamId: widget.teamId, memberId: currentMember!.id!)),
                    );
                    load(); // refresh count after viewing
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
                        child: Text(
                          hasActiveGameWeek
                              ? 'Gameweek $nextWeekNumber — deadline ${nextDeadline != null ? _formatDate(nextDeadline!) : '—'}'
                              : 'No active gameweek',
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.black),
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
    if (hasActiveGameWeek && !(activeGameWeek?.isLocked ?? false)) return _submissionStatusBox();
    if (hasActiveGameWeek && (activeGameWeek?.isLocked ?? false)) return _lockedLegsBox();
    return _noActiveGameWeekSummary();
  }

    // State 1: active gameweek, not yet locked — who's picked, who hasn't.
  Widget _submissionStatusBox() {
    final deadline = activeGameWeek?.deadline;
    final within24h = deadline != null && deadline.isAfter(DateTime.now()) && deadline.difference(DateTime.now()).inHours <= 24;
    final eligibleMembers = members.where((m) => m.id != null).toList();
    final submittedCount = activeWeekLegs.map((l) => l.memberId).toSet().length;
    return Column(
      children: [
        SubmissionGauge(submittedCount: submittedCount, totalMembers: eligibleMembers.length),
        const SizedBox(height: 16),
        Container(
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
              Row(
                children: const [
                  Icon(Icons.fact_check, color: AccaColors.primary, size: 18),
                  SizedBox(width: 6),
                  Text('Acca Selection Inspection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                ],
              ),
              const SizedBox(height: 12),
              for (final member in members)
                if (member.id != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.sports_soccer, size: 16, color: AccaColors.gold),
                        const SizedBox(width: 8),
                        Expanded(child: Text(member.displayName, style: const TextStyle(color: Colors.black))),
                        if (within24h && !activeWeekLegs.any((l) => l.memberId == member.id))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: OutlinedButton(
                              onPressed: () => nudge(member),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: AccaColors.gold),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Nudge', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        Icon(
                          activeWeekLegs.any((l) => l.memberId == member.id) ? Icons.check_circle : Icons.cancel,
                          color: activeWeekLegs.any((l) => l.memberId == member.id) ? AccaColors.win : AccaColors.loss,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  // State 2: active gameweek, locked — everyone's actual pick + Challenge stub.
  Widget _lockedLegsBox() {
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
          Row(
            children: const [
              Icon(Icons.list_alt, color: AccaColors.primary, size: 18),
              SizedBox(width: 6),
              Text("This Gameweek's Legs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
            ],
          ),
          if (activeGameWeek?.combinedOdds != null) ...[
            const SizedBox(height: 8),
            Text(
              'Accumulator odds: ${decimalToFractional(activeGameWeek!.combinedOdds!)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
            ),
          ],
          const SizedBox(height: 12),
          for (final leg in activeWeekLegs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.sports_soccer, size: 16, color: AccaColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          members.firstWhere((m) => m.id == leg.memberId, orElse: () => Member(userId: '', displayName: 'Unknown', teamId: widget.teamId, joinedAt: DateTime.now())).displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
                        ),
                        Text(leg.selectionDescription, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
                    child: Text(decimalToFractional(leg.decimalOddsAtSelection), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                  if (DateTime.now().isBefore(leg.kickoff))
                  SizedBox(                  
                    width: 78,
                    child: ElevatedButton(
                      onPressed: (currentMember?.id == leg.memberId || myChallengesRemaining <= 0 || hasChallengedThisWeek)
                        ? null
                        : () async {
                            final myLeg = activeWeekLegs.where((l) => l.memberId == currentMember?.id).firstOrNull;
                            final challengedName = members
                                .firstWhere((m) => m.id == leg.memberId, orElse: () => Member(userId: '', displayName: 'Unknown', teamId: widget.teamId, joinedAt: DateTime.now()))
                                .displayName;
                            final placed = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => PlaceChallengeScreen(
                                  teamId: widget.teamId,
                                  season: activeGameWeek?.season ?? '',
                                  gameWeek: activeGameWeek!,
                                  challengedLeg: leg,
                                  challengedMemberName: challengedName,
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
                        backgroundColor: AccaColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      ),
                      child: const Text('Challenge', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
  // State 5: no active gameweek — team summary.
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