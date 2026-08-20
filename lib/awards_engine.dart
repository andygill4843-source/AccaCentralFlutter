import 'models.dart';

enum Achievement {
  firstBlood,
  hatTrick,
  hotStreak,
  unstoppable,
  underdog,
  longShotLegend,
  centuryClub,
  champion,
  onFire,
  mastermind,
  howler,
  cleanSheet,
  bankRoller,
  choker,
}

extension AchievementInfo on Achievement {
  String get title {
    switch (this) {
      case Achievement.firstBlood: return 'First Blood';
      case Achievement.hatTrick: return 'Hat-Trick';
      case Achievement.hotStreak: return 'Hot Streak';
      case Achievement.unstoppable: return 'Unstoppable';
      case Achievement.underdog: return 'Underdog';
      case Achievement.longShotLegend: return 'Long Shot Legend';
      case Achievement.centuryClub: return 'Century Club';
      case Achievement.champion: return 'Champion';
      case Achievement.onFire: return 'On Fire';
      case Achievement.mastermind: return 'Mastermind';
      case Achievement.howler: return 'The Howler';
      case Achievement.cleanSheet: return 'Clean Sheet';
      case Achievement.bankRoller: return 'Bank Roller';
      case Achievement.choker: return 'The Choker';
    }
  }
  String get description {
    switch (this) {
      case Achievement.firstBlood: return 'Won your first leg this season';
      case Achievement.hatTrick: return '3 winning legs in a row this season';
      case Achievement.hotStreak: return '5 winning legs in a row this season';
      case Achievement.unstoppable: return '10 winning legs in a row this season';
      case Achievement.underdog: return 'Won a leg at odds of 5/1 or bigger this season';
      case Achievement.longShotLegend: return 'Won a leg at odds of 10/1 or bigger this season';
      case Achievement.centuryClub: return 'Reached 100 base points this season';
      case Achievement.champion: return 'Topped the table at the end of the season';
      case Achievement.onFire: return "Currently holds the team's longest active win streak";
      case Achievement.mastermind: return 'Over 60% win rate with weighted points more than double your base points';
      case Achievement.howler: return "Lowest-odds losing leg in last week's gameweek";
      case Achievement.cleanSheet: return 'No fines this season';
      case Achievement.bankRoller: return 'Most fines this season';
      case Achievement.choker: return 'Was the only losing leg in a gameweek, at least once this season';
    }
  }
  String get emoji {
    switch (this) {
      case Achievement.firstBlood: return '🩸';
      case Achievement.hatTrick: return '🎩';
      case Achievement.hotStreak: return '🔥';
      case Achievement.unstoppable: return '🚀';
      case Achievement.underdog: return '🐶';
      case Achievement.longShotLegend: return '🎯';
      case Achievement.centuryClub: return '💯';
      case Achievement.champion: return '👑';
      case Achievement.onFire: return '⚡';
      case Achievement.mastermind: return '🧠';
      case Achievement.howler: return '😱';
      case Achievement.cleanSheet: return '🧤';
      case Achievement.bankRoller: return '💸';
      case Achievement.choker: return '🫣';
    }
  }
}

class AwardsEngine {
  /// Evaluates every achievement for one member, scoped to a single season.
  /// [seasonLegs] / [seasonGameWeeks] / [seasonFines] must already be filtered
  /// to the season being evaluated — this method does no season filtering itself.
  static Set<Achievement> evaluate({
    required String memberId,
    required List<Member> members,
    required List<AccumulatorLeg> seasonLegs,
    required List<GameWeek> seasonGameWeeks,
    required List<Fine> seasonFines,
    String? seasonChampionMemberId,
  }) {
    final unlocked = <Achievement>{};

    // ---- Personal achievements (this member's own legs only) ----
    final mine = seasonLegs.where((l) => l.memberId == memberId).toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final mySettled = mine.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost).toList();

    if (mySettled.any((l) => l.outcome == LegOutcome.won)) {
      unlocked.add(Achievement.firstBlood);
    }

    int runningWin = 0;
    for (final leg in mySettled) {
      if (leg.outcome == LegOutcome.won) {
        runningWin++;
        if (runningWin >= 3) unlocked.add(Achievement.hatTrick);
        if (runningWin >= 5) unlocked.add(Achievement.hotStreak);
        if (runningWin >= 10) unlocked.add(Achievement.unstoppable);
      } else {
        runningWin = 0;
      }
    }

