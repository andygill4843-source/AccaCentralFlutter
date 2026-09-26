import 'api_football_service.dart';


/// Bumped whenever the prediction algorithm materially changes (e.g. the
/// depth-based row-splitting fix). LineupTab treats any cached
/// prediction with a different version as stale and recomputes, rather
/// than requiring manual Firestore cleanup after an algorithm change.
const int kPredictedLineupAlgorithmVersion = 2;

/// Predicts a team's likely starting XI (and bench) for an upcoming
/// fixture, based on how often each player started (or appeared as a
/// substitute) in that team's recent matches, AND how advanced they
/// typically played (used to correctly split multi-line formations like
/// 4-2-3-1 into their real distinct rows, rather than flattening every
/// midfielder onto one line).
///
/// API-Football has no direct "predicted lineup" endpoint — this is a
/// heuristic built entirely from real historical lineup data already
/// available via fetchLineups.
class PredictedLineupService {
  final ApiFootballService apiFootball;

  PredictedLineupService({ApiFootballService? apiFootball})
      : apiFootball = apiFootball ?? ApiFootballService.instance;

  Future<PredictedLineupResult> predictLineup({
    required int teamId,
    required int fixtureId,
    int recentFixtureCount = 8,
  }) async {
    final recentFixtures = await apiFootball.fetchLastFixtures(teamId, last: recentFixtureCount);
    if (recentFixtures.isEmpty) {
      return PredictedLineupResult.insufficientData(teamId: teamId);
    }

    final appearances = <int, _PlayerAppearance>{};
    final formationTally = <String, int>{};
    String? teamName;

    for (final fixture in recentFixtures) {
      try {
        final lineups = await apiFootball.fetchLineups(fixture.id);
        final teamLineup = lineups.home?.teamId == teamId
            ? lineups.home
            : (lineups.away?.teamId == teamId ? lineups.away : null);
        if (teamLineup == null) continue;

        teamName ??= teamLineup.teamName;
        if (teamLineup.formation.isNotEmpty) {
          formationTally[teamLineup.formation] = (formationTally[teamLineup.formation] ?? 0) + 1;
        }

        // How advanced each player played IN THIS SPECIFIC MATCH,
        // normalised 0 (deepest row, e.g. GK/last defender) to 1 (most
        // advanced row, e.g. lone striker) — used to correctly split
        // multi-line formations later, rather than a coarse 4-category
        // guess.
        final maxRow = teamLineup.startXI.isEmpty
            ? 1
            : teamLineup.startXI.map((p) => p.gridRow).reduce((a, b) => a > b ? a : b);

        for (final player in teamLineup.startXI) {
          final depthFraction = maxRow > 1 ? (player.gridRow - 1) / (maxRow - 1) : 0.0;
          final existing = appearances[player.id];
          appearances[player.id] = existing == null
              ? _PlayerAppearance(player: player, starts: 1, appearances: 1, depthFractionSum: depthFraction, depthSamples: 1)
              : existing.copyWith(
                  starts: existing.starts + 1,
                  appearances: existing.appearances + 1,
                  depthFractionSum: existing.depthFractionSum + depthFraction,
                  depthSamples: existing.depthSamples + 1,
                );
        }
        for (final player in teamLineup.substitutes) {
          final existing = appearances[player.id];
          appearances[player.id] = existing == null
              ? _PlayerAppearance(player: player, starts: 0, appearances: 1)
              : existing.copyWith(appearances: existing.appearances + 1);
        }
      } catch (_) {
        // One unavailable historical fixture shouldn't block prediction
        // from the rest.
      }
    }

    if (appearances.isEmpty) {
      return PredictedLineupResult.insufficientData(teamId: teamId);
    }

    final formation = formationTally.isEmpty
        ? '4-3-3'
        : (formationTally.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final shape = _FormationShape.parse(formation);

    final ranked = appearances.values.toList()
      ..sort((a, b) => b.predictionScore.compareTo(a.predictionScore));

    final selectedWithGrid = _selectByShape(ranked, shape);

    // Bench: next 7 most-likely players by the same frequency score,
    // excluding whoever made the starting XI. Grid coordinates aren't
    // meaningful for a substitute, so left at 0/0 — lineup_tab.dart
    // renders these in a plain list, not positioned on the pitch.
    final startXIIds = selectedWithGrid.map((p) => p.id).toSet();
    final substitutes = ranked
        .where((p) => !startXIIds.contains(p.player.id))
        .take(7)
        .map((p) => ApiFootballLineupPlayer(
              id: p.player.id,
              name: p.player.name,
              number: p.player.number,
              position: p.player.position,
              gridRow: 0,
              gridCol: 0,
            ))
        .toList();

    final confidence = _calculateConfidence(selectedWithGrid, recentFixtures.length);

    return PredictedLineupResult(
      teamId: teamId,
      teamName: teamName ?? '',
      formation: shape.label,
      startXI: selectedWithGrid,
      substitutes: substitutes,
      confidence: confidence,
      isOfficial: false,
    );
  }

  Future<PredictedLineupResult?> fetchOfficialLineup({
    required int teamId,
    required int fixtureId,
  }) async {
    final lineups = await apiFootball.fetchLineups(fixtureId);
    final teamLineup = lineups.home?.teamId == teamId
        ? lineups.home
        : (lineups.away?.teamId == teamId ? lineups.away : null);
    if (teamLineup == null || teamLineup.startXI.isEmpty) return null;

    return PredictedLineupResult(
      teamId: teamId,
      teamName: teamLineup.teamName,
      formation: teamLineup.formation,
      startXI: teamLineup.startXI,
      substitutes: teamLineup.substitutes,
      confidence: 100,
      isOfficial: true,
    );
  }

  /// Picks 1 goalkeeper by position category, then the next 10 most
  /// likely outfield players by appearance frequency — ordered by their
  /// TYPICAL DEPTH (most defensive first) and sliced into rows matching
  /// the formation's actual segments (e.g. [4, 2, 3, 1] for 4-2-3-1),
  /// rather than lumping every midfielder onto one line.
  List<ApiFootballLineupPlayer> _selectByShape(List<_PlayerAppearance> ranked, _FormationShape shape) {
    final gkList = ranked.where((p) => p.positionCategory == _PositionCategory.goalkeeper).toList();
    final gk = gkList.isNotEmpty ? gkList.first : null;

    final outfieldPool = ranked.where((p) => p.positionCategory != _PositionCategory.goalkeeper).toList();
    final selectedOutfield = outfieldPool.take(shape.totalOutfield).toList()
      ..sort((a, b) => a.averageDepthFraction.compareTo(b.averageDepthFraction));

    final withGrid = <ApiFootballLineupPlayer>[];
    if (gk != null) {
      withGrid.add(_toGridPlayer(gk, row: 1, col: 1));
    }

    var cursor = 0;
    for (var rowIndex = 0; rowIndex < shape.segments.length; rowIndex++) {
      final count = shape.segments[rowIndex];
      final rowPlayers = selectedOutfield.skip(cursor).take(count).toList();
      cursor += count;
      for (var col = 0; col < rowPlayers.length; col++) {
        withGrid.add(_toGridPlayer(rowPlayers[col], row: rowIndex + 2, col: col + 1));
      }
    }

    return withGrid;
  }

  ApiFootballLineupPlayer _toGridPlayer(_PlayerAppearance p, {required int row, required int col}) {
    return ApiFootballLineupPlayer(
      id: p.player.id,
      name: p.player.name,
      number: p.player.number,
      position: p.player.position,
      gridRow: row,
      gridCol: col,
    );
  }

  /// Purely a function of how much historical data was available —
  /// capped at 75% since a prediction should never claim near-certainty
  /// the way a real announcement would. Not currently shown in the UI
  /// (removed from lineup_tab.dart), but kept on the result in case it's
  /// useful again later.
  double _calculateConfidence(List<ApiFootballLineupPlayer> selected, int matchesAnalysed) {
    if (selected.length < 11 || matchesAnalysed == 0) return 0.0;
    final dataConfidence = matchesAnalysed >= 5 ? 1.0 : matchesAnalysed / 5.0;
    return (dataConfidence * 75.0).clamp(0.0, 100.0).toDouble();
  }
}

class PredictedLineupResult {
  final int teamId;
  final String teamName;
  final String formation;
  final List<ApiFootballLineupPlayer> startXI;
  final List<ApiFootballLineupPlayer> substitutes;
  final double confidence;
  final bool isOfficial;

