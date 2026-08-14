import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'profile_screen.dart';
import 'main.dart'; // for AccaColors

class HomeScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final void Function(int tabIndex) onNavigateToTab;

  const HomeScreen({super.key, required this.appState, required this.teamId, required this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isLoading = true;
  int? nextWeekNumber;
  DateTime? nextDeadline;
  bool hasActiveGameWeek = false;
  List<LeagueTableEntry> topThree = [];
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final table = ScoringEngine.buildLeagueTable(members: members, legs: legs);

      if (mounted) {
        setState(() {
          hasActiveGameWeek = gameWeek != null;
          nextWeekNumber = gameWeek?.weekNumber;
          nextDeadline = gameWeek?.deadline;
          topThree = table.take(3).toList();
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

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acca Central'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: Colors.white,
                  child: Text(
                    hasActiveGameWeek
                        ? 'Gameweek $nextWeekNumber — deadline ${_formatDate(nextDeadline!)}'
                        : 'No active gameweek',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 110,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AccaColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(8),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Top 3 in league', style: TextStyle(fontSize: 11, color: AccaColors.textSecondary)),
                              const SizedBox(height: 6),
                              if (topThree.isEmpty)
                                Text('No data yet', style: TextStyle(fontSize: 12, color: AccaColors.textSecondary))
                              else
                                for (int i = 0; i < topThree.length; i++)
                                  Text(
                                    '${i + 1}. ${topThree[i].displayName}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _navButton(icon: Icons.sports_soccer, label: 'Acca Hub', onTap: () => widget.onNavigateToTab(1)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _navButton(icon: Icons.bar_chart, label: 'Stats', onTap: () => widget.onNavigateToTab(3)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _navButton(icon: Icons.military_tech, label: 'Awards', onTap: () => widget.onNavigateToTab(4)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _navButton(
                        icon: Icons.person,
                        label: 'Profile',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ProfileScreen(appState: widget.appState, teamId: widget.teamId)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
  Widget _navButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: AccaColors.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}