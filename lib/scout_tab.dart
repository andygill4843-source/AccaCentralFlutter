import 'package:flutter/material.dart';
import 'api_football_service.dart';
import 'poisson_predictor.dart';
import 'main.dart'; // for AccaColors

class ScoutTab extends StatefulWidget {
  final int fixtureId;
  const ScoutTab({super.key, required this.fixtureId});

  @override
  State<ScoutTab> createState() => _ScoutTabState();
}

/// A team's real last-5 results, derived from actual fixtures rather
/// than API-Football's last_5.form field — that field is a composite
/// percentage, not a W/D/L sequence.
class _TeamRecentForm {
  final String teamName;
  final List<String> resultsMostRecentFirst; // 'W' / 'D' / 'L'
  const _TeamRecentForm({required this.teamName, required this.resultsMostRecentFirst});
  int get wins => resultsMostRecentFirst.where((r) => r == 'W').length;
}

class _ScoutTabState extends State<ScoutTab> {
  ApiFootballPredictionData? data;
  _TeamRecentForm? homeForm;
  _TeamRecentForm? awayForm;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ApiFootballService.instance.fetchPredictions(widget.fixtureId);
      if (result == null) {
        if (!mounted) return;
        setState(() {
          data = null;
          isLoading = false;
        });
        return;
      }

      // Real last-5 fixtures per team, fetched separately — derives an
      // actual W/D/L sequence, which the predictions endpoint itself
      // doesn't provide directly.
      final homeFixtures = await ApiFootballService.instance.fetchLastFixtures(result.home.teamId);
      final awayFixtures = await ApiFootballService.instance.fetchLastFixtures(result.away.teamId);

      if (!mounted) return;
      setState(() {
        data = result;
        homeForm = _TeamRecentForm(
          teamName: result.home.teamName,
          resultsMostRecentFirst: homeFixtures.map((f) => _resultFor(f, result.home.teamId)).toList(),
        );
        awayForm = _TeamRecentForm(
          teamName: result.away.teamName,
          resultsMostRecentFirst: awayFixtures.map((f) => _resultFor(f, result.away.teamId)).toList(),
        );
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load stats: $e";
        isLoading = false;
      });
    }
  }

  /// W/D/L for [teamId] in a given completed fixture, based on which
  /// side they played and the final score.
  String _resultFor(ApiFootballFixture fixture, int teamId) {
    if (fixture.homeGoals == null || fixture.awayGoals == null) return 'D'; // shouldn't happen for a completed fixture
    final isHome = fixture.homeTeamId == teamId;
    final teamGoals = isHome ? fixture.homeGoals! : fixture.awayGoals!;
    final opponentGoals = isHome ? fixture.awayGoals! : fixture.homeGoals!;
    if (teamGoals > opponentGoals) return 'W';
    if (teamGoals < opponentGoals) return 'L';
    return 'D';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (data == null) {
      return const Center(child: Text('No stats available for this fixture.', style: TextStyle(color: Colors.white70)));
    }

    final home = data!.home;
    final away = data!.away;
    final prediction = PoissonPrediction.compute(
      homeAvgScored: home.goalsForAvg,
      homeAvgConceded: home.goalsAgainstAvg,
      awayAvgScored: away.goalsForAvg,
      awayAvgConceded: away.goalsAgainstAvg,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          title: 'WHO WILL WIN?',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _resultRing('W', prediction.homeWinPercent, AccaColors.win, home.teamName),
              _resultRing('D', prediction.drawPercent, Colors.grey, 'Draw'),
              _resultRing('L', prediction.awayWinPercent, AccaColors.loss, away.teamName),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'GOALS',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statRing(prediction.over15Percent, 'Over 1.5'),
              _statRing(prediction.over25Percent, 'Over 2.5'),
              _statRing(prediction.bttsPercent, 'BTTS'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'LAST 5 GAMES',
          child: Column(
            children: [
              if (homeForm != null) _teamFormRow(homeForm!),
              const SizedBox(height: 10),
              if (awayForm != null) _teamFormRow(awayForm!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'GOALS SCORED / CONCEDED (LAST 5 AVG)',
          child: Column(
            children: [
              _statCompareRow(home.goalsForAvg.toStringAsFixed(1), away.goalsForAvg.toStringAsFixed(1), 'Scored'),
              const SizedBox(height: 8),
              _statCompareRow(home.goalsAgainstAvg.toStringAsFixed(1), away.goalsAgainstAvg.toStringAsFixed(1), 'Conceded'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'HEAD TO HEAD (LAST 5)',
          child: data!.h2h.isEmpty
              ? const Text('No previous meetings on record.', style: TextStyle(color: Colors.white54, fontSize: 13))
              : Column(
                  children: [for (final result in data!.h2h) _h2hRow(result)],
                ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A24), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _resultRing(String letter, double percent, Color color, String label) {
    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              CircleAvatar(radius: 18, backgroundColor: color, child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 76,
          child: Text(
            '$label ${percent.round()}%',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _statRing(double percent, String label) {
    return Column(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(AccaColors.gold),
                ),
              ),
              Text('${percent.round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _resultDot(String r) {
    final color = r == 'W' ? AccaColors.win : (r == 'L' ? AccaColors.loss : Colors.grey);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 22,
      height: 22,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _teamFormRow(_TeamRecentForm team) {
    final results = team.resultsMostRecentFirst;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(team.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: results.isEmpty
              ? const Text('—', style: TextStyle(color: Colors.white38))
              : Row(children: [for (final r in results) _resultDot(r)]),
        ),
        if (results.isNotEmpty)
          Text('${team.wins}/${results.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _statCompareRow(String homeValue, String awayValue, String metricLabel) {
    return Row(
      children: [
        Expanded(child: Text(homeValue, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center)),
        SizedBox(width: 90, child: Text(metricLabel, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        Expanded(child: Text(awayValue, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _h2hRow(ApiFootballH2HResult result) {
    final dateStr = '${result.date.day.toString().padLeft(2, '0')}/${result.date.month.toString().padLeft(2, '0')}/${(result.date.year % 100).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${result.homeTeam} ${result.scoreLabel} ${result.awayTeam}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}