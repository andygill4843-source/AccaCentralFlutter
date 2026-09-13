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
  const pick = leg.pickValue ? String(leg.pickValue).toLowerCase().trim() : null;
  const market = (leg.marketName || '').toLowerCase();

  if (betType.includes('matchwinner') || betType === '1x2') {
    if (pick !== null) {
      if (pick === 'home') return homeGoals > awayGoals;
      if (pick === 'away') return awayGoals > homeGoals;
      if (pick === 'draw') return homeGoals === awayGoals;
      return false;
    }
    if (desc.includes(homeTeam.toLowerCase()) || desc === 'home' || desc.includes('home win')) {
      return homeGoals > awayGoals;
    }
    if (desc.includes(awayTeam.toLowerCase()) || desc === 'away' || desc.includes('away win')) {
      return awayGoals > homeGoals;
    }
    if (desc === 'draw' || desc === 'x') return homeGoals === awayGoals;
    return false;
  }

  // BTTS & Goals combo bets — BOTH halves must be true for a win. Checked
  // here, before the plain BTTS check and before the generic over/under
  // block below, because the combo's stored betType string (e.g. "BTTS &
  // Over 2.5 (Estimate)") contains "over"/"under" as a substring and was
  // previously falling straight into the generic block, which only
  // checked total goals and silently ignored the BTTS half entirely —
  // the actual cause of combo legs settling as a win off goals alone.
  // The combo market is always fixed at the 2.5 line, so no line-parsing
  // is needed here.
  const isBttsCombo = betType.includes('btts');
  if (isBttsCombo) {
    let bttsYes, isOver;
    if (pick !== null) {
      // pickValue looks like "BTTS Yes & Over 2.5" / "BTTS No & Under 2.5"
      bttsYes = pick.includes('yes');
      isOver = pick.includes('over');
    } else {
      // Legacy fallback — reconstruct from the stored betType display
      // name. 'No BTTS & Over 2.5 (Estimate)' normalises to
      // 'nobtts&over2.5(estimate)'; the Yes variant has no 'no' prefix.
      bttsYes = !betType.includes('nobtts');
      isOver = betType.includes('over');
    }
    const bttsCondition = bttsYes ? (homeGoals > 0 && awayGoals > 0) : !(homeGoals > 0 && awayGoals > 0);
    const totalsCondition = isOver ? totalGoals > 2.5 : totalGoals < 2.5;
    return bttsCondition && totalsCondition;
  }

  if (betType.includes('bothteams') || betType === 'btts') {
    const valueStr = pick ?? desc;
    const isYes = valueStr.includes('yes');
    return isYes ? (homeGoals > 0 && awayGoals > 0) : !(homeGoals > 0 && awayGoals > 0);
  }

  const isTeamTotals = leg.marketName
    ? (market.includes('total - home') || market.includes('total - away'))
    : betType.includes('teamgoals');

  if (isTeamTotals) {
    const valueStr = pick ?? desc;
    const lineMatch = valueStr.match(/(\d+\.?\d*)/);
    if (!lineMatch) return false;
    const line = parseFloat(lineMatch[1]);
    let isHome;
    if (leg.marketName) {
      isHome = market.includes('home');
    } else {
      isHome = desc.includes('home') || desc.includes(homeTeam.toLowerCase());
    }
    const teamGoals = isHome ? homeGoals : awayGoals;
    if (valueStr.includes('over')) return teamGoals > line;
    if (valueStr.includes('under')) return teamGoals < line;
    return false;
  }

  if (betType.includes('over') || betType.includes('under') || betType.includes('goals')) {
    const valueStr = pick ?? desc;
    const lineMatch = valueStr.match(/(\d+\.?\d*)/);
    if (!lineMatch) return false;
    const line = parseFloat(lineMatch[1]);
    if (valueStr.includes('over')) return totalGoals > line;
    if (valueStr.includes('under')) return totalGoals < line;
    return false;
  }

  if (betType.includes('correctscore') || betType.includes('exactscore')) {
    const valueStr = pick ?? desc;
    const scoreMatch = valueStr.match(/(\d+)\s*[-–]\s*(\d+)/);
    if (!scoreMatch) return false;
    return homeGoals === parseInt(scoreMatch[1]) && awayGoals === parseInt(scoreMatch[2]);
  }

  if (betType.includes('doublechance')) {
    const valueStr = pick ?? desc;
    if (valueStr.includes('1x') || valueStr.includes('home or draw')) return homeGoals >= awayGoals;
    if (valueStr.includes('x2') || valueStr.includes('draw or away')) return awayGoals >= homeGoals;
    if (valueStr.includes('12') || valueStr.includes('home or away')) return homeGoals !== awayGoals;
    return false;
  }

  if (betType.includes('drawnobet')) {
    if (pick !== null) {
      if (pick === 'home') return homeGoals > awayGoals;
      if (pick === 'away') return awayGoals > homeGoals;
      return false;
    }
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

    const legsSnap = await db.collection('legs')
      .where('outcome', '==', 'pending')
      .get();

    if (legsSnap.empty) return;

    const activeLegDocs = legsSnap.docs.filter(doc => {
      const leg = doc.data();
      if (!leg.apiFootballFixtureId) return false;
      const kickoffMs = leg.kickoff.toMillis();
      const windowEnd = kickoffMs + (105 * 60 * 1000) + thirtyMinMs;
      return now >= (kickoffMs - thirtyMinMs) && now <= windowEnd;
    });

    if (activeLegDocs.length === 0) return;

    const fixtureToLegs = {};

    for (const doc of activeLegDocs) {
      const leg = doc.data();
      const fid = leg.apiFootballFixtureId;
      if (!fixtureToLegs[fid]) fixtureToLegs[fid] = [];
      fixtureToLegs[fid].push({ id: doc.id, ...leg });
    }

    const fixtureIds = Object.keys(fixtureToLegs).map(Number);
    if (fixtureIds.length === 0) return;

    const BATCH_SIZE = 20;
    const liveById = {};

    for (let i = 0; i < fixtureIds.length; i += BATCH_SIZE) {
      const batch = fixtureIds.slice(i, i + BATCH_SIZE);
      const batchData = await apiGet(`/fixtures?ids=${batch.join('-')}`);
      for (const f of (batchData.response ?? [])) {
        liveById[f.fixture.id] = f;
      }
    }

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

      const membersSnap = await db.collection('members')
        .where('teamId', '==', teamId)
        .get();
      const allMemberIds = membersSnap.docs.map(d => d.id);

      if (isLive) {
        const eventsData = await apiGet(`/fixtures/events?fixture=${fixtureId}`);
        const allEvents = eventsData.response ?? [];

        const processedSnap = await db.collection('liveMatchEvents')
          .where('apiFootballFixtureId', '==', fixtureId)
          .get();
        const processedIds = new Set(processedSnap.docs.map(d => d.data().eventId));

        const ownMemberIds = new Set(legsForFixture.map(l => l.memberId));

        for (const event of allEvents) {
          const rawType = event.type;
          const detail = event.detail || '';

          const isGoal = rawType === 'Goal' && detail !== 'Missed Penalty';
          const isRedCard = rawType === 'Card' && detail.toLowerCase() === 'red card';
          const isSubstitution = rawType === 'Subst';
          const isDisallowedGoal = rawType === 'Var' && detail === 'Goal cancelled';

          if (!isGoal && !isRedCard && !isSubstitution && !isDisallowedGoal) continue;

          const elapsed = event.time.elapsed;
          const extra = event.time.extra ?? 0;
          const eventTeamId = event.team.id;
          const eventTeamName = event.team.name;
          const timeLabel = extra > 0 ? `${elapsed}'+${extra}` : `${elapsed}'`;
          const scoreLabel = `${homeTeam} ${homeGoals} – ${awayGoals} ${awayTeam}`;

          let emoji;
          let eventDetail;
          let notifyEveryone;
          let eventKeyPart;

          if (isGoal) {
            const displayDetail = detail === 'Normal Goal' ? 'Goal' : detail;
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '⚽';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — ${displayDetail}`;
            notifyEveryone = true;
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          } else if (isRedCard) {
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '🟥';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — Red Card`;
            notifyEveryone = false;
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          } else if (isSubstitution) {
            const playerOff = event.player?.name ?? 'Player';
            const playerOn = event.assist?.name ?? 'Player';
            emoji = '🔄';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName} — ${playerOff} off, ${playerOn} on`;
            notifyEveryone = false;
            eventKeyPart = `${playerOff.replace(/ /g, '_')}_${playerOn.replace(/ /g, '_')}`;
          } else {
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '🚫';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — Goal Disallowed`;
            notifyEveryone = true;
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          }

          const eventId = `${elapsed}_${extra}_${eventTeamId}_${rawType}_${eventKeyPart}`;
          if (processedIds.has(eventId)) continue;

          await db.collection('liveMatchEvents').add({
            apiFootballFixtureId: fixtureId,
            eventId,
            teamId,
            type: rawType,
            detail,
            elapsed,
            teamName: eventTeamName,
            playerName: event.player?.name ?? null,
            processedAt: new Date(),
          });

          if (notifyEveryone) {
            for (const memberId of allMemberIds) {
              await sendNotification({
                teamId,
                recipientMemberId: memberId,
                type: 'liveEvent',
                title: `${emoji} ${scoreLabel}`,
                body: ownMemberIds.has(memberId) ? eventDetail : scoreLabel,
              });
            }
          } else {
            for (const memberId of ownMemberIds) {
              await sendNotification({
                teamId,
                recipientMemberId: memberId,
                type: 'liveEvent',
                title: `${emoji} ${scoreLabel}`,
                body: eventDetail,
              });
            }
          }
        }
      }

      if (isFinished) {
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