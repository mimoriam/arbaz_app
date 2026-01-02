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

/// Represents a round in the Word Categories game
class WordCategoryRound {
  final String? categoryHint; // Optional hint for lower levels
  final List<String> words;
  final int oddOneIndex;
  final String explanation;

  const WordCategoryRound({
    this.categoryHint,
    required this.words,
    required this.oddOneIndex,
    required this.explanation,
  });
}

/// Metrics for tracking game performance
class WordCategoriesMetrics {
  final int roundsShown;
  final int roundsCorrect;
  final int roundsIncorrect;
  final List<int> responseTimes;
  final int totalTimeMs;

  WordCategoriesMetrics({
    required this.roundsShown,
    required this.roundsCorrect,
    required this.roundsIncorrect,
    required this.responseTimes,
    required this.totalTimeMs,
  });

  double get accuracy =>
      roundsShown > 0 ? (roundsCorrect / roundsShown) * 100 : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;
}

class WordCategoriesScreen extends StatefulWidget {
  const WordCategoriesScreen({super.key});

  @override
  State<WordCategoriesScreen> createState() => _WordCategoriesScreenState();
}

class _WordCategoriesScreenState extends State<WordCategoriesScreen>
    with TickerProviderStateMixin {
  // Round data - Level 1-3 rounds (obvious to moderate difficulty)
  static const List<WordCategoryRound> _allRounds = [
    // Level 1: Very obvious categories (with hints)
    WordCategoryRound(
      categoryHint: 'Think: Food',
      words: ['Apple', 'Bread', 'Milk', 'Chair'],
      oddOneIndex: 3,
      explanation: 'Chair is not a food!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Animals',
      words: ['Dog', 'Cat', 'Bird', 'Blue'],
      oddOneIndex: 3,
      explanation: 'Blue is a color, not an animal!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Body Parts',
      words: ['Hand', 'Foot', 'Head', 'Shirt'],
      oddOneIndex: 3,
      explanation: 'Shirt is clothing, not a body part!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Vehicles',
      words: ['Car', 'Bus', 'Bicycle', 'Table'],
      oddOneIndex: 3,
      explanation: 'Table is furniture, not a vehicle!',
    ),

    // Level 2: Clear categories (hints optional)
    WordCategoryRound(
      categoryHint: 'Think: Fruits',
      words: ['Apple', 'Banana', 'Orange', 'Carrot'],
      oddOneIndex: 3,
      explanation: 'Carrot is a vegetable, not a fruit!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Land Animals',
      words: ['Dog', 'Cat', 'Horse', 'Fish'],
      oddOneIndex: 3,
      explanation: 'Fish lives in water, not on land!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Hot Drinks',
      words: ['Coffee', 'Tea', 'Cocoa', 'Lemonade'],
      oddOneIndex: 3,
      explanation: 'Lemonade is a cold drink!',
    ),
    WordCategoryRound(
      categoryHint: 'Think: Things to Wear',
      words: ['Hat', 'Shoes', 'Jacket', 'Plate'],
      oddOneIndex: 3,
      explanation: 'Plate is kitchenware, not clothing!',
    ),
    WordCategoryRound(
      words: ['Pen', 'Pencil', 'Marker', 'Spoon'],
      oddOneIndex: 3,
      explanation: 'Spoon is for eating, not writing!',
    ),
    WordCategoryRound(
      words: ['Rose', 'Tulip', 'Daisy', 'Oak'],
      oddOneIndex: 3,
      explanation: 'Oak is a tree, not a flower!',
    ),

    // Level 3: Related but different categories (no hints)
    WordCategoryRound(
      words: ['Pot', 'Pan', 'Plate', 'Soap'],
      oddOneIndex: 3,
      explanation: 'Soap is for bathing, not cooking!',
    ),
    WordCategoryRound(
      words: ['Book', 'Magazine', 'Newspaper', 'Radio'],
      oddOneIndex: 3,
      explanation: 'Radio is for listening, not reading!',
    ),
    WordCategoryRound(
      words: ['Car', 'Bicycle', 'Skateboard', 'Ladder'],
      oddOneIndex: 3,
      explanation: 'Ladder has no wheels!',
    ),
    WordCategoryRound(
      words: ['Guitar', 'Piano', 'Violin', 'Microphone'],
      oddOneIndex: 3,
      explanation: 'Microphone is not a musical instrument!',
    ),
    WordCategoryRound(
      words: ['Soccer', 'Basketball', 'Tennis', 'Chess'],
      oddOneIndex: 3,
      explanation: 'Chess is a board game, not a sport with a ball!',
    ),
    WordCategoryRound(
      words: ['Hammer', 'Screwdriver', 'Wrench', 'Scissors'],
      oddOneIndex: 3,
      explanation: 'Scissors are for cutting, not fixing!',
    ),
    WordCategoryRound(
      words: ['Monday', 'Tuesday', 'March', 'Friday'],
      oddOneIndex: 2,
      explanation: 'March is a month, not a day!',
    ),
    WordCategoryRound(
      words: ['Doctor', 'Nurse', 'Teacher', 'Hospital'],
      oddOneIndex: 3,
      explanation: 'Hospital is a place, not a profession!',
    ),
    WordCategoryRound(
      words: ['Happy', 'Sad', 'Angry', 'Hungry'],
      oddOneIndex: 3,
      explanation: 'Hungry is a physical state, not an emotion!',
    ),
    WordCategoryRound(
      words: ['Tree', 'Flower', 'Grass', 'Rock'],
      oddOneIndex: 3,
      explanation: 'Rock is not a plant - it doesn\'t grow!',
    ),
  ];

  // Game state
  List<WordCategoryRound> _sessionRounds = [];
  int _currentRoundIndex = 0;
  bool _showingInstructions = true;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  bool _gameEnded = false;
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;
  int? _selectedIndex;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _roundStartTime;
  bool _resultsSaved = false;

  // Metrics tracking
  int _roundsCorrect = 0;
  int _roundsIncorrect = 0;
  List<int> _responseTimes = [];

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

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

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  void _initializeGame() {
    final random = Random();
    // Shuffle and pick 8 rounds for this session
    final shuffled = List<WordCategoryRound>.from(_allRounds)..shuffle(random);
    _sessionRounds = shuffled.take(8).toList();
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
        _startGame();
      }
    });
  }

  void _startGame() {
    setState(() {
      _showingCountdown = false;
      _roundStartTime = DateTime.now();
    });

    _fadeController.forward();

    // Start game timer
    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedMs += 100;
      });
    });
  }

  void _handleWordTap(int index) {
    if (_showingFeedback || _gameEnded) return;

    final round = _sessionRounds[_currentRoundIndex];
    final responseTime =
        DateTime.now().difference(_roundStartTime!).inMilliseconds;
    _responseTimes.add(responseTime);

    final isCorrect = index == round.oddOneIndex;

    setState(() {
      _selectedIndex = index;
      _showingFeedback = true;
      _lastAnswerCorrect = isCorrect;
      if (isCorrect) {
        _roundsCorrect++;
      } else {
        _roundsIncorrect++;
        _shakeController.forward().then((_) => _shakeController.reset());
      }
    });

    // Move to next round after delay
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        _moveToNextRound();
      }
    });
  }

  void _moveToNextRound() {
    if (_currentRoundIndex < _sessionRounds.length - 1) {
      setState(() {
        _currentRoundIndex++;
        _showingFeedback = false;
        _selectedIndex = null;
        _roundStartTime = DateTime.now();
      });
    } else {
      _endGame();
    }
  }

  Future<void> _endGame() async {
    _gameTimer?.cancel();
    setState(() {
      _gameEnded = true;
    });
    await _saveGameResult();
  }

  Future<void> _saveGameResult() async {
    if (_resultsSaved) return;
    _resultsSaved = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final metrics = _getMetrics();
    final score = GameResult.calculateWordCategoriesScore(
      accuracy: metrics.accuracy,
      averageResponseTimeMs: metrics.averageResponseTime,
    );

    final result = GameResult(
      id: '',
      gameType: 'word_categories',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'roundsShown': metrics.roundsShown,
        'roundsCorrect': metrics.roundsCorrect,
        'roundsIncorrect': metrics.roundsIncorrect,
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
            gameType: 'word_categories',
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

  WordCategoriesMetrics _getMetrics() {
    return WordCategoriesMetrics(
      roundsShown: _currentRoundIndex + 1,
      roundsCorrect: _roundsCorrect,
      roundsIncorrect: _roundsIncorrect,
      responseTimes: _responseTimes,
      totalTimeMs: _elapsedMs,
    );
  }

  void _restartGame() {
    _gameTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _currentRoundIndex = 0;
      _showingInstructions = true;
      _showingCountdown = true;
      _countdownValue = 3;
      _gameEnded = false;
      _showingFeedback = false;
      _lastAnswerCorrect = false;
      _selectedIndex = null;
      _elapsedMs = 0;
      _roundsCorrect = 0;
      _roundsIncorrect = 0;
      _responseTimes = [];
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
    _countdownTimer?.cancel();
    _fadeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  /// Handles exit by saving game results proactively before popping.
  Future<void> _handleExit() async {
    if (!_resultsSaved && !_showingInstructions && !_showingCountdown && !_gameEnded) {
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
                      : _gameEnded
                          ? _buildResultsScreen(isDarkMode)
                          : _buildGameArea(isDarkMode),
            ),
            if (!_showingInstructions) _buildExitButton(isDarkMode),
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
                'WORD CATEGORIES',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF59E0B),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _showingInstructions || _showingCountdown
                    ? 'Get Ready!'
                    : 'Round ${_currentRoundIndex + 1} of ${_sessionRounds.length}',
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
          if (!_showingInstructions && !_showingCountdown && !_gameEnded)
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
                    '$_roundsCorrect',
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
                  '📁',
                  style: TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  'Find the word that doesn\'t belong in the group!',
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
                // Example words
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildExampleWord('Apple', false, isDarkMode),
                    _buildExampleWord('Banana', false, isDarkMode),
                    _buildExampleWord('Chair', true, isDarkMode),
                    _buildExampleWord('Orange', false, isDarkMode),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lightbulb,
                          color: AppColors.successGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Chair is not a fruit!',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successGreen,
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
                backgroundColor: AppColors.successGreen,
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

  Widget _buildExampleWord(String word, bool isOddOne, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isOddOne
            ? AppColors.successGreen.withValues(alpha: 0.1)
            : (isDarkMode
                ? AppColors.surfaceDark.withValues(alpha: 0.5)
                : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOddOne ? AppColors.successGreen : Colors.transparent,
          width: 2,
        ),
      ),
      child: Text(
        word,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDarkMode
              ? AppColors.textPrimaryDark
              : AppColors.textPrimary,
        ),
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
    final round = _sessionRounds[_currentRoundIndex];

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Which word doesn\'t belong?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            if (round.categoryHint != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  round.categoryHint!,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Word buttons
            ...List.generate(round.words.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildWordButton(round, index, isDarkMode),
              );
            }),
            const SizedBox(height: 16),
            // Feedback area
            if (_showingFeedback) _buildFeedback(round, isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildWordButton(WordCategoryRound round, int index, bool isDarkMode) {
    final word = round.words[index];
    final isSelected = _selectedIndex == index;
    final isOddOne = index == round.oddOneIndex;
    final showResult = _showingFeedback;

    Color? borderColor;
    Color? bgColor;

    if (showResult) {
      if (isOddOne) {
        borderColor = AppColors.successGreen;
        bgColor = AppColors.successGreen.withValues(alpha: 0.1);
      } else if (isSelected && !isOddOne) {
        borderColor = AppColors.dangerRed;
        bgColor = AppColors.dangerRed.withValues(alpha: 0.1);
      }
    }

    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: bgColor ?? (isDarkMode ? AppColors.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ??
              (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
          width: borderColor != null ? 3 : 1,
        ),
        boxShadow: isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Text(
        word.toUpperCase(),
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDarkMode
              ? AppColors.textPrimaryDark
              : AppColors.textPrimary,
        ),
      ),
    );

    // Add shake animation for wrong answers
    if (showResult && isSelected && !isOddOne) {
      button = AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeAnimation.value * sin(_shakeAnimation.value * 3), 0),
            child: child,
          );
        },
        child: button,
      );
    }

    return GestureDetector(
      onTap: showResult ? null : () => _handleWordTap(index),
      child: button,
    );
  }

  Widget _buildFeedback(WordCategoryRound round, bool isDarkMode) {
    final oddWord = round.words[round.oddOneIndex];

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
                  ? 'Correct! $oddWord - ${round.explanation}'
                  : 'Not quite. $oddWord was the odd one - ${round.explanation}',
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

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();
    final accuracy = metrics.accuracy;

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (accuracy >= 90) {
      performanceLevel = 'Word Wizard!';
      performanceColor = AppColors.successGreen;
      emoji = '🧙';
    } else if (accuracy >= 70) {
      performanceLevel = 'Great Thinking!';
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
                  '${metrics.roundsCorrect} out of ${metrics.roundsShown}',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'correct',
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
