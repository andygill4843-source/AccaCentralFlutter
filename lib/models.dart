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
    };
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

enum FineType { lateSelection, accaKiller, reminderTax, repeatOffender }
extension FineTypeValue on FineType {
  String get value {
    switch (this) {
      case FineType.lateSelection: return 'late_selection';
      case FineType.accaKiller: return 'acca_killer';
      case FineType.reminderTax: return 'reminder_tax';
      case FineType.repeatOffender: return 'repeat_offender';
    }
  }
  String get displayName {
    switch (this) {
      case FineType.lateSelection: return 'Late Selection Fine';
      case FineType.accaKiller: return 'Acca Killer';
      case FineType.reminderTax: return 'Reminder Tax';
      case FineType.repeatOffender: return 'Repeat Offender';
    }
  }
  static FineType fromValue(String? value) {
    switch (value) {
      case 'acca_killer': return FineType.accaKiller;
      case 'reminder_tax': return FineType.reminderTax;
      case 'repeat_offender': return FineType.repeatOffender;
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

enum NotificationType { deadlineReminder, legRejected, fineIssued, fineDisputeVote, disputeResolved, nudge, challengePlaced, challengeResolved, gameweekLocked, leaguePosition, newGameweek, physioUsed }
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