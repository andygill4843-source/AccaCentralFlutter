import 'match_data.dart';
import 'match_prediction_engine.dart';

class BatchPredictionEngine {
  final MatchPredictionEngine engine;

  BatchPredictionEngine({MatchPredictionEngine? engine})
      : engine = engine ?? MatchPredictionEngine();

  List<MatchPredictionResult> predictAll(
    List<MatchPredictionInput> fixtures,
  ) {
    return fixtures.map(engine.predict).toList();
  }
}
