import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/game_result.dart';
import 'package:arbaz_app/models/activity_log.dart';

/// Represents an element in a picture scene
class SceneElement {
  final String emoji;
  final String label;
  final Color? color;

  const SceneElement({
    required this.emoji,
    required this.label,
    this.color,
  });
}

/// Represents a question about the scene
class PictureQuestion {
  final String question;
  final List<String> choices;
  final int correctIndex;

  const PictureQuestion({
    required this.question,
    required this.choices,
    required this.correctIndex,
  });
}

/// Represents a complete picture scene with questions
class PictureScene {
  final String title;
  final List<SceneElement> elements;
  final List<PictureQuestion> questions;
  final Color backgroundColor;
  final int studyTimeSeconds;

  const PictureScene({
    required this.title,
    required this.elements,
    required this.questions,
    this.backgroundColor = const Color(0xFFE8F5E9),
    this.studyTimeSeconds = 10,
  });
}

/// Metrics for tracking game performance
class PictureRecallMetrics {
  final int questionsAsked;
  final int questionsCorrect;
  final int questionsIncorrect;
  final int studyTimeMs;
  final List<int> responseTimes;
  final int totalTimeMs;

  PictureRecallMetrics({
    required this.questionsAsked,
    required this.questionsCorrect,
    required this.questionsIncorrect,
    required this.studyTimeMs,
    required this.responseTimes,
    required this.totalTimeMs,
  });

  double get accuracy =>
      questionsAsked > 0 ? (questionsCorrect / questionsAsked) * 100 : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;
}

class PictureRecallScreen extends StatefulWidget {
  const PictureRecallScreen({super.key});

  @override
  State<PictureRecallScreen> createState() => _PictureRecallScreenState();
}

