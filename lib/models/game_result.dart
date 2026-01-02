import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for storing cognitive game results
/// Stored in users/{uid}/gameResults/{docId}
class GameResult {
  final String id;
  final String gameType; // 'memory_match' or 'speed_tap'
  final DateTime timestamp;
  final int score; // Normalized 0-100 score
  final Map<String, dynamic> metrics; // Raw game metrics

  GameResult({
    required this.id,
    required this.gameType,
    required this.timestamp,
    required this.score,
    required this.metrics,
  });

  factory GameResult.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GameResult(
      id: doc.id,
      gameType: data['gameType'] as String? ?? '',
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      score: (data['score'] as num?)?.toInt() ?? 0,
      metrics: data['metrics'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'gameType': gameType,
      'timestamp': Timestamp.fromDate(timestamp),
      'score': score,
      'metrics': metrics,
    };
  }

  /// Calculate normalized score (0-100) from MemoryMatch metrics
  static int calculateMemoryMatchScore({
    required double efficiency,
    required int averageMatchTimeMs,
    required int totalTimeMs,
  }) {
    // Efficiency: 100% is perfect (min moves), weight 50%
    // Time: faster is better, cap at 60 seconds, weight 50%
    final efficiencyScore = efficiency.clamp(0, 100);
    
    // Time score: 0-30s = 100, 30-60s = 50-100, >60s = 0-50
    final timeScore = ((60000 - totalTimeMs) / 600).clamp(0, 100).toDouble();
    
    return ((efficiencyScore * 0.5) + (timeScore * 0.5)).round();
  }

  /// Calculate normalized score (0-100) from SpeedTap metrics
  static int calculateSpeedTapScore({
    required double accuracy,
    required int averageResponseTimeMs,
  }) {
    // Accuracy: weight 60%
    final accuracyScore = accuracy.clamp(0, 100);
    
    // Response time: faster is better, <500ms = 100, >2000ms = 0
    final responseScore = ((2000 - averageResponseTimeMs) / 15).clamp(0, 100).toDouble();
    
    return ((accuracyScore * 0.6) + (responseScore * 0.4)).round();
  }

