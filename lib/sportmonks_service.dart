import 'package:collection/collection.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SportmonksFixture {
  final int id;
  final String name;
  final DateTime startingAt;
  final String stateShortName; // e.g. "NS", "LIVE", "HT", "FT"
  final List<SportmonksParticipant> participants;
  final List<SportmonksScoreEntry> scores;

  SportmonksFixture({
    required this.id,
    required this.name,
    required this.startingAt,
    required this.stateShortName,
    required this.participants,
    required this.scores,
  });

  factory SportmonksFixture.fromJson(Map<String, dynamic> json) {
    return SportmonksFixture(
      id: json['id'],
      name: json['name'] ?? '',
      startingAt: DateTime.tryParse(json['starting_at'] ?? '') ?? DateTime.now(),
      stateShortName: json['state']?['short_name'] ?? '',
      participants: ((json['participants'] as List?) ?? [])
          .map((p) => SportmonksParticipant.fromJson(p))
          .toList(),
      scores: ((json['scores'] as List?) ?? [])
          .map((s) => SportmonksScoreEntry.fromJson(s))
          .toList(),
    );
  }

  String get homeTeamName =>
      participants.firstWhere((p) => p.location == 'home', orElse: () => SportmonksParticipant(name: 'Home', location: 'home')).name;

  String get awayTeamName =>
      participants.firstWhere((p) => p.location == 'away', orElse: () => SportmonksParticipant(name: 'Away', location: 'away')).name;

  int? get homeGoals => scores
      .where((s) => s.description == 'CURRENT' && s.participant == 'home')
      .map((s) => s.goals)
      .firstOrNull;

  int? get awayGoals => scores
      .where((s) => s.description == 'CURRENT' && s.participant == 'away')
      .map((s) => s.goals)
      .firstOrNull;

  static const _liveStates = ['LIVE', 'INPLAY_1ST', 'INPLAY_2ND', 'HT', 'ET', 'BREAK', 'PEN_LIVE', 'INT', 'SUSP'];
  static const _finishedStates = ['FT', 'AET', 'FT_PEN', 'ABAN', 'CANCL'];

  bool get isLive => _liveStates.contains(stateShortName);
  bool get isFinished => _finishedStates.contains(stateShortName);
}

class SportmonksParticipant {
  final String name;
  final String? location;

  SportmonksParticipant({required this.name, this.location});

  factory SportmonksParticipant.fromJson(Map<String, dynamic> json) {
    return SportmonksParticipant(
      name: json['name'] ?? '',
      location: json['meta']?['location'],
    );
  }
}

class SportmonksScoreEntry {
  final String description;
  final String participant;
  final int goals;

  SportmonksScoreEntry({required this.description, required this.participant, required this.goals});

  factory SportmonksScoreEntry.fromJson(Map<String, dynamic> json) {
    return SportmonksScoreEntry(
      description: json['description'] ?? '',
      participant: json['score']?['participant'] ?? '',
      goals: json['score']?['goals'] ?? 0,
    );
  }
}

class SportmonksService {
  static final SportmonksService instance = SportmonksService._();
  SportmonksService._();

  static const _baseUrl = 'https://api.sportmonks.com/v3/football';
  static const _apiToken = 'hdkhpa8UZkgocItDmHY5rctiXFbqguYweioOEgMHzMTB0iB06V71fAVOE10E'; // load from a secrets file, never hardcode for real

  Future<SportmonksFixture> fetchFixture(int id) async {
    final uri = Uri.parse('$_baseUrl/fixtures/$id').replace(queryParameters: {
      'api_token': _apiToken,
      'include': 'participants;scores;state',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load fixture: ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    return SportmonksFixture.fromJson(json['data']);
  }

  Future<List<SportmonksFixture>> fetchFixturesOnDate(DateTime date) async {
    final dateString = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$_baseUrl/fixtures/date/$dateString').replace(queryParameters: {
      'api_token': _apiToken,
      'include': 'participants;state',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load fixtures: ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    final List<dynamic> data = json['data'];
    return data.map((f) => SportmonksFixture.fromJson(f)).toList();
  }
}