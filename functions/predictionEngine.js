/**
 * predictionEngine.js — JavaScript port of the Dart prediction engine
 * package. predict() now accepts weights as a parameter, so the
 * learning pipeline can call the SAME real production formula with
 * candidate weights during walk-forward validation, rather than a
 * duplicate approximation.
 */

const DEFAULT_WEIGHTS = {
  recentForm: 0.25,
  homeAway: 0.25,
  goalsXg: 0.20,
  h2h: 0.10,
  injuries: 0.10,
  apiPrediction: 0.10,
};

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

function share(home, away) {
  const total = home + away;
  if (total <= 0) return 0.5;
  return clamp01(home / total);
}

function teamFormScore(matches) {
  if (matches.length === 0) return 1.0;
  const ordered = matches.slice().reverse().slice(0, 8);
  let weighted = 0, weights = 0;
  for (let i = 0; i < ordered.length; i++) {
    const m = ordered[i];
    const weight = Math.pow(0.85, i);
    const result = m.goalsFor > m.goalsAgainst ? 1.0 : (m.goalsFor === m.goalsAgainst ? 0.5 : 0.0);
    const gd = clamp((m.goalsFor - m.goalsAgainst), -3, 3) / 6.0 + 0.5;
    const xgSignal = (m.xgFor != null && m.xgAgainst != null)
      ? clamp01(0.5 + (m.xgFor - m.xgAgainst) / 3.0)
      : 0.5;
    const score = 0.55 * result + 0.25 * gd + 0.20 * xgSignal;
    weighted += score * weight;
    weights += weight;
  }
  return weights === 0 ? 1.0 : weighted / weights;
}

function recentFormFactor(home, away) {
  return share(teamFormScore(home.recentMatches), teamFormScore(away.recentMatches));
}

function goalDifferenceSignal(gf, ga) {
  return clamp01(0.5 + (gf - ga) / 4.0);
}

function homeAwayFactor(home, away) {
  const h = home.homeRecord;
  const a = away.awayRecord;
  if (!h && !a) return 0.5;
  const hScore = !h ? 0.5 : 0.55 * (h.wins / (h.played || 1)) + 0.20 * (h.draws / (h.played || 1)) + 0.25 * goalDifferenceSignal(h.goalsForPerGame, h.goalsAgainstPerGame);
  const aScore = !a ? 0.5 : 0.55 * (a.wins / (a.played || 1)) + 0.20 * (a.draws / (a.played || 1)) + 0.25 * goalDifferenceSignal(a.goalsForPerGame, a.goalsAgainstPerGame);
  return share(hScore, aScore);
}

function attackScore(goals, xg, leagueGoals, leagueXg) {
  const values = [];
  if (goals != null && leagueGoals > 0) values.push(clamp01(0.5 + ((goals / leagueGoals) - 1.0) * 0.35));
  if (xg != null && leagueXg != null && leagueXg > 0) values.push(clamp01(0.5 + ((xg / leagueXg) - 1.0) * 0.35));
  if (values.length === 0) return 0.5;
  return values.reduce((a, b) => a + b) / values.length;
}

function defensiveWeakness(goalsAgainst, xga, leagueGoals, leagueXga) {
  const values = [];
  if (goalsAgainst != null && leagueGoals > 0) values.push(clamp01(0.5 + (1.0 - goalsAgainst / leagueGoals) * 0.35));
  if (xga != null && leagueXga != null && leagueXga > 0) values.push(clamp01(0.5 + (1.0 - xga / leagueXga) * 0.35));
  if (values.length === 0) return 0.5;
  return values.reduce((a, b) => a + b) / values.length;
}

function goalsXgFactor(input) {
  const { home: h, away: a, leagueBaseline: lb } = input;
  const hAttack = attackScore(h.seasonGoalsForPerGame, h.seasonXgForPerGame, lb.homeGoalsPerGame, lb.homeXgPerGame);
  const aAttack = attackScore(a.seasonGoalsForPerGame, a.seasonXgForPerGame, lb.awayGoalsPerGame, lb.awayXgPerGame);
  const hDefWeakness = defensiveWeakness(h.seasonGoalsAgainstPerGame, h.seasonXgAgainstPerGame, lb.awayGoalsPerGame, lb.awayXgPerGame);
  const aDefWeakness = defensiveWeakness(a.seasonGoalsAgainstPerGame, a.seasonXgAgainstPerGame, lb.homeGoalsPerGame, lb.homeXgPerGame);
  const homeScore = 0.65 * hAttack + 0.35 * aDefWeakness;
  const awayScore = 0.65 * aAttack + 0.35 * hDefWeakness;
  return share(homeScore, awayScore);
}

