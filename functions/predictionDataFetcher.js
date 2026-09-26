/**
 * predictionDataFetcher.js — fetches and shapes API-Football data into
 * the prediction engine's input format. JS port of
 * match_prediction_data_provider.dart + api_football_mapper.dart.
 */

const API_KEY = process.env.API_FOOTBALL_KEY;
const BASE_URL = 'https://v3.football.api-sports.io';

async function apiGet(path) {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { 'x-apisports-key': API_KEY },
  });
  if (!res.ok) throw new Error(`API Football ${path} → HTTP ${res.status}`);
  return res.json();
}

function toTeamMatch(fixture, teamId) {
  const isHome = fixture.teams.home.id === teamId;
  const goalsFor = isHome ? (fixture.goals.home ?? 0) : (fixture.goals.away ?? 0);
  const goalsAgainst = isHome ? (fixture.goals.away ?? 0) : (fixture.goals.home ?? 0);
  return { isHome, goalsFor, goalsAgainst };
}

function resultFor(fixture, teamId) {
  if (fixture.goals.home == null || fixture.goals.away == null) return 'D';
  const isHome = fixture.teams.home.id === teamId;
  const teamGoals = isHome ? fixture.goals.home : fixture.goals.away;
  const opponentGoals = isHome ? fixture.goals.away : fixture.goals.home;
  if (teamGoals > opponentGoals) return 'W';
  if (teamGoals < opponentGoals) return 'L';
  return 'D';
}

function parseTeamStatistics(json) {
  if (!json) return null;
  const avg = (raw) => parseFloat(raw) || 0;
  const asInt = (raw) => (typeof raw === 'number' ? raw : parseInt(raw) || 0);
  const fixtures = json.fixtures || {};
  const played = fixtures.played || {};
  const wins = fixtures.wins || {};
  const draws = fixtures.draws || {};
  const loses = fixtures.loses || {};
  const goals = json.goals || {};
  const goalsFor = goals.for || {};
  const goalsAgainst = goals.against || {};
  const goalsForAvg = goalsFor.average || {};
  const goalsAgainstAvg = goalsAgainst.average || {};
  return {
    seasonGoalsForAvg: avg(goalsForAvg.total),
    seasonGoalsAgainstAvg: avg(goalsAgainstAvg.total),
    homePlayed: asInt(played.home),
    homeWins: asInt(wins.home),
    homeDraws: asInt(draws.home),
    homeLosses: asInt(loses.home),
    homeGoalsForAvg: avg(goalsForAvg.home),
    homeGoalsAgainstAvg: avg(goalsAgainstAvg.home),
    awayPlayed: asInt(played.away),
    awayWins: asInt(wins.away),
    awayDraws: asInt(draws.away),
    awayLosses: asInt(loses.away),
    awayGoalsForAvg: avg(goalsForAvg.away),
    awayGoalsAgainstAvg: avg(goalsAgainstAvg.away),
  };
}

function percentOrNull(value) {
  if (value == null) return null;
  const n = typeof value === 'number' ? value : parseFloat(String(value).replace('%', ''));
  if (isNaN(n)) return null;
  return Math.min(1.0, Math.max(0.0, n > 1 ? n / 100.0 : n));
}

function parseApiPrediction(predictionsJson) {
  const response = predictionsJson.response;
  if (!Array.isArray(response) || response.length === 0) return null;
  const root = response[0];
  const percent = root.percent;
  if (!percent) return null;
  const home = percentOrNull(percent.home);
  const draw = percentOrNull(percent.draw);
  const away = percentOrNull(percent.away);
  if (home == null || draw == null || away == null) return null;
  const goals = root.goals || {};
  const num = (v) => (v == null ? null : parseFloat(v));
  return {
    home, draw, away,
    predictedHomeGoals: num(goals.home),
    predictedAwayGoals: num(goals.away),
  };
}

function h2hFromFixtureJson(fixture, homeTeamId, awayTeamId) {
  const teams = fixture.teams;
  const goals = fixture.goals;
  if (!teams || !goals || !teams.home || !teams.away) return null;
  const homeId = teams.home.id;
  const awayId = teams.away.id;
  const homeGoals = goals.home;
  const awayGoals = goals.away;
  if (homeId == null || awayId == null || homeGoals == null || awayGoals == null) return null;
  return {
    homeTeamId: homeId,
    awayTeamId: awayId,
    homeGoals,
    awayGoals,
    date: fixture.fixture?.date ? new Date(fixture.fixture.date) : null,
  };
}

function toPlayerAbsence(injury) {
  const player = injury.player || injury;
  const reason = injury.reason ?? player.reason ?? null;
  const type = injury.type ?? player.type ?? 'Unavailable';
  return {
    playerName: player.name || 'Unknown',
    type,
    reason,
    importance: 0.5,
    attackingImpact: 0.5,
    defensiveImpact: 0.5,
  };
}

