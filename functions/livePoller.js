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

const EARLY_SETTLEMENT_STATUSES = new Set(['1H', 'HT', '2H', 'ET', 'FT', 'LIVE']);

// Mirrors LiveNotificationMute in models.dart. Muting is per fixture,
// per member, and affects notifications about ANY leg on that fixture.
function isMutedForCategory(mutedCategoriesByMember, memberId, category) {
  return mutedCategoriesByMember[memberId]?.has(category) ?? false;
}

// ── Full-time settlement logic (mirrors settlement_engine.dart) ────────────

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

  const isBttsCombo = betType.includes('btts');
  if (isBttsCombo) {
    let bttsYes, isOver;
    if (pick !== null) {
      bttsYes = pick.includes('yes');
      isOver = pick.includes('over');
    } else {
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

// ── Early (mid-match) settlement logic ──────────────────────────────────

function earlySettlementResult(leg, homeGoals, awayGoals) {
  const totalGoals = homeGoals + awayGoals;
  const desc = (leg.selectionDescription || '').toLowerCase().trim();
  const betType = (leg.betType || '').toLowerCase().replace(/\s/g, '');
  const pick = leg.pickValue ? String(leg.pickValue).toLowerCase().trim() : null;
  const market = (leg.marketName || '').toLowerCase();

  const bothScored = homeGoals > 0 && awayGoals > 0;

  if (betType.includes('btts')) {
    let bttsYes, isOver;
    if (pick !== null) {
      bttsYes = pick.includes('yes');
      isOver = pick.includes('over');
    } else {
      bttsYes = !betType.includes('nobtts');
      isOver = betType.includes('over');
    }
    const overLockedTrue = totalGoals > 2.5;
    const underLockedFalse = totalGoals > 2.5;

    if (bttsYes && isOver) {
      if (bothScored && overLockedTrue) return true;
      return null;
    }
    if (bttsYes && !isOver) {
      if (underLockedFalse) return false;
      return null;
    }
    if (!bttsYes && isOver) {
      if (bothScored) return false;
      return null;
    }
    if (bothScored || underLockedFalse) return false;
    return null;
  }

  if (betType.includes('bothteams') || betType === 'btts') {
    const valueStr = pick ?? desc;
    const isYes = valueStr.includes('yes');
    if (bothScored) return isYes;
    return null;
  }

  const isTeamTotals = leg.marketName
    ? (market.includes('total - home') || market.includes('total - away'))
    : betType.includes('teamgoals');
  if (isTeamTotals) {
    const valueStr = pick ?? desc;
    const lineMatch = valueStr.match(/(\d+\.?\d*)/);
    if (!lineMatch) return null;
    const line = parseFloat(lineMatch[1]);
    let isHome;
    if (leg.marketName) {
      isHome = market.includes('home');
    } else {
      isHome = desc.includes('home');
    }
    const teamGoals = isHome ? homeGoals : awayGoals;
    if (valueStr.includes('over')) {
      if (teamGoals > line) return true;
      return null;
    }
    if (valueStr.includes('under')) {
      if (teamGoals > line) return false;
      return null;
    }
    return null;
  }

  if (betType.includes('over') || betType.includes('under') || betType.includes('goals')) {
    const valueStr = pick ?? desc;
    const lineMatch = valueStr.match(/(\d+\.?\d*)/);
    if (!lineMatch) return null;
    const line = parseFloat(lineMatch[1]);
    if (valueStr.includes('over')) {
      if (totalGoals > line) return true;
      return null;
    }
    if (valueStr.includes('under')) {
      if (totalGoals > line) return false;
      return null;
    }
    return null;
  }

  return null;
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

function memberNameFor(membersSnap, memberId) {
  const memberDoc = membersSnap.docs.find(d => d.id === memberId);
  return memberDoc?.data()?.displayName ?? 'Someone';
}

/// Resolves any learning-engine prediction record for this fixture now
/// that a final score exists — feeds the weight-learning pipeline.
/// Guarded so a fixture is only ever resolved once.
async function resolvePredictionRecord(fixtureId, homeGoals, awayGoals) {
  try {
    const predRef = db.collection('prediction_records').doc(String(fixtureId));
    const predSnap = await predRef.get();
    if (predSnap.exists && !predSnap.data().resolved) {
      await predRef.update({
        resolved: true,
        actual: { homeGoals, awayGoals },
        resolvedAt: new Date(),
      });
    }
  } catch (e) {
    console.error(`Couldn't resolve prediction_records for fixture ${fixtureId}:`, e.message);
  }
}

// ── Full-time / early settlement notifications — category 'settlement' ──

async function settleLegAndNotify({ leg, winning, teamId, membersSnap, allMemberIds, totalLegs, wonCountRef, mutedCategoriesByMember }) {
  const newOutcome = winning ? 'won' : 'lost';
  await db.collection('legs').doc(leg.id).update({ outcome: newOutcome, settledAt: new Date() });
  if (winning) wonCountRef.count++;

  const memberName = memberNameFor(membersSnap, leg.memberId);

  for (const memberId of allMemberIds) {
    if (isMutedForCategory(mutedCategoriesByMember, memberId, 'settlement')) continue;
    const isOwn = memberId === leg.memberId;
    await sendNotification({
      teamId,
      recipientMemberId: memberId,
      type: 'leaguePosition',
      title: isOwn
        ? (winning
            ? `Job done! Your bet is in ✅ 🏋️ ⭐ — ${wonCountRef.count}/${totalLegs} won so far`
            : `Hard luck. Your bet didn't come in ❌ — ${wonCountRef.count}/${totalLegs} won so far`)
        : (winning
            ? `${memberName}'s bet is in ✅ — ${wonCountRef.count}/${totalLegs} won so far`
            : `${memberName}'s bet has settled and it's a loss 🫣 — ${wonCountRef.count}/${totalLegs} won so far`),
    });
  }
}

async function settleAsEarlyWinner({ leg, teamId, membersSnap, allMemberIds, totalLegs, wonCountRef, mutedCategoriesByMember }) {
  await db.collection('legs').doc(leg.id).update({ outcome: 'won', settledAt: new Date() });
  wonCountRef.count++;
  const memberName = memberNameFor(membersSnap, leg.memberId);

  for (const memberId of allMemberIds) {
    if (isMutedForCategory(mutedCategoriesByMember, memberId, 'settlement')) continue;
    await sendNotification({
      teamId,
      recipientMemberId: memberId,
      type: 'leaguePosition',
      title: `✅ ${memberName} bags a winner — ${wonCountRef.count}/${totalLegs}`,
      body: `${leg.selectionDescription} — WON ✅`,
    });
  }
}

// Fires whenever a previously-WON leg is no longer won — grouped under
// 'goals' (not 'settlement'), since it's caused by a VAR reversal, not a
// new settlement event.
async function revertWonLegAndNotifyCorrection({
  leg, newOutcome, teamId, membersSnap, allMemberIds, totalLegs, wonCountRef, homeTeam, awayTeam, homeGoals, awayGoals, allEvents, mutedCategoriesByMember,
}) {
  await db.collection('legs').doc(leg.id).update({ outcome: newOutcome, settledAt: new Date() });
  wonCountRef.count--;
  const memberName = memberNameFor(membersSnap, leg.memberId);
  const scoreLabel = `${homeTeam} ${homeGoals}-${awayGoals} ${awayTeam}`;

  const cancellations = allEvents
    .filter(e => e.type === 'Var' && e.detail === 'Goal cancelled')
    .sort((a, b) => a.time.elapsed - b.time.elapsed);
  const cancelledTeam = cancellations.length > 0
    ? cancellations[cancellations.length - 1].team.name
    : null;

  const title = cancelledTeam
    ? `❌ CORRECTION: VAR - ${cancelledTeam} Goal Cancelled`
    : `❌ CORRECTION: Goal disallowed`;

  for (const memberId of allMemberIds) {
    if (isMutedForCategory(mutedCategoriesByMember, memberId, 'goals')) continue;
    await sendNotification({
      teamId,
      recipientMemberId: memberId,
      type: 'leaguePosition',
      title,
      body: `${scoreLabel} - Bad luck ${memberName} - ${wonCountRef.count}/${totalLegs}`,
    });
  }
}

async function settleAsEarlyLossSilently(leg) {
  await db.collection('legs').doc(leg.id).update({ outcome: 'lost', settledAt: new Date() });
}
async function revertLostLegSilently(leg) {
  await db.collection('legs').doc(leg.id).update({ outcome: 'pending', settledAt: new Date() });
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

      // Every member's mute preferences for THIS fixture, keyed by
      // memberId → Set of muted category strings.
      const mutesSnap = await db.collection('liveNotificationMutes')
        .where('apiFootballFixtureId', '==', fixtureId)
        .get();
      const mutedCategoriesByMember = {};
      for (const doc of mutesSnap.docs) {
        const d = doc.data();
        const muted = new Set(
          Object.entries(d.mutedCategories || {}).filter(([, v]) => v).map(([k]) => k)
        );
        mutedCategoriesByMember[d.memberId] = muted;
      }

      const allGameWeekLegsSnap = await db.collection('legs')
        .where('gameWeekId', '==', gameWeekId)
        .where('teamId', '==', teamId)
        .where('isSecondaryTournamentLeg', '==', false)
        .get();
      const totalLegs = allGameWeekLegsSnap.size;
      const wonCountRef = {
        count: allGameWeekLegsSnap.docs.filter(d => d.data().outcome === 'won').length,
      };

      let allEvents = [];

      // Half-time entry for the home screen's Acca News Feed — NOT a
      // notification trigger, purely a feed entry. Idempotent via a
      // fixed eventId per fixture.
      if (statusShort === 'HT') {
        const htId = `HT_${fixtureId}`;
        const htExists = await db.collection('liveMatchEvents').where('eventId', '==', htId).limit(1).get();
        if (htExists.empty) {
          await db.collection('liveMatchEvents').add({
            apiFootballFixtureId: fixtureId,
            eventId: htId,
            teamId,
            type: 'HalfTime',
            detail: 'Half Time',
            elapsed: 45,
            teamName: '',
            playerName: null,
            processedAt: new Date(),
          });
        }
      }

      if (isLive) {
        const eventsData = await apiGet(`/fixtures/events?fixture=${fixtureId}`);
        allEvents = eventsData.response ?? [];

        const processedSnap = await db.collection('liveMatchEvents')
          .where('apiFootballFixtureId', '==', fixtureId)
          .get();
        const processedIds = new Set(processedSnap.docs.map(d => d.data().eventId));

        const ownMemberIds = new Set(legsForFixture.map(l => l.memberId));

        for (const event of allEvents) {
          const rawType = event.type;
          const detail = (event.detail || '') === 'Normal Goal' ? 'Goal' : (event.detail || '');
          const detailLower = detail.toLowerCase();

          const isGoal = rawType === 'Goal' && detail !== 'Missed Penalty';
          const isRedCard = rawType === 'Card' && detailLower === 'red card';
          const isYellowCard = rawType === 'Card' && detailLower === 'yellow card';
          const isCard = isRedCard || isYellowCard;
          const isSubstitution = rawType === 'Subst';
          const isDisallowedGoal = rawType === 'Var' && detail === 'Goal cancelled';

          if (!isGoal && !isCard && !isSubstitution && !isDisallowedGoal) continue;

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
          let category;

          if (isGoal) {
            const displayDetail = detail === 'Normal Goal' ? 'Goal' : detail;
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '⚽';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — ${displayDetail}`;
            notifyEveryone = true;
            category = 'goals';
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          } else if (isCard) {
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = isRedCard ? '🟥' : '🟨';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — ${isRedCard ? 'Red Card' : 'Yellow Card'}`;
            notifyEveryone = false;
            category = 'cards';
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          } else if (isSubstitution) {
            const playerOff = event.player?.name ?? 'Player';
            const playerOn = event.assist?.name ?? 'Player';
            emoji = '🔄';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName} — ${playerOff} off, ${playerOn} on`;
            notifyEveryone = false;
            category = 'subs';
            eventKeyPart = `${playerOff.replace(/ /g, '_')}_${playerOn.replace(/ /g, '_')}`;
          } else {
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '🚫';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — Goal Disallowed`;
            notifyEveryone = true;
            category = 'goals';
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
              if (isMutedForCategory(mutedCategoriesByMember, memberId, category)) continue;
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
              if (isMutedForCategory(mutedCategoriesByMember, memberId, category)) continue;
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

        // ── Reconcile every eligible leg against the CURRENT live score.
        if (EARLY_SETTLEMENT_STATUSES.has(statusShort)) {
          for (const leg of legsForFixture) {
            const result = earlySettlementResult(leg, homeGoals, awayGoals);
            const currentAsBool = leg.outcome === 'won' ? true : leg.outcome === 'lost' ? false : null;
            if (result === currentAsBool) continue;

            if (result === true) {
              await settleAsEarlyWinner({ leg, teamId, membersSnap, allMemberIds, totalLegs, wonCountRef, mutedCategoriesByMember });
            } else if (currentAsBool === true) {
              await revertWonLegAndNotifyCorrection({
                leg,
                newOutcome: result === false ? 'lost' : 'pending',
                teamId, membersSnap, allMemberIds, totalLegs, wonCountRef,
                homeTeam, awayTeam, homeGoals, awayGoals, allEvents, mutedCategoriesByMember,
              });
            } else if (result === false) {
              await settleAsEarlyLossSilently(leg);
            } else {
              await revertLostLegSilently(leg);
            }
          }
        }
      }

      if (isFinished) {
        const ftId = `FT_${fixtureId}`;
        const ftExists = await db.collection('liveMatchEvents').where('eventId', '==', ftId).limit(1).get();
        if (ftExists.empty) {
          await db.collection('liveMatchEvents').add({
            apiFootballFixtureId: fixtureId,
            eventId: ftId,
            teamId,
            type: 'FullTime',
            detail: 'Full Time',
            elapsed: 90,
            teamName: '',
            playerName: null,
            processedAt: new Date(),
          });
        }

        for (const leg of legsForFixture) {
          if (leg.outcome !== 'pending') continue;

          const winning = isCurrentlyWinning(leg, homeGoals, awayGoals, homeTeam, awayTeam);
          await settleLegAndNotify({
            leg,
            winning,
            teamId,
            membersSnap,
            allMemberIds,
            totalLegs,
            wonCountRef,
            mutedCategoriesByMember,
          });
        }

        // Resolve any learning-engine prediction record now that a
        // final score exists for this fixture — once per fixture.
        await resolvePredictionRecord(fixtureId, homeGoals, awayGoals);
      }
    }
  }
);