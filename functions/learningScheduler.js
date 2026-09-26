/**
 * learningScheduler.js — Firebase Cloud Function (v2, scheduled)
 *
 * Runs daily. Checks how many prediction_records are RESOLVED (scouted
 * by at least one user AND the fixture has since finished). First
 * reassessment triggers at 100 resolved records; every subsequent
 * reassessment triggers after 30 MORE resolved records beyond the last
 * one attempted — regardless of whether that attempt actually changed
 * the weights.
 *
 * Uses the FULL resolved dataset each run (not a rolling window), per
 * explicit instruction — this deliberately overrides the Dart
 * package's default rollingWindow behaviour.
 *
 * Publishes a new model version ONLY if walk-forward validation
 * confirms the candidate weights genuinely outperform the current
 * ones (lower Brier score, and log-loss no worse) — otherwise current
 * weights stay published and only the checkpoint advances.
 *
 * Add to functions/index.js:
 *   exports.runLearningCycle = require('./learningScheduler').runLearningCycle;
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');
const { DEFAULT_WEIGHTS } = require('./predictionEngine');
const { proposeWeights, factorPerformance, walkForwardValidate } = require('./learningEngine');

const db = getFirestore();

const CONFIG = {
  minimumWeightSamples: 50,   // reduced from the package's default 500, per explicit request
  reassessmentInterval: 30,    // every N more resolved records after the first threshold
  minimumValidationSamples: 20, // reduced from 200 to stay consistent with the lower threshold above — see caveat below
  learningRate: 0.10,
  maxWeightChangePerRun: 0.02,
};

exports.runLearningCycle = onSchedule(
  { schedule: 'every 24 hours', timeoutSeconds: 300, memory: '512MiB' },
  async () => {
    const stateRef = db.collection('learningState').doc('singleton');
    const stateSnap = await stateRef.get();
    const lastAssessedCount = stateSnap.exists ? (stateSnap.data().lastAssessedResolvedCount ?? 0) : 0;

    const countSnap = await db.collection('prediction_records').where('resolved', '==', true).count().get();
    const resolvedCount = countSnap.data().count;

    const dueForReassessment = lastAssessedCount === 0
      ? resolvedCount >= CONFIG.minimumWeightSamples
      : resolvedCount - lastAssessedCount >= CONFIG.reassessmentInterval;

    if (!dueForReassessment) {
      console.log(`Learning cycle: ${resolvedCount} resolved records, not yet due (last assessed at ${lastAssessedCount}).`);
      return;
    }

    console.log(`Learning cycle: reassessing at ${resolvedCount} resolved records (last assessed at ${lastAssessedCount}).`);

    // Full dataset — no rolling-window slicing, per explicit instruction.
    const recordsSnap = await db.collection('prediction_records').where('resolved', '==', true).get();
    const records = recordsSnap.docs.map((d) => {
      const data = d.data();
      return {
        ...data,
        predictedAt: data.predictedAt.toMillis(),
        resolvedAt: data.resolvedAt?.toMillis?.() ?? null,
      };
    });

    const weightsSnap = await db.collection('prediction_model_versions').orderBy('createdAt', 'desc').limit(1).get();
    const currentWeights = weightsSnap.empty ? DEFAULT_WEIGHTS : weightsSnap.docs[0].data().weights;

    let result;
    try {
      const perf = factorPerformance(records);
      const candidateWeights = proposeWeights(currentWeights, perf, CONFIG);
      const validation = walkForwardValidate(records, currentWeights, candidateWeights, CONFIG.minimumValidationSamples);

      if (validation.candidateImproved) {
        const version = `v${resolvedCount}`;
        await db.collection('prediction_model_versions').doc(version).set({
          version,
          createdAt: new Date(),
          weights: candidateWeights,
          trainingSampleSize: validation.trainingSize,
          validationBrier: validation.candidateBrier,
          validationLogLoss: validation.candidateLogLoss,
          reason: 'Candidate passed walk-forward validation.',
        });
        console.log(`Learning cycle: published new weights as ${version}.`, candidateWeights);
        result = { updated: true, version };
      } else {
        console.log('Learning cycle: candidate did not improve on current weights — no change published.', validation);
        result = { updated: false };
      }
    } catch (e) {
      console.error('Learning cycle failed:', e.message);
      result = { updated: false, error: e.message };
    }

    // Checkpoint advances regardless of outcome, so the next
    // reassessment is exactly 30 games later, not a retry loop.
    await stateRef.set({
      lastAssessedResolvedCount: resolvedCount,
      lastRunAt: new Date(),
      lastResult: result,
    });
  }
);