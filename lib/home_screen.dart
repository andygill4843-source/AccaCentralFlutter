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

  Member? currentMember;
  List<Member> members = [];
  List<AccumulatorLeg> activeWeekLegs = [];
  List<LeagueTableEntry> fullTable = [];
  LeagueTableEntry? myEntry;
  int? pointsOffThird;
  ({String name, double weightedPoints})? previousWeekTopScorer;
  int myOutstandingFines = 0;
  List<Fine> recentFines = [];
  int myChallengesRemaining = 2;
  int unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    load();
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

      Member? me;
      if (userId != null) {
        try {
          me = loadedMembers.firstWhere((m) => m.userId == userId);
        } catch (_) {
          me = null;
        }
      }

      final challenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: team?.season ?? '');
      final myLosses = me?.id != null
          ? challenges.where((c) => c.challengerMemberId == me!.id && c.status == ChallengeStatus.resolved && c.challengerWon == false).length
          : 0;
      final remaining = (2 - myLosses).clamp(0, 2);

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
      final settledWeeks = currentSeasonGameWeeks.where((g) => g.isSettled).toList()
        ..sort((a, b) => b.weekNumber.compareTo(a.weekNumber));
      ({String name, double weightedPoints})? topScorer;
      if (settledWeeks.isNotEmpty) {
        final lastWeek = settledWeeks.first;
        final lastWeekLegs = allLegs.where((l) => l.gameWeekId == lastWeek.id).toList();
        final Map<String, double> pointsByMember = {};
        for (final leg in lastWeekLegs.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost)) {
          pointsByMember[leg.memberId] = (pointsByMember[leg.memberId] ?? 0) + leg.weightedPoints;
        }
        if (pointsByMember.isNotEmpty) {
          final topEntry = pointsByMember.entries.reduce((a, b) => a.value > b.value ? a : b);
          final name = loadedMembers.firstWhere((m) => m.id == topEntry.key, orElse: () => Member(userId: '', displayName: 'Unknown', teamId: widget.teamId, joinedAt: DateTime.now())).displayName;
          topScorer = (name: name, weightedPoints: topEntry.value);
        }
      }

      final myFineCount = me?.id != null
          ? fines.where((f) => f.memberId == me!.id && f.countsTowardTally).length
          : 0;

      final recent = fines.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
          previousWeekTopScorer = topScorer;
          myOutstandingFines = myFineCount;
          recentFines = recent.take(5).toList();
          myChallengesRemaining = remaining;
          unreadNotifications = unreadCount;
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
                  SizedBox(
                    width: 78,
                    child: ElevatedButton(
                      onPressed: (currentMember?.id == leg.memberId || myChallengesRemaining <= 0)
                        ? null // can't challenge your own leg
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

  // State 3: no active gameweek — team summary.
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
          Text(
            previousWeekTopScorer != null
                ? '${previousWeekTopScorer!.name} top-scored with ${previousWeekTopScorer!.weightedPoints.toStringAsFixed(1)} weighted points.'
                : 'No settled gameweeks yet.',
            style: const TextStyle(color: Colors.black),
          ),
          const Divider(height: 28),
          Row(children: const [Icon(Icons.gavel, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Your Fines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          Text('$myOutstandingFines outstanding fine${myOutstandingFines == 1 ? '' : 's'}.', style: const TextStyle(color: Colors.black)),
          const Divider(height: 28),
          Row(children: const [Icon(Icons.campaign, color: AccaColors.primary, size: 18), SizedBox(width: 6), Text('Squad Activity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black))]),
          const SizedBox(height: 8),
          if (recentFines.isEmpty)
            const Text('Nothing recent.', style: TextStyle(color: Colors.black87))
          else
            for (final fine in recentFines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('${fine.memberName} fined — ${fine.fineType.displayName}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ),
        ],
      ),
    );
  }
}