const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore } = require("firebase-admin/firestore");
const db = getFirestore();
const SPORTMONKS_TOKEN = process.env.SPORTMONKS_API_TOKEN;
const FINISHED_STATES = ["FT", "AET", "FT_PEN", "ABAN", "CANCL"];

// ============================================================
// TEAM NAME NORMALISATION
//
// Ported from fixture_matching_service.dart's alias table, since Cloud
// Functions run as separate JS code and can't import the Dart file
// directly. Keep both lists in sync if either grows — this is what
// resolves cases like UK Odds API writing "Man City" into a leg's
// selectionDescription while Sportmonks' own participant name for the
// same fixture is "Manchester City".
// ============================================================

const TEAM_ALIASES = {
  // England — Premier League & Championship
  "man city": "manchester city",
  "man utd": "manchester united",
  "man united": "manchester united",
  "spurs": "tottenham hotspur",
  "tottenham": "tottenham hotspur",
  "wolves": "wolverhampton wanderers",
  "wolverhampton": "wolverhampton wanderers",
  "nottm forest": "nottingham forest",
  "forest": "nottingham forest",
  "newcastle": "newcastle united",
  "west brom": "west bromwich albion",
  "wba": "west bromwich albion",
  "qpr": "queens park rangers",
  "leeds": "leeds united",
  "norwich": "norwich city",
  "cardiff": "cardiff city",
  "swansea": "swansea city",
  "sheff utd": "sheffield united",
  "sheffield utd": "sheffield united",
  "sheff wed": "sheffield wednesday",
  "stoke": "stoke city",
  "hull": "hull city",
  "preston": "preston north end",
  "derby": "derby county",
  "coventry": "coventry city",
  "ipswich": "ipswich town",
  "blackburn": "blackburn rovers",
  "bolton": "bolton wanderers",
  "charlton": "charlton athletic",
  "birmingham": "birmingham city",
  "west ham": "west ham united",
  "brighton": "brighton and hove albion",
  "brighton & hove albion": "brighton and hove albion",
  "brighton hove albion": "brighton and hove albion",
  "bournemouth": "afc bournemouth",

  // Spain — La Liga
  "athletic bilbao": "athletic club",
  "atletico madrid": "atletico de madrid",
  "atleti": "atletico de madrid",
  "barca": "fc barcelona",
  "barcelona": "fc barcelona",
  "betis": "real betis",
  "sociedad": "real sociedad",
  "depor": "deportivo la coruna",
  "deportivo la coruña": "deportivo la coruna",
  "espanyol barcelona": "espanyol",
  "rayo": "rayo vallecano",
  "valencia cf": "valencia",
  "sevilla fc": "sevilla",
  "villarreal cf": "villarreal",
  "alaves": "deportivo alaves",
  "deportivo alavés": "deportivo alaves",
  "osasuna": "ca osasuna",
  "celta": "celta de vigo",
  "celta vigo": "celta de vigo",
  "malaga": "malaga cf",
  "elche": "elche cf",
  "getafe": "getafe cf",
  "levante": "levante ud",
  "spanish primera liga": "la liga",

  // Italy — Serie A
  "inter": "inter milan",
  "internazionale": "inter milan",
  "milan": "ac milan",
  "roma": "as roma",
  "lazio": "lazio roma",
  "napoli": "ssc napoli",
  "monza": "ac monza",
  "cagliari": "cagliari calcio",
  "como": "como 1907",
  "frosinone": "frosinone calcio",
  "genoa": "genoa cfc",
  "parma": "parma calcio 1913",
  "sassuolo": "sassuolo calcio",
  "torino": "torino fc",
  "udinese": "udinese calcio",
  "lecce": "us lecce",
  "venezia": "venezia fc",

  // Germany — Bundesliga
  "bayern": "bayern munchen",
  "bayern munich": "bayern munchen",
  "fc bayern munich": "bayern munchen",
  "bayern münchen": "bayern munchen",
  "dortmund": "borussia dortmund",
  "bvb": "borussia dortmund",
  "gladbach": "borussia monchengladbach",
  "monchengladbach": "borussia monchengladbach",
  "mönchengladbach": "borussia monchengladbach",
  "leverkusen": "bayer leverkusen",
  "frankfurt": "eintracht frankfurt",
  "leipzig": "rb leipzig",
  "rasenballsport leipzig": "rb leipzig",
  "stuttgart": "vfb stuttgart",
  "bremen": "sv werder bremen",
  "werder bremen": "sv werder bremen",
  "augsburg": "fc augsburg",
  "schalke": "fc schalke 04",
  "schalke 04": "fc schalke 04",
  "hamburg": "hamburger sv",
  "hsv": "hamburger sv",
  "freiburg": "sc freiburg",
  "paderborn": "sc paderborn",
  "elversberg": "sv elversberg",
  "hoffenheim": "tsg hoffenheim",
  "union berlin": "1. fc union berlin",
  "koln": "1. fc koln",
  "köln": "1. fc koln",
  "cologne": "1. fc koln",
  "mainz": "1. fsv mainz 05",
};

