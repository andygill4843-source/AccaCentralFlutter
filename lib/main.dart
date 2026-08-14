import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'app_state.dart';
import 'auth_screen.dart';
import 'team_setup_screen.dart';
import 'gameweek_setup_screen.dart';
import 'submit_leg_screen.dart';
import 'manual_settlement_screen.dart';
import 'accumulator_summary_screen.dart';
import 'live_accumulator_screen.dart';
import 'current_leg_screen.dart';
import 'profile_screen.dart';
import 'models.dart';
import 'stats_screen.dart';
import 'awards_screen.dart';
import 'main_tab_scaffold.dart';
import 'splash_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AccaCentralApp());
}

// Champion Navy palette — same hex values as Colors.swift
class AccaColors {
  static const primary = Color(0xFF0F1B3C);
  static const secondary = Color(0xFF1D2E5C);
  static const gold = Color(0xFFE8B923);
  static const background = Color(0xFFF4F4F0);
  static const textPrimary = Color(0xFF0F1B3C);
  static const textSecondary = Color(0xFF5F5E5A);
  static const win = Color(0xFF16A34A);
  static const loss = Color(0xFFDC2626);
}


class AccaCentralApp extends StatelessWidget {
  const AccaCentralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acca Central',
      theme: ThemeData(
        scaffoldBackgroundColor: AccaColors.background,
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final appState = AppState();

  @override
  void initState() {
    super.initState();
    appState.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    switch (appState.screen) {
      case AppScreen.splash:
        return SplashScreen(appState: appState);
      case AppScreen.auth:
        return AuthScreen(appState: appState, onAuthenticated: () {});
      case AppScreen.teamSetup:
  	return TeamSetupScreen(appState: appState, onTeamReady: () {});
      case AppScreen.main:
  return MainTabScaffold(appState: appState, teamId: appState.activeTeamId ?? appState.currentUser?.teamIds.first ?? '');
    }
  }
}

class LeagueTableScreen extends StatefulWidget {
  final String teamId;
  final AppState appState;

  const LeagueTableScreen({super.key, required this.teamId, required this.appState});

  @override
  State<LeagueTableScreen> createState() => _LeagueTableScreenState();
}

class _LeagueTableScreenState extends State<LeagueTableScreen> {
  List<LeagueTableEntry> entries = [];
  bool isLoading = true;
  String? errorMessage;
  Member? currentMember;
  GameWeek? activeGameWeek;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> openSubmitLeg() async {
    try {
      final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
      if (gameWeek == null || gameWeek.id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active gameweeks for selection.')),
          );
        }
        return;
      }
      if (gameWeek.isLocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This gameweek is locked — selections are closed.')),
          );
        }
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

      final bool? submitted;
      if (existingLeg != null) {
        submitted = await Navigator.of(context).push<bool>(
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
        submitted = await Navigator.of(context).push<bool>(
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
      if (submitted == true) load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> endGameWeek() async {
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (gameWeek == null || gameWeek.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End gameweek?'),
        content: Text('This ends Week ${gameWeek.weekNumber}. You can create a new gameweek afterward.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End gameweek')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirestoreService.instance.settleGameWeek(teamId: widget.teamId, gameWeekId: gameWeek.id!);
      load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending gameweek: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> openAccumulatorSummary() async {
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (gameWeek == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active gameweeks for selection.')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccumulatorSummaryScreen(gameWeek: gameWeek)),
    );
  }

  Future<void> openLiveView() async {
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (gameWeek == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active gameweeks for selection.')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveAccumulatorScreen(gameWeek: gameWeek)),
    );
  }

  Future<void> load() async {
    try {
      final userId = widget.appState.currentUser?.id;
      if (userId != null) {
        currentMember = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      }
      activeGameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      setState(() {
        entries = ScoringEngine.buildLeagueTable(members: members, legs: legs);
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
        title: const Text('League table'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: BottomAppBar(
        color: AccaColors.primary,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (currentMember?.role == MemberRole.manager)
                IconButton(
                  icon: Icon(
                    activeGameWeek != null ? Icons.flag : Icons.add_circle_outline,
                    color: Colors.white,
                  ),
                  tooltip: activeGameWeek != null ? 'End gameweek' : 'New gameweek',
                  onPressed: () async {
                    if (activeGameWeek != null) {
                      await endGameWeek();
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => GameWeekSetupScreen(appState: widget.appState)),
                      );
                      load();
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.sports_soccer, color: Colors.white),
                tooltip: 'Pick your leg',
                onPressed: openSubmitLeg,
              ),
              IconButton(
                icon: const Icon(Icons.live_tv, color: Colors.white),
                tooltip: 'Live',
                onPressed: openLiveView,
              ),
              if (currentMember?.role == MemberRole.manager)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                  tooltip: 'Settle legs',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ManualSettlementScreen(teamId: widget.teamId)),
                    );
                    load();
                  },
                ),
              if (currentMember?.role == MemberRole.manager)
                IconButton(
                  icon: const Icon(Icons.bar_chart, color: Colors.white),
                  tooltip: 'Best odds',
                  onPressed: openAccumulatorSummary,
                ),
              IconButton(
                icon: const Icon(Icons.person, color: Colors.white),
                tooltip: 'Profile',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProfileScreen(appState: widget.appState, teamId: widget.teamId)),
                  );
                },
              ),
	      IconButton(
                icon: const Icon(Icons.bar_chart_outlined, color: Colors.white),
                tooltip: 'Stats',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => StatsScreen(teamId: widget.teamId)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.white),
                tooltip: 'Awards',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AwardsScreen(appState: widget.appState, teamId: widget.teamId)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  )
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
                            title: Text(
                              entry.displayName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              '${entry.legsWon}/${entry.legsPlayed} legs won',
                              style: const TextStyle(fontSize: 12, color: AccaColors.textSecondary),
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
                                  style: const TextStyle(fontSize: 11, color: AccaColors.textSecondary),
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