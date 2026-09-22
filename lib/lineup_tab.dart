import 'package:flutter/material.dart';
import 'api_football_service.dart';

class LineupTab extends StatefulWidget {
  final int fixtureId;
  final String homeTeamName;
  final String awayTeamName;
  const LineupTab({
    super.key,
    required this.fixtureId,
    required this.homeTeamName,
    required this.awayTeamName,
  });

  @override
  State<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends State<LineupTab> {
  ApiFootballLineups? lineups;
  bool isLoading = true;
  String? errorMessage;
  bool showingHome = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ApiFootballService.instance.fetchLineups(widget.fixtureId);
      if (!mounted) return;
      setState(() {
        lineups = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load the line-up: $e";
        isLoading = false;
      });
    }
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
    if (lineups == null || !lineups!.isAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Line-ups haven't been announced for this fixture yet — they're usually published closer to kickoff.",
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final team = showingHome ? lineups!.home! : lineups!.away!;

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
        Expanded(child: _pitch(team)),
      ],
    );
  }

  Widget _pitch(ApiFootballTeamLineup team) {
    if (team.startXI.isEmpty) {
      return const Center(child: Text('No starting XI available.', style: TextStyle(color: Colors.white54)));
    }
    final rows = team.startXI.map((p) => p.gridRow).toSet().toList()..sort();

    return Padding(
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
          Expanded(
            child: AspectRatio(
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
          ),
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
}

/// Simple pitch markings — a green gradient, halfway line, centre circle,
/// and a goal box at each end.
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