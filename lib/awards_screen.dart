import 'package:flutter/material.dart';
import 'app_state.dart';
import 'awards_engine.dart';
import 'firestore_service.dart';
import 'main.dart'; // for AccaColors, accaFieldTextStyle
import 'profile_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notifications_screen.dart';
import 'models.dart';

class AwardsScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  const AwardsScreen({super.key, required this.appState, required this.teamId});
  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

class _AwardsScreenState extends State<AwardsScreen> {
  // Raw data, fetched once — season filtering happens locally, no refetch.
  List<Member> rawMembers = [];
  List<AccumulatorLeg> rawLegs = [];
  List<GameWeek> rawGameWeeks = [];
  List<Fine> rawFines = [];
  List<SeasonWinner> rawSeasonWinners = [];
  String? teamCurrentSeason;

  List<String> allSeasons = [];
  String? selectedSeason;
  Set<Achievement> unlocked = {};

  bool isLoading = true;
  String? errorMessage;
  Member? currentMember;
  bool get isManager => currentMember?.role == MemberRole.manager;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant AwardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      load();
    }
  }

  Future<void> load() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      if (member == null || member.id == null) {
        setState(() {
          errorMessage = 'No member profile found.';
          isLoading = false;
        });
        return;
      }
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      final fines = await FirestoreService.instance.fetchFines(widget.teamId);
      final seasonWinners = await FirestoreService.instance.fetchSeasonWinners(widget.teamId);

      rawMembers = members;
      rawLegs = legs;
      rawGameWeeks = gameWeeks;
      rawFines = fines;
      rawSeasonWinners = seasonWinners;
      teamCurrentSeason = team?.season;
      selectedSeason ??= teamCurrentSeason;
      currentMember = member;

      recompute();
      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  void recompute() {
    final seasonsFromGameWeeks = rawGameWeeks.map((g) => g.season).toSet();
    final seasonsFromWinners = rawSeasonWinners.map((w) => w.season).toSet();
    final combined = <String>{
      ...seasonsFromGameWeeks,
      ...seasonsFromWinners,
      if (teamCurrentSeason != null) teamCurrentSeason!,
    }..removeWhere((s) => s.isEmpty);
    allSeasons = combined.toList()..sort((a, b) => b.compareTo(a));

    final season = selectedSeason;
    final seasonGameWeekIds = rawGameWeeks.where((g) => g.season == season).map((g) => g.id).toSet();
    final seasonLegs = rawLegs.where((l) => seasonGameWeekIds.contains(l.gameWeekId)).toList();
    final seasonGameWeeksList = rawGameWeeks.where((g) => g.season == season).toList();
    final seasonFines = rawFines.where((f) => f.season == season).toList();
    final winnerMatch = rawSeasonWinners.where((w) => w.season == season);
    final seasonChampionMemberId = winnerMatch.isNotEmpty ? winnerMatch.first.winnerMemberId : null;

    if (currentMember?.id != null) {
      unlocked = AwardsEngine.evaluate(
        memberId: currentMember!.id!,
        members: rawMembers,
        seasonLegs: seasonLegs,
        seasonGameWeeks: seasonGameWeeksList,
        seasonFines: seasonFines,
        seasonChampionMemberId: seasonChampionMemberId,
      );
    }
  }

  void onSeasonChanged(String? newSeason) {
    if (newSeason == null) return;
    setState(() {
      selectedSeason = newSeason;
      recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: 'Awa', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              TextSpan(text: 'rds', style: GoogleFonts.poppins(color: AccaColors.gold, fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: currentMember?.id == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NotificationsScreen(teamId: widget.teamId, memberId: currentMember!.id!)),
                    ),
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
                      if (allSeasons.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Season', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSeason,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                            ),
                          ),
                          dropdownColor: Colors.white,
                          style: accaFieldTextStyle,
                          items: allSeasons
                              .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.black))))
                              .toList(),
                          onChanged: onSeasonChanged,
                        ),
                        const SizedBox(height: 16),
                      ],
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.85,
                        children: [
                          for (final achievement in Achievement.values) _achievementCard(achievement),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _achievementCard(Achievement achievement) {
    final isUnlocked = unlocked.contains(achievement);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnlocked ? AccaColors.gold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isUnlocked ? AccaColors.gold : Colors.transparent),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(achievement.emoji, style: TextStyle(fontSize: 32, color: isUnlocked ? null : Colors.grey)),
          const SizedBox(height: 8),
          Text(
            achievement.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isUnlocked ? AccaColors.textPrimary : AccaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AccaColors.textSecondary),
          ),
        ],
      ),
    );
  }
}