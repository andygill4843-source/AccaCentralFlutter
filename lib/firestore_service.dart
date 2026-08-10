import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';
import 'package:uuid/uuid.dart';

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

  Future<List<GameWeek>> fetchGameWeeks(String teamId) async {
    final snapshot = await _db
        .collection('gameWeeks')
        .where('teamId', isEqualTo: teamId)
        .orderBy('weekNumber')
        .get();
    return snapshot.docs.map((doc) => GameWeek.fromMap(doc.id, doc.data())).toList();
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
      transaction.update(gameWeekRef, {'isSettled': true});
      final teamSnap = await transaction.get(teamRef);
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
    await _db.collection('members').add(member.toMap());
  }
}