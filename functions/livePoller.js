/**
 * livePoller.js — Firebase Cloud Function (v2)
 *
 * Polls API Football for live match data every minute.
 * Only polls during active leg windows — zero wasted requests outside match times.
 *
 * Add to functions/.env:
 *   API_FOOTBALL_KEY=your_key_here
 *
 * Add to functions/index.js:
 *   exports.liveMatchPoller = require('./livePoller').liveMatchPoller;
 *
 * Deploy:
 *   firebase deploy --only functions
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');

// Do NOT call initializeApp() here — index.js already does it.
const db = getFirestore();

const API_KEY = process.env.API_FOOTBALL_KEY;
const BASE_URL = 'https://v3.football.api-sports.io';

// ── Settlement logic (mirrors settlement_engine.dart) ──────────────────────

function isCurrentlyWinning(leg, homeGoals, awayGoals, homeTeam, awayTeam) {
  const totalGoals = homeGoals + awayGoals;
  const desc = (leg.selectionDescription || '').toLowerCase().trim();
  const betType = (leg.betType || '').toLowerCase().replace(/\s/g, '');

  if (betType.includes('matchwinner') || betType === '1x2') {
    if (desc.includes(homeTeam.toLowerCase()) || desc === 'home' || desc.includes('home win')) {
      return homeGoals > awayGoals;
    }
    if (desc.includes(awayTeam.toLowerCase()) || desc === 'away' || desc.includes('away win')) {
      return awayGoals > homeGoals;
    }
    if (desc === 'draw' || desc === 'x') return homeGoals === awayGoals;
    return false;
  }

  if (betType.includes('bothteams') || betType === 'btts') {
    const isYes = desc.includes('yes');
    return isYes ? (homeGoals > 0 && awayGoals > 0) : !(homeGoals > 0 && awayGoals > 0);
  }

  if (betType.includes('over') || betType.includes('under') || betType.includes('goals')) {
    const lineMatch = desc.match(/(\d+\.?\d*)/);
    if (!lineMatch) return false;
    const line = parseFloat(lineMatch[1]);
    const isHome = desc.includes('home') || desc.includes(homeTeam.toLowerCase());
    const isAway = desc.includes('away') || desc.includes(awayTeam.toLowerCase());
    const goals = isHome ? homeGoals : isAway ? awayGoals : totalGoals;
    if (desc.includes('over')) return goals > line;
    if (desc.includes('under')) return goals < line;
    return false;
  }

  if (betType.includes('correctscore') || betType.includes('exactscore')) {
    const scoreMatch = desc.match(/(\d+)\s*[-–]\s*(\d+)/);
    if (!scoreMatch) return false;
    return homeGoals === parseInt(scoreMatch[1]) && awayGoals === parseInt(scoreMatch[2]);
  }

  if (betType.includes('doublechance')) {
    if (desc.includes('1x') || desc.includes('home or draw')) return homeGoals >= awayGoals;
    if (desc.includes('x2') || desc.includes('draw or away')) return awayGoals >= homeGoals;
    if (desc.includes('12') || desc.includes('home or away')) return homeGoals !== awayGoals;
    return false;
  }

  if (betType.includes('drawnobet')) {
    if (desc.includes(homeTeam.toLowerCase()) || desc.includes('home')) return homeGoals > awayGoals;
    if (desc.includes(awayTeam.toLowerCase()) || desc.includes('away')) return awayGoals > homeGoals;
    return false;
  }

  return false;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

async function apiGet(path) {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { 'x-apisports-key': API_KEY },
  });
  if (!res.ok) throw new Error(`API Football ${path} → ${res.status}`);
  return res.json();
}

async function sendNotification({ teamId, recipientMemberId, type, title, body }) {
  await db.collection('notifications').add({
    teamId,
    recipientMemberId, // singular — matches the push trigger in index.js
    type,
    title,
    body,
    read: false,
    createdAt: new Date(),
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

exports.liveMatchPoller = onSchedule(
  { schedule: 'every 1 minutes', timeoutSeconds: 540, memory: '512MiB' },
  async () => {
    if (!API_KEY) {
      console.error('API_FOOTBALL_KEY not set in functions/.env');
      return;
    }

    const now = Date.now();
    const thirtyMinMs = 30 * 60 * 1000;

    // ── 1. Fetch pending legs ──────────────────────────────────────────────
    const legsSnap = await db.collection('legs')
      .where('outcome', '==', 'pending')
      .get();

    if (legsSnap.empty) return;

    // Filter to legs within their polling window that have an API Football ID.
    const activeLegDocs = legsSnap.docs.filter(doc => {
      const leg = doc.data();
      if (!leg.apiFootballFixtureId) return false;
      const kickoffMs = leg.kickoff.toMillis();
      const windowEnd = kickoffMs + (105 * 60 * 1000) + thirtyMinMs;
      return now >= (kickoffMs - thirtyMinMs) && now <= windowEnd;
    });

    if (activeLegDocs.length === 0) return;

    // ── 2. Deduplicate by fixture, collect league IDs ──────────────────────
    const fixtureToLegs = {};
    const leagueIds = new Set();

    for (const doc of activeLegDocs) {
      const leg = doc.data();
      const fid = leg.apiFootballFixtureId;
      if (!fixtureToLegs[fid]) fixtureToLegs[fid] = [];
      fixtureToLegs[fid].push({ id: doc.id, ...leg });
      if (leg.apiFootballLeagueId) leagueIds.add(leg.apiFootballLeagueId);
    }

    if (leagueIds.size === 0) return;

    // ── 3. Fetch live fixtures for relevant leagues only ───────────────────
    const leagueStr = [...leagueIds].join('-');
    const liveData = await apiGet(`/fixtures?live=${leagueStr}`);
    const liveFixtures = liveData.response ?? [];

    const liveById = {};
    for (const f of liveFixtures) {
      liveById[f.fixture.id] = f;
    }

    // ── 4. Process each fixture ────────────────────────────────────────────
    for (const [fixtureIdStr, legsForFixture] of Object.entries(fixtureToLegs)) {
      const fixtureId = parseInt(fixtureIdStr);
      const liveFixture = liveById[fixtureId];
      if (!liveFixture) continue;

      const statusShort = liveFixture.fixture.status.short;
      const isLive = ['1H', 'HT', '2H', 'ET', 'BT', 'P'].includes(statusShort);
      const isFinished = ['FT', 'AET', 'PEN', 'AWD', 'WO'].includes(statusShort);
      if (!isLive && !isFinished) continue;

      const homeGoals = liveFixture.goals.home ?? 0;
      const awayGoals = liveFixture.goals.away ?? 0;
      const homeTeam = liveFixture.teams.home.name;
      const awayTeam = liveFixture.teams.away.name;
      const teamId = legsForFixture[0].teamId;
      const gameWeekId = legsForFixture[0].gameWeekId;

      // Fetch all members for this team.
      const membersSnap = await db.collection('members')
        .where('teamId', '==', teamId)
        .get();
      const allMemberIds = membersSnap.docs.map(d => d.id);

      // ── 4a. Process new match events (goals + cards) ───────────────────
      if (isLive) {
        const eventsData = await apiGet(`/fixtures/events?fixture=${fixtureId}`);
        const allEvents = eventsData.response ?? [];

        const processedSnap = await db.collection('liveMatchEvents')
          .where('apiFootballFixtureId', '==', fixtureId)
          .get();
        const processedIds = new Set(processedSnap.docs.map(d => d.data().eventId));

        for (const event of allEvents) {
          const type = event.type;
          if (!['Goal', 'Card'].includes(type)) continue;

          const elapsed = event.time.elapsed;
          const extra = event.time.extra ?? 0;
          const detail = event.detail;
          const playerName = event.player?.name ?? '';
          const eventTeamId = event.team.id;
          const eventTeamName = event.team.name;

          const eventId = `${elapsed}_${extra}_${eventTeamId}_${type}_${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          if (processedIds.has(eventId)) continue;

          // Record as processed.
          await db.collection('liveMatchEvents').add({
            apiFootballFixtureId: fixtureId,
            eventId,
            teamId,
            type,
            detail,
            elapsed,
            teamName: eventTeamName,
            playerName: playerName || null,
            processedAt: new Date(),
          });

          const emoji = type === 'Goal' ? '⚽' : detail.includes('Yellow') ? '🟨' : '🟥';
          const timeLabel = extra > 0 ? `${elapsed}'+${extra}` : `${elapsed}'`;
          const playerPart = playerName ? ` ${playerName}` : '';
          const scoreLabel = `${homeTeam} ${homeGoals} – ${awayGoals} ${awayTeam}`;
          const eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — ${detail}`;

          // Own leg members get full event detail; others get score only.
          const ownMemberIds = new Set(legsForFixture.map(l => l.memberId));

          for (const memberId of allMemberIds) {
            await sendNotification({
              teamId,
              recipientMemberId: memberId,
              type: 'liveEvent',
              title: `${emoji} ${scoreLabel}`,
              body: ownMemberIds.has(memberId) ? eventDetail : scoreLabel,
            });
          }
        }
      }

      // ── 4b. Settle legs when the match is finished ─────────────────────
      if (isFinished) {
        // Get total primary leg count for X/Y display.
        const allGameWeekLegsSnap = await db.collection('legs')
          .where('gameWeekId', '==', gameWeekId)
          .where('teamId', '==', teamId)
          .where('isSecondaryTournamentLeg', '==', false)
          .get();
        const totalLegs = allGameWeekLegsSnap.size;
        let settledCount = allGameWeekLegsSnap.docs
          .filter(d => d.data().outcome !== 'pending').length;

        for (const leg of legsForFixture) {
          if (leg.outcome !== 'pending') continue;

          const winning = isCurrentlyWinning(leg, homeGoals, awayGoals, homeTeam, awayTeam);
          const newOutcome = winning ? 'won' : 'lost';

          await db.collection('legs').doc(leg.id).update({ outcome: newOutcome });
          settledCount++;

          // Look up the member's display name.
          const memberDoc = membersSnap.docs.find(d => d.id === leg.memberId);
          const memberName = memberDoc?.data()?.displayName ?? 'Someone';

          for (const memberId of allMemberIds) {
            const isOwn = memberId === leg.memberId;
            await sendNotification({
              teamId,
              recipientMemberId: memberId,
              type: 'leaguePosition',
              title: isOwn
                ? (winning
                    ? `Job done! Your bet is in ✅ 🏋️ ⭐ — ${settledCount}/${totalLegs} so far`
                    : `Hard luck. Your bet didn't come in ❌ — ${settledCount}/${totalLegs} so far`)
                : `${memberName}'s bet is in ${winning ? '✅' : '❌'} — ${settledCount}/${totalLegs} so far`,
              body: `${leg.selectionDescription} — ${winning ? 'WON ✅' : 'LOST ❌'}`,
            });
          }
        }
      }
    }
  }
);