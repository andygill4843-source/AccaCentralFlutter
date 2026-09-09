import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';
import 'package:uuid/uuid.dart';
import 'scoring_engine.dart'; // for LeagueTableEntry
import 'tournament_bracket_engine.dart';
import 'odds_format.dart';

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

  /// Firestore doc IDs can't contain '/', but season strings like "2026/27"
  /// do — replace it with a safe separator so the ID stays valid and
  /// fetch/create always agree on the same doc.
  String _seasonSettingsDocId(String teamId, String season) {
    return '${teamId}_${season.replaceAll('/', '-')}';
  }

  Future<SeasonSettings?> fetchSeasonSettings({required String teamId, required String season}) async {
    final doc = await _db.collection('seasonSettings').doc(_seasonSettingsDocId(teamId, season)).get();
    if (!doc.exists) return null;
    return SeasonSettings.fromMap(doc.id, doc.data()!);
  }

  Future<void> updateMemberDisplayName({required String memberDocId, required String newDisplayName}) async {
  await _db.collection('members').doc(memberDocId).update({'displayName': newDisplayName});
  }

  Future<void> updateGameWeekDeadline({required String gameWeekId, required DateTime newDeadline}) async {
    await _db.collection('gameWeeks').doc(gameWeekId).update({'deadline': newDeadline});
  }

  Future<void> createSeasonSettings(SeasonSettings settings) async {
    final docId = _seasonSettingsDocId(settings.teamId, settings.season);
    await _db.collection('seasonSettings').doc(docId).set(settings.toMap());
  }

  Future<int> fetchPhysioSessionsUsed({required String teamId, required String memberId, required String season}) async {
    final snapshot = await _db
        .collection('physioSessions')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('season', isEqualTo: season)
        .get();
    return snapshot.docs.length;
  }

  Future<List<PhysioSession>> fetchPhysioSessions(String teamId) async {
    final snapshot = await _db.collection('physioSessions').where('teamId', isEqualTo: teamId).get();
    return snapshot.docs.map((doc) => PhysioSession.fromMap(doc.id, doc.data())).toList();
  }

  /// Whether [memberId] has an active (unconsumed by a leg yet, or already
  /// applied) physio booking for this specific gameweek.
  Future<bool> hasPhysioProtectionPending({required String teamId, required String memberId, required String gameWeekId}) async {
    final snapshot = await _db
        .collection('physioSessions')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Books a physio session for [memberId] on [gameWeek]. If they've already
  /// submitted a leg for this gameweek, that leg is protected immediately;
  /// otherwise protection is picked up automatically whenever they do submit
  /// (see PickOutcomeScreen.submit()/submitCombo()).
  Future<void> bookPhysioSession({
    required String teamId,
    required String memberId,
    required String memberName,
    required String season,
    required GameWeek gameWeek,
  }) async {
    if (gameWeek.id == null) return;
    final settings = await fetchSeasonSettings(teamId: teamId, season: season);
    final maxSessions = settings?.maxPhysioSessionsPerMember ?? 2;
    final usedThisSeason = await fetchPhysioSessionsUsed(teamId: teamId, memberId: memberId, season: season);
    if (usedThisSeason >= maxSessions) {
      throw Exception('No physio sessions remaining this season.');
    }
    final alreadyBooked = await hasPhysioProtectionPending(teamId: teamId, memberId: memberId, gameWeekId: gameWeek.id!);
    if (alreadyBooked) {
      throw Exception('Already booked a physio session for this gameweek.');
    }
    final session = PhysioSession(
      teamId: teamId,
      memberId: memberId,
      memberName: memberName,
      season: season,
      gameWeekId: gameWeek.id!,
      weekNumber: gameWeek.weekNumber,
      usedAt: DateTime.now(),
    );
    await _db.collection('physioSessions').add(session.toMap());

    final legSnap = await _db
        .collection('legs')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('gameWeekId', isEqualTo: gameWeek.id)
        .limit(1)
        .get();
    if (legSnap.docs.isNotEmpty) {
      await legSnap.docs.first.reference.update({'physioProtected': true});
    }

    final members = await fetchMembers(teamId);
    final physioMessages = [
      "$memberName books in with the physio for week ${gameWeek.weekNumber}. Nothing a massage and an ice bath can't sort out 💪",
      '$memberName has gone into recovery mode for week ${gameWeek.weekNumber}. They\'ve protected their points for the week 👀',
    ];
    await sendNotification(
      teamId: teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.physioUsed,
      title: '🚑 PHYSIO ALERT 🩺',
      body: physioMessages[Random().nextInt(physioMessages.length)],
    );
  }

  Future<void> createChallenge(Challenge challenge) async {
    await _db.collection('challenges').add(challenge.toMap());
    final members = await fetchMembers(challenge.teamId);
    await sendNotification(
      teamId: challenge.teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.challengePlaced,
      title: '🤺 CHALLENGE TIME 👊',
      body: "${challenge.challengerName} doesn't fancy ${challenge.challengedName}'s chances and lays down a challenge!",
    );
  }

  // ============================================================
  // KNOCKOUT TOURNAMENT
  // ============================================================

  /// Creates the season's tournament and notifies every current member of
  /// the draw date/time. Bracket size isn't known yet (member count can
  /// still change before the draw actually happens) — that gets computed
  /// and stored separately once the manager triggers the draw.
  Future<void> createTournament(Tournament tournament) async {
    await _db.collection('tournaments').add(tournament.toMap());
    final members = await fetchMembers(tournament.teamId);
    final dt = tournament.drawDateTime;
    final formatted =
        '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    await sendNotification(
      teamId: tournament.teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.tournamentDrawDateSet,
      title: 'Tournament draw date set 🗓️',
      body: '${tournament.name} — the draw is set for $formatted. Get ready!',
    );
  }

  Future<Tournament?> fetchTournament({required String teamId, required String season}) async {
    final snapshot = await _db
        .collection('tournaments')
        .where('teamId', isEqualTo: teamId)
        .where('season', isEqualTo: season)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Tournament.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  /// Live league-table position (1-indexed) per memberId, at the moment
  /// this is called — used for big-cup-tie detection at each round's draw.
  /// NOTE: once secondary tournament legs exist (a later stage), this must
  /// exclude them from scoring — only the primary leg counts toward the
  /// main league table. ScoringEngine.buildLeagueTable doesn't yet
  /// distinguish primary/secondary legs; revisit this once that stage
  /// actually introduces secondary legs, since right now none exist to
  /// double-count.
  Future<Map<String, int>> _leagueTablePositions({required String teamId, required String season}) async {
    final members = await fetchMembers(teamId);
    final allLegs = await fetchLegs(teamId);
    final gameWeeks = await fetchGameWeeks(teamId);
    final seasonGameWeekIds = gameWeeks.where((g) => g.season == season).map((g) => g.id).toSet();
    final seasonLegs = allLegs.where((l) => seasonGameWeekIds.contains(l.gameWeekId)).toList();
    final challenges = await fetchChallenges(teamId: teamId, season: season);
    final table = ScoringEngine.buildLeagueTable(members: members, legs: seasonLegs, challenges: challenges);
    return {for (var i = 0; i < table.length; i++) table[i].memberId: i + 1};
  }

  Future<List<TournamentMatch>> fetchTournamentMatches({required String teamId, required String tournamentId}) async {
    final snapshot = await _db
        .collection('tournamentMatches')
        .where('teamId', isEqualTo: teamId)
        .where('tournamentId', isEqualTo: tournamentId)
        .get();
    return snapshot.docs.map((d) => TournamentMatch.fromMap(d.id, d.data())).toList();
  }

  Future<List<TournamentMatch>> fetchTournamentMatchesForRound({
    required String teamId,
    required String tournamentId,
    required int roundSize,
  }) async {
    final snapshot = await _db
        .collection('tournamentMatches')
        .where('teamId', isEqualTo: teamId)
        .where('tournamentId', isEqualTo: tournamentId)
        .where('roundSize', isEqualTo: roundSize)
        .get();
    return snapshot.docs.map((d) => TournamentMatch.fromMap(d.id, d.data())).toList();
  }

  /// The manager's "draw" for a brand-new tournament with no rounds yet.
  /// Splits the current membership into byes + a preliminary round (or
  /// straight into the main bracket if the count is already a power of 2).
  /// Every member currently on the team is a participant.
  Future<void> drawInitialTournamentRound(Tournament tournament) async {
    if (tournament.id == null) throw Exception('Tournament has no id.');
    final existing = await fetchTournamentMatches(teamId: tournament.teamId, tournamentId: tournament.id!);
    if (existing.isNotEmpty) {
      throw Exception('This tournament has already been drawn.');
    }
    final members = await fetchMembers(tournament.teamId);
    final participants = [for (final m in members) if (m.id != null) (id: m.id!, name: m.displayName)]..shuffle();
    if (participants.length < 2) {
      throw Exception('Need at least 2 members to draw a tournament.');
    }
    final positions = await _leagueTablePositions(teamId: tournament.teamId, season: tournament.season);
    final matches = TournamentBracketEngine.buildInitialRound(
      tournament: tournament,
      shuffledParticipants: participants,
      leaguePositions: positions,
    );
    final mainBracketSize = TournamentBracketEngine.largestPowerOfTwoAtMost(participants.length);
    final firstRoundSize = matches.isNotEmpty ? matches.first.roundSize : mainBracketSize;

    final batch = _db.batch();
    for (final match in matches) {
      final ref = _db.collection('tournamentMatches').doc();
      batch.set(ref, match.toMap());
    }
    batch.update(_db.collection('tournaments').doc(tournament.id), {
      'mainBracketSize': mainBracketSize,
      'currentRoundSize': firstRoundSize,
      'status': TournamentStatus.inProgress.value,
    });
    await batch.commit();
  }

  /// Draws the next round once every match in the current round has a
  /// winnerMemberId set. Throws if that gate isn't met, or if the current
  /// round was already the Final (tournament is complete at that point).
  Future<void> drawNextTournamentRound(Tournament tournament) async {
    if (tournament.id == null || tournament.currentRoundSize == null) {
      throw Exception('This tournament has not had its first draw yet.');
    }
    if (tournament.currentRoundSize == 2) {
      throw Exception('The Final is the last round — nothing left to draw.');
    }
    final currentMatches = await fetchTournamentMatchesForRound(
      teamId: tournament.teamId,
      tournamentId: tournament.id!,
      roundSize: tournament.currentRoundSize!,
    );
    if (currentMatches.isEmpty) {
      throw Exception('No matches found for the current round.');
    }
    if (currentMatches.any((m) => m.winnerMemberId == null)) {
      throw Exception('Not every match in the current round has been settled yet.');
    }
    final nextRoundSize =
        tournament.currentRoundSize == 0 ? tournament.mainBracketSize! : tournament.currentRoundSize! ~/ 2;
    final alreadyDrawn = await fetchTournamentMatchesForRound(
      teamId: tournament.teamId,
      tournamentId: tournament.id!,
      roundSize: nextRoundSize,
    );
    if (alreadyDrawn.isNotEmpty) {
      throw Exception('The next round has already been drawn.');
    }
    final winners = [
      for (final m in currentMatches) (id: m.winnerMemberId!, name: m.winnerName ?? m.memberAName)
    ]..shuffle();
    final positions = await _leagueTablePositions(teamId: tournament.teamId, season: tournament.season);
    final matches = TournamentBracketEngine.buildNextRound(
      tournament: tournament,
      completedRoundSize: tournament.currentRoundSize!,
      shuffledWinners: winners,
      leaguePositions: positions,
    );
    if (matches.isEmpty) {
      throw Exception('Tournament is already complete.');
    }
    final batch = _db.batch();
    for (final match in matches) {
      final ref = _db.collection('tournamentMatches').doc();
      batch.set(ref, match.toMap());
    }
    batch.update(_db.collection('tournaments').doc(tournament.id), {
      'currentRoundSize': matches.first.roundSize,
    });
    await batch.commit();
  }

  /// Whether every match in the tournament's current round has a winner —
  /// used to gate the "Draw Next Round" button. False (not thrown) if
  /// there's no current round or no matches at all, so it's safe to use
  /// directly for UI enable/disable state.
  Future<bool> isCurrentTournamentRoundFullySettled(Tournament tournament) async {
    if (tournament.id == null || tournament.currentRoundSize == null) return false;
    final matches = await fetchTournamentMatchesForRound(
      teamId: tournament.teamId,
      tournamentId: tournament.id!,
      roundSize: tournament.currentRoundSize!,
    );
    if (matches.isEmpty) return false;
    return matches.every((m) => m.winnerMemberId != null);
  }

  Future<void> _notifyTournamentDrawLive({required String teamId, required String tournamentName}) async {
    final members = await fetchMembers(teamId);
    await sendNotification(
      teamId: teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.tournamentDrawLive,
      title: 'The draw is live! 📺',
      body: '$tournamentName — find out who you\'re facing next.',
    );
  }

  Future<void> _notifyTournamentMatchDrawn(TournamentMatch match) async {
    if (match.isBye || match.memberBId == null) return; // nothing to draw for a bye
    await sendNotification(
      teamId: match.teamId,
      recipientMemberIds: [match.memberAId, match.memberBId!],
      type: NotificationType.tournamentDrawnAgainst,
      title: 'You\'ve been drawn! ⚔️',
      body: '${match.memberAName} will face ${match.memberBName} in the ${tournamentRoundLabel(match.roundSize)}.',
    );
    if (match.isBigCupTie) {
      await sendNotification(
        teamId: match.teamId,
        recipientMemberIds: [match.memberAId, match.memberBId!],
        type: NotificationType.tournamentBigCupTie,
        title: 'Big Cup Tie! 🏆',
        body: '${match.memberAName} vs ${match.memberBName} — two closely-matched rivals go head to head.',
      );
    }
  }

  Future<void> _notifyTournamentDrawCompleted({required String teamId, required String tournamentName}) async {
    final members = await fetchMembers(teamId);
    await sendNotification(
      teamId: teamId,
      recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
      type: NotificationType.tournamentDrawCompleted,
      title: 'Draw complete ✅',
      body: '$tournamentName — the full draw is now revealed.',
    );
  }

  /// Reveals every not-yet-revealed match in the round at once, notifying
  /// each pairing (and the whole team once done) as part of the same call.
  Future<void> revealAllTournamentMatches({
    required String tournamentId,
    required int roundSize,
    required String teamId,
    required String tournamentName,
  }) async {
    await _notifyTournamentDrawLive(teamId: teamId, tournamentName: tournamentName);
    final matches = await fetchTournamentMatchesForRound(teamId: teamId, tournamentId: tournamentId, roundSize: roundSize);
    final unrevealed = matches.where((m) => !m.revealed).toList();
    if (unrevealed.isEmpty) return;
    final batch = _db.batch();
    for (final match in unrevealed) {
      if (match.id == null) continue;
      batch.update(_db.collection('tournamentMatches').doc(match.id), {'revealed': true});
    }
    await batch.commit();
    for (final match in unrevealed) {
      await _notifyTournamentMatchDrawn(match);
    }
    await _notifyTournamentDrawCompleted(teamId: teamId, tournamentName: tournamentName);
  }

  /// Sends the "draw is live" notice once, ahead of a one-by-one reveal —
  /// call this before the first call to revealNextTournamentMatch.
  Future<void> notifyTournamentDrawStarting({required String teamId, required String tournamentName}) {
    return _notifyTournamentDrawLive(teamId: teamId, tournamentName: tournamentName);
  }

  /// Reveals exactly one not-yet-revealed match, for the one-by-one reveal
  /// flow. Returns true if there are more matches still waiting after this
  /// one, so the caller knows whether to keep looping.
  Future<bool> revealNextTournamentMatch({
    required String tournamentId,
    required int roundSize,
    required String teamId,
    required String tournamentName,
  }) async {
    final matches = await fetchTournamentMatchesForRound(teamId: teamId, tournamentId: tournamentId, roundSize: roundSize);
    final unrevealed = matches.where((m) => !m.revealed).toList();
    if (unrevealed.isEmpty) return false;
    final next = unrevealed.first;
    if (next.id != null) {
      await _db.collection('tournamentMatches').doc(next.id).update({'revealed': true});
    }
    await _notifyTournamentMatchDrawn(next);
    final remaining = unrevealed.length - 1;
    if (remaining == 0) {
      await _notifyTournamentDrawCompleted(teamId: teamId, tournamentName: tournamentName);
    }
    return remaining > 0;
  }

  /// Whether the tournament's current round has already been attached to
  /// some gameweek (i.e. at least one match in it already has a
  /// gameWeekId) — used to gate the "Part of tournament?" toggle in
  /// gameweek setup to only rounds that haven't been assigned yet.
  Future<bool> isTournamentRoundAttached({
    required String teamId,
    required String tournamentId,
    required int roundSize,
  }) async {
    final matches = await fetchTournamentMatchesForRound(teamId: teamId, tournamentId: tournamentId, roundSize: roundSize);
    return matches.any((m) => m.gameWeekId != null);
  }

  /// Attaches every match in the tournament's current round to
  /// [gameWeekId] — the whole round plays out together in one gameweek,
  /// not match-by-match.
  Future<void> attachTournamentRoundToGameWeek({
    required String teamId,
    required String tournamentId,
    required int roundSize,
    required String gameWeekId,
  }) async {
    final matches = await fetchTournamentMatchesForRound(teamId: teamId, tournamentId: tournamentId, roundSize: roundSize);
    final batch = _db.batch();
    for (final match in matches) {
      if (match.id == null) continue;
      batch.update(_db.collection('tournamentMatches').doc(match.id), {'gameWeekId': gameWeekId});
    }
    await batch.commit();
  }

  /// The member's own unresolved, real (non-bye) TournamentMatch for
  /// [gameWeekId], if this gameweek is tournament-linked and the member is
  /// still active in the current round. Null means: not a tournament
  /// round, the member isn't in it, or their match already has a winner —
  /// any of which means they get the normal single-leg flow instead.
  Future<TournamentMatch?> fetchActiveTournamentMatchForGameWeek({
    required String teamId,
    required String gameWeekId,
    required String memberId,
  }) async {
    final snapshot = await _db
        .collection('tournamentMatches')
        .where('teamId', isEqualTo: teamId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .get();
    for (final doc in snapshot.docs) {
      final match = TournamentMatch.fromMap(doc.id, doc.data());
      if (match.isBye || match.winnerMemberId != null) continue;
      if (match.memberAId == memberId || match.memberBId == memberId) return match;
    }
    return null;
  }

  /// Flips which of a member's two tournament legs is primary vs
  /// secondary. Both legs already exist as fully independent picks (own
  /// fixture, odds, outcome) — swapping never re-fetches or re-picks
  /// anything, it's purely a role change on the two existing documents.
  Future<void> swapPrimaryAndSecondaryLegs({
    required String primaryLegId,
    required String secondaryLegId,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('legs').doc(primaryLegId), {'isSecondaryTournamentLeg': true});
    batch.update(_db.collection('legs').doc(secondaryLegId), {'isSecondaryTournamentLeg': false});
    await batch.commit();
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
          title: challengerWon ? '🥇 CHALLENGE CHAMPION 🥇' : '🤪 CHALLENGE LOST',
          body: challengerWon
              ? '${challenge.challengerName} called it and it doesn\'t look like ${challenge.challengedName} has what it takes!'
              : 'That aged well! Too big for your boots ${challenge.challengerName}. Enjoy the points ${challenge.challengedName}.',
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

  /// Removes a member from the team. Concretely: removes their userId from
  /// team.memberIds (the Firestore-level access check) and deletes their
  /// member document. Historical data (legs, fines, etc.) is left intact —
  /// it still shows in league history under their old display name.
  /// Note: their AppUser document's teamIds list is NOT updated here
  /// (would require a Cloud Function to write to another user's doc).
  /// Their app will simply fail to load the team once they're no longer
  /// in memberIds.
  Future<void> removeMember({
    required String teamId,
    required String memberId,
    required String userId,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('teams').doc(teamId), {
      'memberIds': FieldValue.arrayRemove([userId]),
    });
    batch.delete(_db.collection('members').doc(memberId));
    await batch.commit();
  }

  Future<void> setTeamSeason({required String teamId, required String season}) async {
    await _db.collection('teams').doc(teamId).update({'season': season});
  }

  // ============================================================
  // FIXTURE ODDS CACHE
  // ============================================================

  /// Returns cached odds for a fixture, or null if not yet fetched.
  Future<FixtureOddsCache?> fetchFixtureOddsCache(int apiFootballFixtureId) async {
    final snapshot = await _db
        .collection('fixtureOdds')
        .where('apiFootballFixtureId', isEqualTo: apiFootballFixtureId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return FixtureOddsCache.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  /// Saves or overwrites cached odds for a fixture.
  Future<void> saveFixtureOddsCache(FixtureOddsCache cache) async {
    if (cache.id != null) {
      await _db.collection('fixtureOdds').doc(cache.id).set(cache.toMap());
    } else {
      await _db.collection('fixtureOdds').add(cache.toMap());
    }
  }

  // ============================================================
  // LIVE MATCH EVENTS
  // ============================================================

  /// Records a processed live match event so it isn't notified twice.
  Future<void> recordLiveMatchEvent({
    required int apiFootballFixtureId,
    required String eventId,
    required String teamId,
    required String type,
    required String detail,
    required int elapsed,
    required String teamName,
    String? playerName,
  }) async {
    await _db.collection('liveMatchEvents').add({
      'apiFootballFixtureId': apiFootballFixtureId,
      'eventId': eventId,
      'teamId': teamId,
      'type': type,
      'detail': detail,
      'elapsed': elapsed,
      'teamName': teamName,
      'playerName': playerName,
      'processedAt': DateTime.now(),
    });
  }

  /// Returns the set of already-processed event IDs for a fixture.
  Future<Set<String>> fetchProcessedEventIds(int apiFootballFixtureId) async {
    final snapshot = await _db
        .collection('liveMatchEvents')
        .where('apiFootballFixtureId', isEqualTo: apiFootballFixtureId)
        .get();
    return snapshot.docs
        .map((d) => d.data()['eventId'] as String)
        .toSet();
  }

  // ============================================================
  // SEASON SUMMARIES
  // ============================================================

  Future<List<SeasonSummary>> fetchSeasonSummariesForMember({
    required String teamId,
    required String memberId,
  }) async {
    final snapshot = await _db
        .collection('seasonSummaries')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .get();
    final summaries = snapshot.docs
        .map((d) => SeasonSummary.fromMap(d.id, d.data()))
        .toList();
    summaries.sort((a, b) => b.season.compareTo(a.season));
    return summaries;
  }

  Future<SeasonSummary?> fetchSeasonSummary({
    required String teamId,
    required String memberId,
    required String season,
  }) async {
    final snapshot = await _db
        .collection('seasonSummaries')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('season', isEqualTo: season)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return SeasonSummary.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

  Future<void> createSeasonSummary(SeasonSummary summary) async {
    await _db.collection('seasonSummaries').add(summary.toMap());
  }

  /// Generates and saves a SeasonSummary for every member at season end.
  /// Called from gameweek_setup_screen's endSeason() flow, just before
  /// the season actually advances, so all the current-season data is
  /// still in place when this runs.
  Future<void> generateSeasonSummaries({
    required String teamId,
    required String season,
    required List<Member> members,
    required List<AccumulatorLeg> legs,
    required List<GameWeek> gameWeeks,
    required List<Challenge> challenges,
    Tournament? tournament,
    List<TournamentMatch> tournamentMatches = const [],
  }) async {
    final table = ScoringEngine.buildLeagueTable(
      members: members,
      legs: legs,
      challenges: challenges,
    );
    final memberStats = MemberStatsEngine.buildMemberStats(
      members: members,
      legs: legs,
      gameWeeks: gameWeeks,
    );
    final statsById = {for (final s in memberStats) s.memberId: s};

    for (int i = 0; i < table.length; i++) {
      final entry = table[i];
      final stats = statsById[entry.memberId];

      // Cup result for this member.
      String? cupResult;
      if (tournament != null && tournamentMatches.isNotEmpty) {
        final memberMatches = tournamentMatches
            .where((m) => !m.isBye && (m.memberAId == entry.memberId || m.memberBId == entry.memberId))
            .toList();
        if (memberMatches.isNotEmpty) {
          final finalMatch = tournamentMatches.where((m) => m.roundSize == 2).firstOrNull;
          if (finalMatch?.winnerMemberId == entry.memberId) {
            cupResult = 'Champion 🏆';
          } else {
            final deepest = memberMatches.reduce((a, b) => a.roundSize < b.roundSize ? a : b);
            cupResult = 'Reached the ${tournamentRoundLabel(deepest.roundSize)}';
          }
        }
      }

      // Biggest win description.
      String? biggestWinDesc;
      if (entry.biggestWin != null) {
        biggestWinDesc = entry.biggestWin!.selectionDescription;
      }

      // Pre-season recommendations based on their own stats.
      final recs = <String>[];
      if (stats != null) {
        final winRate = entry.legsPlayed == 0 ? 0.0 : entry.legsWon / entry.legsPlayed;
        if (winRate < 0.3 && entry.legsPlayed >= 5) {
          recs.add('Your win rate was ${(winRate * 100).round()}% this season — consider sticking to shorter-odds picks to build consistency.');
        } else if (winRate > 0.6 && entry.legsPlayed >= 5) {
          recs.add('Great win rate of ${(winRate * 100).round()}%! Consider pushing for bigger odds to maximise your weighted points.');
        }
        if (stats.avgPickTimeMinutes != null && stats.avgPickTimeMinutes! > 60 * 48) {
          recs.add('You tend to pick late in the week — try locking in earlier to avoid deadline pressure.');
        }
        if (entry.longestWinStreak >= 3) {
          recs.add('You hit a ${entry.longestWinStreak}-game winning streak — keep that momentum going next season.');
        }
        if (stats.valueHunterCount > 0) {
          recs.add('You picked ${stats.valueHunterCount} high-value leg${stats.valueHunterCount == 1 ? '' : 's'} (3/1+) this season — value betting suits you.');
        }
        if (i <= 2) {
          recs.add("You finished in the top 3 — you're a genuine title contender. Consistency is your friend next season.");
        } else if (i >= table.length - 2 && table.length > 3) {
          recs.add('Finishing near the bottom can hurt — try to pick more consistently and avoid risky bets in the early weeks.');
        }
      }
      if (recs.isEmpty) {
        recs.add('Keep making your picks every week — consistency is the foundation of winning the league.');
      }

      // Check if a summary already exists for this member+season to avoid duplicates.
      final existing = await fetchSeasonSummary(teamId: teamId, memberId: entry.memberId, season: season);
      if (existing != null) continue;

      final summary = SeasonSummary(
        teamId: teamId,
        memberId: entry.memberId,
        memberDisplayName: entry.displayName,
        season: season,
        leaguePosition: i + 1,
        totalMembers: table.length,
        totalBasePoints: entry.totalBasePoints,
        totalWeightedPoints: entry.totalWeightedPoints,
        legsPlayed: entry.legsPlayed,
        legsWon: entry.legsWon,
        longestWinStreak: entry.longestWinStreak,
        biggestWinDescription: biggestWinDesc,
        biggestWinOdds: entry.biggestWin?.decimalOddsAtSelection,
        cupName: tournament?.name,
        cupResult: cupResult,
        recommendations: recs,
        createdAt: DateTime.now(),
      );
      await createSeasonSummary(summary);
    }
  }

  // ============================================================
  // KUDOS REACTIONS
  // ============================================================

  Future<List<Reaction>> fetchReactionsForGameWeek({
    required String teamId,
    required String gameWeekId,
  }) async {
    final snapshot = await _db
        .collection('reactions')
        .where('teamId', isEqualTo: teamId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .get();
    return snapshot.docs.map((d) => Reaction.fromMap(d.id, d.data())).toList();
  }

  /// Toggle: if the reactor already reacted to this leg with this emoji,
  /// remove the reaction; otherwise add it. Sends a notification to the
  /// leg's owner when a new reaction is added (not on removal — that
  /// would be confusing).
  Future<void> toggleReaction({
    required String teamId,
    required String legId,
    required String gameWeekId,
    required String reactorMemberId,
    required String reactorName,
    required String recipientMemberId,
    required String emoji,
  }) async {
    // Find any existing reaction from this reactor on this leg — regardless
    // of emoji, since each person can only hold one reaction per leg at a time.
    final existing = await _db
        .collection('reactions')
        .where('teamId', isEqualTo: teamId)
        .where('legId', isEqualTo: legId)
        .where('reactorMemberId', isEqualTo: reactorMemberId)
        .get();
    if (existing.docs.isNotEmpty) {
      final existingDoc = existing.docs.first;
      final existingEmoji = existingDoc.data()['emoji'] as String? ?? '';
      await existingDoc.reference.delete();
      // Same emoji tapped again → pure toggle off, nothing more to do.
      if (existingEmoji == emoji) return;
      // Different emoji → remove the old one and fall through to add the new one.
    }
    final reaction = Reaction(
      teamId: teamId,
      legId: legId,
      gameWeekId: gameWeekId,
      reactorMemberId: reactorMemberId,
      reactorName: reactorName,
      recipientMemberId: recipientMemberId,
      emoji: emoji,
      createdAt: DateTime.now(),
    );
    await _db.collection('reactions').add(reaction.toMap());
    // Only notify if reacting to someone else's leg.
    if (reactorMemberId != recipientMemberId) {
      await sendNotification(
        teamId: teamId,
        recipientMemberIds: [recipientMemberId],
        type: NotificationType.kudosReceived,
        title: '$emoji Kudos!',
        body: '$reactorName reacted to your selection.',
      );
    }
  }

  Future<Team?> fetchTeam(String teamId) async {
    final doc = await _db.collection('teams').doc(teamId).get();
    if (!doc.exists) return null;
    return Team.fromMap(doc.id, doc.data()!);
  }

  Future<List<Fine>> fetchFines(String teamId) async {
    final snapshot = await _db.collection('fines').where('teamId', isEqualTo: teamId).get();
    final fines = snapshot.docs.map((doc) => Fine.fromMap(doc.id, doc.data())).toList();

    // Resolve any disputes whose 3-day window has passed — client-side
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
          title: finalStatus == FineStatus.overturned ? '👨🏻‍⚖️ Dispute resolved 👨🏻‍⚖️' : '👺 Dispute resolved 👺',
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
    // Notify the whole team — everyone should know when someone's been fined.
    final members = await fetchMembers(fine.teamId);
    final allMemberIds = [for (final m in members) if (m.id != null) m.id!];
    final otherMemberIds = allMemberIds.where((id) => id != fine.memberId).toList();
    // Personal notification to the fined member.
    await sendNotification(
      teamId: fine.teamId,
      recipientMemberIds: [fine.memberId],
      type: NotificationType.fineIssued,
      title: '👺 Fine issued 👺',
      body: 'You have been fined by the gaffa — ${fine.fineType.displayName}.',
    );
    // Squad-wide notification to everyone else.
    if (otherMemberIds.isNotEmpty) {
      await sendNotification(
        teamId: fine.teamId,
        recipientMemberIds: otherMemberIds,
        type: NotificationType.fineIssued,
        title: '👺 The gaffa\'s put their foot down 👺',
        body: 'Enough is enough! ${fine.memberName} has been fined by the gaffa.',
      );
    }
  }

  // ============================================================
  // YELLOW CARDS
  // ============================================================

  /// Random-variant copy, matching the playful/team-banter tone used
  /// elsewhere (walkovers, round won/lost) — these go to the whole team,
  /// not just the fined member, since they're meant to be seen and enjoyed
  /// by everyone.
  static const List<(String title, String bodySuffix)> _singleYellowCardMessages = [
    ('🟨 Left the referee with no choice. 🟨', "receives a yellow card. They're on thin ice."),
    ("🟨 They've gone into the book. 🟨", 'receives a yellow card. Could that come back to bite?'),
    ('🟨 Sometimes you have to take a yellow. 🟨', 'receives a yellow card. Walking on a tightrope.'),
  ];
  static const List<(String title, String bodySuffix)> _twoYellowCardFineMessages = [
    ('🟨➡️🟥 Two yellows, one red, and an early bath. 🟨➡️🟥', 'gets a second yellow and a fine.'),
    ("🟨➡️🟥 You can't be doing that in today's game. 🟨➡️🟥", 'gets a second yellow and a fine.'),
    ('🟨➡️🟥 A needless challenge from a player who knew he was already walking a tightrope. 🟨➡️🟥', 'gets a second yellow and a fine.'),
  ];

  Future<List<YellowCard>> fetchYellowCards({required String teamId, required String season}) async {
    final snapshot = await _db
        .collection('yellowCards')
        .where('teamId', isEqualTo: teamId)
        .where('season', isEqualTo: season)
        .get();
    return snapshot.docs.map((d) => YellowCard.fromMap(d.id, d.data())).toList();
  }

  /// Issues a yellow card, then automatically fines the member if this is
  /// their second unconsumed one this season — the fine goes through the
  /// exact same Fine flow as any manually-issued one (so it's still
  /// disputable), while the two contributing yellow cards get marked
  /// consumed, resetting the visible tally back to 0. Exactly one
  /// notification fires per call: the plain yellow-card one for a first
  /// card, or the fine one for a second — never both.
  Future<void> createYellowCard(YellowCard card) async {
    await _db.collection('yellowCards').add(card.toMap());

    final random = Random();
    final allMembers = await fetchMembers(card.teamId);
    final allMemberIds = [for (final m in allMembers) if (m.id != null) m.id!];

    final unconsumedSnapshot = await _db
        .collection('yellowCards')
        .where('teamId', isEqualTo: card.teamId)
        .where('memberId', isEqualTo: card.memberId)
        .where('season', isEqualTo: card.season)
        .where('consumedByFineId', isEqualTo: null)
        .get();

    if (unconsumedSnapshot.docs.length < 2) {
      final cardMessage = _singleYellowCardMessages[random.nextInt(_singleYellowCardMessages.length)];
      await sendNotification(
        teamId: card.teamId,
        recipientMemberIds: allMemberIds,
        type: NotificationType.yellowCardIssued,
        title: cardMessage.$1,
        body: '${card.memberName} ${cardMessage.$2}',
      );
      return;
    }

    // Consume the two oldest unconsumed cards, in case more than 2 ever
    // somehow accumulate before this check runs.
    final sorted = unconsumedSnapshot.docs.toList()
      ..sort((a, b) =>
          (a.data()['createdAt'] as Timestamp).compareTo(b.data()['createdAt'] as Timestamp));
    final toConsume = sorted.take(2).toList();

    final fine = Fine(
      teamId: card.teamId,
      memberId: card.memberId,
      memberName: card.memberName,
      fineType: FineType.twoYellowCards,
      reason: 'Accumulated two yellow cards this season.',
      status: FineStatus.pending,
      createdByMemberId: card.issuedByMemberId,
      createdByName: card.issuedByName,
      createdAt: DateTime.now(),
      season: card.season,
    );
    final fineRef = await _db.collection('fines').add(fine.toMap());

    final batch = _db.batch();
    for (final doc in toConsume) {
      batch.update(doc.reference, {'consumedByFineId': fineRef.id});
    }
    await batch.commit();

    final fineMessage = _twoYellowCardFineMessages[random.nextInt(_twoYellowCardFineMessages.length)];
    await sendNotification(
      teamId: card.teamId,
      recipientMemberIds: allMemberIds,
      type: NotificationType.fineIssued,
      title: fineMessage.$1,
      body: '${card.memberName} ${fineMessage.$2}',
    );
  }

  Future<void> respondToFine({
    required String fineId,
    required bool accept,
    String? disputeReason,
  }) async {
    if (accept) {
      await _db.collection('fines').doc(fineId).update({'status': FineStatus.accepted.value});
    } else {
      await _db.collection('fines').doc(fineId).update({
        'status': FineStatus.disputed.value,
        'disputeDeadline': DateTime.now().add(const Duration(days: 3)),
        if (disputeReason != null && disputeReason.isNotEmpty) 'disputeReason': disputeReason,
      });
      final fineDoc = await _db.collection('fines').doc(fineId).get();
      if (fineDoc.exists) {
        final fine = Fine.fromMap(fineDoc.id, fineDoc.data()!);
        final members = await fetchMembers(fine.teamId);
        await sendNotification(
          teamId: fine.teamId,
          recipientMemberIds: [for (final m in members) if (m.id != null) m.id!],
          type: NotificationType.fineDisputeVote,
          title: '🤔 Dispute lodged ✍️',
          body: '${fine.memberName} has disputed the gaffa\'s fine. Get your vote in!',
        );
      }
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

  /// Every leg a member has submitted for a gameweek — for a normal
  /// gameweek this is 0 or 1, but a tournament-linked gameweek can have up
  /// to 2 (primary + secondary), which fetchMemberLegForGameWeek's
  /// single-result design can't represent.
  Future<List<AccumulatorLeg>> fetchMemberLegsForGameWeek({
    required String teamId,
    required String memberId,
    required String gameWeekId,
  }) async {
    final snapshot = await _db
        .collection('legs')
        .where('teamId', isEqualTo: teamId)
        .where('memberId', isEqualTo: memberId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .get();
    return snapshot.docs.map((d) => AccumulatorLeg.fromMap(d.id, d.data())).toList();
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
      title: '🔐 Gameweek locked 🔐',
      body: 'Gameweek $weekNumber is locked in with $bookmaker — combined odds ${decimalToFractional(combinedOdds)}.'
    );
    await resolveTournamentWalkovers(teamId: teamId, gameWeekId: gameWeekId);
  }

  /// Called once a gameweek's odds are locked in — the confirmed trigger
  /// point for walkovers, since that's the moment selections are truly
  /// finalised for the week. Checks every still-unresolved, non-bye
  /// tournament match tied to this gameweek: if exactly one side never
  /// submitted a primary leg, the other side wins by walkover; if neither
  /// side submitted, a random pick between the two advances instead.
  /// Matches where both sides did submit are left for the scheduled
  /// cascade (settleLegs.js) to resolve once results are in.
  Future<void> resolveTournamentWalkovers({
    required String teamId,
    required String gameWeekId,
  }) async {
    final snapshot = await _db
        .collection('tournamentMatches')
        .where('teamId', isEqualTo: teamId)
        .where('gameWeekId', isEqualTo: gameWeekId)
        .get();
    final matches = snapshot.docs
        .map((d) => TournamentMatch.fromMap(d.id, d.data()))
        .where((m) => !m.isBye && m.winnerMemberId == null && m.memberBId != null)
        .toList();
    if (matches.isEmpty) return;

    final legs = await fetchLegs(teamId);
    final team = await fetchTeam(teamId);
    final tournament = await fetchTournament(teamId: teamId, season: team?.season ?? '');
    final tournamentName = tournament?.name ?? 'the tournament';
    final allMembers = await fetchMembers(teamId);
    final allMemberIds = [for (final m in allMembers) if (m.id != null) m.id!];
    final random = Random();

    for (final match in matches) {
      final aSubmitted = legs.any(
        (l) => l.tournamentMatchId == match.id && l.memberId == match.memberAId && !l.isSecondaryTournamentLeg,
      );
      final bSubmitted = legs.any(
        (l) => l.tournamentMatchId == match.id && l.memberId == match.memberBId && !l.isSecondaryTournamentLeg,
      );
      if (aSubmitted && bSubmitted) continue; // both submitted — leave for the scheduled cascade
      if (match.id == null) continue;

      final isWalkover = aSubmitted != bSubmitted;
      String winnerId;
      String winnerName;
      String? loserName;
      if (isWalkover) {
        if (aSubmitted) {
          winnerId = match.memberAId;
          winnerName = match.memberAName;
          loserName = match.memberBName;
        } else {
          winnerId = match.memberBId!;
          winnerName = match.memberBName ?? '';
          loserName = match.memberAName;
        }
      } else {
        // Neither side submitted — random pick between the two advances.
        final aWins = random.nextBool();
        winnerId = aWins ? match.memberAId : match.memberBId!;
        winnerName = aWins ? match.memberAName : (match.memberBName ?? '');
      }

      await _db.collection('tournamentMatches').doc(match.id).update({
        'winnerMemberId': winnerId,
        'winnerName': winnerName,
      });

      if (isWalkover && loserName != null) {
        await sendNotification(
          teamId: teamId,
          recipientMemberIds: allMemberIds,
          type: NotificationType.tournamentRoundWon,
          title: "🫣🚶‍➡️➡️ IT'S A WALKOVER 🫣🚶‍➡️➡️",
          body: '$winnerName progresses to the ${tournamentRoundLabel(match.roundSize)} in the $tournamentName '
              'after $loserName fails to submit a leg. Pressure isn\'t for everyone!',
        );
      }
    }
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
    return GameWeek.fromMap(gwDoc.id, gwDoc.data()!);
  }

  /// Whether every leg in [gameWeekId] has actually settled (won/lost) yet —
  /// intended to gate a manager's "End Gameweek" button, since ending a
  /// gameweek with legs still pending wouldn't reflect final results.
  Future<bool> areAllLegsSettled({required String teamId, required String gameWeekId}) async {
    final legsSnap = await _db.collection('legs').where('teamId', isEqualTo: teamId).where('gameWeekId', isEqualTo: gameWeekId).get();
    final legs = legsSnap.docs.map((d) => AccumulatorLeg.fromMap(d.id, d.data())).toList();
    return legs.isNotEmpty && legs.every((l) => l.outcome != LegOutcome.pending);
  }

  /// Explicitly ends a gameweek — now only ever triggered by the manager's
  /// "End Gameweek" button, not automatically once every leg happens to settle.
  Future<void> endActiveGameWeek({required String teamId, required GameWeek gameWeek}) async {
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
    final gameWeekLegs = seasonLegs.where((l) => l.gameWeekId == gameWeek.id && !l.isSecondaryTournamentLeg).toList();
    final teamWonCount = gameWeekLegs.where((l) => l.outcome == LegOutcome.won).length;
    final teamTotalCount = gameWeekLegs.length;
    final allWon = teamTotalCount > 0 && teamWonCount == teamTotalCount;
    if (teamTotalCount > 0) {
      for (int i = 0; i < table.length; i++) {
        final entry = table[i];
        await sendNotification(
          teamId: teamId,
          recipientMemberIds: [entry.memberId],
          type: NotificationType.leaguePosition,
          title: allWon ? '🏆 Gameweek ${gameWeek.weekNumber} settled 🏆' : '✅ Gameweek ${gameWeek.weekNumber} settled ✅',
          body: allWon
              ? "All legs are in for Gameweek ${gameWeek.weekNumber} and IT'S A WINNER — all legs win and you're now ${_ordinal(i + 1)} in the table."
              : "All legs are in for Gameweek ${gameWeek.weekNumber} and $teamWonCount / $teamTotalCount legs won — no winnings to count but you're now ${_ordinal(i + 1)} in the table.",
        );
      }
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
    if (leg.tournamentMatchId != null && !leg.isSecondaryTournamentLeg) {
      await _notifyTournamentOpponentOfSubmission(leg);
    }
  }

  /// "Your opponent has picked" nudge — fires once a member's primary
  /// tournament leg goes in, notifying only the other person in that
  /// specific match. The primary leg is what "your weekly selection"
  /// means everywhere else in the app, so that's the trigger — not the
  /// secondary pick.
  Future<void> _notifyTournamentOpponentOfSubmission(AccumulatorLeg leg) async {
    if (leg.tournamentMatchId == null) return;
    final matchDoc = await _db.collection('tournamentMatches').doc(leg.tournamentMatchId).get();
    if (!matchDoc.exists) return;
    final match = TournamentMatch.fromMap(matchDoc.id, matchDoc.data()!);
    if (match.isBye || match.memberBId == null) return;
    final opponentId = leg.memberId == match.memberAId ? match.memberBId! : match.memberAId;
    final submitterName = leg.memberId == match.memberAId ? match.memberAName : (match.memberBName ?? '');
    await sendNotification(
      teamId: leg.teamId,
      recipientMemberIds: [opponentId],
      type: NotificationType.tournamentOpponentSubmitted,
      title: 'Eyes on you 👀',
      body: '$submitterName has locked in their ${tournamentRoundLabel(match.roundSize)} selection. Time to get yours in!',
    );
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
      title: '🙌 New gameweek 🙌',
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