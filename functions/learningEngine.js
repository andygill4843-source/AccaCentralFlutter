/**
 * learningEngine.js — JS port of the uploaded Dart learning-engine
 * package's core (learning_metrics.dart, weight_optimizer.dart,
 * walk_forward_validator.dart). Calibration (calibration_engine.dart)
 * is NOT ported in this pass — a follow-up, not implemented here.
 *
 * Deliberately mirrors the Dart formulas function-for-function rather
 * than reimplementing from scratch, so the two stay comparable if the
 * Dart package is ever revisited.
 */

const { predict } = require('./predictionEngine');

// Maps predict()'s display-style probability keys to the learning
// package's camelCase PredictionMarket keys (learning_models.dart's
// PredictionMarketX.key === enum name) — the two systems use different
// naming conventions for the same 13 markets.
const MARKET_KEY_MAP = {
  'Home Win': 'homeWin',
  'Draw': 'draw',
  'Away Win': 'awayWin',
  'Over 1.5': 'over15',
  'Over 2.5': 'over25',
  'Over 3.5': 'over35',
  'Under 2.5': 'under25',
  'BTTS Yes': 'bttsYes',
  'BTTS No': 'bttsNo',
  'Home Over 0.5': 'homeOver05',
  'Home Over 1.5': 'homeOver15',
  'Away Over 0.5': 'awayOver05',
  'Away Over 1.5': 'awayOver15',
};
const MARKETS = Object.values(MARKET_KEY_MAP);

function mapProbabilities(displayKeyedProbs) {
  const out = {};
  for (const [displayKey, learningKey] of Object.entries(MARKET_KEY_MAP)) {
    out[learningKey] = displayKeyedProbs[displayKey];
  }
  return out;
}

function valueForMarket(actual, marketKey) {
  const total = actual.homeGoals + actual.awayGoals;
  switch (marketKey) {
    case 'homeWin': return actual.homeGoals > actual.awayGoals;
    case 'draw': return actual.homeGoals === actual.awayGoals;
    case 'awayWin': return actual.homeGoals < actual.awayGoals;
    case 'over15': return total >= 2;
    case 'over25': return total >= 3;
    case 'over35': return total >= 4;
    case 'under25': return total <= 2;
    case 'bttsYes': return actual.homeGoals > 0 && actual.awayGoals > 0;
    case 'bttsNo': return !(actual.homeGoals > 0 && actual.awayGoals > 0);
    case 'homeOver05': return actual.homeGoals >= 1;
    case 'homeOver15': return actual.homeGoals >= 2;
    case 'awayOver05': return actual.awayGoals >= 1;
    case 'awayOver15': return actual.awayGoals >= 2;
    default: throw new Error(`Unknown market ${marketKey}`);
  }
}

function marketMetrics(rows, marketKey) {
  const filtered = rows.filter((r) => r.resolved && r.probabilities[marketKey] != null);
  if (filtered.length === 0) return { sampleSize: 0, brierScore: NaN, logLoss: NaN };
  let b = 0, l = 0;
  for (const r of filtered) {
    const p = Math.min(Math.max(r.probabilities[marketKey], 1e-6), 1 - 1e-6);
    const y = valueForMarket(r.actual, marketKey) ? 1 : 0;
    b += Math.pow(p - y, 2);
    l -= y * Math.log(p) + (1 - y) * Math.log(1 - p);
  }
  const n = filtered.length;
  return { sampleSize: n, brierScore: b / n, logLoss: l / n };
}

function overallMetrics(rows) {
  let b = 0, l = 0, n = 0;
  for (const marketKey of MARKETS) {
    const m = marketMetrics(rows, marketKey);
    if (m.sampleSize === 0) continue;
    b += m.brierScore;
    l += m.logLoss;
    n++;
  }
  if (n === 0) throw new Error('No valid markets in this dataset.');
  return { brier: b / n, logLoss: l / n };
}

