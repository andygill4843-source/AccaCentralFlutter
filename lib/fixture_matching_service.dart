import 'dart:math';
import 'sportmonks_service.dart';

/// Bridges The UK Odds API's fixture (used when a member picks a leg) to its
/// Sportmonks equivalent (used for live scores and settlement). The two
/// providers don't share an ID scheme, so this does a best-effort match by
/// kickoff date and team name at the moment a leg is submitted.
///
/// Matching strategy:
/// 1. Fetch every Sportmonks fixture on the kickoff date (existing,
///    already-working call — no new endpoint).
/// 2. Normalise team names: lowercase, strip diacritics, strip common
///    suffixes (FC/CF/AFC/etc), apply a known-alias table.
/// 3. Score every same-day fixture on home-name similarity + away-name
///    similarity + kickoff-time proximity.
/// 4. Accept the best-scoring candidate only if it clears a minimum
///    confidence threshold — otherwise return null (same "—" fallback
///    behaviour as today) rather than guessing wrong.
/// 5. If nothing on the exact date clears the threshold, also check the
///    day before/after, in case a late-night kickoff falls on a different
///    calendar date between the two providers' timezones.
class FixtureMatchingService {
  FixtureMatchingService._();

  /// Minimum score (0-100) required before a candidate is accepted.
  /// Kept conservative on purpose — a wrong match mis-settles a leg,
  /// so it's safer to leave a fixture unmatched than to guess wrong.
  static const double _minimumMatchScore = 75.0;

  /// How close the two providers' kickoff times must be to score any
  /// points at all on the time component. Generous, since providers can
  /// occasionally disagree by a few minutes or even show a slightly
  /// different scheduled time before kickoff is finalised.
  static const Duration _maxKickoffDifference = Duration(hours: 6);

  /// Known nickname/abbreviation aliases, keyed by normalised form.
  /// Add to this whenever a new mismatch is found in practice.
  static const Map<String, String> _aliases = {
    // England — Premier League & Championship
    'man city': 'manchester city',
    'man utd': 'manchester united',
    'man united': 'manchester united',
    'spurs': 'tottenham hotspur',
    'tottenham': 'tottenham hotspur',
    'wolves': 'wolverhampton wanderers',
    'wolverhampton': 'wolverhampton wanderers',
    'nottm forest': 'nottingham forest',
    'forest': 'nottingham forest',
    'newcastle': 'newcastle united',
    'west brom': 'west bromwich albion',
    'wba': 'west bromwich albion',
    'qpr': 'queens park rangers',
    'leeds': 'leeds united',
    'norwich': 'norwich city',
    'cardiff': 'cardiff city',
    'swansea': 'swansea city',
    'sheff utd': 'sheffield united',
    'sheffield utd': 'sheffield united',
    'sheff wed': 'sheffield wednesday',
    'stoke': 'stoke city',
    'hull': 'hull city',
    'preston': 'preston north end',
    'derby': 'derby county',
    'coventry': 'coventry city',
    'ipswich': 'ipswich town',
    'blackburn': 'blackburn rovers',
    'bolton': 'bolton wanderers',
    'charlton': 'charlton athletic',
    'birmingham': 'birmingham city',
    'west ham': 'west ham united',
    'brighton': 'brighton and hove albion',
    'brighton & hove albion': 'brighton and hove albion',
    'brighton hove albion': 'brighton and hove albion',
    'bournemouth': 'afc bournemouth',

    // Spain — La Liga
    'athletic bilbao': 'athletic club',
    'atletico madrid': 'atletico de madrid',
    'atleti': 'atletico de madrid',
    'barca': 'fc barcelona',
    'barcelona': 'fc barcelona',
    'betis': 'real betis',
    'sociedad': 'real sociedad',
    'depor': 'deportivo la coruna',
    'deportivo la coruña': 'deportivo la coruna',
    'espanyol barcelona': 'espanyol',
    'rayo': 'rayo vallecano',
    'valencia cf': 'valencia',
    'sevilla fc': 'sevilla',
    'villarreal cf': 'villarreal',
    'alaves': 'deportivo alaves',
    'deportivo alavés': 'deportivo alaves',
    'osasuna': 'ca osasuna',
    'celta': 'celta de vigo',
    'celta vigo': 'celta de vigo',
    'malaga': 'malaga cf',
    'elche': 'elche cf',
    'getafe': 'getafe cf',
    'levante': 'levante ud',
    'racing santander': 'racing santander',

    // Italy — Serie A
    'inter': 'inter milan',
    'internazionale': 'inter milan',
    'milan': 'ac milan',
    'roma': 'as roma',
    'lazio': 'lazio roma',
    'napoli': 'ssc napoli',
    'fiorentina': 'fiorentina',
    'atalanta': 'atalanta',
    'monza': 'ac monza',
    'cagliari': 'cagliari calcio',
    'como': 'como 1907',
    'frosinone': 'frosinone calcio',
    'genoa': 'genoa cfc',
    'parma': 'parma calcio 1913',
    'sassuolo': 'sassuolo calcio',
    'torino': 'torino fc',
    'udinese': 'udinese calcio',
    'lecce': 'us lecce',
    'venezia': 'venezia fc',

    // Germany — Bundesliga
    'bayern': 'bayern munchen',
    'bayern munich': 'bayern munchen',
    'fc bayern munich': 'bayern munchen',
    'bayern münchen': 'bayern munchen',
    'dortmund': 'borussia dortmund',
    'bvb': 'borussia dortmund',
    'gladbach': 'borussia monchengladbach',
    'monchengladbach': 'borussia monchengladbach',
    'mönchengladbach': 'borussia monchengladbach',
    'leverkusen': 'bayer leverkusen',
    'frankfurt': 'eintracht frankfurt',
    'leipzig': 'rb leipzig',
    'rasenballsport leipzig': 'rb leipzig',
    'stuttgart': 'vfb stuttgart',
    'bremen': 'sv werder bremen',
    'werder bremen': 'sv werder bremen',
    'augsburg': 'fc augsburg',
    'schalke': 'fc schalke 04',
    'schalke 04': 'fc schalke 04',
    'hamburg': 'hamburger sv',
    'hsv': 'hamburger sv',
    'freiburg': 'sc freiburg',
    'paderborn': 'sc paderborn',
    'elversberg': 'sv elversberg',
    'hoffenheim': 'tsg hoffenheim',
    'union berlin': '1. fc union berlin',
    'koln': '1. fc koln',
    'köln': '1. fc koln',
    'cologne': '1. fc koln',
    'mainz': '1. fsv mainz 05',
  };

