import 'models.dart';

enum Achievement {
  firstBlood,
  hatTrick,
  onFire,
  unstoppable,
  underdog,
  longShotLegend,
  centuryClub,
  ironWill,
  comebackKid,
  allRounder,
}

extension AchievementInfo on Achievement {
  String get title {
    switch (this) {
      case Achievement.firstBlood: return 'First Blood';
      case Achievement.hatTrick: return 'Hat-Trick';
      case Achievement.onFire: return 'On Fire';
      case Achievement.unstoppable: return 'Unstoppable';
      case Achievement.underdog: return 'Underdog';
      case Achievement.longShotLegend: return 'Long Shot Legend';
      case Achievement.centuryClub: return 'Century Club';
      case Achievement.ironWill: return 'Iron Will';
      case Achievement.comebackKid: return 'Comeback Kid';
      case Achievement.allRounder: return 'All-Rounder';
    }
  }

  String get description {
    switch (this) {
      case Achievement.firstBlood: return 'Won your first ever leg';
      case Achievement.hatTrick: return '3 winning legs in a row';
      case Achievement.onFire: return '5 winning legs in a row';
      case Achievement.unstoppable: return '10 winning legs in a row';
      case Achievement.underdog: return 'Won a leg at odds of 5/1 or bigger';
      case Achievement.longShotLegend: return 'Won a leg at odds of 10/1 or bigger';
      case Achievement.centuryClub: return 'Reached 100 base points in a season';
      case Achievement.ironWill: return 'Submitted a leg in every gameweek this season';
      case Achievement.comebackKid: return 'Won a leg right after a 5-leg losing streak';
      case Achievement.allRounder: return 'Placed a leg of every bet type at least once';
    }
  }

  String get emoji {
    switch (this) {
      case Achievement.firstBlood: return '🩸';
      case Achievement.hatTrick: return '🎩';
      case Achievement.onFire: return '🔥';
      case Achievement.unstoppable: return '🚀';
      case Achievement.underdog: return '🐶';
      case Achievement.longShotLegend: return '🎯';
      case Achievement.centuryClub: return '💯';
      case Achievement.ironWill: return '🛡️';
      case Achievement.comebackKid: return '🔁';
      case Achievement.allRounder: return '🎓';
    }
  }
}

class AwardsEngine {
  static Set<Achievement> evaluate({
    required String memberId,
    required List<AccumulatorLeg> legs,
    required int totalGameWeeks,
  }) {
    final mine = legs.where((l) => l.memberId == memberId).toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final settled = mine.where((l) => l.outcome == LegOutcome.won || l.outcome == LegOutcome.lost).toList();

    final unlocked = <Achievement>{};

    if (settled.any((l) => l.outcome == LegOutcome.won)) {
      unlocked.add(Achievement.firstBlood);
    }

    int runningWin = 0;
    int runningLoss = 0;
    for (final leg in settled) {
      if (leg.outcome == LegOutcome.won) {
        if (runningLoss >= 5) unlocked.add(Achievement.comebackKid);
        runningLoss = 0;
        runningWin++;
        if (runningWin >= 3) unlocked.add(Achievement.hatTrick);
        if (runningWin >= 5) unlocked.add(Achievement.onFire);
        if (runningWin >= 10) unlocked.add(Achievement.unstoppable);
      } else {
        runningWin = 0;
        runningLoss++;
      }
    }

    for (final leg in settled.where((l) => l.outcome == LegOutcome.won)) {
      final fraction = leg.decimalOddsAtSelection - 1.0;
      if (fraction >= 5.0) unlocked.add(Achievement.underdog);
      if (fraction >= 10.0) unlocked.add(Achievement.longShotLegend);
    }

    final totalBasePoints = settled.fold<int>(0, (sum, l) => sum + l.basePoints);
    if (totalBasePoints >= 100) unlocked.add(Achievement.centuryClub);

    final weeksPlayed = mine.map((l) => l.gameWeekId).toSet().length;
    if (totalGameWeeks > 0 && weeksPlayed >= totalGameWeeks) unlocked.add(Achievement.ironWill);

    final betTypesUsed = mine.map((l) => l.betType).toSet();
    if (betTypesUsed.length == BetType.values.length) unlocked.add(Achievement.allRounder);

    return unlocked;
  }
}