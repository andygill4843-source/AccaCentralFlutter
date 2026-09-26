import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

String? canonicalMarketFor(AccumulatorLeg leg) {
  final pick = (leg.pickValue ?? leg.selectionDescription).toLowerCase();
  final market = (leg.marketName ?? '').toLowerCase();

  switch (leg.betType) {
    case BetType.matchWinner:
      if (pick.contains('home')) return 'Home Win';
      if (pick.contains('away')) return 'Away Win';
      if (pick.contains('draw')) return 'Draw';
      return null;
    case BetType.bothTeamsToScore:
      return pick.contains('yes') ? 'BTTS Yes' : 'BTTS No';
    case BetType.overUnderGoals:
      if (pick.contains('1.5') && pick.contains('over')) return 'Over 1.5';
      if (pick.contains('2.5') && pick.contains('over')) return 'Over 2.5';
      if (pick.contains('3.5') && pick.contains('over')) return 'Over 3.5';
      if (pick.contains('2.5') && pick.contains('under')) return 'Under 2.5';
      return null;
    case BetType.teamTotals:
      final isHome = market.contains('home');
      if (pick.contains('0.5') && pick.contains('over')) return isHome ? 'Home Over 0.5' : 'Away Over 0.5';
      if (pick.contains('1.5') && pick.contains('over')) return isHome ? 'Home Over 1.5' : 'Away Over 1.5';
      return null;
    default:
      return null;
  }
}

Future<double?> fetchScoutProbabilityForLeg(AccumulatorLeg leg) async {
  final fixtureId = leg.apiFootballFixtureId;
  final market = canonicalMarketFor(leg);
  if (fixtureId == null || market == null) return null;

  final doc = await FirebaseFirestore.instance.collection('matchPredictions').doc(fixtureId.toString()).get();
  if (!doc.exists) return null;
  final payload = doc.data()?['payload'] as Map<String, dynamic>?;
  final probabilities = payload?['probabilities'] as Map<String, dynamic>?;
  final raw = probabilities?[market];
  if (raw == null) return null;
  return (raw as num).toDouble();
}

/// Three-tier qualitative wording — HIGH (≥80%), MEDIUM (50–80%), LOW (<50%).
class ScoutConfidenceBadge extends StatelessWidget {
  final AccumulatorLeg leg;
  const ScoutConfidenceBadge({super.key, required this.leg});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: fetchScoutProbabilityForLeg(leg),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
        final probability = snapshot.data!;

        final Color color;
        final String label;
        if (probability >= 0.80) {
          color = Colors.greenAccent;
          label = 'Scout confidence: HIGH';
        } else if (probability >= 0.50) {
          color = Colors.orangeAccent;
          label = 'Scout confidence: MEDIUM';
        } else {
          color = Colors.redAccent;
          label = 'Scout confidence: LOW';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}

/// Two-tier raw percentage — green (≥50%) or red (<50%). A simpler,
/// literal companion to ScoutConfidenceBadge's three-tier wording.
class ScoutProbabilityBadge extends StatelessWidget {
  final AccumulatorLeg leg;
  const ScoutProbabilityBadge({super.key, required this.leg});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: fetchScoutProbabilityForLeg(leg),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
        final probability = snapshot.data!;
        final Color color;
        if (probability >= 0.80) {
          color = AccaColors.win;
        } else if (probability >= 0.50) {
          color = Colors.orangeAccent;
        } else {
          color = AccaColors.loss;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text('${(probability * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}