const IGNORED_WORDS = new Set([
  "fc", "cf", "afc", "sc", "ac", "as", "ss", "ssc", "calcio", "club",
  "football", "de", "the", "1913", "1907", "04", "05",
]);

const ACCENT_MAP = {
  "á": "a", "à": "a", "ä": "a", "â": "a", "ã": "a", "å": "a",
  "ç": "c", "é": "e", "è": "e", "ë": "e", "ê": "e",
  "í": "i", "ì": "i", "ï": "i", "î": "i", "ñ": "n",
  "ó": "o", "ò": "o", "ö": "o", "ô": "o", "õ": "o", "ø": "o",
  "ú": "u", "ù": "u", "ü": "u", "û": "u", "ý": "y", "ÿ": "y", "ß": "ss",
};

function normalise(value) {
  let result = (value || "").toLowerCase().trim();
  result = result.replace(/[áàäâãåçéèëêíìïîñóòöôõøúùüûýÿß]/g, (ch) => ACCENT_MAP[ch] || ch);
  result = result.replace(/[^a-z0-9\s]/g, " ");
  result = result.replace(/\s+/g, " ").trim();
  return result;
}

function canonicalTeamName(value) {
  let normalised = normalise(value);
  if (TEAM_ALIASES[normalised]) normalised = normalise(TEAM_ALIASES[normalised]);
  const words = normalised.split(" ").filter((w) => w && !IGNORED_WORDS.has(w));
  normalised = words.join(" ");
  if (TEAM_ALIASES[normalised]) normalised = normalise(TEAM_ALIASES[normalised]);
  return normalised.trim();
}

// Reverse index (canonical name -> every alias that maps to it), built once
// at module load, so a check for "does this text mention Manchester City"
// can also match "man city" directly, not just the fully-canonical form.
const REVERSE_ALIASES = {};
for (const [alias, canonical] of Object.entries(TEAM_ALIASES)) {
  const canon = normalise(canonical);
  if (!REVERSE_ALIASES[canon]) REVERSE_ALIASES[canon] = [];
  REVERSE_ALIASES[canon].push(alias);
}

/// Whether [selection] (already-lowercased free text) mentions [teamName],
/// tolerant of the two providers using different variants of the same
/// team's name (e.g. "Man City" vs "Manchester City").
function selectionMentionsTeam(selection, teamName) {
  const canonical = canonicalTeamName(teamName);
  if (!canonical) return false;
  const candidates = new Set([canonical, normalise(teamName)]);
  (REVERSE_ALIASES[canonical] || []).forEach((alias) => candidates.add(alias));
  for (const candidate of candidates) {
    if (candidate && selection.includes(candidate)) return true;
  }
  return false;
}

function matchResultKey(homeG, awayG, homeTeam, awayTeam) {
  if (homeG > awayG) return canonicalTeamName(homeTeam);
  if (awayG > homeG) return canonicalTeamName(awayTeam);
  return "draw";
}

