import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';

class SeasonSummaryScreen extends StatelessWidget {
  final SeasonSummary summary;
  const SeasonSummaryScreen({super.key, required this.summary});

  String get _shareText {
    final buffer = StringBuffer();
    buffer.writeln('📊 My ${summary.season} Acca Central Season Summary');
    buffer.writeln();
    buffer.writeln('🏅 League: ${_positionLabel(summary.leaguePosition)} of ${summary.totalMembers}');
    buffer.writeln('📈 ${summary.totalBasePoints} points | ${summary.legsWon}/${summary.legsPlayed} legs won');
    if (summary.longestWinStreak >= 3) {
      buffer.writeln('🔥 Best streak: ${summary.longestWinStreak} in a row');
    }
    if (summary.biggestWinDescription != null && summary.biggestWinOdds != null) {
      buffer.writeln('💰 Biggest win: ${summary.biggestWinDescription} @ ${decimalToFractional(summary.biggestWinOdds!)}');
    }
    if (summary.cupResult != null) {
      buffer.writeln('🏆 ${summary.cupName ?? 'Cup'}: ${summary.cupResult}');
    }
    buffer.writeln();
    buffer.writeln('Download Acca Central: https://apps.apple.com/app/acca-central');
    return buffer.toString();
  }

  String _positionLabel(int pos) {
    if (pos == 1) return '1st';
    if (pos == 2) return '2nd';
    if (pos == 3) return '3rd';
    return '${pos}th';
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open WhatsApp — is it installed?")),
        );
      }
    }
  }

  Future<void> _copyText(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary copied to clipboard.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${summary.season} Summary'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card(
              child: Column(
                children: [
                  Text(summary.memberDisplayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text(summary.season, style: TextStyle(fontSize: 14, color: AccaColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('🏅 League Position'),
            _card(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statBlock(_positionLabel(summary.leaguePosition), 'of ${summary.totalMembers}'),
                  _statBlock('${summary.totalBasePoints}', 'points'),
                  _statBlock('${summary.legsWon}/${summary.legsPlayed}', 'legs won'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('✨ Season Highlights'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summary.longestWinStreak >= 3) ...[
                    _highlightRow('🔥', 'Best winning streak', '${summary.longestWinStreak} in a row'),
                    const SizedBox(height: 8),
                  ],
                  if (summary.biggestWinDescription != null && summary.biggestWinOdds != null) ...[
                    _highlightRow('💰', 'Biggest win', '${summary.biggestWinDescription}\n@ ${decimalToFractional(summary.biggestWinOdds!)}'),
                    const SizedBox(height: 8),
                  ],
                  _highlightRow(
                    summary.leaguePosition == 1 ? '🏆' : (summary.leaguePosition <= 3 ? '🥇' : '📊'),
                    'Season record',
                    '${(summary.winRate * 100).round()}% win rate across ${summary.legsPlayed} legs',
                  ),
                  if (summary.longestWinStreak < 3 && summary.biggestWinDescription == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('No standout moments this season — but every season is a new start!', style: TextStyle(color: Colors.black54, fontSize: 13)),
                    ),
                ],
              ),
            ),
            if (summary.cupResult != null) ...[
              const SizedBox(height: 16),
              _sectionHeader('🏆 ${summary.cupName ?? 'Cup'} Summary'),
              _card(
                child: Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(summary.cupResult!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _sectionHeader('💡 Pre-Season Recommendations'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < summary.recommendations.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(summary.recommendations[i], style: const TextStyle(fontSize: 13, color: Colors.black87))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyText(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareWhatsApp(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Share on WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AccaColors.gold,
                      foregroundColor: AccaColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AccaColors.gold, width: 1.5),
        ),
        child: child,
      );

  Widget _statBlock(String value, String label) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      );

  Widget _highlightRow(String emoji, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
              ],
            ),
          ),
        ],
      );
}