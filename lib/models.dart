// Direct translation of Models.swift — same fields, same logic.
class Team {
  final String? id;
  final String name;
  final String managerId;
  final List<String> memberIds;
  final String inviteCode;
  final DateTime createdAt;
  final String season;
  final String? activeGameWeekId;
  Team({
    this.id,
    required this.name,
    required this.managerId,
    required this.memberIds,
    required this.inviteCode,
    required this.createdAt,
    required this.season,
    this.activeGameWeekId,
  });
  factory Team.fromMap(String id, Map<String, dynamic> map) {
    return Team(
      id: id,
      name: map['name'],
      managerId: map['managerId'],
      memberIds: List<String>.from(map['memberIds']),
      inviteCode: map['inviteCode'],
      createdAt: map['createdAt'].toDate(),
      season: map['season'],
      activeGameWeekId: map['activeGameWeekId'], // absent on older docs — reads as null, that's fine
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'managerId': managerId,
      'memberIds': memberIds,
      'inviteCode': inviteCode,
      'createdAt': createdAt,
      'season': season,
      'activeGameWeekId': activeGameWeekId,
    };
  }
}
class AppUser {
  final String? id;
  final String username;
  final String displayName;
  final String email;
  final List<String> teamIds;
  final String? fcmToken;
  final DateTime createdAt;
  AppUser({
    this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.teamIds,
    this.fcmToken,
    required this.createdAt,
  });
  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      username: map['username'],
      displayName: map['displayName'],
      email: map['email'],
      teamIds: List<String>.from(map['teamIds'] ?? []),
      fcmToken: map['fcmToken'],
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'displayName': displayName,
      'email': email,
      'teamIds': teamIds,
      'fcmToken': fcmToken,
      'createdAt': createdAt,
    };
  }
}
enum MemberRole { manager, squadMember }
extension MemberRoleValue on MemberRole {
  String get value => this == MemberRole.manager ? 'manager' : 'squad_member';
  static MemberRole fromValue(String? value) {
    return value == 'manager' ? MemberRole.manager : MemberRole.squadMember;
  }
}
class Member {
  final String? id;
  final String userId;
  final String displayName;
  final String teamId;
  final DateTime joinedAt;
  final MemberRole role;
  Member({
    this.id,
    required this.userId,
    required this.displayName,
    required this.teamId,
    required this.joinedAt,
    this.role = MemberRole.squadMember,
  });
  factory Member.fromMap(String id, Map<String, dynamic> map) {
    return Member(
      id: id,
      userId: map['userId'],
      displayName: map['displayName'],
      teamId: map['teamId'],
      joinedAt: map['joinedAt'].toDate(),
      role: MemberRoleValue.fromValue(map['role']),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'teamId': teamId,
      'joinedAt': joinedAt,
      'role': role.value,
    };
  }
}
class GameWeek {
  final String? id;
  final String teamId;
  final int weekNumber;
  final DateTime startDate;
  final DateTime endDate;
  final bool isSettled;
  final String? selectedBookmaker;
  final double? combinedOdds;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime deadline;
  final String season;
  GameWeek({
    this.id,
    required this.teamId,
    required this.weekNumber,
    required this.startDate,
    required this.endDate,
    required this.isSettled,
    this.selectedBookmaker,
    this.combinedOdds,
    this.isLocked = false,
    DateTime? createdAt,
    DateTime? deadline,
    required this.season,
  })  : createdAt = createdAt ?? startDate,
        deadline = deadline ?? startDate; // fallback for older gameweeks without a real deadline set
  factory GameWeek.fromMap(String id, Map<String, dynamic> map) {
    return GameWeek(
      id: id,
      teamId: map['teamId'],
      weekNumber: map['weekNumber'],
      startDate: map['startDate'].toDate(),
      endDate: map['endDate'].toDate(),
      isSettled: map['isSettled'],
      selectedBookmaker: map['selectedBookmaker'],
      combinedOdds: (map['combinedOdds'] as num?)?.toDouble(),
      isLocked: map['isLocked'] ?? false,
      createdAt: (map['createdAt'] as dynamic)?.toDate(),
      deadline: (map['deadline'] as dynamic)?.toDate(),
      season: map['season'] ?? 'Unknown Season',
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'weekNumber': weekNumber,
      'startDate': startDate,
      'endDate': endDate,
      'isSettled': isSettled,
      'selectedBookmaker': selectedBookmaker,
      'combinedOdds': combinedOdds,
      'isLocked': isLocked,
      'deadline': deadline,
      'season': season,
    };
  }
}
enum LegOutcome { pending, won, lost, void_ }
extension LegOutcomeValue on LegOutcome {
  String get value {
    switch (this) {
      case LegOutcome.pending: return 'pending';
      case LegOutcome.won: return 'won';
      case LegOutcome.lost: return 'lost';
      case LegOutcome.void_: return 'void';
    }
  }
  static LegOutcome fromValue(String value) {
    switch (value) {
      case 'won': return LegOutcome.won;
      case 'lost': return LegOutcome.lost;
      case 'void': return LegOutcome.void_;
      default: return LegOutcome.pending;
    }
  }
}
enum BetType {
  matchWinner,
  bothTeamsToScore,
  overUnderGoals,
  drawNoBet,
  handicap,
  correctScore,
  anytimeScorer,
  doubleChance,
  halfTimeFullTime,
  teamTotals,
  bttsYesOverCombo,
  bttsYesUnderCombo,
  bttsNoOverCombo,
  bttsNoUnderCombo,
  other,
}
extension BetTypeValue on BetType {
  String get displayName {
    switch (this) {
      case BetType.matchWinner: return 'Match Winner';
      case BetType.bothTeamsToScore: return 'Both Teams to Score';
      case BetType.overUnderGoals: return 'Over/Under Goals';
      case BetType.drawNoBet: return 'Draw No Bet';
      case BetType.handicap: return 'Handicap';
      case BetType.correctScore: return 'Correct Score';
      case BetType.anytimeScorer: return 'Anytime Goalscorer';
      case BetType.doubleChance: return 'Double Chance';
      case BetType.halfTimeFullTime: return 'Half Time / Full Time';
      case BetType.teamTotals: return 'Team Goals Over/Under';
      case BetType.bttsYesOverCombo: return 'BTTS & Over 2.5 (Estimate)';
      case BetType.bttsYesUnderCombo: return 'BTTS & Under 2.5 (Estimate)';
      case BetType.bttsNoOverCombo: return 'No BTTS & Over 2.5 (Estimate)';
      case BetType.bttsNoUnderCombo: return 'No BTTS & Under 2.5 (Estimate)';
      case BetType.other: return 'Other';
    }
  }
  static BetType fromDisplayName(String name) {
    return BetType.values.firstWhere(
      (t) => t.displayName == name,
      orElse: () => BetType.other,
    );
  }
}
class AccumulatorLeg {
  final String? id;
  final String gameWeekId;
  final String teamId;
  final String memberId;
  final String fixtureId;
  final String fixtureDescription;
  final DateTime kickoff;
  final BetType betType;
  final String selectionDescription;
  final double decimalOddsAtSelection;
  final String bookmaker;
  final Map<String, double>? bookmakerPrices;
  final int? sportmonksFixtureId;
  final LegOutcome outcome;
  final DateTime submittedAt;
  final bool physioProtected;
  /// Set when this leg was submitted as part of a tournament-linked
  /// gameweek — links back to the specific TournamentMatch it counts
  /// toward. Null for an ordinary (non-tournament) leg.
  final String? tournamentMatchId;
  /// True for the secondary pick in a tournament round. Secondary legs
  /// never feed the main league table or the odds-selection screen — only
  /// the primary leg does. Always false outside a tournament context.
  final bool isSecondaryTournamentLeg;
  /// API Football numeric fixture ID — used for live score polling and
  /// odds fetching from both API Football and the Odds API.
  /// Null for legs submitted before this field was added, or where the
  /// fixture could only be matched by team name.
  final int? apiFootballFixtureId;
  /// API Football league ID for the fixture — used to filter live polling
  /// requests to only the leagues that have pending legs this gameweek.
  final int? apiFootballLeagueId;
  AccumulatorLeg({
    this.id,
    required this.gameWeekId,
    required this.teamId,
    required this.memberId,
    required this.fixtureId,
    required this.fixtureDescription,
    required this.kickoff,
    required this.betType,
    required this.selectionDescription,
    required this.decimalOddsAtSelection,
    required this.bookmaker,
    this.bookmakerPrices,
    this.sportmonksFixtureId,
    required this.outcome,
    required this.submittedAt,
    this.physioProtected = false,
    this.tournamentMatchId,
    this.isSecondaryTournamentLeg = false,
    this.apiFootballFixtureId,
    this.apiFootballLeagueId,
  });
  int get basePoints => outcome == LegOutcome.won ? 3 : 0;
  double get weightedPoints {
    if (outcome != LegOutcome.won) return 0;
    return (decimalOddsAtSelection - 1.0) * 3.0;
  }
  factory AccumulatorLeg.fromMap(String id, Map<String, dynamic> map) {
    return AccumulatorLeg(
      id: id,
      gameWeekId: map['gameWeekId'],
      teamId: map['teamId'],
      memberId: map['memberId'],
      fixtureId: map['fixtureId'],
      fixtureDescription: map['fixtureDescription'],
      kickoff: map['kickoff'].toDate(),
      betType: BetTypeValue.fromDisplayName(map['betType']),
      selectionDescription: map['selectionDescription'],
      decimalOddsAtSelection: (map['decimalOddsAtSelection'] as num).toDouble(),
      bookmaker: map['bookmaker'],
      bookmakerPrices: (map['bookmakerPrices'] as Map?)?.map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
      sportmonksFixtureId: map['sportmonksFixtureId'],
      outcome: LegOutcomeValue.fromValue(map['outcome']),
      submittedAt: map['submittedAt'].toDate(),
      physioProtected: map['physioProtected'] ?? false,
      tournamentMatchId: map['tournamentMatchId'],
      isSecondaryTournamentLeg: map['isSecondaryTournamentLeg'] ?? false,
      apiFootballFixtureId: map['apiFootballFixtureId'] as int?,
      apiFootballLeagueId: map['apiFootballLeagueId'] as int?,
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'gameWeekId': gameWeekId,
      'teamId': teamId,
      'memberId': memberId,
      'fixtureId': fixtureId,
      'fixtureDescription': fixtureDescription,
      'kickoff': kickoff,
      'betType': betType.displayName,
      'selectionDescription': selectionDescription,
      'decimalOddsAtSelection': decimalOddsAtSelection,
      'bookmaker': bookmaker,
      'bookmakerPrices': bookmakerPrices,
      'sportmonksFixtureId': sportmonksFixtureId,
      'outcome': outcome.value,
      'submittedAt': submittedAt,
      'physioProtected': physioProtected,
      'tournamentMatchId': tournamentMatchId,
      'isSecondaryTournamentLeg': isSecondaryTournamentLeg,
      'apiFootballFixtureId': apiFootballFixtureId,
      'apiFootballLeagueId': apiFootballLeagueId,
    };
  }
}
// ============================================================
// SEASON SUMMARY
// ============================================================
class SeasonSummary {
  final String? id;
  final String teamId;
  final String memberId;
  final String memberDisplayName;
  final String season;
  final int leaguePosition;
  final int totalMembers;
  final int totalBasePoints;
  final double totalWeightedPoints;
  final int legsPlayed;
  final int legsWon;
  final int longestWinStreak;
  final String? biggestWinDescription; // e.g. "Arsenal to win at 5/1"
  final double? biggestWinOdds;
  final String? cupName;
  final String? cupResult; // e.g. "Reached the Semi-Final", "Champion 🏆"
  final List<String> recommendations;
  final DateTime createdAt;
  SeasonSummary({
    this.id,
    required this.teamId,
    required this.memberId,
    required this.memberDisplayName,
    required this.season,
    required this.leaguePosition,
    required this.totalMembers,
    required this.totalBasePoints,
    required this.totalWeightedPoints,
    required this.legsPlayed,
    required this.legsWon,
    required this.longestWinStreak,
    this.biggestWinDescription,
    this.biggestWinOdds,
    this.cupName,
    this.cupResult,
    required this.recommendations,
    required this.createdAt,
  });
  double get winRate => legsPlayed == 0 ? 0 : legsWon / legsPlayed;
  factory SeasonSummary.fromMap(String id, Map<String, dynamic> map) {
    return SeasonSummary(
      id: id,
      teamId: map['teamId'],
      memberId: map['memberId'],
      memberDisplayName: map['memberDisplayName'] ?? 'Unknown',
      season: map['season'] ?? '',
      leaguePosition: map['leaguePosition'] ?? 0,
      totalMembers: map['totalMembers'] ?? 0,
      totalBasePoints: map['totalBasePoints'] ?? 0,
      totalWeightedPoints: (map['totalWeightedPoints'] as num?)?.toDouble() ?? 0,
      legsPlayed: map['legsPlayed'] ?? 0,
      legsWon: map['legsWon'] ?? 0,
      longestWinStreak: map['longestWinStreak'] ?? 0,
      biggestWinDescription: map['biggestWinDescription'],
      biggestWinOdds: (map['biggestWinOdds'] as num?)?.toDouble(),
      cupName: map['cupName'],
      cupResult: map['cupResult'],
      recommendations: List<String>.from(map['recommendations'] ?? []),
      createdAt: (map['createdAt'] as dynamic).toDate(),
    );
  }
  Map<String, dynamic> toMap() => {
    'teamId': teamId,
    'memberId': memberId,
    'memberDisplayName': memberDisplayName,
    'season': season,
    'leaguePosition': leaguePosition,
    'totalMembers': totalMembers,
    'totalBasePoints': totalBasePoints,
    'totalWeightedPoints': totalWeightedPoints,
    'legsPlayed': legsPlayed,
    'legsWon': legsWon,
    'longestWinStreak': longestWinStreak,
    'biggestWinDescription': biggestWinDescription,
    'biggestWinOdds': biggestWinOdds,
    'cupName': cupName,
    'cupResult': cupResult,
    'recommendations': recommendations,
    'createdAt': createdAt,
  };
}

