class MarketValue {
  final String market;
  final double modelProbability;
  final double bookmakerOdds;
  final double impliedProbability;
  final double fairOdds;
  final double edge;

  const MarketValue({
    required this.market,
    required this.modelProbability,
    required this.bookmakerOdds,
    required this.impliedProbability,
    required this.fairOdds,
    required this.edge,
  });

  Map<String, double> toMap() => {
        'modelProbability': modelProbability,
        'bookmakerOdds': bookmakerOdds,
        'impliedProbability': impliedProbability,
        'fairOdds': fairOdds,
        'edge': edge,
      };
}

class ValueEngine {
  MarketValue? calculate({
    required String market,
    required double modelProbability,
    required double bookmakerOdds,
  }) {
    if (modelProbability <= 0 ||
        modelProbability >= 1 ||
        bookmakerOdds <= 1) {
      return null;
    }

    final implied = 1.0 / bookmakerOdds;
    final fairOdds = 1.0 / modelProbability;
    final edge = modelProbability - implied;

    return MarketValue(
      market: market,
      modelProbability: modelProbability,
      bookmakerOdds: bookmakerOdds,
      impliedProbability: implied,
      fairOdds: fairOdds,
      edge: edge,
    );
  }

  List<MarketValue> calculateAll(
    Map<String, double> probabilities,
    Map<String, double> bookmakerOdds,
  ) {
    final values = <MarketValue>[];

    for (final entry in bookmakerOdds.entries) {
      final probability = probabilities[entry.key];
      if (probability == null) continue;

      final result = calculate(
        market: entry.key,
        modelProbability: probability,
        bookmakerOdds: entry.value,
      );

      if (result != null) values.add(result);
    }

    return values;
  }

  MarketValue? bestBet(
    List<MarketValue> values, {
    double minEdge = 0.02,
    double minProbability = 0.15,
  }) {
    final eligible = values.where(
      (v) => v.edge >= minEdge && v.modelProbability >= minProbability,
    );
    if (eligible.isEmpty) return null;
    return eligible.reduce((a, b) => b.edge > a.edge ? b : a);
  }

  /// Top [count] markets by the model's own probability alone — not by
  /// edge over the bookmaker's price. minOdds excludes very short-priced
  /// outcomes (e.g. 1/10 favourites) that would otherwise dominate on
  /// probability alone despite being poor picks to actually stake on.
  List<MarketValue> strongestSelections(
    List<MarketValue> values, {
    int count = 3,
    double minOdds = 1.5,
  }) {
    final eligible = values.where((v) => v.bookmakerOdds >= minOdds).toList()
      ..sort((a, b) => b.modelProbability.compareTo(a.modelProbability));
    return eligible.take(count).toList();
  }

  /// Top [count] markets by edge, restricted to outcomes the model is
  /// at least [minProbability] confident in (80% by default) and priced
  /// at [minOdds] or above. Only positive-edge outcomes are eligible.
  List<MarketValue> valueHunter(
    List<MarketValue> values, {
    int count = 3,
    double minProbability = 0.80,
    double minOdds = 1.5,
  }) {
    final eligible = values
        .where((v) => v.modelProbability >= minProbability && v.edge > 0 && v.bookmakerOdds >= minOdds)
        .toList()
      ..sort((a, b) => b.edge.compareTo(a.edge));
    return eligible.take(count).toList();
  }
}