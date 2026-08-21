import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'profile_screen.dart';
import 'notifications_screen.dart';

enum FitnessStatus { inForm, fullyFit, minorKnock, majorSurgery, fitToPick }

extension FitnessStatusInfo on FitnessStatus {
  String get label {
    switch (this) {
      case FitnessStatus.inForm: return 'In Form';
      case FitnessStatus.fullyFit: return 'Fully Fit';
      case FitnessStatus.minorKnock: return 'Minor Knock';
      case FitnessStatus.majorSurgery: return 'Major Surgery';
      case FitnessStatus.fitToPick: return 'Fit To Pick';
    }
  }

  IconData get icon {
    switch (this) {
      case FitnessStatus.inForm: return Icons.emoji_events; // crown-style
      case FitnessStatus.fullyFit: return Icons.star;
      case FitnessStatus.minorKnock: return Icons.arrow_downward;
      case FitnessStatus.majorSurgery: return Icons.sick;
      case FitnessStatus.fitToPick: return Icons.check_circle;
    }
  }

  Color get color {
    switch (this) {
      case FitnessStatus.inForm: return AccaColors.gold;
      case FitnessStatus.fullyFit: return AccaColors.win;
      case FitnessStatus.minorKnock: return Colors.orange;
      case FitnessStatus.majorSurgery: return AccaColors.loss;
      case FitnessStatus.fitToPick: return AccaColors.textSecondary;
    }
  }
}

FitnessStatus classifyFitness(int currentStreak) {
  if (currentStreak >= 4) return FitnessStatus.inForm;
  if (currentStreak >= 2) return FitnessStatus.fullyFit;
  if (currentStreak <= -4) return FitnessStatus.majorSurgery;
  if (currentStreak <= -2) return FitnessStatus.minorKnock;
  return FitnessStatus.fitToPick;
}

class PhysioScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final int refreshToken;
  const PhysioScreen({super.key, required this.appState, required this.teamId, this.refreshToken = 0});
  @override
  State<PhysioScreen> createState() => _PhysioScreenState();
}

class _PhysioScreenState extends State<PhysioScreen> {
  List<LeagueTableEntry> entries = [];
  GameWeek? activeGameWeek;
  Member? currentMember;
  int sessionsUsed = 0;
  int unreadNotifications = 0;
  bool isLoading = true;
  bool isBooking = false;
  String? errorMessage;
  int maxPhysioSessions = 2;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant PhysioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.refreshToken != widget.refreshToken) {
      load();
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
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      final challenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: team?.season ?? '');
      Member? me;
      if (userId != null) {
        me = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      }
      final unreadCount = me?.id != null
          ? await FirestoreService.instance.fetchUnreadNotificationCount(teamId: widget.teamId, memberId: me!.id!)
          : 0;
      final currentSeasonGameWeeks = gameWeeks.where((g) => g.season == team?.season).toList();
      final currentSeasonGameWeekIds = currentSeasonGameWeeks.map((g) => g.id).toSet();
      final currentSeasonLegs = legs.where((l) => currentSeasonGameWeekIds.contains(l.gameWeekId)).toList();
      final table = ScoringEngine.buildLeagueTable(members: members, legs: currentSeasonLegs, challenges: challenges);
      final active = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
      final seasonSettings = await FirestoreService.instance.fetchSeasonSettings(teamId: widget.teamId, season: team?.season ?? '');
      final maxSessions = seasonSettings?.maxPhysioSessionsPerMember ?? 2;
      int used = 0;
      if (me?.id != null) {
        used = await FirestoreService.instance.fetchPhysioSessionsUsed(
          teamId: widget.teamId,
          memberId: me!.id!,
          season: team?.season ?? '',
        );
      }
      setState(() {
        entries = table;
        activeGameWeek = active;
        currentMember = me;
        sessionsUsed = used;
        maxPhysioSessions = maxSessions;
        unreadNotifications = unreadCount;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> bookSession() async {
    if (currentMember?.id == null || activeGameWeek?.id == null) return;
    setState(() {
      isBooking = true;
      errorMessage = null;
    });
    try {
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      await FirestoreService.instance.bookPhysioSession(
        teamId: widget.teamId,
        memberId: currentMember!.id!,
        memberName: currentMember!.displayName,
        season: team?.season ?? '',
        gameWeek: activeGameWeek!,
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Physio session booked — your points are protected this week.')),
        );
      }
    } catch (e) {
      setState(() => errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsRemaining = maxPhysioSessions - sessionsUsed;
    final canBook = currentMember?.id != null &&
        activeGameWeek?.id != null &&
        !(activeGameWeek?.isLocked ?? true) &&
        sessionsRemaining > 0;

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: 'Phy', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              TextSpan(text: 'sio', style: GoogleFonts.poppins(color: AccaColors.gold, fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
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
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
                        const Text('Fitness Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                        const SizedBox(height: 12),
                        if (entries.isEmpty)
                          const Text('No data yet.', style: TextStyle(color: Colors.black87))
                        else
                          for (final e in entries) _fitnessRow(e),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (errorMessage != null) ...[
                    Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton(
                    onPressed: (canBook && !isBooking) ? bookSession : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AccaColors.gold,
                      foregroundColor: AccaColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: isBooking
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Book Physio Session ($sessionsRemaining left)'),
                  ),
                  if (activeGameWeek == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No open gameweek right now.', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    )
                  else if (activeGameWeek!.isLocked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('This gameweek is locked — sessions can only be booked before the odds are selected.', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _fitnessRow(LeagueTableEntry e) {
    final status = classifyFitness(e.currentStreak);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(status.icon, size: 18, color: status.color),
          const SizedBox(width: 8),
          Expanded(child: Text(e.displayName, style: const TextStyle(color: Colors.black))),
          Text(status.label, style: TextStyle(color: status.color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
