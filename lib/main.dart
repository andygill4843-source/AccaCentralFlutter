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
    appState.resolveAuthState();
  }

  @override
  Widget build(BuildContext context) {
    switch (appState.screen) {
      case AppScreen.splash:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AppScreen.auth:
        return AuthScreen(appState: appState, onAuthenticated: () {});
      case AppScreen.teamSetup:
  	return TeamSetupScreen(appState: appState, onTeamReady: () {});
      case AppScreen.main:
  	return LeagueTableScreen(teamId: appState.currentUser?.teamIds.first ?? '', appState: appState);
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> openSubmitLeg() async {
    final gameWeek = await FirestoreService.instance.fetchActiveGameWeek(widget.teamId);
    if (gameWeek == null || gameWeek.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active gameweeks for selection. Please ask the boss to setup a new gameweek.')),
        );
      }
      return;
    }
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    if (member == null || member.id == null || !mounted) return;

    final submitted = await Navigator.of(context).push<bool>(
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
    if (submitted == true) load();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GameWeekSetupScreen(appState: widget.appState)),
              );
              load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.sports_soccer),
            onPressed: openSubmitLeg,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.appState.logOut();
            },
          ),
	  IconButton(
  	    icon: const Icon(Icons.bar_chart),
  	    onPressed: openAccumulatorSummary,
	  ),
	  IconButton(
  	    icon: const Icon(Icons.check_circle_outline),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ManualSettlementScreen(teamId: widget.teamId)),
    	      );
              load();
            },
	  ),
	  IconButton(
  	    icon: const Icon(Icons.live_tv),
  	    onPressed: openLiveView,
	  ),
        ],
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