function determineOutcome(leg, homeTeam, awayTeam, homeGoals, awayGoals, homeHTGoals, awayHTGoals) {
  // selectionDescription is "{pick} — {home} vs {away}" — the fixture suffix
  // always contains both team names, so matching the full string made every
  // home-team check true regardless of what was actually picked.
  // Split tolerantly on either a spaced em-dash or a spaced hyphen — a real
  // Half Time/Full Time example came through using a plain " - " separator.
  const selectionPart = leg.selectionDescription.split(/\s[-—]\s/)[0] || '';
  const selection = selectionPart.toLowerCase();
  if (leg.betType === "Match Winner") {
    const homeWon = homeGoals > awayGoals;
    const awayWon = awayGoals > homeGoals;
    const isDraw = homeGoals === awayGoals;
    if (selectionMentionsTeam(selection, homeTeam)) return homeWon ? "won" : "lost";
    if (selectionMentionsTeam(selection, awayTeam)) return awayWon ? "won" : "lost";
    if (selection.includes("draw")) return isDraw ? "won" : "lost";
    return "pending";
  }
  if (leg.betType === "Over/Under Goals") {
    const totalGoals = homeGoals + awayGoals;
    const match = selection.match(/(\d+(?:\.\d+)?)/);
    if (!match) return "pending";
    const line = parseFloat(match[1]);
    if (selection.includes("over")) return totalGoals > line ? "won" : "lost";
    if (selection.includes("under")) return totalGoals < line ? "won" : "lost";
    return "pending";
  }
  if (leg.betType === "Team Goals Over/Under") {
    // Only resolvable if the selection text actually names which team the
    // line refers to — legs submitted before the team name was included in
    // selectionDescription can't be disambiguated and are left pending for
    // manual settlement.
    const match = selection.match(/(\d+(?:\.\d+)?)/);
    if (!match) return "pending";
    const line = parseFloat(match[1]);
    let teamGoals;
    if (selectionMentionsTeam(selection, homeTeam)) {
      teamGoals = homeGoals;
    } else if (selectionMentionsTeam(selection, awayTeam)) {
      teamGoals = awayGoals;
    } else {
      return "pending"; // can't tell which team's goals this refers to
    }
    if (selection.includes("over")) return teamGoals > line ? "won" : "lost";
    if (selection.includes("under")) return teamGoals < line ? "won" : "lost";
    return "pending";
  }
  if (leg.betType === "Both Teams to Score") {
    const bothScored = homeGoals > 0 && awayGoals > 0;
    if (selection.startsWith("yes")) return bothScored ? "won" : "lost";
    if (selection.startsWith("no")) return bothScored ? "lost" : "won";
    return "pending";
  }
  if (leg.betType === "Draw No Bet") {
    const isDraw = homeGoals === awayGoals;
    if (isDraw) return "void"; // stake refunded — doesn't count as played or won
    const homeWon = homeGoals > awayGoals;
    if (selectionMentionsTeam(selection, homeTeam)) return homeWon ? "won" : "lost";
    if (selectionMentionsTeam(selection, awayTeam)) return !homeWon ? "won" : "lost";
    return "pending";
  }
  if (leg.betType === "Handicap") {
    const match = selection.match(/([+-]?\d+(?:\.\d+)?)/);
    if (!match) return "pending";
    const handicapValue = parseFloat(match[1]);
    let adjustedTeamScore, opponentScore;
    if (selectionMentionsTeam(selection, homeTeam)) {
      adjustedTeamScore = homeGoals + handicapValue;
      opponentScore = awayGoals;
    } else if (selectionMentionsTeam(selection, awayTeam)) {
      adjustedTeamScore = awayGoals + handicapValue;
      opponentScore = homeGoals;
    } else {
      return "pending";
    }
    if (adjustedTeamScore === opponentScore) return "void"; // push
    return adjustedTeamScore > opponentScore ? "won" : "lost";
  }
  if (leg.betType === "Correct Score") {
    // Real example: "Coventry 3-2 — Arsenal vs Coventry". The scoreline
    // digits are what matter, not whatever label precedes them (this API
    // seems to label the selection with a team name that isn't necessarily
    // meaningful here) — matching the H-A digit pattern anywhere in the
    // selection text works regardless of that prefix.
    const match = selection.match(/(\d+)\s*-\s*(\d+)/);
    if (!match) return "pending";
    const predictedHome = parseInt(match[1], 10);
    const predictedAway = parseInt(match[2], 10);
    return (homeGoals === predictedHome && awayGoals === predictedAway) ? "won" : "lost";
  }
  if (leg.betType === "Double Chance") {
    // Real example: "Crystal Palace-Draw — Everton vs Crystal Palace".
    // Checking which two of {home, away, draw} are actually named, rather
    // than splitting on the hyphen, avoids breaking on any team name that
    // itself happens to contain a hyphen.
    const isDraw = homeGoals === awayGoals;
    const homeWon = homeGoals > awayGoals;
    const awayWon = awayGoals > homeGoals;
    const coversHome = selectionMentionsTeam(selection, homeTeam);
    const coversAway = selectionMentionsTeam(selection, awayTeam);
    const coversDraw = selection.includes("draw");
    if (!coversHome && !coversAway && !coversDraw) return "pending";
    if ((coversHome && homeWon) || (coversAway && awayWon) || (coversDraw && isDraw)) {
      return "won";
    }
    return "lost";
  }
  if (leg.betType === "BTTS & Over 2.5 (Estimate)") {
    const bothScored = homeGoals > 0 && awayGoals > 0;
    const over = (homeGoals + awayGoals) > 2.5;
    return (bothScored && over) ? "won" : "lost";
  }
  if (leg.betType === "BTTS & Under 2.5 (Estimate)") {
    const bothScored = homeGoals > 0 && awayGoals > 0;
    const under = (homeGoals + awayGoals) < 2.5;
    return (bothScored && under) ? "won" : "lost";
  }
  if (leg.betType === "No BTTS & Over 2.5 (Estimate)") {
    const bothScored = homeGoals > 0 && awayGoals > 0;
    const over = (homeGoals + awayGoals) > 2.5;
    return (!bothScored && over) ? "won" : "lost";
  }
  if (leg.betType === "No BTTS & Under 2.5 (Estimate)") {
    const bothScored = homeGoals > 0 && awayGoals > 0;
    const under = (homeGoals + awayGoals) < 2.5;
    return (!bothScored && under) ? "won" : "lost";
  }
  if (leg.betType === "Half Time / Full Time") {
    if (homeHTGoals == null || awayHTGoals == null) return "pending"; // no HT data yet
    // Canonicalise both the parsed selection fragments and the computed
    // result keys before comparing — this was previously an exact string
    // match against raw team-name casing/variant, which is exactly the
    // kind of check a provider name mismatch (e.g. "Man City" vs
    // "Manchester City") would silently break.
    const parts = selection.split("/").map((p) => canonicalTeamName(p.trim()));
    if (parts.length !== 2) return "pending";
    const [htPick, ftPick] = parts;
    const htResult = matchResultKey(homeHTGoals, awayHTGoals, homeTeam, awayTeam);
    const ftResult = matchResultKey(homeGoals, awayGoals, homeTeam, awayTeam);
    return (htPick === htResult && ftPick === ftResult) ? "won" : "lost";
  }
  return "pending";
}
exports.settleLegs = onSchedule("every 15 minutes", async () => {
  const pendingSnap = await db.collection("legs")
    .where("outcome", "==", "pending")
    .get();
  console.log(`settleLegs: found ${pendingSnap.docs.length} pending leg(s) to check.`);
  let updated = 0;
  let skippedNoFixtureId = 0;
  let skippedApiError = 0;
  let skippedNotFinished = 0;
  let skippedNoParticipants = 0;
  let skippedNoScores = 0;
  let skippedStillPending = 0;
  for (const legDoc of pendingSnap.docs) {
    try {
      const leg = legDoc.data();
      if (!leg.sportmonksFixtureId) {
        skippedNoFixtureId++;
        continue;
      }
      const url =
        `https://api.sportmonks.com/v3/football/fixtures/${leg.sportmonksFixtureId}` +
        `?api_token=${SPORTMONKS_TOKEN}` +
        `&include=participants;scores;state`;
      const response = await fetch(url);
      if (!response.ok) {
        const body = await response.text().catch(() => "");
        console.error(
          `settleLegs: Sportmonks API call failed for leg ${legDoc.id} ` +
          `(fixture ${leg.sportmonksFixtureId}): ${response.status} ${body}`
        );
        skippedApiError++;
        continue;
      }
      const json = await response.json();
      const fixture = json.data;
      if (!fixture) {
        skippedApiError++;
        continue;
      }
      if (!FINISHED_STATES.includes(fixture.state?.short_name)) {
        skippedNotFinished++;
        continue;
      }
      const home = fixture.participants?.find((p) => p.meta?.location === "home");
      const away = fixture.participants?.find((p) => p.meta?.location === "away");
      if (!home || !away) {
        skippedNoParticipants++;
        continue;
      }
      const homeScore = fixture.scores?.find((s) => s.description === "CURRENT" && s.score.participant === "home");
      const awayScore = fixture.scores?.find((s) => s.description === "CURRENT" && s.score.participant === "away");
      if (!homeScore || !awayScore) {
        skippedNoScores++;
        continue;
      }
      const homeHTScore = fixture.scores?.find((s) => s.description === "1ST_HALF" && s.score.participant === "home");
      const awayHTScore = fixture.scores?.find((s) => s.description === "1ST_HALF" && s.score.participant === "away");
      const outcome = determineOutcome(
        leg, home.name, away.name,
        homeScore.score.goals, awayScore.score.goals,
        homeHTScore?.score?.goals, awayHTScore?.score?.goals
      );
      if (outcome === "pending") {
        console.log(
          `settleLegs: leg ${legDoc.id} (betType="${leg.betType}", ` +
          `selection="${leg.selectionDescription}") could not be resolved ` +
          `against ${home.name} ${homeScore.score.goals}-${awayScore.score.goals} ${away.name}.`
        );
        skippedStillPending++;
        continue;
      }
      await legDoc.ref.update({ outcome });
      console.log(`settleLegs: leg ${legDoc.id} settled as "${outcome}".`);
      updated++;
    } catch (error) {
      // A single malformed/unexpected leg (e.g. missing selectionDescription
      // on an older document) must never take down the whole run — without
      // this, one bad leg would silently block every other pending leg from
      // ever being checked, on every future run, since the crash happens
      // before the loop reaches them.
      console.error(`settleLegs: failed to process leg ${legDoc.id}:`, error);
    }
  }
  console.log(
    `settleLegs: run complete. updated=${updated}, ` +
    `noFixtureId=${skippedNoFixtureId}, apiError=${skippedApiError}, ` +
    `notFinished=${skippedNotFinished}, noParticipants=${skippedNoParticipants}, ` +
    `noScores=${skippedNoScores}, stillPending=${skippedStillPending}.`
  );
  await settleTournamentMatches();
});

