import 'models.dart';

class LeagueTableEntry {
  final String memberId;
  final String displayName;
  final int totalBasePoints;
  final double totalWeightedPoints;
  final int legsPlayed;
  final int legsWon;

  const LeagueTableEntry({
    required this.memberId,
    required this.displayName,
    required this.totalBasePoints,
    required this.totalWeightedPoints,
    required this.legsPlayed,
    required this.legsWon,
  });
}

class ScoringEngine {
  /// Direct translation of ScoringEngine.swift's buildLeagueTable —
  /// same sort: base points desc, then weighted points desc.
  static List<LeagueTableEntry> buildLeagueTable({
    required List<Member> members,
    required List<AccumulatorLeg> legs,
  }) {
    final Map<String, List<AccumulatorLeg>> grouped = {};
    for (final leg in legs) {
      grouped.putIfAbsent(leg.memberId, () => []).add(leg);
    }

    final entries = members.map((member) {
      final memberId = member.id ?? member.userId;
      final memberLegs = grouped[memberId] ?? [];

      final settled = memberLegs
          .where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost)
          .toList()
        ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

      final totalBasePoints = settled.fold<int>(0, (sum, l) => sum + l.basePoints);
      final totalWeightedPoints = settled.fold<double>(0, (sum, l) => sum + l.weightedPoints);
      final legsWon = settled.where((l) => l.outcome == LegOutcome.won).length;

      return LeagueTableEntry(
        memberId: memberId,
        displayName: member.displayName,
        totalBasePoints: totalBasePoints,
        totalWeightedPoints: totalWeightedPoints,
        legsPlayed: settled.length,
        legsWon: legsWon,
      );
    }).toList();

    entries.sort((a, b) {
      if (a.totalBasePoints != b.totalBasePoints) {
        return b.totalBasePoints.compareTo(a.totalBasePoints);
      }
      return b.totalWeightedPoints.compareTo(a.totalWeightedPoints);
    });

    return entries;
  }
}