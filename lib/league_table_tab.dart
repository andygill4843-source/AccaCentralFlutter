import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors

class LeagueTableTab extends StatefulWidget {
  final String teamId;

  const LeagueTableTab({super.key, required this.teamId});

  @override
  State<LeagueTableTab> createState() => _LeagueTableTabState();
}

class _LeagueTableTabState extends State<LeagueTableTab> {
  List<LeagueTableEntry> entries = [];
  bool isLoading = true;
  String? errorMessage;
  String? currentSeason;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      currentSeason = team?.season;

      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);

      final currentSeasonGameWeekIds = gameWeeks
          .where((g) => g.season == team?.season)
          .map((g) => g.id)
          .toSet();
      final currentSeasonLegs = legs.where((l) => currentSeasonGameWeekIds.contains(l.gameWeekId)).toList();

      setState(() {
        entries = ScoringEngine.buildLeagueTable(members: members, legs: currentSeasonLegs);
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
        title: Text(currentSeason != null ? 'League table — $currentSeason' : 'League table'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
                : entries.isEmpty
                    ? const Center(child: Text('No members found for this team.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            leading: SizedBox(
                              width: 28,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: index == 0 ? AccaColors.gold : AccaColors.textSecondary,
                                ),
                              ),
                            ),
                            title: Text(entry.displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              '${entry.legsWon}/${entry.legsPlayed} legs won',
                              style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${entry.totalBasePoints} pts',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AccaColors.primary),
                                ),
                                Text(
                                  '${entry.totalWeightedPoints.toStringAsFixed(1)} weighted',
                                  style: TextStyle(fontSize: 11, color: AccaColors.textSecondary),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}