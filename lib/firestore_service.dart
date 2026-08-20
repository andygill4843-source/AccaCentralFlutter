
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';
import 'package:uuid/uuid.dart';
import 'scoring_engine.dart'; // for LeagueTableEntry

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final _db = FirebaseFirestore.instance;

  Future<List<Member>> fetchMembers(String teamId) async {
    final snapshot = await _db
        .collection('members')
        .where('teamId', isEqualTo: teamId)
        .get();
    return snapshot.docs.map((doc) => Member.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> createChallenge(Challenge challenge) async {
    await _db.collection('challenges').add(challenge.toMap());
  }

  /// Resolves any active challenge whose challenged leg has now settled
  /// (won/lost), same client-side-on-load pattern used for fine disputes.
  Future<List<Challenge>> fetchChallenges({required String teamId, required String season}) async {
    final snapshot = await _db.collection('challenges').where('teamId', isEqualTo: teamId).where('season', isEqualTo: season).get();
    final all = snapshot.docs.map((doc) => Challenge.fromMap(doc.id, doc.data())).toList();

    final activeOnes = all.where((c) => c.status == ChallengeStatus.active).toList();
    if (activeOnes.isNotEmpty) {
      final legsSnapshot = await _db.collection('legs').where('teamId', isEqualTo: teamId).get();
      final legsById = {for (final doc in legsSnapshot.docs) doc.id: doc.data()};
      final teamMembers = await fetchMembers(teamId);
      final memberIds = [for (final m in teamMembers) if (m.id != null) m.id!];
      for (final challenge in activeOnes) {
        final legData = legsById[challenge.challengedLegId];
        if (legData == null) continue;
        final outcome = LegOutcomeValue.fromValue(legData['outcome']);
        if (outcome != LegOutcome.won && outcome != LegOutcome.lost) continue; // not settled yet
        final challengedLegWon = outcome == LegOutcome.won;
        final challengerWon = !challengedLegWon; // challenger wins the challenge if the challenged leg LOST
        await _db.collection('challenges').doc(challenge.id).update({
          'status': ChallengeStatus.resolved.value,
          'challengerWon': challengerWon,
        });
        await sendNotification(
          teamId: teamId,
          recipientMemberIds: memberIds,
          type: NotificationType.challengeResolved,
          title: challengerWon ? 'CHALLENGE CHAMPION' : 'CHALLENGE LOST',
          body: challengerWon
              ? '${challenge.challengerName} called it and it doesn\'t look like ${challenge.challengedName} has what it takes!'
              : 'That ages well! Too big for your boots ${challenge.challengerName}. Enjoy the points ${challenge.challengedName}.',
        );
      }
      final refreshed = await _db.collection('challenges').where('teamId', isEqualTo: teamId).get();
      return refreshed.docs.map((doc) => Challenge.fromMap(doc.id, doc.data())).toList();
    }

    return all;
  }

  Future<List<Team>> fetchTeams(List<String> teamIds) async {
    final teams = <Team>[];
    for (final id in teamIds) {
      final team = await fetchTeam(id);
      if (team != null) teams.add(team);
    }
    return teams;
  }

  /// Writes one notification doc per recipient — the Cloud Function
  /// (notifications.js) picks each one up via onCreate and sends the
  /// actual push. This call itself is what powers the in-app bell list.
  Future<void> sendNotification({
    required String teamId,
    required List<String> recipientMemberIds,
    required NotificationType type,
    required String title,
    required String body,
  }) async {
    final batch = _db.batch();
    for (final memberId in recipientMemberIds) {
      final ref = _db.collection('notifications').doc();
      batch.set(ref, AppNotification(
        teamId: teamId,
        recipientMemberId: memberId,
        type: type,
        title: title,
        body: body,
        createdAt: DateTime.now(),
      ).toMap());
    }
    await batch.commit();
  }

  Future<List<AppNotification>> fetchNotifications({required String teamId, required String memberId}) async {
    final snapshot = await _db
        .collection('notifications')
        .where('teamId', isEqualTo: teamId)
        .where('recipientMemberId', isEqualTo: memberId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snapshot.docs.map((doc) => AppNotification.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> markNotificationRead(String id) async {
    await _db.collection('notifications').doc(id).update({'read': true});
  }

  Future<void> saveFcmToken({required String userId, required String token}) async {
    await _db.collection('users').doc(userId).update({'fcmToken': token});
  }
 
  Future<void> markFinePaid(String fineId) async {
    await _db.collection('fines').doc(fineId).update({
      'paid': true,
      'paidAt': DateTime.now(),
    });
  }

  Future<void> deleteLeg(String legId) async {
    await _db.collection('legs').doc(legId).delete();
  }

  Future<void> setTeamSeason({required String teamId, required String season}) async {
    await _db.collection('teams').doc(teamId).update({'season': season});
  }

  Future<Team?> fetchTeam(String teamId) async {
    final doc = await _db.collection('teams').doc(teamId).get();
    if (!doc.exists) return null;
    return Team.fromMap(doc.id, doc.data()!);
  }

  Future<List<Fine>> fetchFines(String teamId) async {
    final snapshot = await _db.collection('fines').where('teamId', isEqualTo: teamId).get();
    final fines = snapshot.docs.map((doc) => Fine.fromMap(doc.id, doc.data())).toList();

    // Resolve any disputes whose 5-day window has passed — client-side
    // check, run whenever anyone loads the fines list, since there's no
    // scheduled backend job for this yet.
    final now = DateTime.now();
    for (final fine in fines) {
      if (fine.status == FineStatus.disputed && fine.disputeDeadline != null && now.isAfter(fine.disputeDeadline!)) {
        final upholdCount = fine.votes.values.where((v) => v == true).length;
        final overturnCount = fine.votes.values.where((v) => v == false).length;
        final finalStatus = upholdCount >= overturnCount ? FineStatus.upheld : FineStatus.overturned;
        await _db.collection('fines').doc(fine.id).update({'status': finalStatus.value});
        await sendNotification(
          teamId: teamId,
          recipientMemberIds: [fine.memberId],
          type: NotificationType.disputeResolved,
          title: 'Dispute resolved',
          body: finalStatus == FineStatus.overturned
              ? 'Your dispute of the ${fine.fineType.displayName} fine was successful — it has been overturned.'
              : 'Your dispute of the ${fine.fineType.displayName} fine was unsuccessful — the fine has been upheld.',
        );
      }
    }

    // Re-fetch so the returned list reflects any resolutions just applied.
    final refreshed = await _db.collection('fines').where('teamId', isEqualTo: teamId).get();
    return refreshed.docs.map((doc) => Fine.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> createFine(Fine fine) async {
    await _db.collection('fines').add(fine.toMap());
  }

  Future<void> respondToFine({required String fineId, required bool accept}) async {
    if (accept) {
      await _db.collection('fines').doc(fineId).update({'status': FineStatus.accepted.value});
    } else {
      await _db.collection('fines').doc(fineId).update({
        'status': FineStatus.disputed.value,
        'disputeDeadline': DateTime.now().add(const Duration(days: 5)),
      });
    }
  }

  Future<void> voteOnFine({required String fineId, required String memberId, required bool upholds}) async {
    await _db.collection('fines').doc(fineId).update({'votes.$memberId': upholds});
  }

  Future<int> fetchUnreadNotificationCount({required String teamId, required String memberId}) async {
    final snapshot = await _db
        .collection('notifications')
        .where('teamId', isEqualTo: teamId)
        .where('recipientMemberId', isEqualTo: memberId)
        .where('read', isEqualTo: false)
        .get();
    return snapshot.docs.length;
  }

  Future<AccumulatorLeg?> fetchMemberLegForGameWeek({
    required String teamId,
    required String memberId,
    required String gameWeekId,
  }) async {
    final snapshot = await _db
        .collection('legs')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .orderBy('submittedAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return AccumulatorLeg.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  Future<void> updateLegOutcome({required String legId, required LegOutcome outcome}) async {
    await _db.collection('legs').doc(legId).update({'outcome': outcome.value});
  }

  Future<List<AccumulatorLeg>> fetchLegs(String teamId) async {
    final snapshot = await _db
        .collection('legs')
        .where('teamId', isEqualTo: teamId)
        .get();
    return snapshot.docs.map((doc) => AccumulatorLeg.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> setGameWeekBookmaker({
    required String teamId,
    required int weekNumber,
    required String gameWeekId,
    required String bookmaker,
    required double combinedOdds,
    required List<AccumulatorLeg> legs,
  }) async {
    final gameWeekRef = _db.collection('gameWeeks').doc(gameWeekId);
    await _db.runTransaction((transaction) async {
      for (final leg in legs) {
        if (leg.id == null) continue;
        final price = (leg.bookmakerPrices ?? {})[bookmaker];
        if (price == null) continue;
        final legRef = _db.collection('legs').doc(leg.id);
        transaction.update(legRef, {
          'decimalOddsAtSelection': price,
          'bookmaker': bookmaker,
          'preLockOddsAtSelection': leg.decimalOddsAtSelection,
          'preLockBookmaker': leg.bookmaker,
        });
      }
      transaction.update(gameWeekRef, {
        'selectedBookmaker': bookmaker,
        'combinedOdds': combinedOdds,
        'isLocked': true,
      });
    });

    final members = await fetchMembers(teamId);
    await sendNotification(
      teamId: teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.gameweekLocked,
      title: 'Gameweek locked',
      body: 'Gameweek $weekNumber is locked in with $bookmaker — combined odds ${combinedOdds.toStringAsFixed(2)}.',
    );
  }

    Future<void> unlockGameWeek(String gameWeekId, {required String teamId}) async {
    final gameWeekRef = _db.collection('gameWeeks').doc(gameWeekId);
    await _db.runTransaction((transaction) async {
      final legsSnap = await _db
          .collection('legs')
          .where('teamId', isEqualTo: teamId)
          .where('gameWeekId', isEqualTo: gameWeekId)
          .get();
      transaction.update(gameWeekRef, {
        'selectedBookmaker': null,
        'combinedOdds': null,
        'isLocked': false,
      });
      for (final doc in legsSnap.docs) {
        final data = doc.data();
        final preLockOdds = data['preLockOddsAtSelection'];
        final preLockBookmaker = data['preLockBookmaker'];
        if (preLockOdds != null && preLockBookmaker != null) {
          transaction.update(doc.reference, {
            'decimalOddsAtSelection': preLockOdds,
            'bookmaker': preLockBookmaker,
          });
        }
      }
    });
  }

  Future<List<GameWeek>> fetchGameWeeks(String teamId) async {
    final snapshot = await _db
        .collection('gameWeeks')
        .where('teamId', isEqualTo: teamId)
        .orderBy('weekNumber')
        .get();
    return snapshot.docs.map((doc) => GameWeek.fromMap(doc.id, doc.data())).toList();
  }

  Future<List<SeasonWinner>> fetchSeasonWinners(String teamId) async {
    final snapshot = await _db
        .collection('seasonWinners')
        .where('teamId', isEqualTo: teamId)
        .orderBy('endedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => SeasonWinner.fromMap(doc.id, doc.data())).toList();
  }

  /// Archives the current season's winner, then advances the team to a new
  /// season string. Existing gameweeks/legs are untouched — they permanently
  /// keep the season they were created under, which is what makes filtering
  /// "this season only" possible later.
  Future<void> endSeason({
    required String teamId,
    required String currentSeason,
    required String newSeason,
    required LeagueTableEntry winner,
  }) async {
    final teamRef = _db.collection('teams').doc(teamId);

    await _db.collection('seasonWinners').add(SeasonWinner(
          teamId: teamId,
          season: currentSeason,
          winnerMemberId: winner.memberId,
          winnerDisplayName: winner.displayName,
          totalBasePoints: winner.totalBasePoints,
          totalWeightedPoints: winner.totalWeightedPoints,
          endedAt: DateTime.now(),
        ).toMap());

    await teamRef.update({'season': newSeason});
  }

  Future<GameWeek?> fetchActiveGameWeek(String teamId) async {
    final teamDoc = await _db.collection('teams').doc(teamId).get();
    final activeId = teamDoc.data()?['activeGameWeekId'] as String?;
    if (activeId == null) return null;
    final gwDoc = await _db.collection('gameWeeks').doc(activeId).get();
    if (!gwDoc.exists) return null;
    final gameWeek = GameWeek.fromMap(gwDoc.id, gwDoc.data()!);

    // Lazy-check: fires whether the last leg settled manually
    // (updateLegOutcome) or via the settleLegs.js Cloud Function — same
    // pattern already used for fine disputes and challenges.
    if (!gameWeek.isSettled) {
      final legsSnap = await _db.collection('legs').where('teamId', isEqualTo: teamId).where('gameWeekId', isEqualTo: activeId).get();
      final legs = legsSnap.docs.map((d) => AccumulatorLeg.fromMap(d.id, d.data())).toList();
      final allSettled = legs.isNotEmpty && legs.every((l) => l.outcome != LegOutcome.pending);
      if (allSettled) {
        await _finishGameWeekAndNotify(teamId: teamId, gameWeek: gameWeek);
        return null; // it just finished — there's no active gameweek anymore
      }
    }
    return gameWeek;
  }

  Future<void> _finishGameWeekAndNotify({required String teamId, required GameWeek gameWeek}) async {
    if (gameWeek.id == null) return;
    await settleGameWeek(teamId: teamId, gameWeekId: gameWeek.id!);

    final team = await fetchTeam(teamId);
    final season = team?.season ?? gameWeek.season;
    final members = await fetchMembers(teamId);
    final allLegs = await fetchLegs(teamId);
    final gameWeeks = await fetchGameWeeks(teamId);
    final seasonGameWeekIds = gameWeeks.where((g) => g.season == season).map((g) => g.id).toSet();
    final seasonLegs = allLegs.where((l) => seasonGameWeekIds.contains(l.gameWeekId)).toList();
    final challenges = await fetchChallenges(teamId: teamId, season: season);
    final table = ScoringEngine.buildLeagueTable(members: members, legs: seasonLegs, challenges: challenges);

    for (int i = 0; i < table.length; i++) {
      final entry = table[i];
      await sendNotification(
        teamId: teamId,
        recipientMemberIds: [entry.memberId],
        type: NotificationType.leaguePosition,
        title: 'Gameweek ${gameWeek.weekNumber} settled',
        body: "All legs are in for Gameweek ${gameWeek.weekNumber} — you're now ${_ordinal(i + 1)} in the table.",
      );
    }
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  Future<void> submitLeg(AccumulatorLeg leg) async {
    await _db.collection('legs').add(leg.toMap());
  }

  Future<Member?> fetchMember({required String teamId, required String userId}) async {
    final snapshot = await _db
        .collection('members')
        .where('teamId', isEqualTo: teamId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Member.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  /// Atomic: only succeeds if the team has no active gameweek right now.
  /// Prevents two rapid "create gameweek" taps from both succeeding.
  Future<void> createGameWeek(GameWeek gameWeek) async {
    final teamRef = _db.collection('teams').doc(gameWeek.teamId);
    final gameWeekRef = _db.collection('gameWeeks').doc();
    await _db.runTransaction((transaction) async {
      final teamSnap = await transaction.get(teamRef);
      final activeId = teamSnap.data()?['activeGameWeekId'] as String?;
      if (activeId != null) {
        throw Exception("There's already an active gameweek. End it before creating a new one.");
      }
      transaction.set(gameWeekRef, gameWeek.toMap());
      transaction.update(teamRef, {'activeGameWeekId': gameWeekRef.id});
    });

    final members = await fetchMembers(gameWeek.teamId);
    await sendNotification(
      teamId: gameWeek.teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.newGameweek,
      title: 'New gameweek',
      body: 'Gameweek ${gameWeek.weekNumber} is open — get your pick in before the deadline.',
    );
  }

  /// Marks a gameweek settled and clears the team's active pointer, so a
  /// new one can be created. Not yet wired to a UI button — ready for when
  /// the manual-settlement screen is rebuilt.
  Future<void> settleGameWeek({required String teamId, required String gameWeekId}) async {
    final teamRef = _db.collection('teams').doc(teamId);
    final gameWeekRef = _db.collection('gameWeeks').doc(gameWeekId);

    await _db.runTransaction((transaction) async {
      final teamSnap = await transaction.get(teamRef);

      transaction.update(gameWeekRef, {'isSettled': true});
      if (teamSnap.data()?['activeGameWeekId'] == gameWeekId) {
        transaction.update(teamRef, {'activeGameWeekId': null});
      }
    });
  }


Future<Team> createTeam({required String name, required String season, required String managerId}) async {
    final inviteCode = _generateInviteCode();

    final docRef = await _db.collection('teams').add({
      'name': name,
      'managerId': managerId,
      'memberIds': [managerId],
      'inviteCode': inviteCode,
      'createdAt': DateTime.now(),
      'season': season,
      'activeGameWeekId': null,
    });

    final doc = await docRef.get();
    return Team.fromMap(doc.id, doc.data()!);
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final uuidBytes = const Uuid().v4().replaceAll('-', '');
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      final hexPair = int.parse(uuidBytes.substring(i * 2, i * 2 + 2), radix: 16);
      buffer.write(chars[hexPair % chars.length]);
    }
    return buffer.toString();
  }

  Future<Team> joinTeam({required String inviteCode, required String userId}) async {
    final snapshot = await _db
        .collection('teams')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('No team found with that invite code.');
    }

    final doc = snapshot.docs.first;
    await doc.reference.update({
      'memberIds': FieldValue.arrayUnion([userId]),
    });

    final updated = await doc.reference.get();
    return Team.fromMap(updated.id, updated.data()!);
  }

  Future<void> updateUserTeamIds({required String userId, required List<String> teamIds}) async {
    await _db.collection('users').doc(userId).update({'teamIds': teamIds});
  }

  Future<void> addMember(Member member) async {
    final docId = '${member.teamId}_${member.userId}';
    await _db.collection('members').doc(docId).set(member.toMap());
  }

  /// Only a manager can call this — enforced server-side by the rules,
  /// not just hidden in the UI.
  Future<void> setMemberRole({required String memberDocId, required MemberRole role}) async {
    await _db.collection('members').doc(memberDocId).update({'role': role.value});
  }
}