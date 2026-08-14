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
  }) : createdAt = createdAt ?? startDate; // fallback keeps older gameweeks from crashing pick-time stats

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
  final Map<String, String>? bookmakerLinks;
  final int? sportmonksFixtureId;

  final LegOutcome outcome;
  final DateTime submittedAt;

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
    this.bookmakerLinks,
    this.sportmonksFixtureId,
    required this.outcome,
    required this.submittedAt,
  });

  // 3 points for a win — primary league table sort key
  int get basePoints => outcome == LegOutcome.won ? 3 : 0;

  // (decimal - 1) x 3 — same formula as the Swift version
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
      bookmakerLinks: (map['bookmakerLinks'] as Map?)?.map(
        (k, v) => MapEntry(k as String, v as String),
      ),
      sportmonksFixtureId: map['sportmonksFixtureId'],
      outcome: LegOutcomeValue.fromValue(map['outcome']),
      submittedAt: map['submittedAt'].toDate(),
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
      'bookmakerLinks': bookmakerLinks,
      'sportmonksFixtureId': sportmonksFixtureId,
      'outcome': outcome.value,
      'submittedAt': submittedAt,
    };
  }
}