  /// Calculate normalized score (0-100) from SequenceFollow metrics
  static int calculateSequenceFollowScore({
    required int maxSequenceLength,
    required int roundsCompleted,
    required int sequenceErrors,
    required int difficultyLevel,
  }) {
    // Max sequence weighted 60%, rounds 30%, errors -10% each
    // Adjust max length expectation based on difficulty
    final expectedMaxLength = difficultyLevel + 3; // e.g., Level 1 -> 4, Level 5 -> 8
    
    final sequenceScore = (maxSequenceLength / expectedMaxLength * 100).clamp(0.0, 100.0);
    final roundScore = (roundsCompleted / 5 * 100).clamp(0.0, 100.0);
    final errorPenalty = (sequenceErrors * 10).clamp(0, 50);
    
    return ((sequenceScore * 0.6) + (roundScore * 0.3) - errorPenalty).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from SimpleSums metrics
  static int calculateSimpleSumsScore({
    required double accuracy,
    required int averageResponseTimeMs,
  }) {
    // Accuracy 70%, speed 30%
    // Speed expectation: 5000ms is slow (0 pts), 1000ms is fast (100 pts)
    final speedScore = ((5000 - averageResponseTimeMs) / 40).clamp(0, 100).toDouble();
    
    return ((accuracy * 0.7) + (speedScore * 0.3)).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from WordJumble metrics
  static int calculateWordJumbleScore({
    required double successRate,
    required int averageSolveTimeMs,
    required int hintsUsed,
  }) {
    // Solved % 60%, speed 25%, hint penalty 15%
    // Speed expectation: 30s is slow (0 pts), 5s is fast (100 pts)
    final speedScore = ((30000 - averageSolveTimeMs) / 250).clamp(0, 100).toDouble();
    final hintPenalty = (hintsUsed * 10).clamp(0, 30);
    
    return ((successRate * 0.6) + (speedScore * 0.25) - hintPenalty).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from OddOneOut metrics
  static int calculateOddOneOutScore({
    required double accuracy,
    required int averageResponseTimeMs,
  }) {
    // Accuracy 70%, Speed 30%
    // Speed expectation: 5000ms is slow (0 pts), 1000ms is fast (100 pts)
    final speedScore = ((5000 - averageResponseTimeMs) / 40).clamp(0, 100).toDouble();
    
    return ((accuracy * 0.7) + (speedScore * 0.3)).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from PatternComplete metrics
  static int calculatePatternCompleteScore({
    required double accuracy,
    required int averageResponseTimeMs,
  }) {
    // Accuracy 70%, Speed 30%
    // Speed expectation: 8000ms is slow (0 pts), 2000ms is fast (100 pts)
    final speedScore = ((8000 - averageResponseTimeMs) / 60).clamp(0, 100).toDouble();
    
    return ((accuracy * 0.7) + (speedScore * 0.3)).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from SpotTheDifference metrics
  static int calculateSpotTheDifferenceScore({
    required int foundedDifferences,
    required int totalDifferences,
    required int hintsUsed,
    required int incorrectTaps,
  }) {
    // Early validation to prevent division by zero
    if (totalDifferences <= 0) {
      return 0;
    }
    
    // Clamp inputs to valid ranges
    final clampedFound = foundedDifferences.clamp(0, totalDifferences);
    final clampedHints = hintsUsed < 0 ? 0 : hintsUsed;
    final clampedTaps = incorrectTaps < 0 ? 0 : incorrectTaps;
    
    // Base score on percentage found
    double score = (clampedFound / totalDifferences) * 100;
    
    // Penalties
    final hintPenalty = clampedHints * 5;
    final tapPenalty = clampedTaps * 2;
    
    score = score - hintPenalty - tapPenalty;
    return score.round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from PictureRecall metrics
  static int calculatePictureRecallScore({
    required int questionsCorrect,
    required int totalQuestions,
    required int averageResponseTimeMs,
  }) {
    // Early validation to prevent division by zero
    if (totalQuestions <= 0) {
      return 0;
    }
    
    // Accuracy 80%, Speed 20%
    final accuracy = (questionsCorrect / totalQuestions) * 100;
    final speedScore = ((8000 - averageResponseTimeMs) / 80).clamp(0, 100).toDouble();
    return ((accuracy * 0.8) + (speedScore * 0.2)).round().clamp(0, 100);
  }

  /// Calculate normalized score (0-100) from WordCategories metrics
  static int calculateWordCategoriesScore({
    required double accuracy,
    required int averageResponseTimeMs,
  }) {
    // Accuracy 70%, Speed 30%
    final speedScore = ((5000 - averageResponseTimeMs) / 50).clamp(0, 100).toDouble();
    return ((accuracy * 0.7) + (speedScore * 0.3)).round().clamp(0, 100);
  }

  /// Creates a copy with updated values
  GameResult copyWith({
    String? id,
    String? gameType,
    DateTime? timestamp,
    int? score,
    Map<String, dynamic>? metrics,
  }) {
    return GameResult(
      id: id ?? this.id,
      gameType: gameType ?? this.gameType,
      timestamp: timestamp ?? this.timestamp,
      score: score ?? this.score,
      metrics: metrics ?? this.metrics,
    );
  }
}

/// Aggregated cognitive metrics for display
class CognitiveMetrics {
  final double memoryRecall; // 0.0 - 1.0
  final double reactionSpeed; // 0.0 - 1.0
  final double problemSolving; // 0.0 - 1.0
  final double verbalSkills; // 0.0 - 1.0
  final double overallScore; // 0.0 - 1.0
  final String trend; // 'improving', 'stable', 'declining'
  final int gamesPlayed;

  CognitiveMetrics({
    required this.memoryRecall,
    required this.reactionSpeed,
    required this.problemSolving,
    required this.verbalSkills,
    required this.overallScore,
    required this.trend,
    required this.gamesPlayed,
  });

  /// Calculate aggregated metrics from a list of game results
  factory CognitiveMetrics.fromResults(List<GameResult> results) {
    if (results.isEmpty) {
      return CognitiveMetrics(
        memoryRecall: 0,
        reactionSpeed: 0,
        problemSolving: 0,
        verbalSkills: 0,
        overallScore: 0,
        trend: 'stable',
        gamesPlayed: 0,
      );
    }

    // Separate by game type
    final memoryResults = results.where((r) => r.gameType == 'memory_match' || r.gameType == 'sequence_follow' || r.gameType == 'picture_recall').toList();
    final speedResults = results.where((r) => r.gameType == 'speed_tap' || r.gameType == 'spot_the_difference').toList();
    final problemSolvingResults = results.where((r) => r.gameType == 'simple_sums' || r.gameType == 'pattern_complete' || r.gameType == 'odd_one_out' || r.gameType == 'word_categories').toList();
    final verbalResults = results.where((r) => r.gameType == 'word_jumble').toList();

    // Calculate averages
    double calculateAvg(List<GameResult> list) {
      if (list.isEmpty) return 0;
      return list.map((r) => r.score).reduce((a, b) => a + b) / list.length / 100;
    }

    final memoryRecall = calculateAvg(memoryResults);
    final reactionSpeed = calculateAvg(speedResults);
    final problemSolving = calculateAvg(problemSolvingResults);
    final verbalSkills = calculateAvg(verbalResults);

    // Overall score
    final allScores = results.map((r) => r.score).toList();
    final overallScore = allScores.reduce((a, b) => a + b) / allScores.length / 100;

    // Calculate trend from recent vs older results
    String trend = 'stable';
    if (results.length >= 4) {
      final sorted = List<GameResult>.from(results)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final recentAvg = sorted.take(2).map((r) => r.score).reduce((a, b) => a + b) / 2;
      final olderAvg = sorted.skip(2).take(2).map((r) => r.score).reduce((a, b) => a + b) / 2;
      
      if (recentAvg > olderAvg + 5) {
        trend = 'improving';
      } else if (recentAvg < olderAvg - 5) {
        trend = 'declining';
      }
    }

    return CognitiveMetrics(
      memoryRecall: memoryRecall.clamp(0, 1),
      reactionSpeed: reactionSpeed.clamp(0, 1),
      problemSolving: problemSolving.clamp(0, 1),
      verbalSkills: verbalSkills.clamp(0, 1),
      overallScore: overallScore.clamp(0, 1),
      trend: trend,
      gamesPlayed: results.length,
    );
  }
}