// ============================================================
// FIXTURE ODDS CACHE
// ============================================================
/// Cached odds for a fixture, stored in Firestore after the first user
/// taps it. Holds per-bookmaker odds from both API Football (Bet365)
/// and The Odds API (Paddy Power, Ladbrokes, William Hill, Sky Bet, Coral),
/// plus pre-computed best odds across all 6 bookmakers per market.
class FixtureOddsCache {
  final String? id;
  final int apiFootballFixtureId;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoff;
  final int apiFootballLeagueId;
  final String leagueKey; // e.g. 'soccer_epl'
  // bookmakerKey → marketName → list of {value, odd}
  final Map<String, Map<String, List<Map<String, dynamic>>>> bookmakerOdds;
  // marketName → list of {value, odd, bookmakerKey} — best across all bookmakers
  final Map<String, List<Map<String, dynamic>>> bestOdds;
  final DateTime fetchedAt;
  FixtureOddsCache({
    this.id,
    required this.apiFootballFixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.apiFootballLeagueId,
    required this.leagueKey,
    required this.bookmakerOdds,
    required this.bestOdds,
    required this.fetchedAt,
  });
  factory FixtureOddsCache.fromMap(String id, Map<String, dynamic> map) {
    Map<String, Map<String, List<Map<String, dynamic>>>> parseBookmakerOdds(
        dynamic raw) {
      final result = <String, Map<String, List<Map<String, dynamic>>>>{};
      if (raw is Map) {
        for (final bmEntry in raw.entries) {
          final markets = <String, List<Map<String, dynamic>>>{};
          if (bmEntry.value is Map) {
            for (final mEntry in (bmEntry.value as Map).entries) {
              markets[mEntry.key as String] = (mEntry.value as List)
                  .map((v) => Map<String, dynamic>.from(v as Map))
                  .toList();
            }
          }
          result[bmEntry.key as String] = markets;
        }
      }
      return result;
    }
    Map<String, List<Map<String, dynamic>>> parseBestOdds(dynamic raw) {
      final result = <String, List<Map<String, dynamic>>>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          result[entry.key as String] = (entry.value as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
        }
      }
      return result;
    }
    return FixtureOddsCache(
      id: id,
      apiFootballFixtureId: map['apiFootballFixtureId'] as int,
      homeTeam: map['homeTeam'] as String,
      awayTeam: map['awayTeam'] as String,
      kickoff: (map['kickoff'] as dynamic).toDate(),
      apiFootballLeagueId: map['apiFootballLeagueId'] as int,
      leagueKey: map['leagueKey'] as String,
      bookmakerOdds: parseBookmakerOdds(map['bookmakerOdds']),
      bestOdds: parseBestOdds(map['bestOdds']),
      fetchedAt: (map['fetchedAt'] as dynamic).toDate(),
    );
  }
  Map<String, dynamic> toMap() => {
    'apiFootballFixtureId': apiFootballFixtureId,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'kickoff': kickoff,
    'apiFootballLeagueId': apiFootballLeagueId,
    'leagueKey': leagueKey,
    'bookmakerOdds': bookmakerOdds,
    'bestOdds': bestOdds,
    'fetchedAt': fetchedAt,
  };
  /// Returns the best available odd for a specific market value.
  double? bestOddFor(String marketName, String value) {
    final market = bestOdds[marketName];
    if (market == null) return null;
    final match = market.firstWhere(
      (v) => v['value'] == value,
      orElse: () => {},
    );
    if (match.isEmpty) return null;
    return (match['odd'] as num?)?.toDouble();
  }
  /// Returns the specific bookmaker's odd for a market value.
  double? bookmakerOddFor(String bookmakerKey, String marketName, String value) {
    final bmData = bookmakerOdds[bookmakerKey];
    if (bmData == null) {
      // ignore: avoid_print
      print('bookmakerOddFor: no data for bookmaker=$bookmakerKey (available: ${bookmakerOdds.keys.join(', ')})');
      return null;
    }
    final market = bmData[marketName];
    if (market == null) {
      // ignore: avoid_print
      print('bookmakerOddFor: no market=$marketName for bookmaker=$bookmakerKey (available: ${bmData.keys.join(', ')})');
      return null;
    }
    final match = market.firstWhere(
      (v) => v['value'] == value,
      orElse: () => {},
    );
    if (match.isEmpty) {
      // ignore: avoid_print
      print('bookmakerOddFor: no value=$value in market=$marketName for bookmaker=$bookmakerKey (values: ${market.map((v) => v['value']).join(', ')})');
      return null;
    }
    return (match['odd'] as num?)?.toDouble();
  }
  /// Combined decimal odds for the bookmaker across a list of selections.
  double combinedOddsForBookmaker(
    String bookmakerKey,
    List<({String marketName, String value})> selections,
  ) {
    double combined = 1.0;
    for (final sel in selections) {
      final odd = bookmakerOddFor(bookmakerKey, sel.marketName, sel.value);
      if (odd == null) return 0.0; // bookmaker doesn't cover this selection
      combined *= odd;
    }
    return combined;
  }
}

