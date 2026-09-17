import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';
import 'package:uuid/uuid.dart';
import 'scoring_engine.dart';
import 'tournament_bracket_engine.dart';
import 'odds_format.dart';
import 'odds_api_service.dart';

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

  /// Member responds to a challenge placed against their leg — accept
  /// activates it ("game on"), decline ends it there permanently. Either
  /// way this uses up the challenger's attempt for the gameweek — a
  /// decline is not a free pass for them to try someone else instead.
  Future<void> respondToChallenge({
    required String challengeId,
    required bool accept,
  }) async {
    final doc = await _db.collection('challenges').doc(challengeId).get();
    if (!doc.exists) return;
    final challenge = Challenge.fromMap(doc.id, doc.data()!);

    await _db.collection('challenges').doc(challengeId).update({
      'status': accept ? ChallengeStatus.active.value : ChallengeStatus.declined.value,
    });

    final members = await fetchMembers(challenge.teamId);
    final memberIds = [for (final m in members) if (m.id != null) m.id!];

    if (accept) {
      await sendNotification(
        teamId: challenge.teamId,
        recipientMemberIds: memberIds,
        type: NotificationType.challengeAccepted,
        title: '💪 Challenge accepted 😱',
        body: '${challenge.challengedName} accepts the challenge from ${challenge.challengerName} 😱. Game on!',
      );
    } else {
      await sendNotification(
        teamId: challenge.teamId,
        recipientMemberIds: memberIds,
        type: NotificationType.challengeDeclined,
        title: '😢 Challenge declined 🙈',
        body: "${challenge.challengedName} doesn't fancy it. ${challenge.challengerName}'s challenge rejected! 🙈",
      );
    }
  }

  /// Challenges awaiting this member's accept/reject decision — surfaced
  /// as a popup whenever they open the app.
  Future<List<Challenge>> fetchPendingAcceptanceChallengesForMember({
    required String teamId,
    required String memberId,
  }) async {
    final snapshot = await _db
        .collection('challenges')
        .where('teamId', isEqualTo: teamId)
        .where('challengedMemberId', isEqualTo: memberId)
        .where('status', isEqualTo: ChallengeStatus.pendingAcceptance.value)
        .get();
    return snapshot.docs.map((d) => Challenge.fromMap(d.id, d.data())).toList();
  }

  // ============================================================
  // KNOCKOUT TOURNAMENT
  // ============================================================

    Future<void> createTournament(Tournament tournament) async {
    final existing = await fetchTournaments(teamId: tournament.teamId, season: tournament.season);
    final normalizedNewName = tournament.name.trim().toLowerCase();
    final duplicate = existing.any((t) => t.name.trim().toLowerCase() == normalizedNewName);
    if (duplicate) {
      throw Exception('A tournament called "${tournament.name.trim()}" already exists this season.');
    }

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

  /// The single tournament for a season — kept for existing call sites
  /// (season summaries) that predate multi-tournament support. Where
  /// there could be several, prefer fetchTournaments below.
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

  /// Every tournament for a season — a team can now run more than one
  /// knockout tournament at the same time.
  Future<List<Tournament>> fetchTournaments({required String teamId, required String season}) async {
    final snapshot = await _db
        .collection('tournaments')
        .where('teamId', isEqualTo: teamId)
        .where('season', isEqualTo: season)
        .get();
    return snapshot.docs.map((d) => Tournament.fromMap(d.id, d.data())).toList();
  }

  /// A single tournament's current document, by ID — used to refresh a
  /// specific tournament's state (e.g. currentRoundSize) after an action
  /// without needing to re-fetch the whole season's list.
  Future<Tournament?> fetchTournamentById(String tournamentId) async {
    final doc = await _db.collection('tournaments').doc(tournamentId).get();
    if (!doc.exists) return null;
    return Tournament.fromMap(doc.id, doc.data()!);
  }

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
  /// Restricted to tournament.participantMemberIds when set (the manager
  /// chose fewer rounds than the team size allows, and pre-selected
  /// exactly enough participants for that bracket size) — otherwise
  /// everyone currently on the team is eligible.
  Future<void> drawInitialTournamentRound(Tournament tournament) async {
    if (tournament.id == null) throw Exception('Tournament has no id.');
    final existing = await fetchTournamentMatches(teamId: tournament.teamId, tournamentId: tournament.id!);
    if (existing.isNotEmpty) {
      throw Exception('This tournament has already been drawn.');
    }
    final allMembers = await fetchMembers(tournament.teamId);
    final eligibleMembers = tournament.participantMemberIds != null
        ? allMembers.where((m) => tournament.participantMemberIds!.contains(m.id)).toList()
        : allMembers;
    final participants = [for (final m in eligibleMembers) if (m.id != null) (id: m.id!, name: m.displayName)]..shuffle();
    if (participants.length < 2) {
      throw Exception('Need at least 2 members to draw a tournament.');
    }
    final positions = await _leagueTablePositions(teamId: tournament.teamId, season: tournament.season);
    final matches = TournamentBracketEngine.buildInitialRound(
      tournament: tournament,
      shuffledParticipants: participants,
      leaguePositions: positions,
    );
    final naturalBracketSize = TournamentBracketEngine.largestPowerOfTwoAtMost(participants.length);
    final effectiveMainBracketSize = tournament.mainBracketSize ?? naturalBracketSize;
    final firstRoundSize = matches.isNotEmpty ? matches.first.roundSize : effectiveMainBracketSize;

    final batch = _db.batch();
    for (final match in matches) {
      final ref = _db.collection('tournamentMatches').doc();
      batch.set(ref, match.toMap());
    }
    batch.update(_db.collection('tournaments').doc(tournament.id), {
      'mainBracketSize': effectiveMainBracketSize,
      'currentRoundSize': firstRoundSize,
      'status': TournamentStatus.inProgress.value,
    });
    await batch.commit();
  }

  /// Draws the next round once every match in the current round has a
  /// winnerMemberId set. Which round comes next — another qualifying tier
  /// or the start of the real named rounds — is decided by how many
  /// winners there actually are, compared against the tournament's target
  /// bracket size (see TournamentBracketEngine.nextRoundSizeFor).
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
    final winners = [
      for (final m in currentMatches) (id: m.winnerMemberId!, name: m.winnerName ?? m.memberAName)
    ]..shuffle();
    final nextRoundSize = TournamentBracketEngine.nextRoundSizeFor(
      remainingParticipants: winners.length,
      targetMainBracketSize: tournament.mainBracketSize!,
    );
    final alreadyDrawn = await fetchTournamentMatchesForRound(
      teamId: tournament.teamId,
      tournamentId: tournament.id!,
      roundSize: nextRoundSize,
    );
    if (alreadyDrawn.isNotEmpty) {
      throw Exception('The next round has already been drawn.');
    }
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
    if (match.isBye || match.memberBId == null) return;
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

  Future<void> notifyTournamentDrawStarting({required String teamId, required String tournamentName}) {
    return _notifyTournamentDrawLive(teamId: teamId, tournamentName: tournamentName);
  }

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

  Future<bool> isTournamentRoundAttached({
    required String teamId,
    required String tournamentId,
    required int roundSize,
  }) async {
    final matches = await fetchTournamentMatchesForRound(teamId: teamId, tournamentId: tournamentId, roundSize: roundSize);
    return matches.any((m) => m.gameWeekId != null);
  }

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
  /// Also auto-accepts any still-pending challenge once its challenged
  /// leg's kickoff has passed.
  Future<List<Challenge>> fetchChallenges({required String teamId, required String season}) async {
    final snapshot = await _db.collection('challenges').where('teamId', isEqualTo: teamId).where('season', isEqualTo: season).get();
    final all = snapshot.docs.map((doc) => Challenge.fromMap(doc.id, doc.data())).toList();

    final legsSnapshot = await _db.collection('legs').where('teamId', isEqualTo: teamId).get();
    final legsById = {for (final doc in legsSnapshot.docs) doc.id: doc.data()};

    bool anyChanges = false;

    for (final challenge in all.where((c) => c.status == ChallengeStatus.pendingAcceptance)) {
      final legData = legsById[challenge.challengedLegId];
      if (legData == null) continue;
      final kickoff = (legData['kickoff'] as dynamic)?.toDate();
      if (kickoff == null) continue;
      if (DateTime.now().isAfter(kickoff)) {
        await _db.collection('challenges').doc(challenge.id).update({
          'status': ChallengeStatus.active.value,
        });
        anyChanges = true;
      }
    }

    final activeOnes = all.where((c) => c.status == ChallengeStatus.active).toList();
    if (activeOnes.isNotEmpty) {
      final teamMembers = await fetchMembers(teamId);
      final memberIds = [for (final m in teamMembers) if (m.id != null) m.id!];
      for (final challenge in activeOnes) {
        final legData = legsById[challenge.challengedLegId];
        if (legData == null) continue;
        final outcome = LegOutcomeValue.fromValue(legData['outcome']);
        if (outcome != LegOutcome.won && outcome != LegOutcome.lost) continue;
        final challengedLegWon = outcome == LegOutcome.won;
        final challengerWon = !challengedLegWon;
        await _db.collection('challenges').doc(challenge.id).update({
          'status': ChallengeStatus.resolved.value,
          'challengerWon': challengerWon,
        });
        anyChanges = true;
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
    }

    if (!anyChanges) return all;

    final refreshed = await _db.collection('challenges').where('teamId', isEqualTo: teamId).where('season', isEqualTo: season).get();
    return refreshed.docs.map((doc) => Challenge.fromMap(doc.id, doc.data())).toList();
  }

  Future<List<Team>> fetchTeams(List<String> teamIds) async {
    final teams = <Team>[];
    for (final id in teamIds) {
      final team = await fetchTeam(id);
      if (team != null) teams.add(team);
    }
    return teams;
  }

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

  Future<FixtureOddsCache?> fetchFixtureOddsCache(int apiFootballFixtureId) async {
    final snapshot = await _db
        .collection('fixtureOdds')
        .where('apiFootballFixtureId', isEqualTo: apiFootballFixtureId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return FixtureOddsCache.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
  }

    Future<void> saveFixtureOddsCache(FixtureOddsCache cache) async {
    if (cache.id != null) {
      await _db.collection('fixtureOdds').doc(cache.id).set(cache.toMap());
    } else {
      await _db.collection('fixtureOdds').add(cache.toMap());
    }
  }

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

  Future<Set<String>> fetchProcessedEventIds(int apiFootballFixtureId) async {
    final snapshot = await _db
        .collection('liveMatchEvents')
        .where('apiFootballFixtureId', isEqualTo: apiFootballFixtureId)
        .get();
    return snapshot.docs
        .map((d) => d.data()['eventId'] as String)
        .toSet();
  }

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

  Future<void> generateSeasonSummaries({
    required String teamId,
    required String season,
    required List<Member> members,
    required List<AccumulatorLeg> legs,
    required List<GameWeek> gameWeeks,
    required List<Challenge> challenges,
    List<({Tournament tournament, List<TournamentMatch> matches})> tournaments = const [],
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

      // A member may have taken part in more than one tournament this
      // season now that a team can run several at once — collect a
      // result per tournament they actually played in (a bye-only
      // "phantom" appearance doesn't count as participation, same as
      // the original single-tournament check).
      final cupResultsForMember = <({String name, String result})>[];
      for (final entryT in tournaments) {
        final matches = entryT.matches;
        if (matches.isEmpty) continue;
        final memberMatches = matches
            .where((m) => !m.isBye && (m.memberAId == entry.memberId || m.memberBId == entry.memberId))
            .toList();
        if (memberMatches.isEmpty) continue;
        final finalMatch = matches.where((m) => m.roundSize == 2).firstOrNull;
        final result = finalMatch?.winnerMemberId == entry.memberId
            ? 'Champion 🏆'
            : 'Reached the ${tournamentRoundLabel(memberMatches.reduce((a, b) => a.roundSize < b.roundSize ? a : b).roundSize)}';
        cupResultsForMember.add((name: entryT.tournament.name, result: result));
      }

      // Exactly one tournament: identical output to the original
      // single-tournament behaviour. More than one: combined into a
      // single self-describing string, since cupName/cupResult can't
      // hold two separate tournament names as-is.
      String? cupName;
      String? cupResult;
      if (cupResultsForMember.length == 1) {
        cupName = cupResultsForMember.first.name;
        cupResult = cupResultsForMember.first.result;
      } else if (cupResultsForMember.length > 1) {
        cupResult = cupResultsForMember.map((c) => '${c.name}: ${c.result}').join('; ');
      }

      String? biggestWinDesc;
      if (entry.biggestWin != null) {
        biggestWinDesc = entry.biggestWin!.selectionDescription;
      }

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
        cupName: cupName,
        cupResult: cupResult,
        recommendations: recs,
        createdAt: DateTime.now(),
      );
      await createSeasonSummary(summary);
    }
  }

 

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

  Future<void> toggleReaction({
    required String teamId,
    required String legId,
    required String gameWeekId,
    required String reactorMemberId,
    required String reactorName,
    required String recipientMemberId,
    required String emoji,
  }) async {
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
      if (existingEmoji == emoji) return;
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

    final refreshed = await _db.collection('fines').where('teamId', isEqualTo: teamId).get();
    return refreshed.docs.map((doc) => Fine.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> createFine(Fine fine) async {
    await _db.collection('fines').add(fine.toMap());
    final members = await fetchMembers(fine.teamId);
    final allMemberIds = [for (final m in members) if (m.id != null) m.id!];
    final otherMemberIds = allMemberIds.where((id) => id != fine.memberId).toList();
    await sendNotification(
      teamId: fine.teamId,
      recipientMemberIds: [fine.memberId],
      type: NotificationType.fineIssued,
      title: '👺 Fine issued 👺',
      body: 'You have been fined by the gaffa — ${fine.fineType.displayName}.',
    );
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
      body: 'Gameweek $weekNumber is locked in with ${OddsApiService.bookmakerDisplayNames[bookmaker] ?? bookmaker} — combined odds ${combinedOddsToFractional(combinedOdds)}.',
    );
    await resolveTournamentWalkovers(teamId: teamId, gameWeekId: gameWeekId);
  }

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
    
    // Which tournament this gameweek's walkovers belong to varies match
    // by match now that a team can run several at once — each match
    // already carries its own tournamentId, so look that up per match
    // rather than assuming a single season-wide tournament.
    final tournamentNameCache = <String, String>{};
    Future<String> tournamentNameFor(String tournamentId) async {
      if (tournamentNameCache.containsKey(tournamentId)) return tournamentNameCache[tournamentId]!;
      final t = await fetchTournamentById(tournamentId);
      final name = t?.name ?? 'the tournament';
      tournamentNameCache[tournamentId] = name;
      return name;
    }
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
      if (aSubmitted && bSubmitted) continue;
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
        final aWins = random.nextBool();
        winnerId = aWins ? match.memberAId : match.memberBId!;
        winnerName = aWins ? match.memberAName : (match.memberBName ?? '');
      }

      await _db.collection('tournamentMatches').doc(match.id).update({
        'winnerMemberId': winnerId,
        'winnerName': winnerName,
      });

      if (isWalkover && loserName != null) {
        final tournamentName = await tournamentNameFor(match.tournamentId);
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

  Future<bool> areAllLegsSettled({required String teamId, required String gameWeekId}) async {
    final legsSnap = await _db.collection('legs').where('teamId', isEqualTo: teamId).where('gameWeekId', isEqualTo: gameWeekId).get();
    final legs = legsSnap.docs.map((d) => AccumulatorLeg.fromMap(d.id, d.data())).toList();
    return legs.isNotEmpty && legs.every((l) => l.outcome != LegOutcome.pending);
  }

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
    // ...rest of the method continues exactly as before...
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

  Future<void> setMemberRole({required String memberDocId, required MemberRole role}) async {
    await _db.collection('members').doc(memberDocId).update({'role': role.value});
  }
}