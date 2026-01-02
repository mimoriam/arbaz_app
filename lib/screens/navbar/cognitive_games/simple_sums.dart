import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/game_result.dart';
import 'package:arbaz_app/models/activity_log.dart';

/// Model for tracking Simple Sums game metrics
class SimpleSumsMetrics {
  final int problemsShown;
  final int problemsCorrect;
  final int problemsIncorrect;
  final List<int> responseTimes; // Time per problem in milliseconds
  final int additionCount;
  final int subtractionCount;
  final int totalDurationMs;
  final int difficultyLevel;

  SimpleSumsMetrics({
    required this.problemsShown,
    required this.problemsCorrect,
    required this.problemsIncorrect,
    required this.responseTimes,
    required this.additionCount,
    required this.subtractionCount,
    required this.totalDurationMs,
    required this.difficultyLevel,
  });

  double get accuracy => problemsShown > 0
      ? (problemsCorrect / problemsShown * 100)
      : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;
}

/// Represents a math problem
class MathProblem {
  final int operand1;
  final int operand2;
  final bool isAddition;
  final int correctAnswer;
  final List<int> choices;

  MathProblem({
    required this.operand1,
    required this.operand2,
    required this.isAddition,
    required this.correctAnswer,
    required this.choices,
  });

  String get displayText {
    final operator = isAddition ? '+' : '-';
    return '$operand1 $operator $operand2 = ?';
  }
}

/// Difficulty configuration for Simple Sums
class SimpleSumsDifficulty {
  final int minNum;
  final int maxNum;
  final int maxResult;
  final bool allowSubtraction;
  final bool allowDoubleDigits;

  const SimpleSumsDifficulty({
    required this.minNum,
    required this.maxNum,
    required this.maxResult,
    required this.allowSubtraction,
    required this.allowDoubleDigits,
  });

  static const Map<int, SimpleSumsDifficulty> levels = {
    1: SimpleSumsDifficulty(minNum: 1, maxNum: 9, maxResult: 10, allowSubtraction: false, allowDoubleDigits: false),
    2: SimpleSumsDifficulty(minNum: 1, maxNum: 9, maxResult: 15, allowSubtraction: false, allowDoubleDigits: false),
    3: SimpleSumsDifficulty(minNum: 1, maxNum: 9, maxResult: 15, allowSubtraction: true, allowDoubleDigits: false),
    4: SimpleSumsDifficulty(minNum: 1, maxNum: 15, maxResult: 20, allowSubtraction: true, allowDoubleDigits: true),
    5: SimpleSumsDifficulty(minNum: 1, maxNum: 20, maxResult: 30, allowSubtraction: true, allowDoubleDigits: true),
  };
}

class SimpleSumsScreen extends StatefulWidget {
  final int difficultyLevel;
  
  const SimpleSumsScreen({super.key, this.difficultyLevel = 1});

  @override
  State<SimpleSumsScreen> createState() => _SimpleSumsScreenState();
}

