import 'package:flutter/material.dart';
import 'team_color_extractor.dart';

class FixtureGradients {
  FixtureGradients._();
  static const List<List<Color>> _palette = [
    [Color(0xFF3D2E6B), Color(0xFF1B1338)],
    [Color(0xFF1E4B3D), Color(0xFF0F241D)],
    [Color(0xFF1E3A5F), Color(0xFF0F1F33)],
    [Color(0xFF5C2E4B), Color(0xFF2B1524)],
    [Color(0xFF4B3B1E), Color(0xFF241C0F)],
  ];
  static List<Color> forFixtureId(int fixtureId) =>
      _palette[fixtureId.abs() % _palette.length];
}

class FixtureHeaderCard extends StatefulWidget {
  final int fixtureId;
  final String homeLogo;
  final String awayLogo;
  final String homeName;
  final String awayName;
  final bool isLive;
  final Widget centerContent;
  /// True when this header stands alone (no FixtureCardFooter below it) —
  /// rounds all four corners itself rather than only the top, so no
  /// outer ClipRRect is needed around it.
  final bool roundAllCorners;

  const FixtureHeaderCard({
    super.key,
    required this.fixtureId,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeName,
    required this.awayName,
    required this.isLive,
    required this.centerContent,
    this.roundAllCorners = false,
  });

  @override
  State<FixtureHeaderCard> createState() => _FixtureHeaderCardState();
}

class _FixtureHeaderCardState extends State<FixtureHeaderCard> {
  Color? _homeColor;
  Color? _awayColor;

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  @override
  void didUpdateWidget(covariant FixtureHeaderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeLogo != widget.homeLogo || oldWidget.awayLogo != widget.awayLogo) {
      _homeColor = null;
      _awayColor = null;
      _loadColors();
    }
  }

  Future<void> _loadColors() async {
    final results = await Future.wait([
      TeamColorExtractor.extract(widget.homeLogo),
      TeamColorExtractor.extract(widget.awayLogo),
    ]);
    if (!mounted) return;
    setState(() {
      _homeColor = results[0];
      _awayColor = results[1];
    });
  }

  Color _darken(Color c) => Color.lerp(c, const Color(0xFF14141C), 0.72)!;

  Widget _crest(String url) {
    if (url.isEmpty) {
      return const CircleAvatar(
        radius: 30,
        backgroundColor: Colors.white24,
        child: Icon(Icons.shield, color: Colors.white54),
      );
    }
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(Icons.shield, color: Colors.black26),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = FixtureGradients.forFixtureId(widget.fixtureId);
    final gradientColors = [
      _homeColor != null ? _darken(_homeColor!) : fallback[0],
      _awayColor != null ? _darken(_awayColor!) : fallback[1],
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: widget.roundAllCorners
            ? const BorderRadius.all(Radius.circular(16))
            : const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          if (widget.isLive) ...[
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam, color: Colors.redAccent, size: 14),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _crest(widget.homeLogo),
                    const SizedBox(height: 6),
                    Text(widget.homeName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: widget.centerContent,
              ),
              Expanded(
                child: Column(
                  children: [
                    _crest(widget.awayLogo),
                    const SizedBox(height: 6),
                    Text(widget.awayName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FixtureCardFooter extends StatelessWidget {
  final Widget child;
  const FixtureCardFooter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: child,
    );
  }
}

Widget fixtureStatusChip(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
  );
}