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
  // Preferred: the raw pick value stored at submission time. Falls back
  // to legacy description-parsing only for legs submitted before this
  // field existed. The old parsing checked whether selectionDescription
  // contained a team's name — but selectionDescription always contains
  // BOTH team names ("Pick — Home vs Away"), so that check could never
  // correctly distinguish a home pick from an away one. pickValue/
  // marketName avoid that collision entirely.
  const pick = leg.pickValue ? String(leg.pickValue).toLowerCase().trim() : null;
  const market = (leg.marketName || '').toLowerCase();

  if (betType.includes('matchwinner') || betType === '1x2') {
    if (pick !== null) {
      if (pick === 'home') return homeGoals > awayGoals;
      if (pick === 'away') return awayGoals > homeGoals;
      if (pick === 'draw') return homeGoals === awayGoals;
      return false;
    }
    // Legacy fallback — best-effort only, has the home-first collision
    // bug described above. Only reached for legs with no pickValue.
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
    const valueStr = pick ?? desc;
    const isYes = valueStr.includes('yes');
    return isYes ? (homeGoals > 0 && awayGoals > 0) : !(homeGoals > 0 && awayGoals > 0);
  }

  // Team Totals ("Team Goals Over/Under") is routed here, before and
  // separate from the generic Game Goals block below, because it also
  // contains "over"/"under"/"goals" and would otherwise be scored
  // against total match goals instead of one team's goals.
  const isTeamTotals = leg.marketName
    ? (market.includes('total - home') || market.includes('total - away'))
    : betType.includes('teamgoals'); // legacy fallback for legs with no marketName

  if (isTeamTotals) {
    const valueStr = pick ?? desc;
    const lineMatch = valueStr.match(/(\d+\.?\d*)/);
    if (!lineMatch) return false;
    const line = parseFloat(lineMatch[1]);
    let isHome;
    if (leg.marketName) {
      isHome = market.includes('home');
    } else {
      // Legacy fallback — same collision bug as match winner above.
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
    // Legacy fallback — same collision bug as match winner above.
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

    // ── 2. Deduplicate by fixture ───────────────────────────────────────────
    const fixtureToLegs = {};

    for (const doc of activeLegDocs) {
      const leg = doc.data();
      const fid = leg.apiFootballFixtureId;
      if (!fixtureToLegs[fid]) fixtureToLegs[fid] = [];
      fixtureToLegs[fid].push({ id: doc.id, ...leg });
    }

    const fixtureIds = Object.keys(fixtureToLegs).map(Number);
    if (fixtureIds.length === 0) return;

    // ── 3. Fetch current status for exactly these fixtures ─────────────────
    // Using /fixtures?ids=... instead of /fixtures?live=... because the
    // live= endpoint only returns matches currently in progress — a
    // finished match (FT/AET/PEN) drops out of that response the moment
    // it ends, making settlement unreachable. ids= returns the fixture's
    // current status regardless of whether it's live, finished, or not
    // yet started, so both event-processing and settlement work off the
    // same reliable source. Batched at 20 IDs per call (API-Football's
    // documented cap for this parameter — verify against current docs
    // if this starts erroring).
    const BATCH_SIZE = 20;
    const liveById = {};

    for (let i = 0; i < fixtureIds.length; i += BATCH_SIZE) {
      const batch = fixtureIds.slice(i, i + BATCH_SIZE);
      const batchData = await apiGet(`/fixtures?ids=${batch.join('-')}`);
      for (const f of (batchData.response ?? [])) {
        liveById[f.fixture.id] = f;
      }
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

      // ── 4a. Process new match events (goals, red cards, subs, VAR) ─────
      if (isLive) {
        const eventsData = await apiGet(`/fixtures/events?fixture=${fixtureId}`);
        const allEvents = eventsData.response ?? [];

        const processedSnap = await db.collection('liveMatchEvents')
          .where('apiFootballFixtureId', '==', fixtureId)
          .get();
        const processedIds = new Set(processedSnap.docs.map(d => d.data().eventId));

        // Own-leg members get goals, red cards, substitutions, and
        // disallowed goals, all with full detail. Everyone else only
        // gets notified for goals and disallowed goals, and only sees
        // the updated score — not who scored or how.
        const ownMemberIds = new Set(legsForFixture.map(l => l.memberId));

        for (const event of allEvents) {
          const rawType = event.type; // 'Goal', 'Card', 'Subst', 'Var'
          const detail = event.detail || '';

          // Confirmed detail values per API-Football's docs:
          //   Goal: Normal Goal, Own Goal, Penalty, Missed Penalty
          //   Card: Yellow Card, Red card
          //   Subst: Substitution [n]
          //   Var: Goal cancelled, Penalty confirmed
          // 'Missed Penalty' is filed under type Goal but is NOT a score
          // — must be excluded or a missed penalty would wrongly fire a
          // "Goal!" notification to the whole team.
          // Own Goal: assumed event.team is the team that benefits on
          // the scoreboard (not the scoring player's own team) — if that
          // assumption is wrong, own goals would be credited to the
          // wrong side in the notification text.
          const isGoal = rawType === 'Goal' && detail !== 'Missed Penalty';
          const isRedCard = rawType === 'Card' && detail.toLowerCase() === 'red card';
          const isSubstitution = rawType === 'Subst';
          const isDisallowedGoal = rawType === 'Var' && detail === 'Goal cancelled';
          // 'Penalty confirmed' (the other Var detail) is deliberately
          // left unhandled — it's a decision confirmation, not a scoring
          // change, and wasn't asked for.

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
            // 'Normal Goal' is simplified to just 'Goal' in the
            // notification text; other goal types (Penalty, Own Goal)
            // are left as-is since they're meaningfully different.
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
            // API-Football's convention — not independently verified —
            // is that `player` is the one going OFF and `assist` is the
            // one coming ON. Swap these if it reads backwards once you
            // see a real substitution notification.
            const playerOff = event.player?.name ?? 'Player';
            const playerOn = event.assist?.name ?? 'Player';
            emoji = '🔄';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName} — ${playerOff} off, ${playerOn} on`;
            notifyEveryone = false;
            eventKeyPart = `${playerOff.replace(/ /g, '_')}_${playerOn.replace(/ /g, '_')}`;
          } else {
            // Disallowed goal — corrects a goal notification that may
            // already have gone out, so it reaches the same audience a
            // goal does: everyone, with own-leg members getting full detail.
            const playerName = event.player?.name ?? '';
            const playerPart = playerName ? ` ${playerName}` : '';
            emoji = '🚫';
            eventDetail = `${timeLabel} ${emoji} ${eventTeamName}${playerPart} — Goal Disallowed`;
            notifyEveryone = true;
            eventKeyPart = `${detail.replace(/ /g, '_')}_${playerName.replace(/ /g, '_')}`;
          }

          const eventId = `${elapsed}_${extra}_${eventTeamId}_${rawType}_${eventKeyPart}`;
          if (processedIds.has(eventId)) continue;

          // Record as processed.
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