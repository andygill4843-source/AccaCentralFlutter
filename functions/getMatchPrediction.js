const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');
const { fetchAndBuild } = require('./predictionDataFetcher');
const { predict, DEFAULT_WEIGHTS } = require('./predictionEngine');
const { mapProbabilities } = require('./learningEngine');

const db = getFirestore();
const CACHE_FRESHNESS_MS = 3 * 60 * 60 * 1000;

async function loadCurrentWeights() {
  const snap = await db.collection('prediction_model_versions').orderBy('createdAt', 'desc').limit(1).get();
  if (snap.empty) return { weights: DEFAULT_WEIGHTS, modelVersion: 'default' };
  const doc = snap.docs[0];
  return { weights: doc.data().weights, modelVersion: doc.id };
}

exports.getMatchPrediction = onCall({ timeoutSeconds: 60, memory: '256MiB' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const { fixtureId, leagueId, season, homeTeamId, homeTeamName, awayTeamId, awayTeamName, isLeagueGame } = request.data || {};
  if (!fixtureId || !leagueId || !season || !homeTeamId || !awayTeamId) {
    throw new HttpsError('invalid-argument', 'Missing required fixture/team fields.');
  }

  const cacheRef = db.collection('matchPredictions').doc(String(fixtureId));
  const cached = await cacheRef.get();
  if (cached.exists) {
    const data = cached.data();
    const age = Date.now() - (data.computedAt?.toMillis?.() ?? 0);
    if (age < CACHE_FRESHNESS_MS) {
      return data.payload;
    }
  }

  const { weights, modelVersion } = await loadCurrentWeights();

  const { input, display } = await fetchAndBuild({
    fixtureId, leagueId, season, homeTeamId, homeTeamName, awayTeamId, awayTeamName, isLeagueGame,
  });
  const result = predict(input, weights);

  const payload = {
    probabilities: result.probabilities,
    expectedGoals: result.expectedGoals,
    home: display.home,
    away: display.away,
    h2h: display.h2h,
  };

  await cacheRef.set({
    fixtureId,
    computedAt: new Date(),
    payload,
  });

  // Learning-engine record — one per fixture (doc id = fixtureId), so a
  // cache-expiry recompute overwrites rather than duplicates. Stores the
  // FULL input so a future candidate-weights rebuild is an exact,
  // deterministic replay rather than a reconstruction from partial data.
  try {
    await db.collection('prediction_records').doc(String(fixtureId)).set({
      fixtureId,
      predictedAt: new Date(),
      leagueId,
      season,
      homeTeam: homeTeamName,
      awayTeam: awayTeamName,
      weights,
      factors: result.factors,
      expectedGoals: result.expectedGoals,
      probabilities: mapProbabilities(result.probabilities),
      modelVersion,
      input,
      resolved: false,
    });
  } catch (e) {
    // Best-effort — a failure here shouldn't block the prediction itself
    // from being returned to the user.
    console.error(`Couldn't save prediction_records for fixture ${fixtureId}:`, e.message);
  }

  return payload;
});