    for (final leg in mySettled.where((l) => l.outcome == LegOutcome.won)) {
      final fraction = leg.decimalOddsAtSelection - 1.0;
      if (fraction >= 5.0) unlocked.add(Achievement.underdog);
      if (fraction >= 10.0) unlocked.add(Achievement.longShotLegend);
    }

    final myBasePoints = mySettled.fold<int>(0, (sum, l) => sum + l.basePoints);
    if (myBasePoints >= 100) unlocked.add(Achievement.centuryClub);

    if (mySettled.isNotEmpty) {
      final myWins = mySettled.where((l) => l.outcome == LegOutcome.won).length;
      final winRate = myWins / mySettled.length;
      final myWeightedPoints = mySettled.fold<double>(0, (sum, l) => sum + l.weightedPoints);
      if (winRate > 0.6 && myBasePoints > 0 && myWeightedPoints > myBasePoints * 2) {
        unlocked.add(Achievement.mastermind);
      }
    }

    if (seasonChampionMemberId != null && seasonChampionMemberId == memberId) {
      unlocked.add(Achievement.champion);
    }

    // ---- Team-wide achievements (need every member's data to compare) ----

    int currentStreakFor(String mId) {
      final legsForMember = seasonLegs.where((l) => l.memberId == mId).toList()
        ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
      final settledForMember =
          legsForMember.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost).toList();
      int streak = 0;
      for (final leg in settledForMember.reversed) {
        if (leg.outcome == LegOutcome.won) {
          streak++;
        } else {
          break;
        }
      }
      return streak;
    }

    final streaksByMember = {
      for (final m in members)
        if (m.id != null) m.id!: currentStreakFor(m.id!),
    };
    final maxStreak = streaksByMember.values.isEmpty ? 0 : streaksByMember.values.reduce((a, b) => a > b ? a : b);
    if (maxStreak > 0 && streaksByMember[memberId] == maxStreak) {
      unlocked.add(Achievement.onFire);
    }

    final settledWeeks = seasonGameWeeks.where((g) => g.isSettled).toList()
      ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

    // The Howler: lowest-odds losing leg in the most recently settled gameweek only.
    if (settledWeeks.isNotEmpty) {
      final lastWeek = settledWeeks.last;
      final losingLegsThatWeek =
          seasonLegs.where((l) => l.gameWeekId == lastWeek.id && l.outcome == LegOutcome.lost).toList()
            ..sort((a, b) => a.decimalOddsAtSelection.compareTo(b.decimalOddsAtSelection));
      if (losingLegsThatWeek.isNotEmpty && losingLegsThatWeek.first.memberId == memberId) {
        unlocked.add(Achievement.howler);
      }
    }

    // The Choker: sole loser in ANY settled gameweek this season — sticky once earned.
    for (final week in settledWeeks) {
      final weekSettled = seasonLegs
          .where((l) => l.gameWeekId == week.id && (l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost))
          .toList();
      final losers = weekSettled.where((l) => l.outcome == LegOutcome.lost).toList();
      if (losers.length == 1 && losers.first.memberId == memberId) {
        unlocked.add(Achievement.choker);
        break;
      }
    }

    // Clean Sheet / Bank Roller — season-scoped fine counts, team-wide comparison.
    final fineCountsByMember = <String, int>{
      for (final m in members)
        if (m.id != null) m.id!: 0,
    };
        // Matches the Fines screen's "Total fines" column: paid fines still count,
    // only overturned fines are excluded.
    for (final fine in seasonFines.where((f) => f.status != FineStatus.overturned)) {
      fineCountsByMember[fine.memberId] = (fineCountsByMember[fine.memberId] ?? 0) + 1;
    }
    final myFineCount = fineCountsByMember[memberId] ?? 0;
    if (myFineCount == 0) unlocked.add(Achievement.cleanSheet);
    final maxFines = fineCountsByMember.values.isEmpty ? 0 : fineCountsByMember.values.reduce((a, b) => a > b ? a : b);
    if (maxFines > 0 && myFineCount == maxFines) unlocked.add(Achievement.bankRoller);

    return unlocked;
  }
}