import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

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

class LeagueTableEntry {
  final String displayName;
  final int totalBasePoints;
  final double totalWeightedPoints;
  final int legsWon;
  final int legsPlayed;

  const LeagueTableEntry({
    required this.displayName,
    required this.totalBasePoints,
    required this.totalWeightedPoints,
    required this.legsWon,
    required this.legsPlayed,
  });
}

// Mock data standing in for ScoringEngine.buildLeagueTable's real output —
// no Firestore reads wired up yet, that's the next step.
final mockEntries = [
  const LeagueTableEntry(displayName: "Andy", totalBasePoints: 21, totalWeightedPoints: 34.5, legsWon: 7, legsPlayed: 10),
  const LeagueTableEntry(displayName: "Sam", totalBasePoints: 18, totalWeightedPoints: 41.0, legsWon: 6, legsPlayed: 10),
  const LeagueTableEntry(displayName: "Priya", totalBasePoints: 18, totalWeightedPoints: 22.5, legsWon: 6, legsPlayed: 9),
  const LeagueTableEntry(displayName: "Jordan", totalBasePoints: 12, totalWeightedPoints: 15.0, legsWon: 4, legsPlayed: 10),
];

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

class LeagueTableScreen extends StatelessWidget {
  const LeagueTableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('League table'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: mockEntries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = mockEntries[index];
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
    );
  }
}