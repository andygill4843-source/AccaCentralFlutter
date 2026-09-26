class MatchProbabilities {
  final double homeWin;
  final double draw;
  final double awayWin;

  final double over15;
  final double over25;
  final double over35;
  final double under25;

  final double bttsYes;
  final double bttsNo;

  final double homeOver05;
  final double homeOver15;
  final double awayOver05;
  final double awayOver15;

  const MatchProbabilities({
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.over15,
    required this.over25,
    required this.over35,
    required this.under25,
    required this.bttsYes,
    required this.bttsNo,
    required this.homeOver05,
    required this.homeOver15,
    required this.awayOver05,
    required this.awayOver15,
  });

  double asPercentage(double probability) => probability * 100;

  Map<String, double> toPercentages() => {
        'Home Win': asPercentage(homeWin),
        'Draw': asPercentage(draw),
        'Away Win': asPercentage(awayWin),
        'Over 1.5': asPercentage(over15),
        'Over 2.5': asPercentage(over25),
        'Over 3.5': asPercentage(over35),
        'Under 2.5': asPercentage(under25),
        'BTTS Yes': asPercentage(bttsYes),
        'BTTS No': asPercentage(bttsNo),
        'Home Over 0.5': asPercentage(homeOver05),
        'Home Over 1.5': asPercentage(homeOver15),
        'Away Over 0.5': asPercentage(awayOver05),
        'Away Over 1.5': asPercentage(awayOver15),
      };

  Map<String, double> toProbabilities() => {
        'Home Win': homeWin,
        'Draw': draw,
        'Away Win': awayWin,
        'Over 1.5': over15,
        'Over 2.5': over25,
        'Over 3.5': over35,
        'Under 2.5': under25,
        'BTTS Yes': bttsYes,
        'BTTS No': bttsNo,
        'Home Over 0.5': homeOver05,
        'Home Over 1.5': homeOver15,
        'Away Over 0.5': awayOver05,
        'Away Over 1.5': awayOver15,
      };

  factory MatchProbabilities.fromMap(Map<String, dynamic> map) {
    double d(String key) => (map[key] as num?)?.toDouble() ?? 0.0;
    return MatchProbabilities(
      homeWin: d('Home Win'),
      draw: d('Draw'),
      awayWin: d('Away Win'),
      over15: d('Over 1.5'),
      over25: d('Over 2.5'),
      over35: d('Over 3.5'),
      under25: d('Under 2.5'),
      bttsYes: d('BTTS Yes'),
      bttsNo: d('BTTS No'),
      homeOver05: d('Home Over 0.5'),
      homeOver15: d('Home Over 1.5'),
      awayOver05: d('Away Over 0.5'),
      awayOver15: d('Away Over 1.5'),
    );
  }
}