// Bounds from weight_optimizer.dart — clamp order and ranges preserved
// exactly, then renormalised to sum to 1.
function proposeWeights(current, factorPerformance, config) {
  const names = ['recentForm', 'homeAway', 'goalsXg', 'h2h', 'injuries', 'apiPrediction'];
  const mean = names.reduce((sum, n) => sum + factorPerformance[n], 0) / names.length;
  const adj = (name, value) => {
    const delta = Math.min(
      Math.max((factorPerformance[name] - mean) * config.learningRate, -config.maxWeightChangePerRun),
      config.maxWeightChangePerRun
    );
    return value + delta;
  };
  const raw = {
    recentForm: adj('recentForm', current.recentForm),
    homeAway: adj('homeAway', current.homeAway),
    goalsXg: adj('goalsXg', current.goalsXg),
    h2h: adj('h2h', current.h2h),
    injuries: adj('injuries', current.injuries),
    apiPrediction: adj('apiPrediction', current.apiPrediction),
  };
  const bounded = {
    recentForm: Math.min(Math.max(raw.recentForm, 0.15), 0.35),
    homeAway: Math.min(Math.max(raw.homeAway, 0.15), 0.35),
    goalsXg: Math.min(Math.max(raw.goalsXg, 0.10), 0.35),
    h2h: Math.min(Math.max(raw.h2h, 0.0), 0.20),
    injuries: Math.min(Math.max(raw.injuries, 0.05), 0.20),
    apiPrediction: Math.min(Math.max(raw.apiPrediction, 0.05), 0.20),
  };
  const total = Object.values(bounded).reduce((a, b) => a + b, 0);
  const normalised = {};
  for (const [k, v] of Object.entries(bounded)) normalised[k] = v / total;
  return normalised;
}

// Mirrors learning_engine.dart's _factorPerformance — how well each
// factor, in isolation, tracked the actual home-win/away-win outcome
// across the resolved records.
function factorPerformance(rows) {
  const out = {};
  for (const name of ['recentForm', 'homeAway', 'goalsXg', 'h2h', 'injuries', 'apiPrediction']) {
    let sum = 0, count = 0;
    for (const r of rows) {
      const f = r.factors[name];
      const a = r.actual;
      if (f == null || a == null) continue;
      const target = a.homeGoals > a.awayGoals ? 1.0 : (a.homeGoals < a.awayGoals ? 0.0 : 0.5);
      sum += (f - 0.5) * (target - 0.5);
      count++;
    }
    out[name] = count === 0 ? 0 : sum / count;
  }
  return out;
}

// Chronological 80/20 walk-forward split — replays EVERY record in the
// validation slice under both weight sets via the real predict()
// function, using each record's own stored input for an exact,
// deterministic rebuild.
function walkForwardValidate(records, currentWeights, candidateWeights, minimumValidationSamples) {
  const sorted = [...records].sort((a, b) => a.predictedAt - b.predictedAt);
  const split = Math.floor(sorted.length * 0.8);
  const validation = sorted.slice(split);
  if (validation.length < minimumValidationSamples) {
    throw new Error(`Not enough records for validation (${validation.length} < ${minimumValidationSamples}).`);
  }

  const baseline = [];
  const candidate = [];
  for (const r of validation) {
    const baseResult = predict(r.input, currentWeights);
    const candResult = predict(r.input, candidateWeights);
    baseline.push({ resolved: true, actual: r.actual, probabilities: mapProbabilities(baseResult.probabilities) });
    candidate.push({ resolved: true, actual: r.actual, probabilities: mapProbabilities(candResult.probabilities) });
  }

  const b = overallMetrics(baseline);
  const c = overallMetrics(candidate);
  return {
    trainingSize: split,
    validationSize: validation.length,
    baselineBrier: b.brier,
    candidateBrier: c.brier,
    baselineLogLoss: b.logLoss,
    candidateLogLoss: c.logLoss,
    candidateImproved: c.brier < b.brier && c.logLoss <= b.logLoss,
  };
}

module.exports = {
  MARKETS,
  MARKET_KEY_MAP,
  mapProbabilities,
  valueForMarket,
  marketMetrics,
  overallMetrics,
  proposeWeights,
  factorPerformance,
  walkForwardValidate,
};