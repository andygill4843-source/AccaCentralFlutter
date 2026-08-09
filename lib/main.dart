import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';

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
      home: const LeagueTableScreen(),
    );
  }
}

class LeagueTableScreen extends StatefulWidget {
  const LeagueTableScreen({super.key});

  @override
  State<LeagueTableScreen> createState() => _LeagueTableScreenState();
}

class _LeagueTableScreenState extends State<LeagueTableScreen> {
  // TEMPORARY — replace with the real signed-in user's team ID once
  // auth/team-setup screens are rebuilt. Paste a real team document ID
  // from Firestore here to test against your actual data.
  static const String testTeamId = 'z1pr9SbvRqmOVqlIk8lw';

  List<LeagueTableEntry> entries = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final members = await FirestoreService.instance.fetchMembers(testTeamId);
      final legs = await FirestoreService.instance.fetchLegs(testTeamId);
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