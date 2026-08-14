import 'package:flutter/material.dart';
import 'app_state.dart';
import 'awards_engine.dart';
import 'firestore_service.dart';
import 'main.dart'; // for AccaColors

class AwardsScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const AwardsScreen({super.key, required this.appState, required this.teamId});

  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

class _AwardsScreenState extends State<AwardsScreen> {
  Set<Achievement> unlocked = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    try {
      final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      if (member == null || member.id == null) {
        setState(() {
          errorMessage = 'No member profile found.';
          isLoading = false;
        });
        return;
      }
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      final settledCount = gameWeeks.where((g) => g.isSettled).length;

      setState(() {
        unlocked = AwardsEngine.evaluate(memberId: member.id!, legs: legs, totalGameWeeks: settledCount);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Awards'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: GridView.count(
                    padding: const EdgeInsets.all(16),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                    children: [
                      for (final achievement in Achievement.values) _achievementCard(achievement),
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
        color: isUnlocked ? AccaColors.gold.withOpacity(0.15) : Colors.grey.withOpacity(0.06),
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