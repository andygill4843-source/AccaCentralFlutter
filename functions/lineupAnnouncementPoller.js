/**
 * lineupAnnouncementPoller.js — Firebase Cloud Function (v2)
 *
 * Runs every 5 minutes. For any pending leg whose fixture kicks off
 * within the next 2 hours, checks whether the OFFICIAL lineup has just
 * been published (both home and away sides present — matching the
 * app's own ApiFootballLineups.isAvailable definition) and, if so:
 *   1. Writes the official lineup straight into the SAME lineupCache
 *      collection that LineupTab reads from — a client opening the tab
 *      after this poller has already run needs zero API-Football calls
 *      of its own.
 *   2. Notifies only the member(s) with a leg on that fixture — once
 *      per fixture ever, tracked via lineupNotificationsSent.
 *
 * Deliberately separate from livePoller.js — lineup checks don't need
 * per-minute freshness, and this is a distinct concern from live match
 * events.
 *
 * Add to functions/index.js:
 *   exports.lineupAnnouncementPoller = require('./lineupAnnouncementPoller').lineupAnnouncementPoller;
 *
 * Deploy:
 *   firebase deploy --only functions
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');

const db = getFirestore();
const API_KEY = process.env.API_FOOTBALL_KEY;
const BASE_URL = 'https://v3.football.api-sports.io';
const CHECK_WINDOW_MS = 2 * 60 * 60 * 1000; // 2 hours ahead of kickoff

async function apiGet(path) {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { 'x-apisports-key': API_KEY },
  });
  if (!res.ok) throw new Error(`API Football ${path} → HTTP ${res.status}`);
  return res.json();
}

async function sendNotification({ teamId, recipientMemberId, type, title, body }) {
  await db.collection('notifications').add({
    teamId,
    recipientMemberId,
    type,
    title,
    body,
    read: false,
    createdAt: new Date(),
  });
}

/// Parses one team's raw /fixtures/lineups response entry into the same
/// shape ApiFootballTeamLineup.toMap() produces on the Dart side, so the
/// cache document this function writes is byte-for-byte compatible with
/// what LineupTab expects to read back via ApiFootballTeamLineup.fromMap.
function parseLineupEntry(entry) {
  const parsePlayer = (raw) => {
    const p = raw.player || raw;
    const gridStr = p.grid;
    let row = 0, col = 0;
    if (typeof gridStr === 'string' && gridStr.includes(':')) {
      const parts = gridStr.split(':');
      row = parseInt(parts[0]) || 0;
      col = parseInt(parts[1]) || 0;
    }
    return {
      id: p.id ?? 0,
      name: p.name ?? 'Unknown',
      number: p.number != null ? String(p.number) : null,
      position: p.pos ?? null,
      gridRow: row,
      gridCol: col,
    };
  };
  return {
    teamId: entry.team?.id ?? 0,
    teamName: entry.team?.name ?? '',
    formation: entry.formation ?? '',
    startXI: (entry.startXI ?? []).map(parsePlayer).filter((p) => p.gridRow > 0),
    substitutes: (entry.substitutes ?? []).map(parsePlayer),
    coachName: entry.coach?.name ?? null,
  };
}

exports.lineupAnnouncementPoller = onSchedule(
  { schedule: 'every 5 minutes', timeoutSeconds: 300, memory: '256MiB' },
  async () => {
    if (!API_KEY) {
      console.error('API_FOOTBALL_KEY not set in functions/.env');
      return;
    }

    const now = Date.now();

    const legsSnap = await db.collection('legs')
      .where('outcome', '==', 'pending')
      .get();
    if (legsSnap.empty) return;

    const eligibleLegs = legsSnap.docs.filter(doc => {
      const leg = doc.data();
      if (!leg.apiFootballFixtureId) return false;
      const kickoffMs = leg.kickoff.toMillis();
      // Only fixtures still upcoming, within the next 2 hours — once a
      // match has started, this function has no further job for it.
      return kickoffMs > now && kickoffMs <= now + CHECK_WINDOW_MS;
    });
    if (eligibleLegs.length === 0) return;

    const fixtureToLegs = {};
    for (const doc of eligibleLegs) {
      const leg = doc.data();
      const fid = leg.apiFootballFixtureId;
      if (!fixtureToLegs[fid]) fixtureToLegs[fid] = [];
      fixtureToLegs[fid].push({ id: doc.id, ...leg });
    }

    for (const [fixtureIdStr, legsForFixture] of Object.entries(fixtureToLegs)) {
      const fixtureId = parseInt(fixtureIdStr);

      const alreadySent = await db.collection('lineupNotificationsSent').doc(String(fixtureId)).get();
      if (alreadySent.exists) continue;

      let lineupData;
      try {
        lineupData = await apiGet(`/fixtures/lineups?fixture=${fixtureId}`);
      } catch (e) {
        console.error(`Lineup check failed for fixture ${fixtureId}:`, e.message);
        continue;
      }

      const response = lineupData.response ?? [];
      // Both sides must be present — matches this app's own
      // ApiFootballLineups.isAvailable definition, so a notification
      // means the same thing as what the Lineup tab itself would show
      // as fully confirmed.
      if (response.length < 2) continue;

      const homeTeamName = response[0]?.team?.name ?? 'Home';
      const awayTeamName = response[1]?.team?.name ?? 'Away';
      const teamId = legsForFixture[0].teamId;
      const ownMemberIds = new Set(legsForFixture.map(l => l.memberId));

      // Write straight into the same cache LineupTab reads from — a
      // client that opens the tab after this poller has already run
      // needs zero API-Football calls of its own.
      await db.collection('lineupCache').doc(String(fixtureId)).set({
        fixtureId,
        isOfficial: true,
        home: parseLineupEntry(response[0]),
        away: parseLineupEntry(response[1]),
        homeConfidence: 0,
        awayConfidence: 0,
        computedAt: new Date(),
      });

      for (const memberId of ownMemberIds) {
        await sendNotification({
          teamId,
          recipientMemberId: memberId,
          type: 'lineupConfirmed',
          title: '🧾 Lineups confirmed!',
          body: `${homeTeamName} vs ${awayTeamName} — the official line-up is in, check your leg.`,
        });
      }

      await db.collection('lineupNotificationsSent').doc(String(fixtureId)).set({
        fixtureId,
        notifiedAt: new Date(),
      });
    }
  }
);