function h2hFactor(input) {
  if (!input.h2h || input.h2h.length === 0) return 0.5;
  const matches = input.h2h.slice().reverse().slice(0, 5);
  let homeScore = 0, weightTotal = 0;
  for (let i = 0; i < matches.length; i++) {
    const m = matches[i];
    const weight = Math.pow(0.8, i);
    const homeWasH2HHome = m.homeTeamId === input.home.id;
    const homeGoals = homeWasH2HHome ? m.homeGoals : m.awayGoals;
    const awayGoals = homeWasH2HHome ? m.awayGoals : m.homeGoals;
    const result = homeGoals > awayGoals ? 1.0 : (homeGoals === awayGoals ? 0.5 : 0.0);
    const goalSignal = clamp01(0.5 + (homeGoals - awayGoals) / 5.0);
    homeScore += (0.7 * result + 0.3 * goalSignal) * weight;
    weightTotal += weight;
  }
  return weightTotal === 0 ? 0.5 : homeScore / weightTotal;
}

function injuriesFactor(home, away) {
  const impact = (absences) => {
    if (!absences || absences.length === 0) return 0.0;
    return absences.reduce((sum, p) => sum + p.importance * (0.55 * p.attackingImpact + 0.45 * p.defensiveImpact), 0.0);
  };
  const h = impact(home.absences);
  const a = impact(away.absences);
  return share(1.0 / (1.0 + h), 1.0 / (1.0 + a));
}

function apiPredictionFactor(prediction) {
  if (!prediction) return 0.5;
  return share(clamp01(prediction.home), clamp01(prediction.away));
}

function buildFactors(input, weights) {
  const factors = {
    recentForm: recentFormFactor(input.home, input.away),
    homeAway: homeAwayFactor(input.home, input.away),
    goalsXg: goalsXgFactor(input),
    h2h: h2hFactor(input),
    injuries: injuriesFactor(input.home, input.away),
    apiPrediction: apiPredictionFactor(input.apiPrediction),
  };
  factors.weightedHomeStrength =
    factors.recentForm * weights.recentForm +
    factors.homeAway * weights.homeAway +
    factors.goalsXg * weights.goalsXg +
    factors.h2h * weights.h2h +
    factors.injuries * weights.injuries +
    factors.apiPrediction * weights.apiPrediction;
  return factors;
}

function attackMultiplier(goals, xg, baselineGoals, baselineXg) {
  const signals = [];
  if (goals != null && baselineGoals > 0) signals.push(clamp(goals / baselineGoals, 0.50, 1.80));
  if (xg != null && baselineXg != null && baselineXg > 0) signals.push(clamp(xg / baselineXg, 0.50, 1.80));
  if (signals.length === 0) return 1.0;
  return signals.reduce((a, b) => a + b) / signals.length;
}

function defenceMultiplier(goalsAgainst, xga, opponentBaselineGoals, opponentBaselineXg) {
  const signals = [];
  if (goalsAgainst != null && opponentBaselineGoals > 0) signals.push(clamp(goalsAgainst / opponentBaselineGoals, 0.55, 1.75));
  if (xga != null && opponentBaselineXg != null && opponentBaselineXg > 0) signals.push(clamp(xga / opponentBaselineXg, 0.55, 1.75));
  if (signals.length === 0) return 1.0;
  return signals.reduce((a, b) => a + b) / signals.length;
}