async function fetchAndBuild({ fixtureId, leagueId, season, homeTeamId, homeTeamName, awayTeamId, awayTeamName, isLeagueGame }) {
  const [
    homeFixturesRaw,
    awayFixturesRaw,
    homeStatsRaw,
    awayStatsRaw,
    h2hRaw,
    predictionsRaw,
    injuriesRaw,
  ] = await Promise.all([
    apiGet(`/fixtures?team=${homeTeamId}&last=8`),
    apiGet(`/fixtures?team=${awayTeamId}&last=8`),
    apiGet(`/teams/statistics?league=${leagueId}&season=${season}&team=${homeTeamId}`),
    apiGet(`/teams/statistics?league=${leagueId}&season=${season}&team=${awayTeamId}`),
    apiGet(`/fixtures/headtohead?h2h=${homeTeamId}-${awayTeamId}&last=5`),
    apiGet(`/predictions?fixture=${fixtureId}`),
    apiGet(`/injuries?fixture=${fixtureId}`),
  ]);

  const sortDesc = (list) => list.slice().sort((a, b) => new Date(b.fixture.date) - new Date(a.fixture.date));
  const homeFixtures = sortDesc(homeFixturesRaw.response ?? []);
  const awayFixtures = sortDesc(awayFixturesRaw.response ?? []);

  // For a LEAGUE fixture, the display sections (Last 5 Games, Goals
  // Scored/Conceded) use a SEPARATE, league-scoped fetch — genuinely
  // the team's last 5 games IN THIS COMPETITION, not just the 5 most
  // recent entries filtered out of their last-8 across all
  // competitions (which could under-represent league form for a team
  // playing midweek cup football). The prediction ENGINE's own
  // recentMatches input deliberately keeps using the global last-8
  // fetched above, unchanged — this only affects what's displayed.
  let homeDisplayFixtures = homeFixtures;
  let awayDisplayFixtures = awayFixtures;
  if (isLeagueGame) {
    const [homeLeagueRaw, awayLeagueRaw] = await Promise.all([
      apiGet(`/fixtures?team=${homeTeamId}&league=${leagueId}&season=${season}&last=5`),
      apiGet(`/fixtures?team=${awayTeamId}&league=${leagueId}&season=${season}&last=5`),
    ]);
    homeDisplayFixtures = sortDesc(homeLeagueRaw.response ?? []);
    awayDisplayFixtures = sortDesc(awayLeagueRaw.response ?? []);
  }

  const homeStats = parseTeamStatistics(homeStatsRaw.response);
  const awayStats = parseTeamStatistics(awayStatsRaw.response);

  const injuriesParsed = (injuriesRaw.response ?? []).map((raw) => {
    const teamId = (raw.team || {}).id ?? 0;
    return { ...toPlayerAbsence(raw), teamId };
  });
  const homeAbsences = injuriesParsed.filter((i) => i.teamId === homeTeamId);
  const awayAbsences = injuriesParsed.filter((i) => i.teamId === awayTeamId);

  const h2hParsed = (h2hRaw.response ?? [])
    .map((f) => h2hFromFixtureJson(f, homeTeamId, awayTeamId))
    .filter((m) => m != null)
    .sort((a, b) => (a.date ?? 0) - (b.date ?? 0));

  const apiPrediction = parseApiPrediction(predictionsRaw);

  const input = {
    fixtureId, leagueId, season,
    home: {
      id: homeTeamId,
      recentMatches: homeFixtures.slice().reverse().map((f) => toTeamMatch(f, homeTeamId)),
      homeRecord: (!homeStats || homeStats.homePlayed === 0) ? null : {
        played: homeStats.homePlayed, wins: homeStats.homeWins, draws: homeStats.homeDraws, losses: homeStats.homeLosses,
        goalsForPerGame: homeStats.homeGoalsForAvg, goalsAgainstPerGame: homeStats.homeGoalsAgainstAvg,
      },
      seasonGoalsForPerGame: homeStats?.seasonGoalsForAvg ?? null,
      seasonGoalsAgainstPerGame: homeStats?.seasonGoalsAgainstAvg ?? null,
      absences: homeAbsences,
    },
    away: {
      id: awayTeamId,
      recentMatches: awayFixtures.slice().reverse().map((f) => toTeamMatch(f, awayTeamId)),
      awayRecord: (!awayStats || awayStats.awayPlayed === 0) ? null : {
        played: awayStats.awayPlayed, wins: awayStats.awayWins, draws: awayStats.awayDraws, losses: awayStats.awayLosses,
        goalsForPerGame: awayStats.awayGoalsForAvg, goalsAgainstPerGame: awayStats.awayGoalsAgainstAvg,
      },
      seasonGoalsForPerGame: awayStats?.seasonGoalsForAvg ?? null,
      seasonGoalsAgainstPerGame: awayStats?.seasonGoalsAgainstAvg ?? null,
      absences: awayAbsences,
    },
    h2h: h2hParsed,
    apiPrediction,
    leagueBaseline: { homeGoalsPerGame: 1.50, awayGoalsPerGame: 1.20, homeXgPerGame: null, awayXgPerGame: null },
  };

  const last5Display = (fixtures, teamId) => {
    const last5 = fixtures.slice(0, 5);
    const results = last5.map((f) => resultFor(f, teamId));
    const goalsFor = last5.map((f) => toTeamMatch(f, teamId).goalsFor);
    const goalsAgainst = last5.map((f) => toTeamMatch(f, teamId).goalsAgainst);
    const avg = (arr) => (arr.length === 0 ? 0 : arr.reduce((a, b) => a + b, 0) / arr.length);
    return {
      last5Results: results,
      last5GoalsForAvg: avg(goalsFor),
      last5GoalsAgainstAvg: avg(goalsAgainst),
    };
  };

  return {
    input,
    display: {
      home: { teamId: homeTeamId, teamName: homeTeamName, ...last5Display(homeDisplayFixtures, homeTeamId), absences: homeAbsences },
      away: { teamId: awayTeamId, teamName: awayTeamName, ...last5Display(awayDisplayFixtures, awayTeamId), absences: awayAbsences },
      h2h: h2hParsed.slice().reverse().slice(0, 5).map((m) => ({
        date: m.date ? m.date.toISOString() : null,
        homeTeamId: m.homeTeamId,
        awayTeamId: m.awayTeamId,
        homeGoals: m.homeGoals,
        awayGoals: m.awayGoals,
      })),
    },
  };
}

module.exports = { fetchAndBuild };