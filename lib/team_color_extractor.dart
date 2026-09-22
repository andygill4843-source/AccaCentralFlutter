import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Extracts each team's own predominant crest colour, ranked by how much
/// of the image it covers, skipping anything white/near-white — since
/// most crests are drawn on a white or near-white background (or have
/// heavy white detailing), a naive "most common colour" would otherwise
/// return white for almost every team.
///
/// Caveat worth knowing: this is genuinely a best-effort heuristic, not
/// a guaranteed match to a club's "real" brand colour — a crest with
/// heavy gold trim, multiple colours of similar size, or unusual
/// artwork can still extract to something that doesn't read as that
/// club's identity at a glance. There's no verification against a
/// canonical source here; it's purely "biggest non-white area in this
/// specific image".
class TeamColorExtractor {
  TeamColorExtractor._();

  // Cached per crest URL for the life of the app session — a crest's
  // colour never changes, so there's no reason to re-extract it every
  // time a card using that team renders.
  static final Map<String, Color?> _cache = {};
  static final Map<String, Future<Color?>> _inFlight = {};

  /// Anything with luminance above this is treated as "white enough to
  /// skip" — covers pure white backgrounds and most white detailing.
  static const double _whiteLuminanceThreshold = 0.85;

  static Future<Color?> extract(String crestUrl) {
    if (crestUrl.isEmpty) return Future.value(null);
    if (_cache.containsKey(crestUrl)) return Future.value(_cache[crestUrl]);
    if (_inFlight.containsKey(crestUrl)) return _inFlight[crestUrl]!;
    final future = _extractUncached(crestUrl);
    _inFlight[crestUrl] = future;
    return future;
  }

  static Future<Color?> _extractUncached(String crestUrl) async {
    try {
      final generator = await PaletteGenerator.fromImageProvider(
        NetworkImage(crestUrl),
        maximumColorCount: 20,
      );
      // Every detected swatch, ranked by how much of the image it
      // actually covers — this is the "predominant colour" ranking.
      final swatches = generator.paletteColors.toList()
        ..sort((a, b) => b.population.compareTo(a.population));
      for (final swatch in swatches) {
        if (swatch.color.computeLuminance() <= _whiteLuminanceThreshold) {
          _cache[crestUrl] = swatch.color;
          _inFlight.remove(crestUrl);
          return swatch.color;
        }
      }
      // Every detected colour was white/near-white — nothing usable.
      _cache[crestUrl] = null;
      _inFlight.remove(crestUrl);
      return null;
    } catch (_) {
      _cache[crestUrl] = null;
      _inFlight.remove(crestUrl);
      return null;
    }
  }
}