function calculateExpectedGoals(input, factors) {
  const baselineHome = input.leagueBaseline.homeGoalsPerGame;
  const baselineAway = input.leagueBaseline.awayGoalsPerGame;

  const homeAttack = attackMultiplier(input.home.seasonGoalsForPerGame, input.home.seasonXgForPerGame, baselineHome, input.leagueBaseline.homeXgPerGame);
  const awayAttack = attackMultiplier(input.away.seasonGoalsForPerGame, input.away.seasonXgForPerGame, baselineAway, input.leagueBaseline.awayXgPerGame);
  const homeDef = defenceMultiplier(input.home.seasonGoalsAgainstPerGame, input.home.seasonXgAgainstPerGame, baselineAway, input.leagueBaseline.awayXgPerGame);
  const awayDef = defenceMultiplier(input.away.seasonGoalsAgainstPerGame, input.away.seasonXgAgainstPerGame, baselineHome, input.leagueBaseline.homeXgPerGame);

  let homeLambda = baselineHome * homeAttack * awayDef;
  let awayLambda = baselineAway * awayAttack * homeDef;

  const homeStrength = factors.weightedHomeStrength;
  homeLambda *= 1.0 + ((homeStrength - 0.5) * 0.55);
  awayLambda *= 1.0 - ((homeStrength - 0.5) * 0.45);

  const api = input.apiPrediction;
  if (api && api.predictedHomeGoals != null) homeLambda = 0.90 * homeLambda + 0.10 * api.predictedHomeGoals;
  if (api && api.predictedAwayGoals != null) awayLambda = 0.90 * awayLambda + 0.10 * api.predictedAwayGoals;

  return {
    home: clamp(homeLambda, 0.05, 5.0),
    away: clamp(awayLambda, 0.05, 5.0),
  };
}

function poissonDistribution(lambda, maxGoals) {
  const p = new Array(maxGoals + 1).fill(0);
  p[0] = Math.exp(-lambda);
  for (let k = 1; k <= maxGoals; k++) {
    p[k] = p[k - 1] * lambda / k;
  }
  return p;
}

function calculateProbabilities(xg, maxGoals = 10) {
  const home = poissonDistribution(xg.home, maxGoals);
  const away = poissonDistribution(xg.away, maxGoals);

  let homeWin = 0, draw = 0, awayWin = 0;
  let over15 = 0, over25 = 0, over35 = 0, under25 = 0;
  let bttsYes = 0, homeOver05 = 0, homeOver15 = 0, awayOver05 = 0, awayOver15 = 0;
  let mass = 0;

  for (let h = 0; h <= maxGoals; h++) {
    for (let a = 0; a <= maxGoals; a++) {
      const p = home[h] * away[a];
      const total = h + a;
      mass += p;

      if (h > a) homeWin += p; else if (h === a) draw += p; else awayWin += p;
      if (total >= 2) over15 += p;
      if (total >= 3) over25 += p;
      if (total >= 4) over35 += p;
      if (total <= 2) under25 += p;
      if (h >= 1 && a >= 1) bttsYes += p;
      if (h >= 1) homeOver05 += p;
      if (h >= 2) homeOver15 += p;
      if (a >= 1) awayOver05 += p;
      if (a >= 2) awayOver15 += p;
    }
  }

  if (mass === 0) mass = 1.0;

  return {
    'Home Win': homeWin / mass,
    'Draw': draw / mass,
    'Away Win': awayWin / mass,
    'Over 1.5': over15 / mass,
    'Over 2.5': over25 / mass,
    'Over 3.5': over35 / mass,
    'Under 2.5': under25 / mass,
    'BTTS Yes': bttsYes / mass,
    'BTTS No': 1.0 - (bttsYes / mass),
    'Home Over 0.5': homeOver05 / mass,
    'Home Over 1.5': homeOver15 / mass,
    'Away Over 0.5': awayOver05 / mass,
    'Away Over 1.5': awayOver15 / mass,
  };
}

/// weights: {recentForm, homeAway, goalsXg, h2h, injuries, apiPrediction},
/// defaults to DEFAULT_WEIGHTS if omitted. Called both for live
/// predictions (getMatchPrediction.js, current published weights) and
/// for walk-forward validation (learningEngine.js, candidate weights
/// replayed against stored historical input).
function predict(input, weights) {
  const w = weights || DEFAULT_WEIGHTS;
  const factors = buildFactors(input, w);
  const expectedGoals = calculateExpectedGoals(input, factors);
  const probabilities = calculateProbabilities(expectedGoals);
  return { factors, expectedGoals, probabilities };
}

module.exports = { predict, DEFAULT_WEIGHTS };