  const PredictedLineupResult({
    required this.teamId,
    required this.teamName,
    required this.formation,
    required this.startXI,
    required this.substitutes,
    required this.confidence,
    required this.isOfficial,
  });

  factory PredictedLineupResult.insufficientData({required int teamId}) => PredictedLineupResult(
        teamId: teamId,
        teamName: '',
        formation: '',
        startXI: const [],
        substitutes: const [],
        confidence: 0,
        isOfficial: false,
      );

  bool get hasData => startXI.isNotEmpty;

  ApiFootballTeamLineup toTeamLineup() => ApiFootballTeamLineup(
        teamId: teamId,
        teamName: teamName,
        formation: formation,
        startXI: startXI,
        substitutes: substitutes,
      );
}

class _PlayerAppearance {
  final ApiFootballLineupPlayer player;
  final int starts;
  final int appearances;
  final double depthFractionSum;
  final int depthSamples;

  const _PlayerAppearance({
    required this.player,
    required this.starts,
    required this.appearances,
    this.depthFractionSum = 0,
    this.depthSamples = 0,
  });

  double get predictionScore => ((starts * 10) + appearances).toDouble();

  /// Average of this player's real historical depth across the
  /// starting matches analysed. Falls back to a coarse guess from their
  /// broad position label only if no starting-XI grid data was ever
  /// recorded for them (e.g. they've only ever appeared as a sub).
  double get averageDepthFraction => depthSamples == 0 ? _fallbackDepthFromCategory() : depthFractionSum / depthSamples;