// ============================================================
// KNOCKOUT TOURNAMENT — MATCH SETTLEMENT
//
// Runs after the per-leg loop above so it always sees this same run's
// freshly-settled leg outcomes, rather than waiting an extra 15-minute
// cycle. Walkovers/no-shows are resolved separately, client-side, at the
// moment a manager locks a gameweek's odds (see resolveTournamentWalkovers
// in firestore_service.dart) — this function only ever handles matches
// where both sides genuinely submitted legs.
// ============================================================

function tournamentRoundLabel(roundSize) {
  if (roundSize === 0) return "Qualifying Round";
  switch (roundSize) {
    case 2: return "Final";
    case 4: return "Semi-Final";
    case 8: return "Quarter-Final";
    case 16: return "Round of 16";
    case 32: return "Round of 32";
    default: return `Round of ${roundSize}`;
  }
}

async function sendTeamNotification(teamId, recipientMemberIds, type, title, body) {
  const batch = db.batch();
  for (const memberId of recipientMemberIds) {
    const ref = db.collection("notifications").doc();
    batch.set(ref, {
      teamId,
      recipientMemberId: memberId,
      type,
      title,
      body,
      createdAt: new Date(),
      read: false,
    });
  }
  await batch.commit();
}

/// A leg counts as "won" only if it genuinely won — void and anything
/// else (including still-somehow-pending, though callers guard against
/// that separately) are treated as a loss for cascade purposes, per the
/// confirmed rule that void legs count as losses.
function wonOrLost(leg) {
  return leg && leg.outcome === "won" ? "won" : "lost";
}

