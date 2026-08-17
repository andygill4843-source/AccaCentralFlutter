import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'gameweek_setup_screen.dart';
import 'submit_leg_screen.dart';
import 'current_leg_screen.dart';
import 'live_accumulator_screen.dart';
import 'manual_settlement_screen.dart';
import 'accumulator_summary_screen.dart';
import 'fines_screen.dart';
import 'profile_screen.dart';
import 'main.dart'; // for AccaColors
import 'package:google_fonts/google_fonts.dart';

class AccaHubScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const AccaHubScreen({super.key, required this.appState, required this.teamId});

  @override
  State<AccaHubScreen> createState() => _AccaHubScreenState();
}

class _AccaHubScreenState extends State<AccaHubScreen> {
  Member? currentMember;
  GameWeek? activeGameWeek;
  int legCount = 0;
  int memberCount = 0;
  bool isLoading = true;

  bool get isManager => currentMember?.role == MemberRole.manager;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant AccaHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      load();
    }
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final userId = widget.appState.currentUser?.id;
    if (userId != null) {
      currentMember = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    }
    activeGameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    final members = await FirestoreService.instance.fetchMembers(widget.teamId);
    memberCount = members.length;
    if (activeGameWeek?.id != null) {
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      legCount = legs.where((l) => l.gameWeekId == activeGameWeek!.id).length;
    } else {
      legCount = 0;
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> openSubmitLeg() async {
    final gameWeek = activeGameWeek;
    if (gameWeek == null || gameWeek.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active gameweeks for selection.')));
      return;
    }
    if (gameWeek.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This gameweek is locked — selections are closed.')));
      return;
    }
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    if (member == null || member.id == null || !mounted) return;

    final existingLeg = await FirestoreService.instance.fetchMemberLegForGameWeek(
      teamId: widget.teamId,
      memberId: member.id!,
      gameWeekId: gameWeek.id!,
    );
    if (!mounted) return;

    if (existingLeg != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CurrentLegScreen(
            leg: existingLeg,
            gameWeekId: gameWeek.id!,
            memberId: member.id!,
            teamId: widget.teamId,
            windowStart: gameWeek.startDate,
            windowEnd: gameWeek.endDate,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubmitLegScreen(
            gameWeekId: gameWeek.id!,
            memberId: member.id!,
            teamId: widget.teamId,
            windowStart: gameWeek.startDate,
            windowEnd: gameWeek.endDate,
          ),
        ),
      );
    }
    load();
  }

  Future<void> openLiveView() async {
    if (activeGameWeek == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active gameweeks for selection.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveAccumulatorScreen(gameWeek: activeGameWeek!)),
    );
  }

  Future<void> openGameWeekManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameWeekSetupScreen(appState: widget.appState)),
    );
    load();
  }

  Future<void> endGameWeek() async {
    if (activeGameWeek == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End gameweek?'),
        content: Text('This ends Week ${activeGameWeek!.weekNumber}. Selections will close.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End gameweek')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirestoreService.instance.settleGameWeek(teamId: widget.teamId, gameWeekId: activeGameWeek!.id!);
      load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error ending gameweek: ${e.toString()}')));
      }
    }
  }

  Future<void> openManualSettlement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ManualSettlementScreen(teamId: widget.teamId)),
    );
    load();
  }

  Future<void> openAccumulatorSummary() async {
    if (activeGameWeek == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active gameweeks for selection.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccumulatorSummaryScreen(gameWeek: activeGameWeek!)),
    );
    load();
  }

  void openFines() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FinesScreen(appState: widget.appState, teamId: widget.teamId)),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: 'Acca ', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              TextSpan(text: 'Hub', style: GoogleFonts.poppins(color: AccaColors.gold, fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
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
                  _gameWeekStatusCard(),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      Row(
                        children: [
                          if (isManager)
                            Expanded(
                              child: _hubButton(
                                icon: activeGameWeek != null ? Icons.flag : Icons.add_circle_outline,
                                label: 'Gameweek manager',
                                onTap: activeGameWeek != null ? endGameWeek : openGameWeekManager,
                              ),
                            ),
                          if (isManager) const SizedBox(width: 12),
                          Expanded(
                            child: _hubButton(icon: Icons.sports_soccer, label: 'Pick selection', onTap: openSubmitLeg),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _hubButton(icon: Icons.live_tv, label: 'Live scores', onTap: openLiveView),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _hubButton(icon: Icons.gavel, label: 'Fines', onTap: openFines),
                          ),
                        ],
                      ),
                      if (isManager) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _hubButton(icon: Icons.check_circle_outline, label: 'Manual settlement', onTap: openManualSettlement),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _hubButton(icon: Icons.bar_chart, label: 'Odds selection', onTap: openAccumulatorSummary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _gameWeekStatusCard() {
    if (activeGameWeek == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AccaColors.gold, width: 1.5),
        ),
        child: const Text('No active gameweek', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black)),
      );
    }

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
          Text('Week ${activeGameWeek!.weekNumber}', style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
          if (activeGameWeek!.isLocked) ...[
            const SizedBox(height: 4),
            const Text('Locked', style: TextStyle(color: Colors.black87, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text('Coverage: $legCount/$memberCount picked', style: const TextStyle(color: Colors.black87, fontSize: 13)),
          const SizedBox(height: 2),
          Text('Deadline: ${_formatDate(activeGameWeek!.deadline)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _hubButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: AccaColors.gold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.black),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
          ],
        ),
      ),
    );
  }
}