class _SimpleSumsScreenState extends State<SimpleSumsScreen>
    with TickerProviderStateMixin {
  // Game configuration
  static const int totalProblems = 10;
  static const int gameDurationSeconds = 45;

  // Game state
  MathProblem? _currentProblem;
  int _currentProblemIndex = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _remainingSeconds = gameDurationSeconds;
  DateTime? _problemStartTime;
  DateTime? _gameStartTime;

  // Feedback state
  int? _selectedAnswer;
  bool? _isCorrect;
  bool _showingFeedback = false;

  // Metrics tracking
  int _problemsCorrect = 0;
  int _problemsIncorrect = 0;
  int _additionCount = 0;
  int _subtractionCount = 0;
  List<int> _responseTimes = [];

  // Difficulty settings
  late SimpleSumsDifficulty _difficulty;
  final Random _random = Random();

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    // Clamp difficulty level to valid range
    final level = widget.difficultyLevel.clamp(1, 5);
    _difficulty = SimpleSumsDifficulty.levels[level]!;
    _initAnimations();
    _startCountdown();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
      } else {
        timer.cancel();
        _startGame();
      }
    });
  }

  void _startGame() {
    if (!mounted) return;
    setState(() {
      _showingCountdown = false;
      _gameStarted = true;
      _gameStartTime = DateTime.now();
    });
    _fadeController.forward();
    _startGameTimer();
    _nextProblem();
  }

  void _startGameTimer() {
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _endGame();
      }
    });
  }

  void _nextProblem() {
    if (!mounted || _gameEnded) return;

    if (_currentProblemIndex >= totalProblems) {
      _endGame();
      return;
    }

    setState(() {
      _currentProblem = _generateProblem();
      _currentProblemIndex++;
      _problemStartTime = DateTime.now();
      _selectedAnswer = null;
      _isCorrect = null;
      _showingFeedback = false;
    });
  }

  MathProblem _generateProblem() {
    final isAddition = !_difficulty.allowSubtraction || _random.nextBool();
    int operand1, operand2, answer;

    if (isAddition) {
      _additionCount++;
      // Generate addition problem
      int attempts = 0;
      do {
        operand1 = _random.nextInt(_difficulty.maxNum - _difficulty.minNum + 1) + _difficulty.minNum;
        operand2 = _random.nextInt(_difficulty.maxNum - _difficulty.minNum + 1) + _difficulty.minNum;
        answer = operand1 + operand2;
        attempts++;
      } while (answer > _difficulty.maxResult && attempts < 100);
      
      // Fallback if loop failed to find valid problem
      if (answer > _difficulty.maxResult) {
        operand1 = _difficulty.minNum;
        operand2 = _difficulty.minNum;
        answer = operand1 + operand2;
      }
    } else {
      _subtractionCount++;
      // Generate subtraction problem (ensure positive result)
      int attempts = 0;
      do {
        operand1 = _random.nextInt(_difficulty.maxNum - _difficulty.minNum + 1) + _difficulty.minNum;
        operand2 = _random.nextInt(operand1) + 1; // Ensure operand2 <= operand1
        answer = operand1 - operand2;
        attempts++;
      } while ((answer < 0 || operand1 > _difficulty.maxResult) && attempts < 100);
      
      // Fallback
      if (answer < 0 || operand1 > _difficulty.maxResult) {
         operand1 = _difficulty.minNum + 1;
         operand2 = _difficulty.minNum;
         answer = operand1 - operand2;
      }
    }

    // Generate answer choices
    final choices = _generateChoices(answer);

    return MathProblem(
      operand1: operand1,
      operand2: operand2,
      isAddition: isAddition,
      correctAnswer: answer,
      choices: choices,
    );
  }

  List<int> _generateChoices(int correctAnswer) {
    final choices = <int>{correctAnswer};
    
    // Generate 2 plausible wrong answers (within ±3 of correct, but must be positive)
    while (choices.length < 3) {
      final offset = _random.nextInt(7) - 3; // -3 to +3
      if (offset != 0) {
        final wrongAnswer = correctAnswer + offset;
        if (wrongAnswer > 0 && wrongAnswer <= _difficulty.maxResult + 5) {
          choices.add(wrongAnswer);
        }
      }
    }

    // Shuffle and return
    final choiceList = choices.toList();
    choiceList.shuffle(_random);
    return choiceList;
  }

  void _handleAnswerTap(int answer) {
    if (_showingFeedback || _gameEnded || _currentProblem == null) return;

    final responseTime = _problemStartTime != null
        ? DateTime.now().difference(_problemStartTime!).inMilliseconds
        : 0;
    
    if (responseTime > 0) {
      _responseTimes.add(responseTime);
    }

    final isCorrect = answer == _currentProblem!.correctAnswer;

    setState(() {
      _selectedAnswer = answer;
      _isCorrect = isCorrect;
      _showingFeedback = true;
      if (isCorrect) {
        _problemsCorrect++;
      } else {
        _problemsIncorrect++;
      }
    });

    HapticFeedback.lightImpact();

    if (!isCorrect) {
      _shakeController.forward().then((_) {
        if (mounted) _shakeController.reset();
      });
    }

    // Show feedback briefly, then next problem
    final feedbackDuration = isCorrect ? 600 : 1500;
    Future.delayed(Duration(milliseconds: feedbackDuration), () {
      if (mounted && !_gameEnded) {
        _nextProblem();
      }
    });
  }

  Future<void> _endGame() async {
    if (_gameEnded) return;
    
    _gameTimer?.cancel();
    setState(() {
      _gameEnded = true;
    });
    await _saveGameResult();
  }

  int _calculateScore() {
    if (_currentProblemIndex == 0) return 0;
    
    final problemsAttempted = _problemsCorrect + _problemsIncorrect;
    if (problemsAttempted == 0) return 0;
    
    // Accuracy 70%, speed 30%
    final accuracy = _problemsCorrect / problemsAttempted * 100;
    final avgTime = _responseTimes.isNotEmpty
        ? _responseTimes.reduce((a, b) => a + b) / _responseTimes.length
        : 5000;
    final speedScore = ((5000 - avgTime) / 50).clamp(0, 100);
    
    return ((accuracy * 0.7) + (speedScore * 0.3)).round().clamp(0, 100);
  }

  Future<void> _saveGameResult() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final metrics = _getMetrics();
    final score = _calculateScore();

    final result = GameResult(
      id: '',
      gameType: 'simple_sums',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'problemsShown': metrics.problemsShown,
        'problemsCorrect': metrics.problemsCorrect,
        'problemsIncorrect': metrics.problemsIncorrect,
        'averageResponseTimeMs': metrics.averageResponseTime,
        'accuracy': metrics.accuracy,
        'additionCount': metrics.additionCount,
        'subtractionCount': metrics.subtractionCount,
        'totalDurationMs': metrics.totalDurationMs,
        'difficultyLevel': metrics.difficultyLevel,
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
            gameType: 'simple_sums', // Standardized: snake_case for all game types
            score: score,
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

  SimpleSumsMetrics _getMetrics() {
    final totalDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inMilliseconds
        : 0;

    return SimpleSumsMetrics(
      problemsShown: _currentProblemIndex,
      problemsCorrect: _problemsCorrect,
      problemsIncorrect: _problemsIncorrect,
      responseTimes: _responseTimes,
      additionCount: _additionCount,
      subtractionCount: _subtractionCount,
      totalDurationMs: totalDuration,
      difficultyLevel: widget.difficultyLevel.clamp(1, 5),
    );
  }

  void _restartGame() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();

    setState(() {
      _currentProblem = null;
      _currentProblemIndex = 0;
      _gameStarted = false;
      _gameEnded = false;
      _showingCountdown = true;
      _countdownValue = 3;
      _remainingSeconds = gameDurationSeconds;
      _selectedAnswer = null;
      _isCorrect = null;
      _showingFeedback = false;
      _problemsCorrect = 0;
      _problemsIncorrect = 0;
      _additionCount = 0;
      _subtractionCount = 0;
      _responseTimes = [];
    });

    _fadeController.reset();
    _shakeController.reset();
    _startCountdown();
  }

  /// Flag to prevent double-saving (once in dispose, once in endGame)
  bool _resultsSaved = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();
    // Save results if game was started but not ended normally (user pressed back)
    if (_gameStarted && !_gameEnded && !_resultsSaved && _currentProblemIndex > 0) {
      _resultsSaved = true;
      _saveGameResult(); // Fire-and-forget - we're disposing anyway
    }
    _fadeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDarkMode),
            Expanded(
              child: _showingCountdown
                  ? _buildCountdown(isDarkMode)
                  : _gameEnded
                  ? _buildResultsScreen(isDarkMode)
                  : _buildGameArea(isDarkMode),
            ),
            _buildExitButton(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PROBLEMS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_currentProblemIndex / $totalProblems',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (_gameStarted && !_gameEnded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _remainingSeconds <= 10
                    ? AppColors.dangerRed
                    : isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _remainingSeconds <= 10
                      ? AppColors.dangerRed
                      : isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: _remainingSeconds <= 10
                        ? Colors.white
                        : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_remainingSeconds}s',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _remainingSeconds <= 10
                          ? Colors.white
                          : (isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary),
                    ),
                  ),
                ],
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

  Widget _buildGameArea(bool isDarkMode) {
    if (_currentProblem == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final shakeOffset = sin(_shakeController.value * pi * 4) * 10;
          return Transform.translate(
            offset: Offset(shakeOffset, 0),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Problem display
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
                decoration: BoxDecoration(
                  color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _showingFeedback
                        ? (_isCorrect! ? AppColors.successGreen : AppColors.dangerRed)
                        : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
                    width: _showingFeedback ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _currentProblem!.displayText,
                      style: GoogleFonts.inter(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (_showingFeedback && !_isCorrect!) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Almost! The answer is ${_currentProblem!.correctAnswer}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dangerRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Answer choices
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _currentProblem!.choices.map((answer) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _buildAnswerButton(answer, isDarkMode),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerButton(int answer, bool isDarkMode) {
    final isSelected = _selectedAnswer == answer;
    final isCorrectAnswer = _currentProblem?.correctAnswer == answer;
    
    Color backgroundColor;
    Color textColor;
    Color borderColor;

    if (_showingFeedback) {
      if (isCorrectAnswer) {
        backgroundColor = AppColors.successGreen;
        textColor = Colors.white;
        borderColor = AppColors.successGreen;
      } else if (isSelected) {
        backgroundColor = AppColors.dangerRed;
        textColor = Colors.white;
        borderColor = AppColors.dangerRed;
      } else {
        backgroundColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
        textColor = isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary;
        borderColor = isDarkMode ? AppColors.borderDark : AppColors.borderLight;
      }
    } else {
      backgroundColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
      textColor = isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary;
      borderColor = isDarkMode ? AppColors.borderDark : AppColors.borderLight;
    }

    return GestureDetector(
      onTap: () => _handleAnswerTap(answer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: isSelected && _showingFeedback
                  ? (isCorrectAnswer
                      ? AppColors.successGreen.withValues(alpha: 0.3)
                      : AppColors.dangerRed.withValues(alpha: 0.3))
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '$answer',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (metrics.accuracy >= 90) {
      performanceLevel = 'Math Whiz!';
      performanceColor = AppColors.successGreen;
      emoji = '🧮';
    } else if (metrics.accuracy >= 70) {
      performanceLevel = 'Great Counting!';
      performanceColor = AppColors.primaryBlue;
      emoji = '⭐';
    } else if (metrics.accuracy >= 50) {
      performanceLevel = 'Well Done!';
      performanceColor = AppColors.warningOrange;
      emoji = '👍';
    } else {
      performanceLevel = 'Keep Practicing!';
      performanceColor = AppColors.dangerRed;
      emoji = '💪';
    }

    // Calculate stars
    final stars = metrics.accuracy >= 90 ? 3 : (metrics.accuracy >= 60 ? 2 : 1);

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
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      i < stars ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                  )),
                ),
                const SizedBox(height: 8),
                Text(
                  '${metrics.problemsCorrect} out of ${metrics.problemsShown} correct',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Accuracy',
                  '${metrics.accuracy.toStringAsFixed(0)}%',
                  Icons.check_circle,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Time',
                  metrics.averageResponseTime > 0
                      ? '${(metrics.averageResponseTime / 1000).toStringAsFixed(1)}s'
                      : '-',
                  Icons.timer,
                  AppColors.primaryBlue,
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Correct',
                  '${metrics.problemsCorrect}',
                  Icons.thumb_up,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Incorrect',
                  '${metrics.problemsIncorrect}',
                  Icons.close,
                  AppColors.dangerRed,
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
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
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDarkMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Exit Game',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