async function settleTournamentMatches() {
  const pendingMatchesSnap = await db.collection("tournamentMatches")
    .where("winnerMemberId", "==", null)
    .get();
  let resolved = 0;
  for (const matchDoc of pendingMatchesSnap.docs) {
    try {
      const match = matchDoc.data();
      // Byes are pre-resolved at creation; unattached or single-member
      // matches have nothing to settle here.
      if (match.isBye || !match.gameWeekId || !match.memberBId) continue;

      const legsSnap = await db.collection("legs")
        .where("tournamentMatchId", "==", matchDoc.id)
        .get();
      const legs = legsSnap.docs.map((d) => d.data());
      const aPrimary = legs.find((l) => l.memberId === match.memberAId && !l.isSecondaryTournamentLeg);
      const aSecondary = legs.find((l) => l.memberId === match.memberAId && l.isSecondaryTournamentLeg);
      const bPrimary = legs.find((l) => l.memberId === match.memberBId && !l.isSecondaryTournamentLeg);
      const bSecondary = legs.find((l) => l.memberId === match.memberBId && l.isSecondaryTournamentLeg);

      // Both sides need at least a primary leg on record — if either is
      // missing entirely, that's a walkover, already handled client-side
      // at gameweek-lock time. Nothing to do here in that case.
      if (!aPrimary || !bPrimary) continue;

      // Wait until every relevant leg has a real outcome.
      const relevantLegs = [aPrimary, aSecondary, bPrimary, bSecondary].filter(Boolean);
      if (relevantLegs.some((l) => l.outcome === "pending")) continue;

      let winnerId = null;

      // 1 & 2: primary legs.
      const aPrimaryResult = wonOrLost(aPrimary);
      const bPrimaryResult = wonOrLost(bPrimary);
      if (aPrimaryResult === "won" && bPrimaryResult !== "won") {
        winnerId = match.memberAId;
      } else if (bPrimaryResult === "won" && aPrimaryResult !== "won") {
        winnerId = match.memberBId;
      } else if (aPrimaryResult === "won" && bPrimaryResult === "won") {
        const aPts = (aPrimary.decimalOddsAtSelection - 1) * 3;
        const bPts = (bPrimary.decimalOddsAtSelection - 1) * 3;
        if (aPts !== bPts) winnerId = aPts > bPts ? match.memberAId : match.memberBId;
      }

      // 3 & 4: only reached if both primaries lost/void — fall through to secondary.
      if (!winnerId) {
        const aSecondaryResult = aSecondary ? wonOrLost(aSecondary) : "lost";
        const bSecondaryResult = bSecondary ? wonOrLost(bSecondary) : "lost";
        if (aSecondaryResult === "won" && bSecondaryResult !== "won") {
          winnerId = match.memberAId;
        } else if (bSecondaryResult === "won" && aSecondaryResult !== "won") {
          winnerId = match.memberBId;
        } else if (aSecondaryResult === "won" && bSecondaryResult === "won") {
          const aPts = (aSecondary.decimalOddsAtSelection - 1) * 3;
          const bPts = (bSecondary.decimalOddsAtSelection - 1) * 3;
          if (aPts !== bPts) winnerId = aPts > bPts ? match.memberAId : match.memberBId;
        }
      }

      // 5: both lost everywhere — higher primary odds (the bolder pick) advances.
      if (!winnerId) {
        if (aPrimary.decimalOddsAtSelection !== bPrimary.decimalOddsAtSelection) {
          winnerId = aPrimary.decimalOddsAtSelection > bPrimary.decimalOddsAtSelection
            ? match.memberAId
            : match.memberBId;
        } else {
          // A genuine complete tie across every criterion — essentially
          // impossible in practice, but resolved randomly rather than
          // leaving the match stuck forever.
          winnerId = Math.random() < 0.5 ? match.memberAId : match.memberBId;
        }
      }

      const winnerName = winnerId === match.memberAId ? match.memberAName : match.memberBName;
      const loserId = winnerId === match.memberAId ? match.memberBId : match.memberAId;
      const loserName = winnerId === match.memberAId ? match.memberBName : match.memberAName;

      await matchDoc.ref.update({ winnerMemberId: winnerId, winnerName });
      console.log(`settleTournamentMatches: match ${matchDoc.id} resolved — winner: ${winnerName}.`);
      resolved++;

      const roundLabel = tournamentRoundLabel(match.roundSize);
      await sendTeamNotification(
        match.teamId, [winnerId], "tournamentRoundWon",
        "Easy work! 🏆",
        `Easy work! You're through to the ${roundLabel} after beating ${loserName}.`
      );
      await sendTeamNotification(
        match.teamId, [loserId], "tournamentRoundLost",
        "The dream is over 💔",
        `The dream is over. You lost in the ${roundLabel} to ${winnerName}.`
      );
    } catch (error) {
      console.error(`settleTournamentMatches: failed to process match ${matchDoc.id}:`, error);
    }
  }
  console.log(`settleTournamentMatches: run complete. resolved=${resolved}.`);
}