  double _fallbackDepthFromCategory() {
    switch (positionCategory) {
      case _PositionCategory.goalkeeper:
        return 0.0;
      case _PositionCategory.defender:
        return 0.25;
      case _PositionCategory.midfielder:
        return 0.55;
      case _PositionCategory.attacker:
        return 0.85;
    }
  }

  _PositionCategory get positionCategory {
    final position = (player.position ?? '').toLowerCase();
    if (position.contains('goalkeeper') || position == 'g') return _PositionCategory.goalkeeper;
    if (position.contains('defender') || position == 'd') return _PositionCategory.defender;
    if (position.contains('midfield') || position == 'm') return _PositionCategory.midfielder;
    if (position.contains('attack') || position == 'f') return _PositionCategory.attacker;
    return _PositionCategory.attacker;
  }

  _PlayerAppearance copyWith({int? starts, int? appearances, double? depthFractionSum, int? depthSamples}) => _PlayerAppearance(
        player: player,
        starts: starts ?? this.starts,
        appearances: appearances ?? this.appearances,
        depthFractionSum: depthFractionSum ?? this.depthFractionSum,
        depthSamples: depthSamples ?? this.depthSamples,
      );
}

enum _PositionCategory { goalkeeper, defender, midfielder, attacker }

/// Parsed from a real formation string like "4-2-3-1" — each element is
/// one distinct row of players between the goalkeeper and the most
/// advanced line, in order.
class _FormationShape {
  final List<int> segments;
  final String label;
  const _FormationShape({required this.segments, required this.label});

  factory _FormationShape.parse(String formation) {
    final parts = formation.split('-').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    if (parts.isEmpty) {
      return const _FormationShape(segments: [4, 3, 3], label: '4-3-3');
    }
    return _FormationShape(segments: parts, label: formation);
  }

  int get totalOutfield => segments.fold(0, (a, b) => a + b);
}