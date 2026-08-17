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

  Future<List<Team>> fetchTeams(List<String> teamIds) async {
    final teams = <Team>[];
    for (final id in teamIds) {
      final team = await fetchTeam(id);
      if (team != null) teams.add(team);
    }
    return teams;
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
  }

  Future<void> unlockGameWeek(String gameWeekId) async {
    final gameWeekRef = _db.collection('gameWeeks').doc(gameWeekId);

    await _db.runTransaction((transaction) async {
      final legsSnap = await _db.collection('legs').where('gameWeekId', isEqualTo: gameWeekId).get();

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
    return GameWeek.fromMap(gwDoc.id, gwDoc.data()!);
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