class _PictureRecallScreenState extends State<PictureRecallScreen>
    with TickerProviderStateMixin {
  // Scene data - Level 1-3 scenes
  static const List<PictureScene> _allScenes = [
    // Level 1: Simple scene (3-4 key elements), 3 questions
    PictureScene(
      title: 'A Day at the Park',
      backgroundColor: Color(0xFFE3F2FD),
      studyTimeSeconds: 12,
      elements: [
        SceneElement(emoji: '👨', label: 'Man', color: Colors.brown),
        SceneElement(emoji: '🔴', label: 'Red hat', color: Colors.red),
        SceneElement(emoji: '🎈', label: 'Blue balloon', color: Colors.blue),
        SceneElement(emoji: '🌳', label: 'Tree', color: Colors.green),
      ],
      questions: [
        PictureQuestion(
          question: 'What color was the hat?',
          choices: ['Red', 'Blue', 'Yellow'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What was the man holding?',
          choices: ['Balloon', 'Umbrella', 'Flower'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What was next to the man?',
          choices: ['Tree', 'Car', 'House'],
          correctIndex: 0,
        ),
      ],
    ),
    // Level 1: Another simple scene
    PictureScene(
      title: 'In the Kitchen',
      backgroundColor: Color(0xFFFFF3E0),
      studyTimeSeconds: 12,
      elements: [
        SceneElement(emoji: '👩', label: 'Woman', color: Colors.brown),
        SceneElement(emoji: '🍎', label: 'Apple', color: Colors.red),
        SceneElement(emoji: '🐱', label: 'Cat', color: Colors.orange),
        SceneElement(emoji: '🕐', label: 'Clock showing 3:00'),
      ],
      questions: [
        PictureQuestion(
          question: 'What animal was in the picture?',
          choices: ['Cat', 'Dog', 'Bird'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What time did the clock show?',
          choices: ['3:00', '6:00', '9:00'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What fruit was on the table?',
          choices: ['Apple', 'Banana', 'Orange'],
          correctIndex: 0,
        ),
      ],
    ),
    // Level 2: Moderate scene (5-6 elements), 3 questions
    PictureScene(
      title: 'Beach Day',
      backgroundColor: Color(0xFFE0F7FA),
      studyTimeSeconds: 12,
      elements: [
        SceneElement(emoji: '☀️', label: 'Sun'),
        SceneElement(emoji: '🏖️', label: 'Beach'),
        SceneElement(emoji: '👦', label: 'Boy'),
        SceneElement(emoji: '🏄', label: 'Surfboard', color: Colors.yellow),
        SceneElement(emoji: '🐚', label: 'Shells'),
        SceneElement(emoji: '🦀', label: 'Crab', color: Colors.red),
      ],
      questions: [
        PictureQuestion(
          question: 'What animal was on the beach?',
          choices: ['Crab', 'Fish', 'Seagull'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What was the weather like?',
          choices: ['Sunny', 'Rainy', 'Cloudy'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What sports equipment was there?',
          choices: ['Surfboard', 'Bicycle', 'Tennis racket'],
          correctIndex: 0,
        ),
      ],
    ),
    // Level 2: Garden scene
    PictureScene(
      title: 'Garden Party',
      backgroundColor: Color(0xFFE8F5E9),
      studyTimeSeconds: 12,
      elements: [
        SceneElement(emoji: '🌻', label: 'Sunflower', color: Colors.yellow),
        SceneElement(emoji: '🦋', label: 'Butterfly', color: Colors.purple),
        SceneElement(emoji: '🐝', label: 'Bee'),
        SceneElement(emoji: '🌹', label: 'Rose', color: Colors.pink),
        SceneElement(emoji: '🐦', label: 'Bird', color: Colors.blue),
      ],
      questions: [
        PictureQuestion(
          question: 'What insect was flying around?',
          choices: ['Butterfly and Bee', 'Dragonfly', 'Ladybug'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What color was the rose?',
          choices: ['Pink', 'Red', 'White'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What type of flower was yellow?',
          choices: ['Sunflower', 'Tulip', 'Daisy'],
          correctIndex: 0,
        ),
      ],
    ),
    // Level 3: Park with more details
    PictureScene(
      title: 'Playground Fun',
      backgroundColor: Color(0xFFF3E5F5),
      studyTimeSeconds: 15,
      elements: [
        SceneElement(emoji: '👧', label: 'Girl'),
        SceneElement(emoji: '👦', label: 'Boy'),
        SceneElement(emoji: '🐕', label: 'Dog running'),
        SceneElement(emoji: '🎢', label: 'Slide', color: Colors.red),
        SceneElement(emoji: '⚽', label: 'Soccer ball'),
        SceneElement(emoji: '🌳', label: 'Trees'),
        SceneElement(emoji: '🦅', label: 'Bird in sky'),
      ],
      questions: [
        PictureQuestion(
          question: 'How many children were in the park?',
          choices: ['2', '3', '4'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What was the dog doing?',
          choices: ['Running', 'Sitting', 'Sleeping'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What color was the slide?',
          choices: ['Red', 'Blue', 'Green'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What was in the sky?',
          choices: ['Bird', 'Airplane', 'Kite'],
          correctIndex: 0,
        ),
      ],
    ),
    // Level 3: Street scene
    PictureScene(
      title: 'Busy Street',
      backgroundColor: Color(0xFFECEFF1),
      studyTimeSeconds: 15,
      elements: [
        SceneElement(emoji: '🚗', label: 'Red car', color: Colors.red),
        SceneElement(emoji: '🚌', label: 'Yellow bus', color: Colors.yellow),
        SceneElement(emoji: '🏪', label: 'Shop'),
        SceneElement(emoji: '👮', label: 'Police officer'),
        SceneElement(emoji: '🚦', label: 'Traffic light'),
        SceneElement(emoji: '🐕', label: 'Dog'),
        SceneElement(emoji: '☁️', label: 'Clouds'),
      ],
      questions: [
        PictureQuestion(
          question: 'What color was the car?',
          choices: ['Red', 'Blue', 'Green'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'Who was directing traffic?',
          choices: ['Police officer', 'Firefighter', 'Teacher'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What public transport was there?',
          choices: ['Bus', 'Train', 'Taxi'],
          correctIndex: 0,
        ),
        PictureQuestion(
          question: 'What animal was on the street?',
          choices: ['Dog', 'Cat', 'Bird'],
          correctIndex: 0,
        ),
      ],
    ),
  ];

  // Game state
  PictureScene? _currentScene;
  int _currentQuestionIndex = 0;
  bool _showingInstructions = true;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  bool _isStudyPhase = false;
  int _studyTimeRemaining = 0;
  bool _isQuestionPhase = false;
  bool _gameEnded = false;
  bool _showingReview = false;
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;
  int? _selectedAnswerIndex;
  Timer? _countdownTimer;
  Timer? _studyTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _questionStartTime;
  bool _resultsSaved = false;

  // Metrics tracking
  int _questionsCorrect = 0;
  int _questionsIncorrect = 0;
  List<int> _responseTimes = [];
  int _studyTimeMs = 0;

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeGame();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
  }

  void _initializeGame() {
    final random = Random();
    // Pick a random scene
    final originalScene = _allScenes[random.nextInt(_allScenes.length)];
    
    // Shuffle question choices at runtime to vary the correct answer position
    final shuffledQuestions = originalScene.questions.map((q) {
      final indices = List<int>.generate(q.choices.length, (i) => i);
      indices.shuffle(random);
      final shuffledChoices = indices.map((i) => q.choices[i]).toList();
      final newCorrectIndex = indices.indexOf(q.correctIndex);
      return PictureQuestion(
        question: q.question,
        choices: shuffledChoices,
        correctIndex: newCorrectIndex,
      );
    }).toList();
    
    _currentScene = PictureScene(
      title: originalScene.title,
      elements: originalScene.elements,
      questions: shuffledQuestions,
      backgroundColor: originalScene.backgroundColor,
      studyTimeSeconds: originalScene.studyTimeSeconds,
    );
  }

  void _startFromInstructions() {
    setState(() {
      _showingInstructions = false;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
      } else {
        timer.cancel();
        _startStudyPhase();
      }
    });
  }

  void _startStudyPhase() {
    setState(() {
      _showingCountdown = false;
      _isStudyPhase = true;
      _studyTimeRemaining = _currentScene!.studyTimeSeconds;
    });

    _fadeController.forward();

    // Start study timer
    _studyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_studyTimeRemaining >= 1) {
        setState(() {
          _studyTimeRemaining--;
          _studyTimeMs += 1000;
        });
        // Transition to question phase after last decrement
        if (_studyTimeRemaining == 0) {
          timer.cancel();
          _startQuestionPhase();
        }
      } else {
        timer.cancel();
        _startQuestionPhase();
      }
    });
  }

  void _startQuestionPhase() {
    setState(() {
      _isStudyPhase = false;
      _isQuestionPhase = true;
      _questionStartTime = DateTime.now();
    });

    // Start game timer for questions
    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedMs += 100;
      });
    });
  }

  void _handleAnswerTap(int index) {
    if (_showingFeedback || _gameEnded) return;

    final question = _currentScene!.questions[_currentQuestionIndex];
    final responseTime =
        DateTime.now().difference(_questionStartTime!).inMilliseconds;
    _responseTimes.add(responseTime);

    final isCorrect = index == question.correctIndex;

    setState(() {
      _selectedAnswerIndex = index;
      _showingFeedback = true;
      _lastAnswerCorrect = isCorrect;
      if (isCorrect) {
        _questionsCorrect++;
      } else {
        _questionsIncorrect++;
      }
    });

    // Move to next question after delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _moveToNextQuestion();
      }
    });
  }

  void _moveToNextQuestion() {
    if (_currentQuestionIndex < _currentScene!.questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _showingFeedback = false;
        _selectedAnswerIndex = null;
        _questionStartTime = DateTime.now();
      });
    } else {
      _showReview();
    }
  }

  void _showReview() {
    _gameTimer?.cancel();
    setState(() {
      _isQuestionPhase = false;
      _showingReview = true;
    });
  }

  void _finishReview() {
    setState(() {
      _showingReview = false;
      _gameEnded = true;
    });
    _saveGameResult();
  }

  Future<void> _saveGameResult() async {
    if (_resultsSaved) return;
    _resultsSaved = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final metrics = _getMetrics();
    final score = GameResult.calculatePictureRecallScore(
      questionsCorrect: metrics.questionsCorrect,
      totalQuestions: metrics.questionsAsked,
      averageResponseTimeMs: metrics.averageResponseTime,
    );

    final result = GameResult(
      id: '',
      gameType: 'picture_recall',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'questionsAsked': metrics.questionsAsked,
        'questionsCorrect': metrics.questionsCorrect,
        'questionsIncorrect': metrics.questionsIncorrect,
        'studyTimeMs': metrics.studyTimeMs,
        'averageResponseTimeMs': metrics.averageResponseTime,
        'totalTimeMs': metrics.totalTimeMs,
        'accuracy': metrics.accuracy,
      },
    );

    try {
      if (mounted) {
        final firestoreService = context.read<FirestoreService>();
        await firestoreService.saveGameResult(user.uid, result);

        try {
          final activityLog = ActivityLog.brainGame(
            seniorId: user.uid,
            timestamp: result.timestamp,
            gameType: 'picture_recall',
            score: score.round(),
          );
          await firestoreService.logActivity(user.uid, activityLog);
        } catch (e) {
          debugPrint('Activity logging failed (non-critical): $e');
        }
      }
    } catch (e) {
      debugPrint('Error saving game result: $e');
    }
  }

  PictureRecallMetrics _getMetrics() {
    return PictureRecallMetrics(
      questionsAsked: _currentScene?.questions.length ?? 0,
      questionsCorrect: _questionsCorrect,
      questionsIncorrect: _questionsIncorrect,
      studyTimeMs: _studyTimeMs,
      responseTimes: _responseTimes,
      totalTimeMs: _elapsedMs,
    );
  }

  void _restartGame() {
    _gameTimer?.cancel();
    _studyTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _currentQuestionIndex = 0;
      _showingInstructions = true;
      _showingCountdown = true;
      _countdownValue = 3;
      _isStudyPhase = false;
      _studyTimeRemaining = 0;
      _isQuestionPhase = false;
      _gameEnded = false;
      _showingReview = false;
      _showingFeedback = false;
      _lastAnswerCorrect = false;
      _selectedAnswerIndex = null;
      _elapsedMs = 0;
      _questionsCorrect = 0;
      _questionsIncorrect = 0;
      _responseTimes = [];
      _studyTimeMs = 0;
      _resultsSaved = false;
    });

    _fadeController.reset();
    _initializeGame();
  }

  @override
  void dispose() {
    // Note: We save proactively via _handleExit() instead of calling async methods here
    // since context and mounted are not valid during dispose.
    _gameTimer?.cancel();
    _studyTimer?.cancel();
    _countdownTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  /// Handles exit by saving game results proactively before popping.
  Future<void> _handleExit() async {
    if (!_resultsSaved && _isQuestionPhase && !_gameEnded) {
      await _saveGameResult();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDarkMode),
            Expanded(
              child: _showingInstructions
                  ? _buildInstructionsScreen(isDarkMode)
                  : _showingCountdown
                      ? _buildCountdown(isDarkMode)
                      : _isStudyPhase
                          ? _buildStudyPhase(isDarkMode)
                          : _isQuestionPhase
                              ? _buildQuestionPhase(isDarkMode)
                              : _showingReview
                                  ? _buildReviewScreen(isDarkMode)
                                  : _gameEnded
                                      ? _buildResultsScreen(isDarkMode)
                                      : const SizedBox(),
            ),
            if (!_showingInstructions) _buildExitButton(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    String subtitle;
    if (_showingInstructions || _showingCountdown) {
      subtitle = 'Get Ready!';
    } else if (_isStudyPhase) {
      subtitle = 'Study the Picture';
    } else if (_isQuestionPhase) {
      subtitle = 'Question ${_currentQuestionIndex + 1} of ${_currentScene?.questions.length ?? 0}';
    } else if (_showingReview) {
      subtitle = 'Review';
    } else {
      subtitle = 'Results';
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PICTURE RECALL',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF22C55E),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (_isStudyPhase)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warningOrange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 18,
                    color: AppColors.warningOrange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_studyTimeRemaining s',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warningOrange,
                    ),
                  ),
                ],
              ),
            ),
          if (_isQuestionPhase && !_showingFeedback)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_questionsCorrect',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionsScreen(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color:
                    isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                const Text(
                  '🖼️',
                  style: TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  'Look at the picture carefully,\nthen answer questions about it!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                // Example
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      Text('👨', style: TextStyle(fontSize: 32)),
                      Text('🔴🎩', style: TextStyle(fontSize: 32)),
                      Text('🌳', style: TextStyle(fontSize: 32)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.help_outline,
                          color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '"What color was the hat?"',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startFromInstructions,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'Start',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown(bool isDarkMode) {
    return Center(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_countdownValue),
        tween: Tween(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$_countdownValue',
                  style: GoogleFonts.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudyPhase(bool isDarkMode) {
    if (_currentScene == null) return const SizedBox();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Remember as many details as you can!',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _currentScene!.backgroundColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _currentScene!.title,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: _currentScene!.elements.map((element) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              element.emoji,
                              style: const TextStyle(fontSize: 48),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              element.label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionPhase(bool isDarkMode) {
    if (_currentScene == null) return const SizedBox();
    final question = _currentScene!.questions[_currentQuestionIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Text(
              question.question,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(question.choices.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildAnswerButton(
                question.choices[index],
                index,
                question.correctIndex,
                isDarkMode,
              ),
            );
          }),
          if (_showingFeedback) ...[
            const SizedBox(height: 16),
            _buildFeedback(question, isDarkMode),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerButton(
    String text,
    int index,
    int correctIndex,
    bool isDarkMode,
  ) {
    final isSelected = _selectedAnswerIndex == index;
    final showResult = _showingFeedback;
    final isCorrect = index == correctIndex;

    Color? bgColor;
    Color? borderColor;

    if (showResult) {
      if (isCorrect) {
        bgColor = AppColors.successGreen.withValues(alpha: 0.1);
        borderColor = AppColors.successGreen;
      } else if (isSelected && !isCorrect) {
        bgColor = AppColors.dangerRed.withValues(alpha: 0.1);
        borderColor = AppColors.dangerRed;
      }
    }

    return GestureDetector(
      onTap: showResult ? null : () => _handleAnswerTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: bgColor ?? (isDarkMode ? AppColors.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor ??
                (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
            width: borderColor != null ? 2 : 1,
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedback(PictureQuestion question, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _lastAnswerCorrect
            ? AppColors.successGreen.withValues(alpha: 0.1)
            : AppColors.dangerRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lastAnswerCorrect
              ? AppColors.successGreen.withValues(alpha: 0.3)
              : AppColors.dangerRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _lastAnswerCorrect ? Icons.check_circle : Icons.cancel,
            color: _lastAnswerCorrect
                ? AppColors.successGreen
                : AppColors.dangerRed,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastAnswerCorrect
                  ? 'Correct! ${question.choices[question.correctIndex]}'
                  : 'The answer was: ${question.choices[question.correctIndex]}',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _lastAnswerCorrect
                    ? AppColors.successGreen
                    : AppColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewScreen(bool isDarkMode) {
    if (_currentScene == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Here\'s what you saw:',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _currentScene!.backgroundColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color:
                      isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentScene!.title,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: _currentScene!.elements.map((element) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            element.emoji,
                            style: const TextStyle(fontSize: 40),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              element.label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.successGreen,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _finishReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'See Results',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();
    final accuracy = metrics.accuracy;

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (accuracy >= 90) {
      performanceLevel = 'Sharp Recall!';
      performanceColor = AppColors.successGreen;
      emoji = '🧠';
    } else if (accuracy >= 70) {
      performanceLevel = 'Great Memory!';
      performanceColor = AppColors.primaryBlue;
      emoji = '⭐';
    } else if (accuracy >= 50) {
      performanceLevel = 'Good Try!';
      performanceColor = AppColors.warningOrange;
      emoji = '👍';
    } else {
      performanceLevel = 'Keep Practicing!';
      performanceColor = AppColors.dangerRed;
      emoji = '💪';
    }

    // Calculate stars
    int stars = accuracy >= 90 ? 3 : (accuracy >= 70 ? 2 : 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Performance header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  performanceColor.withValues(alpha: 0.1),
                  performanceColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: performanceColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  performanceLevel,
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: performanceColor,
                  ),
                ),
                const SizedBox(height: 8),
                // Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    return Icon(
                      index < stars ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Score
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${metrics.questionsCorrect} out of ${metrics.questionsAsked}',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'questions correct',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _restartGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Play Again',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(
                      color: isDarkMode
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        onTap: _handleExit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close,
                size: 18,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'EXIT',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
