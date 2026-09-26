import 'package:flutter/material.dart';
import 'api_football_service.dart';
import 'firestore_service.dart';
import 'predicted_lineup_service.dart';

class LineupTab extends StatefulWidget {
  final int fixtureId;
  final int homeTeamId;
  final String homeTeamName;
  final int awayTeamId;
  final String awayTeamName;
  final DateTime kickoff;
  const LineupTab({
    super.key,
    required this.fixtureId,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.kickoff,
  });

  @override
  State<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends State<LineupTab> {
  static const _officialCheckThrottle = Duration(minutes: 10);

  ApiFootballTeamLineup? homeTeam;
  ApiFootballTeamLineup? awayTeam;
  bool isOfficial = false;
  bool isLoading = true;
  String? errorMessage;
  bool showingHome = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  bool get _withinOfficialLineupWindow =>
      DateTime.now().isAfter(widget.kickoff.subtract(const Duration(minutes: 90)));

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final cache = await FirestoreService.instance.fetchLineupCache(widget.fixtureId);

      final isStalePrediction = cache != null &&
          !cache.isOfficial &&
          cache.predictionVersion != kPredictedLineupAlgorithmVersion;

      if (cache != null && cache.isOfficial) {
        _applyCache(cache);
        return;
      }

      if (cache != null && !isStalePrediction) {
        final dueForRecheck = _withinOfficialLineupWindow &&
            (cache.lastOfficialCheckAt == null ||
                DateTime.now().difference(cache.lastOfficialCheckAt!) > _officialCheckThrottle);

        if (dueForRecheck) {
          final official = await _tryFetchOfficial();
          if (official != null) {
            await FirestoreService.instance.saveLineupCache(official);
            _applyCache(official);
            return;
          }
          await FirestoreService.instance.touchLineupCacheOfficialCheck(widget.fixtureId);
        }

        _applyCache(cache);
        return;
      }

      // No usable cache — either genuinely nothing cached, or the cached
      // prediction is from an old algorithm version. Either way, check
      // official first (cheap), then fall back to a fresh prediction.
      if (_withinOfficialLineupWindow) {
        final official = await _tryFetchOfficial();
        if (official != null) {
          await FirestoreService.instance.saveLineupCache(official);
          _applyCache(official);
          return;
        }
      }

      final service = PredictedLineupService();
      final results = await Future.wait([
        service.predictLineup(teamId: widget.homeTeamId, fixtureId: widget.fixtureId),
        service.predictLineup(teamId: widget.awayTeamId, fixtureId: widget.fixtureId),
      ]);
      final homeResult = results[0];
      final awayResult = results[1];

      final predicted = LineupCache(
        fixtureId: widget.fixtureId,
        isOfficial: false,
        home: homeResult.hasData ? homeResult.toTeamLineup() : null,
        away: awayResult.hasData ? awayResult.toTeamLineup() : null,
        homeConfidence: homeResult.confidence,
        awayConfidence: awayResult.confidence,
        computedAt: DateTime.now(),
        lastOfficialCheckAt: _withinOfficialLineupWindow ? DateTime.now() : null,
        predictionVersion: kPredictedLineupAlgorithmVersion,
      );
      await FirestoreService.instance.saveLineupCache(predicted);
      _applyCache(predicted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load the line-up: $e";
        isLoading = false;
      });
    }
  }

  /// Single fetchLineups call covers both teams — cheap, always worth
  /// trying before assuming a prediction is still needed.
  Future<LineupCache?> _tryFetchOfficial() async {
    final lineups = await ApiFootballService.instance.fetchLineups(widget.fixtureId);
    if (!lineups.isAvailable) return null;
    return LineupCache(
      fixtureId: widget.fixtureId,
      isOfficial: true,
      home: lineups.home,
      away: lineups.away,
      computedAt: DateTime.now(),
    );
  }

  void _applyCache(LineupCache cache) {
    if (!mounted) return;
    setState(() {
      homeTeam = cache.home;
      awayTeam = cache.away;
      isOfficial = cache.isOfficial;
      isLoading = false;
    });
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

    final team = showingHome ? homeTeam : awayTeam;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(widget.homeTeamName, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: false, label: Text(widget.awayTeamName, overflow: TextOverflow.ellipsis)),
            ],
            selected: {showingHome},
            onSelectionChanged: (s) => setState(() => showingHome = s.first),
          ),
        ),
        if (team != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(isOfficial ? Icons.verified : Icons.auto_graph, size: 16, color: isOfficial ? Colors.greenAccent : Colors.amberAccent),
                const SizedBox(width: 6),
                Text(
                  isOfficial ? 'Confirmed Lineup' : 'Predicted Lineup',
                  style: TextStyle(color: isOfficial ? Colors.greenAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        Expanded(child: team == null ? _noDataMessage() : _pitchAndSubs(team)),
      ],
    );
  }

  Widget _noDataMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "Not enough recent match data to predict this team's line-up, and the official line-up isn't out yet.",
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _pitchAndSubs(ApiFootballTeamLineup team) {
    if (team.startXI.isEmpty) {
      return const Center(child: Text('No starting XI available.', style: TextStyle(color: Colors.white54)));
    }
    final rows = team.startXI.map((p) => p.gridRow).toSet().toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(team.formation, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(team.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 0.62,
            child: CustomPaint(
              painter: _PitchPainter(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final children = <Widget>[];
                  for (var i = 0; i < rows.length; i++) {
                    final row = rows[i];
                    final playersInRow = team.startXI.where((p) => p.gridRow == row).toList()
                      ..sort((a, b) => a.gridCol.compareTo(b.gridCol));
                    final dy = rows.length == 1 ? 0.5 : i / (rows.length - 1);
                    for (var j = 0; j < playersInRow.length; j++) {
                      final dx = playersInRow.length == 1 ? 0.5 : (j + 1) / (playersInRow.length + 1);
                      children.add(Positioned(
                        left: dx * constraints.maxWidth - 26,
                        top: (0.06 + dy * 0.86) * constraints.maxHeight - 26,
                        child: _playerNode(playersInRow[j]),
                      ));
                    }
                  }
                  return Stack(children: children);
                },
              ),
            ),
          ),
          if (team.substitutes.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('SUBSTITUTES', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final p in team.substitutes) _substituteNode(p)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _playerNode(ApiFootballLineupPlayer player) {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.network(
                player.photoUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person, color: Colors.black26, size: 26),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
            child: Text(
              player.name.split(' ').last,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _substituteNode(ApiFootballLineupPlayer player) {
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.network(
                player.photoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person, color: Colors.black26, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            player.name.split(' ').last,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF1E4B3D), Color(0xFF0F241D)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), linePaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.16, linePaint);

    final boxWidth = size.width * 0.5;
    final boxHeight = size.height * 0.1;
    canvas.drawRect(Rect.fromLTWH((size.width - boxWidth) / 2, 0, boxWidth, boxHeight), linePaint);
    canvas.drawRect(Rect.fromLTWH((size.width - boxWidth) / 2, size.height - boxHeight, boxWidth, boxHeight), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}