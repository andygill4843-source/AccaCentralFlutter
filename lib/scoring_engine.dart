import 'models.dart';

class LeagueTableEntry {
  final String memberId;
  final String displayName;
  final int totalBasePoints;
  final double totalWeightedPoints;
  final int legsPlayed;
  final int legsWon;
  final int currentStreak;
  final int longestWinStreak;
  final AccumulatorLeg? biggestWin;

  const LeagueTableEntry({
    required this.memberId,
    required this.displayName,
    required this.totalBasePoints,
    required this.totalWeightedPoints,
    required this.legsPlayed,
    required this.legsWon,
    this.currentStreak = 0,
    this.longestWinStreak = 0,
    this.biggestWin,
  });
}

class ScoringEngine {
  static List<LeagueTableEntry> buildLeagueTable({
    required List<Member> members,
    required List<AccumulatorLeg> legs,
    List<Challenge> challenges = const [],
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

      // A physio-protected leg always contributes exactly 3 base / 0 weighted
      // once settled, regardless of its real outcome. The outcome itself is
      // left untouched, so legsWon/streaks/biggestWin below are unaffected —
      // physio only ever changes points, never stats, awards, or streaks.
      int totalBasePoints = settled.fold<int>(0, (sum, l) => sum + (l.physioProtected ? 3 : l.basePoints));
      double totalWeightedPoints = settled.fold<double>(0, (sum, l) => sum + (l.physioProtected ? 0 : l.weightedPoints));

      for (final challenge in challenges.where((c) => c.status == ChallengeStatus.resolved)) {
        final challengerGetsBonus = challenge.challengerWon == true;
        if (challengerGetsBonus && challenge.challengerMemberId == memberId) {
          totalBasePoints += Challenge.hypotheticalBasePoints;
          totalWeightedPoints += Challenge.hypotheticalWeightedPoints(challenge.challengedLegOdds);
        } else if (!challengerGetsBonus && challenge.challengedMemberId == memberId && challenge.challengerLegOdds != null) {
          totalBasePoints += Challenge.hypotheticalBasePoints;
          totalWeightedPoints += Challenge.hypotheticalWeightedPoints(challenge.challengerLegOdds!);
        }
      }
      final legsWon = settled.where((l) => l.outcome == LegOutcome.won).length;

      final streaks = _computeStreaks(settled);

      final wins = settled.where((l) => l.outcome == LegOutcome.won).toList();
      AccumulatorLeg? biggestWin;
      for (final w in wins) {
        if (biggestWin == null || w.decimalOddsAtSelection > biggestWin.decimalOddsAtSelection) {
          biggestWin = w;
        }
      }

      return LeagueTableEntry(
        memberId: memberId,
        displayName: member.displayName,
        totalBasePoints: totalBasePoints,
        totalWeightedPoints: totalWeightedPoints,
        legsPlayed: settled.length,
        legsWon: legsWon,
        currentStreak: streaks.$1,
        longestWinStreak: streaks.$2,
        biggestWin: biggestWin,
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

  static (int, int) _computeStreaks(List<AccumulatorLeg> settledLegs) {
    if (settledLegs.isEmpty) return (0, 0);

    int longestWin = 0;
    int runningWin = 0;
    for (final leg in settledLegs) {
      if (leg.outcome == LegOutcome.won) {
        runningWin++;
        if (runningWin > longestWin) longestWin = runningWin;
      } else {
        runningWin = 0;
      }
    }

    int i = settledLegs.length - 1;
    final lastOutcome = settledLegs[i].outcome;
    int trailing = 0;
    while (i >= 0 && settledLegs[i].outcome == lastOutcome) {
      trailing++;
      i--;
    }
    final current = lastOutcome == LegOutcome.won ? trailing : -trailing;

    return (current, longestWin);
  }

  static List<(BetType, int)> betTypePopularity(List<AccumulatorLeg> legs) {
    final Map<BetType, int> counts = {};
    for (final leg in legs) {
      counts[leg.betType] = (counts[leg.betType] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => (e.key, e.value)).toList();
    list.sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  }
}

class MemberStats {
  final String memberId;
  final String displayName;
  final AccumulatorLeg? lowestOddsWin;
  final double? averageWinningOdds;
  final double? averageLosingOdds;
  final AccumulatorLeg? biggestLosingOdds;
  final int valueHunterCount;
  final double? avgPickTimeMinutes;

  const MemberStats({
    required this.memberId,
    required this.displayName,
    this.lowestOddsWin,
    this.averageWinningOdds,
    this.averageLosingOdds,
    this.biggestLosingOdds,
    this.valueHunterCount = 0,
    this.avgPickTimeMinutes,
  });
}

extension MemberStatsEngine on ScoringEngine {
  static const valueHunterThreshold = 4.0; // decimal odds — i.e. 3/1 fractional or bigger

  static List<MemberStats> buildMemberStats({
    required List<Member> members,
    required List<AccumulatorLeg> legs,
    required List<GameWeek> gameWeeks,
  }) {
    final gameWeeksById = {for (final g in gameWeeks) if (g.id != null) g.id!: g};
    final Map<String, List<AccumulatorLeg>> grouped = {};
    for (final leg in legs) {
      grouped.putIfAbsent(leg.memberId, () => []).add(leg);
    }

    return members.map((member) {
      final memberId = member.id ?? member.userId;
      final memberLegs = grouped[memberId] ?? [];
      final settled = memberLegs.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost).toList();
      final wins = settled.where((l) => l.outcome == LegOutcome.won).toList();
      final losses = settled.where((l) => l.outcome == LegOutcome.lost).toList();

      AccumulatorLeg? lowestOddsWin;
      for (final w in wins) {
        if (lowestOddsWin == null || w.decimalOddsAtSelection < lowestOddsWin.decimalOddsAtSelection) {
          lowestOddsWin = w;
        }
      }

      AccumulatorLeg? biggestLosingOdds;
      for (final l in losses) {
        if (biggestLosingOdds == null || l.decimalOddsAtSelection > biggestLosingOdds.decimalOddsAtSelection) {
          biggestLosingOdds = l;
        }
      }

      final avgWinOdds = wins.isEmpty
          ? null
          : wins.fold<double>(0, (sum, l) => sum + l.decimalOddsAtSelection) / wins.length;
      final avgLossOdds = losses.isEmpty
          ? null
          : losses.fold<double>(0, (sum, l) => sum + l.decimalOddsAtSelection) / losses.length;

      final valueHunterCount = settled.where((l) => l.decimalOddsAtSelection >= valueHunterThreshold).length;

      final pickTimes = <int>[];
      for (final leg in memberLegs) {
        final gameWeek = gameWeeksById[leg.gameWeekId];
        if (gameWeek == null) continue;
        final diff = leg.submittedAt.difference(gameWeek.createdAt).inMinutes;
        if (diff >= 0) pickTimes.add(diff);
      }
      final avgPickTime = pickTimes.isEmpty ? null : pickTimes.reduce((a, b) => a + b) / pickTimes.length;

      return MemberStats(
        memberId: memberId,
        displayName: member.displayName,
        lowestOddsWin: lowestOddsWin,
        averageWinningOdds: avgWinOdds,
        averageLosingOdds: avgLossOdds,
        biggestLosingOdds: biggestLosingOdds,
        valueHunterCount: valueHunterCount,
        avgPickTimeMinutes: avgPickTime,
      );
    }).toList();
  }
}