class SeasonWinner {
  final String? id;
  final String teamId;
  final String season;
  final String winnerMemberId;
  final String winnerDisplayName;
  final int totalBasePoints;
  final double totalWeightedPoints;
  final DateTime endedAt;
  SeasonWinner({
    this.id,
    required this.teamId,
    required this.season,
    required this.winnerMemberId,
    required this.winnerDisplayName,
    required this.totalBasePoints,
    required this.totalWeightedPoints,
    required this.endedAt,
  });
  factory SeasonWinner.fromMap(String id, Map<String, dynamic> map) {
    return SeasonWinner(
      id: id,
      teamId: map['teamId'],
      season: map['season'],
      winnerMemberId: map['winnerMemberId'],
      winnerDisplayName: map['winnerDisplayName'],
      totalBasePoints: map['totalBasePoints'],
      totalWeightedPoints: (map['totalWeightedPoints'] as num).toDouble(),
      endedAt: map['endedAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'season': season,
      'winnerMemberId': winnerMemberId,
      'winnerDisplayName': winnerDisplayName,
      'totalBasePoints': totalBasePoints,
      'totalWeightedPoints': totalWeightedPoints,
      'endedAt': endedAt,
    };
  }
}
class SeasonSettings {
  final String? id;
  final String teamId;
  final String season;
  final int maxChallengesPerMember;
  final int maxPhysioSessionsPerMember;
  final DateTime createdAt;
  SeasonSettings({
    this.id,
    required this.teamId,
    required this.season,
    required this.maxChallengesPerMember,
    required this.maxPhysioSessionsPerMember,
    required this.createdAt,
  });
  factory SeasonSettings.fromMap(String id, Map<String, dynamic> map) {
    return SeasonSettings(
      id: id,
      teamId: map['teamId'],
      season: map['season'],
      maxChallengesPerMember: map['maxChallengesPerMember'] ?? 2,
      maxPhysioSessionsPerMember: map['maxPhysioSessionsPerMember'] ?? 2,
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'season': season,
      'maxChallengesPerMember': maxChallengesPerMember,
      'maxPhysioSessionsPerMember': maxPhysioSessionsPerMember,
      'createdAt': createdAt,
    };
  }
}
enum FineType { lateSelection, accaKiller, reminderTax, repeatOffender, twoYellowCards }
extension FineTypeValue on FineType {
  String get value {
    switch (this) {
      case FineType.lateSelection: return 'late_selection';
      case FineType.accaKiller: return 'acca_killer';
      case FineType.reminderTax: return 'reminder_tax';
      case FineType.repeatOffender: return 'repeat_offender';
      case FineType.twoYellowCards: return 'two_yellow_cards';
    }
  }
  String get displayName {
    switch (this) {
      case FineType.lateSelection: return 'Late Selection Fine';
      case FineType.accaKiller: return 'Acca Killer';
      case FineType.reminderTax: return 'Reminder Tax';
      case FineType.repeatOffender: return 'Repeat Offender';
      case FineType.twoYellowCards: return 'Two Yellow Cards';
    }
  }
  static FineType fromValue(String? value) {
    switch (value) {
      case 'acca_killer': return FineType.accaKiller;
      case 'reminder_tax': return FineType.reminderTax;
      case 'repeat_offender': return FineType.repeatOffender;
      case 'two_yellow_cards': return FineType.twoYellowCards;
      default: return FineType.lateSelection;
    }
  }
}
enum FineStatus { pending, accepted, disputed, upheld, overturned }
extension FineStatusValue on FineStatus {
  String get value {
    switch (this) {
      case FineStatus.pending: return 'pending';
      case FineStatus.accepted: return 'accepted';
      case FineStatus.disputed: return 'disputed';
      case FineStatus.upheld: return 'upheld';
      case FineStatus.overturned: return 'overturned';
    }
  }
  static FineStatus fromValue(String? value) {
    switch (value) {
      case 'accepted': return FineStatus.accepted;
      case 'disputed': return FineStatus.disputed;
      case 'upheld': return FineStatus.upheld;
      case 'overturned': return FineStatus.overturned;
      default: return FineStatus.pending;
    }
  }
}
class Fine {
  final String? id;
  final String teamId;
  final String memberId; // who's being fined
  final String memberName;
  final FineType fineType;
  final String reason;
  final FineStatus status;
  final String createdByMemberId;
  final String createdByName;
  final DateTime createdAt;
  final String season;
  final DateTime? disputeDeadline;
  final bool paid;
  final DateTime? paidAt;
  final Map<String, bool> votes; // memberId -> true (uphold) / false (overturn)
  Fine({
    this.id,
    required this.teamId,
    required this.memberId,
    required this.memberName,
    required this.fineType,
    required this.reason,
    required this.status,
    required this.createdByMemberId,
    required this.createdByName,
    required this.createdAt,
    required this.season,
    this.disputeDeadline,
    this.paid = false,
    this.paidAt,
    this.votes = const {},
  });
  /// Counts toward the tally from the moment it's placed, and stays on the
  /// tally the whole way through — pending, accepted, or under dispute.
  /// The only outcome that removes it is a successful dispute (Overturned);
  /// Upheld or a tied vote leaves it counted.
  bool get countsTowardTally => status != FineStatus.overturned && !paid;
  factory Fine.fromMap(String id, Map<String, dynamic> map) {
    return Fine(
      id: id,
      teamId: map['teamId'],
      memberId: map['memberId'],
      memberName: map['memberName'] ?? 'Unknown',
      fineType: FineTypeValue.fromValue(map['fineType']),
      reason: map['reason'] ?? '',
      status: FineStatusValue.fromValue(map['status']),
      createdByMemberId: map['createdByMemberId'],
      createdByName: map['createdByName'] ?? 'Unknown',
      createdAt: map['createdAt'].toDate(),
      season: map['season'] ?? 'Unknown Season', // fines placed before this field existed
      disputeDeadline: (map['disputeDeadline'] as dynamic)?.toDate(),
      paid: map['paid'] ?? false,
      paidAt: (map['paidAt'] as dynamic)?.toDate(),
      votes: Map<String, bool>.from(map['votes'] ?? {}),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'memberId': memberId,
      'memberName': memberName,
      'fineType': fineType.value,
      'reason': reason,
      'status': status.value,
      'createdByMemberId': createdByMemberId,
      'createdByName': createdByName,
      'createdAt': createdAt,
      'season': season,
      'disputeDeadline': disputeDeadline,
      'votes': votes,
      'paid': paid,
      'paidAt': paidAt,
    };
  }
}
enum ChallengeStatus { active, resolved }
extension ChallengeStatusValue on ChallengeStatus {
  String get value => this == ChallengeStatus.active ? 'active' : 'resolved';
  static ChallengeStatus fromValue(String? v) => v == 'resolved' ? ChallengeStatus.resolved : ChallengeStatus.active;
}
class Challenge {
  final String? id;
  final String teamId;
  final String season;
  final String gameWeekId;
  final String challengerMemberId;
  final String challengerName;
  final String challengedMemberId;
  final String challengedName;
  final String challengedLegId;
  final String challengedLegDescription;
  final double challengedLegOdds;
  final String? challengerLegId;
  final String? challengerLegDescription;
  final double? challengerLegOdds;
  final ChallengeStatus status;
  final bool? challengerWon; // null until resolved
  final DateTime createdAt;
  Challenge({
    this.id,
    required this.teamId,
    required this.season,
    required this.gameWeekId,
    required this.challengerMemberId,
    required this.challengerName,
    required this.challengedMemberId,
    required this.challengedName,
    required this.challengedLegId,
    required this.challengedLegDescription,
    required this.challengedLegOdds,
    this.challengerLegId,
    this.challengerLegDescription,
    this.challengerLegOdds,
    required this.status,
    this.challengerWon,
    required this.createdAt,
  });
  /// The hypothetical win value of a leg at these odds — 3 base points,
  /// plus weighted points the same way any winning leg is scored.
  static double hypotheticalWeightedPoints(double odds) => (odds - 1) * 3;
  static const int hypotheticalBasePoints = 3;
  factory Challenge.fromMap(String id, Map<String, dynamic> map) {
    return Challenge(
      id: id,
      teamId: map['teamId'],
      season: map['season'] ?? '',
      gameWeekId: map['gameWeekId'],
      challengerMemberId: map['challengerMemberId'],
      challengerName: map['challengerName'] ?? 'Unknown',
      challengedMemberId: map['challengedMemberId'],
      challengedName: map['challengedName'] ?? 'Unknown',
      challengedLegId: map['challengedLegId'],
      challengedLegDescription: map['challengedLegDescription'] ?? '',
      challengedLegOdds: (map['challengedLegOdds'] as num?)?.toDouble() ?? 0,
      challengerLegId: map['challengerLegId'],
      challengerLegDescription: map['challengerLegDescription'],
      challengerLegOdds: (map['challengerLegOdds'] as num?)?.toDouble(),
      status: ChallengeStatusValue.fromValue(map['status']),
      challengerWon: map['challengerWon'],
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'season': season,
      'gameWeekId': gameWeekId,
      'challengerMemberId': challengerMemberId,
      'challengerName': challengerName,
      'challengedMemberId': challengedMemberId,
      'challengedName': challengedName,
      'challengedLegId': challengedLegId,
      'challengedLegDescription': challengedLegDescription,
      'challengedLegOdds': challengedLegOdds,
      'challengerLegId': challengerLegId,
      'challengerLegDescription': challengerLegDescription,
      'challengerLegOdds': challengerLegOdds,
      'status': status.value,
      'challengerWon': challengerWon,
      'createdAt': createdAt,
    };
  }
}
enum NotificationType {
  deadlineReminder,
  legRejected,
  fineIssued,
  fineDisputeVote,
  disputeResolved,
  nudge,
  challengePlaced,
  challengeResolved,
  gameweekLocked,
  leaguePosition,
  newGameweek,
  physioUsed,
  yellowCardIssued,
  kudosReceived,
  // Knockout tournament
  tournamentDrawDateSet,
  tournamentDrawLive,
  tournamentDrawnAgainst,
  tournamentBigCupTie,
  tournamentDrawCompleted,
  tournamentOpponentSubmitted,
  tournamentRoundWon,
  tournamentRoundLost,
}
extension NotificationTypeValue on NotificationType {
  String get value => toString().split('.').last;
  static NotificationType fromValue(String? v) =>
      NotificationType.values.firstWhere((t) => t.value == v, orElse: () => NotificationType.deadlineReminder);
}
class AppNotification {
  final String? id;
  final String teamId;
  final String recipientMemberId;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  AppNotification({
    this.id,
    required this.teamId,
    required this.recipientMemberId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });
  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      teamId: map['teamId'],
      recipientMemberId: map['recipientMemberId'],
      type: NotificationTypeValue.fromValue(map['type']),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      createdAt: map['createdAt'].toDate(),
      read: map['read'] ?? false,
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'recipientMemberId': recipientMemberId,
      'type': type.value,
      'title': title,
      'body': body,
      'createdAt': createdAt,
      'read': read,
    };
  }
}
// ============================================================
// YELLOW CARDS
// ============================================================
/// A generic, non-disputable offence recorded against a member. Kept
/// permanently for history — [consumedByFineId] is what tracks the
/// "current" tally: null means it still counts toward the next fine,
/// non-null means it was one of the pair that already triggered one.
class YellowCard {
  final String? id;
  final String teamId;
  final String memberId;
  final String memberName;
  final String reason;
  final String season;
  final String issuedByMemberId;
  final String issuedByName;
  final DateTime createdAt;
  final String? consumedByFineId;
  YellowCard({
    this.id,
    required this.teamId,
    required this.memberId,
    required this.memberName,
    required this.reason,
    required this.season,
    required this.issuedByMemberId,
    required this.issuedByName,
    required this.createdAt,
    this.consumedByFineId,
  });
  factory YellowCard.fromMap(String id, Map<String, dynamic> map) {
    return YellowCard(
      id: id,
      teamId: map['teamId'],
      memberId: map['memberId'],
      memberName: map['memberName'] ?? 'Unknown',
      reason: map['reason'] ?? '',
      season: map['season'] ?? '',
      issuedByMemberId: map['issuedByMemberId'] ?? '',
      issuedByName: map['issuedByName'] ?? 'Unknown',
      createdAt: map['createdAt'].toDate(),
      consumedByFineId: map['consumedByFineId'],
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'memberId': memberId,
      'memberName': memberName,
      'reason': reason,
      'season': season,
      'issuedByMemberId': issuedByMemberId,
      'issuedByName': issuedByName,
      'createdAt': createdAt,
      'consumedByFineId': consumedByFineId,
    };
  }
}
// ============================================================
// KUDOS REACTIONS
// ============================================================
/// An emoji reaction on a locked leg. Each member can react with each
/// emoji independently — tapping the same emoji again removes the
/// reaction (toggle). Three supported emojis: 👍 ❤️ 😂
class Reaction {
  final String? id;
  final String teamId;
  final String legId;
  final String gameWeekId;
  final String reactorMemberId;
  final String reactorName;
  final String recipientMemberId;
  final String emoji;
  final DateTime createdAt;
  Reaction({
    this.id,
    required this.teamId,
    required this.legId,
    required this.gameWeekId,
    required this.reactorMemberId,
    required this.reactorName,
    required this.recipientMemberId,
    required this.emoji,
    required this.createdAt,
  });
  factory Reaction.fromMap(String id, Map<String, dynamic> map) {
    return Reaction(
      id: id,
      teamId: map['teamId'],
      legId: map['legId'],
      gameWeekId: map['gameWeekId'],
      reactorMemberId: map['reactorMemberId'],
      reactorName: map['reactorName'] ?? 'Unknown',
      recipientMemberId: map['recipientMemberId'],
      emoji: map['emoji'] ?? '👍',
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() => {
    'teamId': teamId,
    'legId': legId,
    'gameWeekId': gameWeekId,
    'reactorMemberId': reactorMemberId,
    'reactorName': reactorName,
    'recipientMemberId': recipientMemberId,
    'emoji': emoji,
    'createdAt': createdAt,
  };
}

class PhysioSession {
  final String? id;
  final String teamId;
  final String memberId;
  final String memberName;
  final String season;
  final String gameWeekId;
  final int weekNumber;
  final DateTime usedAt;
  PhysioSession({
    this.id,
    required this.teamId,
    required this.memberId,
    required this.memberName,
    required this.season,
    required this.gameWeekId,
    required this.weekNumber,
    required this.usedAt,
  });
  factory PhysioSession.fromMap(String id, Map<String, dynamic> map) {
    return PhysioSession(
      id: id,
      teamId: map['teamId'],
      memberId: map['memberId'],
      memberName: map['memberName'] ?? 'Unknown',
      season: map['season'] ?? '',
      gameWeekId: map['gameWeekId'],
      weekNumber: map['weekNumber'] ?? 0,
      usedAt: map['usedAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'memberId': memberId,
      'memberName': memberName,
      'season': season,
      'gameWeekId': gameWeekId,
      'weekNumber': weekNumber,
      'usedAt': usedAt,
    };
  }
}
// ============================================================
// KNOCKOUT TOURNAMENT
// ============================================================
enum TournamentStatus { pendingDraw, drawn, inProgress, completed }
extension TournamentStatusValue on TournamentStatus {
  String get value => toString().split('.').last;
  static TournamentStatus fromValue(String? v) =>
      TournamentStatus.values.firstWhere((s) => s.value == v, orElse: () => TournamentStatus.pendingDraw);
}
class Tournament {
  final String? id;
  final String teamId;
  final String season;
  final String name;
  final DateTime drawDateTime;
  final TournamentStatus status;
  /// Next-lower-power-of-2 size of the first main round (e.g. 8 = starts
  /// at Quarter-Finals). Deliberately null until the draw actually happens
  /// (Stage 2) — at creation time, a brand-new team only has the manager
  /// as a member, so there's nothing meaningful to compute this from yet.
  final int? mainBracketSize;
  /// Which round is currently live: null before the first draw, 0 for the
  /// preliminary/byes tier, then mainBracketSize, mainBracketSize/2, ...
  /// down to 2 (the Final). Single source of truth for round progression —
  /// avoids inferring it by querying/grouping TournamentMatch documents.
  final int? currentRoundSize;
  final DateTime createdAt;
  Tournament({
    this.id,
    required this.teamId,
    required this.season,
    required this.name,
    required this.drawDateTime,
    this.status = TournamentStatus.pendingDraw,
    this.mainBracketSize,
    this.currentRoundSize,
    required this.createdAt,
  });
  factory Tournament.fromMap(String id, Map<String, dynamic> map) {
    return Tournament(
      id: id,
      teamId: map['teamId'],
      season: map['season'] ?? '',
      name: map['name'] ?? '',
      drawDateTime: map['drawDateTime'].toDate(),
      status: TournamentStatusValue.fromValue(map['status']),
      mainBracketSize: map['mainBracketSize'],
      currentRoundSize: map['currentRoundSize'],
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'season': season,
      'name': name,
      'drawDateTime': drawDateTime,
      'status': status.value,
      'mainBracketSize': mainBracketSize,
      'currentRoundSize': currentRoundSize,
      'createdAt': createdAt,
    };
  }
}
/// A single tournament fixture — one pairing (or a bye) within a round.
/// roundSize follows Tournament.currentRoundSize's convention: 0 for the
/// preliminary/byes tier, then mainBracketSize down to 2 (the Final).
class TournamentMatch {
  final String? id;
  final String tournamentId;
  final String teamId;
  final String season;
  final int roundSize;
  final String memberAId;
  final String memberAName;
  final String? memberBId; // null = a bye
  final String? memberBName;
  final bool isBye;
  final bool isBigCupTie;
  final bool revealed;
  final String? gameWeekId; // set once this round is attached to a gameweek
  final String? winnerMemberId; // pre-set at creation for a bye; null otherwise until resolved
  final String? winnerName;
  final DateTime createdAt;
  TournamentMatch({
    this.id,
    required this.tournamentId,
    required this.teamId,
    required this.season,
    required this.roundSize,
    required this.memberAId,
    required this.memberAName,
    this.memberBId,
    this.memberBName,
    this.isBye = false,
    this.isBigCupTie = false,
    this.revealed = false,
    this.gameWeekId,
    this.winnerMemberId,
    this.winnerName,
    required this.createdAt,
  });
  bool get isResolved => winnerMemberId != null;
  factory TournamentMatch.fromMap(String id, Map<String, dynamic> map) {
    return TournamentMatch(
      id: id,
      tournamentId: map['tournamentId'],
      teamId: map['teamId'],
      season: map['season'] ?? '',
      roundSize: map['roundSize'] ?? 0,
      memberAId: map['memberAId'],
      memberAName: map['memberAName'] ?? 'Unknown',
      memberBId: map['memberBId'],
      memberBName: map['memberBName'],
      isBye: map['isBye'] ?? false,
      isBigCupTie: map['isBigCupTie'] ?? false,
      revealed: map['revealed'] ?? false,
      gameWeekId: map['gameWeekId'],
      winnerMemberId: map['winnerMemberId'],
      winnerName: map['winnerName'],
      createdAt: map['createdAt'].toDate(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'tournamentId': tournamentId,
      'teamId': teamId,
      'season': season,
      'roundSize': roundSize,
      'memberAId': memberAId,
      'memberAName': memberAName,
      'memberBId': memberBId,
      'memberBName': memberBName,
      'isBye': isBye,
      'isBigCupTie': isBigCupTie,
      'revealed': revealed,
      'gameWeekId': gameWeekId,
      'winnerMemberId': winnerMemberId,
      'winnerName': winnerName,
      'createdAt': createdAt,
    };
  }
}
/// Human-readable label for a round, derived from roundSize rather than
/// stored, so it stays correct even if mainBracketSize varies between
/// tournaments (e.g. 8 members vs 20 members both eventually reach "Final").
String tournamentRoundLabel(int roundSize) {
  if (roundSize == 0) return 'Qualifying Round';
  switch (roundSize) {
    case 2: return 'Final';
    case 4: return 'Semi-Final';
    case 8: return 'Quarter-Final';
    case 16: return 'Round of 16';
    case 32: return 'Round of 32';
    default: return 'Round of $roundSize';
  }
}