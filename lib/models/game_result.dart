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
}

/// Aggregated cognitive metrics for display
class CognitiveMetrics {
  final double memoryRecall; // 0.0 - 1.0
  final double reactionSpeed; // 0.0 - 1.0
  final double overallScore; // 0.0 - 1.0
  final String trend; // 'improving', 'stable', 'declining'
  final int gamesPlayed;

  CognitiveMetrics({
    required this.memoryRecall,
    required this.reactionSpeed,
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
        overallScore: 0,
        trend: 'stable',
        gamesPlayed: 0,
      );
    }

    // Separate by game type
    final memoryResults = results.where((r) => r.gameType == 'memory_match').toList();
    final speedResults = results.where((r) => r.gameType == 'speed_tap').toList();

    // Calculate averages
    double memoryRecall = 0;
    if (memoryResults.isNotEmpty) {
      memoryRecall = memoryResults.map((r) => r.score).reduce((a, b) => a + b) / 
          memoryResults.length / 100;
    }

    double reactionSpeed = 0;
    if (speedResults.isNotEmpty) {
      reactionSpeed = speedResults.map((r) => r.score).reduce((a, b) => a + b) / 
          speedResults.length / 100;
    }

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
      overallScore: overallScore.clamp(0, 1),
      trend: trend,
      gamesPlayed: results.length,
    );
  }
}