  /// Suffixes/prefixes stripped before comparison — these vary a lot
  /// between providers and carry no matching value once both names are
  /// tokenised.
  static const Set<String> _ignoredWords = {
    'fc', 'cf', 'afc', 'sc', 'ac', 'as', 'ss', 'ssc', 'calcio', 'club',
    'football', 'de', 'the', '1913', '1907', '04', '05',
  };

  static Future<int?> resolveSportmonksFixtureId({
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) async {
    try {
      // Try the exact kickoff date first, then adjacent days as a
      // fallback for any date-boundary/timezone edge cases.
      for (final offset in [0, -1, 1]) {
        final candidateDate = kickoff.add(Duration(days: offset));
        final fixtures = await SportmonksService.instance.fetchFixturesOnDate(candidateDate);
        final match = _findBestMatch(
          fixtures: fixtures,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoff: kickoff,
        );
        if (match != null) return match;
      }
      return null; // best-effort — a leg with no match just shows "—" on the live screen
    } catch (_) {
      return null;
    }
  }

  static int? _findBestMatch({
    required List<SportmonksFixture> fixtures,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) {
    SportmonksFixture? best;
    double bestScore = 0;

    for (final fixture in fixtures) {
      final homeSimilarity = _teamSimilarity(homeTeam, fixture.homeTeamName);
      final awaySimilarity = _teamSimilarity(awayTeam, fixture.awayTeamName);
      final kickoffScore = _kickoffSimilarity(kickoff, fixture.startingAt);

      // Team names carry the most weight; kickoff time is a tiebreaker
      // between plausible same-day candidates rather than a hard filter.
      final score = (homeSimilarity * 40) + (awaySimilarity * 40) + (kickoffScore * 20);

      if (score > bestScore) {
        bestScore = score;
        best = fixture;
      }
    }

    if (best == null || bestScore < _minimumMatchScore) return null;
    return best.id;
  }

  static double _teamSimilarity(String a, String b) {
    final canonicalA = _canonicalName(a);
    final canonicalB = _canonicalName(b);
    if (canonicalA.isEmpty || canonicalB.isEmpty) return 0;
    if (canonicalA == canonicalB) return 1;
    if (canonicalA.contains(canonicalB) || canonicalB.contains(canonicalA)) return 0.92;

    final tokensA = canonicalA.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = canonicalB.split(' ').where((t) => t.isNotEmpty).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0;

    final tokenScore = tokensA.intersection(tokensB).length / tokensA.union(tokensB).length;

    final distance = _levenshtein(canonicalA, canonicalB);
    final maxLen = max(canonicalA.length, canonicalB.length);
    final editScore = maxLen == 0 ? 0.0 : 1.0 - (distance / maxLen);

    return max(tokenScore, editScore).clamp(0.0, 1.0);
  }

  static double _kickoffSimilarity(DateTime expected, DateTime actual) {
    final difference = expected.toUtc().difference(actual.toUtc()).abs();
    if (difference > _maxKickoffDifference) return 0;
    final maxMinutes = _maxKickoffDifference.inMinutes.toDouble();
    return 1.0 - (difference.inMinutes.toDouble() / maxMinutes);
  }

  static String _canonicalName(String value) {
    var normalised = _normalise(value);
    final alias = _aliases[normalised];
    if (alias != null) normalised = _normalise(alias);

    final words = normalised.split(' ').where((w) => w.isNotEmpty && !_ignoredWords.contains(w)).toList();
    normalised = words.join(' ');

    final secondAlias = _aliases[normalised];
    if (secondAlias != null) normalised = _normalise(secondAlias);

    return normalised.trim();
  }

  static String _normalise(String value) {
    var result = value.trim().toLowerCase();
    const replacements = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'ç': 'c', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ñ': 'n',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
    };
    replacements.forEach((accented, plain) => result = result.replaceAll(accented, plain));
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  static int _levenshtein(String source, String target) {
    if (source == target) return 0;
    if (source.isEmpty) return target.length;
    if (target.isEmpty) return source.length;

    var previous = List<int>.generate(target.length + 1, (i) => i);
    for (var i = 0; i < source.length; i++) {
      final current = List<int>.filled(target.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < target.length; j++) {
        final cost = source[i] == target[j] ? 0 : 1;
        current[j + 1] = min(min(current[j] + 1, previous[j + 1] + 1), previous[j] + cost);
      }
      previous = current;
    }
    return previous[target.length];
  }
}