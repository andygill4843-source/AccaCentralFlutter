import 'models.dart';

/// Pure bracket math for the knockout tournament — no Firestore access here,
/// mirroring how ScoringEngine keeps scoring logic separate from data
/// fetching. Given the current participants (and, for later rounds, their
/// live league positions for big-cup-tie detection), this returns the
/// TournamentMatch objects to create; FirestoreService is responsible for
/// actually writing them and updating the tournament's currentRoundSize.
class TournamentBracketEngine {
  TournamentBracketEngine._();

  /// Largest power of 2 that is <= n. E.g. 10 -> 8, 14 -> 8, 8 -> 8.
  static int largestPowerOfTwoAtMost(int n) {
    var power = 1;
    while (power * 2 <= n) {
      power *= 2;
    }
    return power;
  }

  /// The initial draw: splits all current members into byes (straight
  /// through to the main bracket) and preliminary-round pairings, so that
  /// exactly mainBracketSize people remain once the preliminary round
  /// resolves. If the member count is already an exact power of 2, no
  /// preliminary round is needed at all — every member is paired straight
  /// into the main bracket instead, and the preliminary/byes tier is
  /// skipped entirely.
  static List<TournamentMatch> buildInitialRound({
    required Tournament tournament,
    required List<({String id, String name})> shuffledParticipants,
    required Map<String, int> leaguePositions,
  }) {
    final n = shuffledParticipants.length;
    final mainBracketSize = largestPowerOfTwoAtMost(n);
    final preliminaryMatchCount = n - mainBracketSize;
    final now = DateTime.now();

    if (preliminaryMatchCount == 0) {
      return _pairUp(
        tournament: tournament,
        roundSize: mainBracketSize,
        participants: shuffledParticipants,
        leaguePositions: leaguePositions,
        createdAt: now,
      );
    }

    final byeCount = n - 2 * preliminaryMatchCount;
    final byeMembers = shuffledParticipants.sublist(0, byeCount);
    final preliminaryMembers = shuffledParticipants.sublist(byeCount);

    final matches = <TournamentMatch>[];
    for (final m in byeMembers) {
      // A bye is instant — nothing to play, so it's pre-resolved at the
      // moment of creation. This keeps the "has every match in this round
      // been settled" gate working identically whether a member got a bye
      // or played (and won) a real preliminary match.
      matches.add(TournamentMatch(
        tournamentId: tournament.id!,
        teamId: tournament.teamId,
        season: tournament.season,
        roundSize: 0,
        memberAId: m.id,
        memberAName: m.name,
        isBye: true,
        winnerMemberId: m.id,
        winnerName: m.name,
        createdAt: now,
      ));
    }
    matches.addAll(_pairUp(
      tournament: tournament,
      roundSize: 0,
      participants: preliminaryMembers,
      leaguePositions: leaguePositions,
      createdAt: now,
    ));
    return matches;
  }

  /// The next round after [completedRoundSize] fully resolves — pairs up
  /// each match's winner, freshly and randomly, same as every round rather
  /// than a pre-fixed bracket. Returns an empty list if [completedRoundSize]
  /// was already the Final (roundSize 2); the caller should treat that as
  /// tournament-complete rather than drawing anything further.
  static List<TournamentMatch> buildNextRound({
    required Tournament tournament,
    required int completedRoundSize,
    required List<({String id, String name})> shuffledWinners,
    required Map<String, int> leaguePositions,
  }) {
    if (completedRoundSize == 2) return [];
    final nextRoundSize = completedRoundSize == 0 ? tournament.mainBracketSize! : completedRoundSize ~/ 2;
    return _pairUp(
      tournament: tournament,
      roundSize: nextRoundSize,
      participants: shuffledWinners,
      leaguePositions: leaguePositions,
      createdAt: DateTime.now(),
    );
  }

  static List<TournamentMatch> _pairUp({
    required Tournament tournament,
    required int roundSize,
    required List<({String id, String name})> participants,
    required Map<String, int> leaguePositions,
    required DateTime createdAt,
  }) {
    final matches = <TournamentMatch>[];
    for (var i = 0; i < participants.length; i += 2) {
      final a = participants[i];
      final b = participants[i + 1];
      final posA = leaguePositions[a.id];
      final posB = leaguePositions[b.id];
      // "Big cup tie" — the two members are adjacent in the live league
      // table at the moment of this specific round's draw.
      final isBigCupTie = posA != null && posB != null && (posA - posB).abs() == 1;
      matches.add(TournamentMatch(
        tournamentId: tournament.id!,
        teamId: tournament.teamId,
        season: tournament.season,
        roundSize: roundSize,
        memberAId: a.id,
        memberAName: a.name,
        memberBId: b.id,
        memberBName: b.name,
        isBigCupTie: isBigCupTie,
        createdAt: createdAt,
      ));
    }
    return matches;
  }
}