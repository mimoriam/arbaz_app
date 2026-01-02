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

/// Represents an item in an Odd One Out puzzle
class OddOneOutItem {
  final String emoji;
  final String label;

  const OddOneOutItem({required this.emoji, required this.label});
}

/// Represents a complete Odd One Out puzzle
class OddOneOutPuzzle {
  final String categoryName;
  final List<OddOneOutItem> items;
  final int oddOneIndex;
  final String explanation;

  const OddOneOutPuzzle({
    required this.categoryName,
    required this.items,
    required this.oddOneIndex,
    required this.explanation,
  });
}

/// Metrics for tracking game performance
class OddOneOutMetrics {
  final int puzzlesShown;
  final int puzzlesCorrect;
  final int puzzlesIncorrect;
  final List<int> responseTimes;
  final int totalTimeMs;

  OddOneOutMetrics({
    required this.puzzlesShown,
    required this.puzzlesCorrect,
    required this.puzzlesIncorrect,
    required this.responseTimes,
    required this.totalTimeMs,
  });

  double get accuracy =>
      puzzlesShown > 0 ? (puzzlesCorrect / puzzlesShown) * 100 : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;
}

class OddOneOutScreen extends StatefulWidget {
  const OddOneOutScreen({super.key});

  @override
  State<OddOneOutScreen> createState() => _OddOneOutScreenState();
}

class _OddOneOutScreenState extends State<OddOneOutScreen>
    with TickerProviderStateMixin {
  // Puzzle data - Level 1 puzzles (obvious differences)
  static const List<OddOneOutPuzzle> _allPuzzles = [
    // Fruits vs Furniture
    OddOneOutPuzzle(
      categoryName: 'Fruits vs Furniture',
      items: [
        OddOneOutItem(emoji: '🍎', label: 'Apple'),
        OddOneOutItem(emoji: '🍌', label: 'Banana'),
        OddOneOutItem(emoji: '🍊', label: 'Orange'),
        OddOneOutItem(emoji: '🪑', label: 'Chair'),
      ],
      oddOneIndex: 3,
      explanation: "Chair is not a fruit!",
    ),
    // Animals vs Food
    OddOneOutPuzzle(
      categoryName: 'Animals vs Food',
      items: [
        OddOneOutItem(emoji: '🐶', label: 'Dog'),
        OddOneOutItem(emoji: '🐱', label: 'Cat'),
        OddOneOutItem(emoji: '🐦', label: 'Bird'),
        OddOneOutItem(emoji: '🍕', label: 'Pizza'),
      ],
      oddOneIndex: 3,
      explanation: "Pizza is not an animal!",
    ),
    // Vehicles vs Clothing
    OddOneOutPuzzle(
      categoryName: 'Vehicles vs Clothing',
      items: [
        OddOneOutItem(emoji: '🚗', label: 'Car'),
        OddOneOutItem(emoji: '🚌', label: 'Bus'),
        OddOneOutItem(emoji: '🚂', label: 'Train'),
        OddOneOutItem(emoji: '🎩', label: 'Hat'),
      ],
      oddOneIndex: 3,
      explanation: "Hat is not a vehicle!",
    ),
    // Flying vs Non-flying
    OddOneOutPuzzle(
      categoryName: 'Things that Fly',
      items: [
        OddOneOutItem(emoji: '🐦', label: 'Bird'),
        OddOneOutItem(emoji: '🦋', label: 'Butterfly'),
        OddOneOutItem(emoji: '✈️', label: 'Airplane'),
        OddOneOutItem(emoji: '🐕', label: 'Dog'),
      ],
      oddOneIndex: 3,
      explanation: "Dog cannot fly!",
    ),
    // Round vs Not round
    OddOneOutPuzzle(
      categoryName: 'Round Things',
      items: [
        OddOneOutItem(emoji: '⚽', label: 'Ball'),
        OddOneOutItem(emoji: '🍊', label: 'Orange'),
        OddOneOutItem(emoji: '🕐', label: 'Clock'),
        OddOneOutItem(emoji: '📖', label: 'Book'),
      ],
      oddOneIndex: 3,
      explanation: "Book is not round!",
    ),
    // Alive vs Not alive
    OddOneOutPuzzle(
      categoryName: 'Living Things',
      items: [
        OddOneOutItem(emoji: '🌳', label: 'Tree'),
        OddOneOutItem(emoji: '🌸', label: 'Flower'),
        OddOneOutItem(emoji: '🐶', label: 'Dog'),
        OddOneOutItem(emoji: '🪨', label: 'Rock'),
      ],
      oddOneIndex: 3,
      explanation: "Rock is not alive!",
    ),
    // Fruits vs Vegetables
    OddOneOutPuzzle(
      categoryName: 'Fruits',
      items: [
        OddOneOutItem(emoji: '🍎', label: 'Apple'),
        OddOneOutItem(emoji: '🍌', label: 'Banana'),
        OddOneOutItem(emoji: '🍇', label: 'Grapes'),
        OddOneOutItem(emoji: '🥕', label: 'Carrot'),
      ],
      oddOneIndex: 3,
      explanation: "Carrot is a vegetable, not a fruit!",
    ),
    // Musical vs Not
    OddOneOutPuzzle(
      categoryName: 'Musical Instruments',
      items: [
        OddOneOutItem(emoji: '🎸', label: 'Guitar'),
        OddOneOutItem(emoji: '🎹', label: 'Piano'),
        OddOneOutItem(emoji: '🥁', label: 'Drum'),
        OddOneOutItem(emoji: '🎤', label: 'Microphone'),
      ],
      oddOneIndex: 3,
      explanation: "Microphone is not a musical instrument!",
    ),
    // Water animals vs Land
    OddOneOutPuzzle(
      categoryName: 'Water Animals',
      items: [
        OddOneOutItem(emoji: '🐟', label: 'Fish'),
        OddOneOutItem(emoji: '🐙', label: 'Octopus'),
        OddOneOutItem(emoji: '🐋', label: 'Whale'),
        OddOneOutItem(emoji: '🐘', label: 'Elephant'),
      ],
      oddOneIndex: 3,
      explanation: "Elephant lives on land, not in water!",
    ),
    // Desserts vs Main course
    OddOneOutPuzzle(
      categoryName: 'Desserts',
      items: [
        OddOneOutItem(emoji: '🍰', label: 'Cake'),
        OddOneOutItem(emoji: '🍦', label: 'Ice Cream'),
        OddOneOutItem(emoji: '🍩', label: 'Donut'),
        OddOneOutItem(emoji: '🍔', label: 'Burger'),
      ],
      oddOneIndex: 3,
      explanation: "Burger is not a dessert!",
    ),
    // Sports equipment vs Kitchen
    OddOneOutPuzzle(
      categoryName: 'Sports Equipment',
      items: [
        OddOneOutItem(emoji: '⚽', label: 'Soccer Ball'),
        OddOneOutItem(emoji: '🏀', label: 'Basketball'),
        OddOneOutItem(emoji: '🎾', label: 'Tennis Ball'),
        OddOneOutItem(emoji: '🍳', label: 'Frying Pan'),
      ],
      oddOneIndex: 3,
      explanation: "Frying pan is a kitchen item, not sports equipment!",
    ),
    // Weather vs Objects
    OddOneOutPuzzle(
      categoryName: 'Weather',
      items: [
        OddOneOutItem(emoji: '☀️', label: 'Sun'),
        OddOneOutItem(emoji: '🌧️', label: 'Rain'),
        OddOneOutItem(emoji: '⛈️', label: 'Storm'),
        OddOneOutItem(emoji: '📺', label: 'TV'),
      ],
      oddOneIndex: 3,
      explanation: "TV is not a type of weather!",
    ),
  ];

  // Game state
  List<OddOneOutPuzzle> _sessionPuzzles = [];
  int _currentPuzzleIndex = 0;
  bool _showingCountdown = true;
  bool _showingInstructions = true;
  int _countdownValue = 3;
  bool _gameEnded = false;
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;
  int? _selectedIndex;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _puzzleStartTime;
  bool _resultsSaved = false;

  // Metrics tracking
  int _puzzlesCorrect = 0;
  int _puzzlesIncorrect = 0;
  List<int> _responseTimes = [];

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
    // Shuffle and pick 8 puzzles for this session
    final shuffled = List<OddOneOutPuzzle>.from(_allPuzzles)..shuffle(random);
    // Shuffle items within each puzzle to randomize the odd item position
    _sessionPuzzles = shuffled.take(8).map((puzzle) => _shufflePuzzle(puzzle, random)).toList();
  }

  /// Shuffles the items in a puzzle and returns a new puzzle with updated oddOneIndex.
  /// This ensures the odd item isn't always in the same position.
  OddOneOutPuzzle _shufflePuzzle(OddOneOutPuzzle puzzle, Random random) {
    // Create a list of indices to track original positions
    final indices = List<int>.generate(puzzle.items.length, (i) => i);
    indices.shuffle(random);
    
    // Create shuffled items list
    final shuffledItems = indices.map((i) => puzzle.items[i]).toList();
    
    // Find the new index of the odd item
    final newOddIndex = indices.indexOf(puzzle.oddOneIndex);
    
    return OddOneOutPuzzle(
      categoryName: puzzle.categoryName,
      items: shuffledItems,
      oddOneIndex: newOddIndex,
      explanation: puzzle.explanation,
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
        _startGame();
      }
    });
  }

  void _startGame() {
    setState(() {
      _showingCountdown = false;
      _puzzleStartTime = DateTime.now();
    });

    _fadeController.forward();

    // Start game timer
    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedMs += 100;
      });
    });
  }

  void _handleItemTap(int index) {
    if (_showingFeedback || _gameEnded) return;

    final puzzle = _sessionPuzzles[_currentPuzzleIndex];
    final responseTime =
        DateTime.now().difference(_puzzleStartTime!).inMilliseconds;
    _responseTimes.add(responseTime);

    final isCorrect = index == puzzle.oddOneIndex;

    setState(() {
      _selectedIndex = index;
      _showingFeedback = true;
      _lastAnswerCorrect = isCorrect;
      if (isCorrect) {
        _puzzlesCorrect++;
      } else {
        _puzzlesIncorrect++;
      }
    });

    // Move to next puzzle after delay
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        _moveToNextPuzzle();
      }
    });
  }

  void _moveToNextPuzzle() {
    if (_currentPuzzleIndex < _sessionPuzzles.length - 1) {
      setState(() {
        _currentPuzzleIndex++;
        _showingFeedback = false;
        _selectedIndex = null;
        _puzzleStartTime = DateTime.now();
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
    final score = GameResult.calculateOddOneOutScore(
      accuracy: metrics.accuracy,
      averageResponseTimeMs: metrics.averageResponseTime,
    );

    final result = GameResult(
      id: '',
      gameType: 'odd_one_out',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'puzzlesShown': metrics.puzzlesShown,
        'puzzlesCorrect': metrics.puzzlesCorrect,
        'puzzlesIncorrect': metrics.puzzlesIncorrect,
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
            gameType: 'odd_one_out',
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

  OddOneOutMetrics _getMetrics() {
    return OddOneOutMetrics(
      puzzlesShown: _currentPuzzleIndex + 1,
      puzzlesCorrect: _puzzlesCorrect,
      puzzlesIncorrect: _puzzlesIncorrect,
      responseTimes: _responseTimes,
      totalTimeMs: _elapsedMs,
    );
  }

  void _restartGame() {
    _gameTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _currentPuzzleIndex = 0;
      _showingCountdown = true;
      _showingInstructions = true;
      _countdownValue = 3;
      _gameEnded = false;
      _showingFeedback = false;
      _lastAnswerCorrect = false;
      _selectedIndex = null;
      _elapsedMs = 0;
      _puzzlesCorrect = 0;
      _puzzlesIncorrect = 0;
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
                'ODD ONE OUT',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _showingInstructions || _showingCountdown
                    ? 'Get Ready!'
                    : 'Round ${_currentPuzzleIndex + 1} of ${_sessionPuzzles.length}',
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
                    '$_puzzlesCorrect',
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
                Text(
                  '🔍',
                  style: const TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap the one that doesn\'t belong!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                // Example grid
                _buildExampleGrid(isDarkMode),
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

  Widget _buildExampleGrid(bool isDarkMode) {
    final exampleItems = [
      const OddOneOutItem(emoji: '🍎', label: 'Apple'),
      const OddOneOutItem(emoji: '🍌', label: 'Banana'),
      const OddOneOutItem(emoji: '🍊', label: 'Orange'),
      const OddOneOutItem(emoji: '🪑', label: 'Chair'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final item = exampleItems[index];
        final isOddOne = index == 3;

        return Container(
          decoration: BoxDecoration(
            color: isOddOne
                ? AppColors.successGreen.withValues(alpha: 0.1)
                : (isDarkMode
                    ? AppColors.surfaceDark.withValues(alpha: 0.5)
                    : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOddOne ? AppColors.successGreen : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
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
    final puzzle = _sessionPuzzles[_currentPuzzleIndex];

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Which one is different?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // 2x2 Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                return _buildItemCard(puzzle, index, isDarkMode);
              },
            ),
            const SizedBox(height: 24),
            // Feedback area
            if (_showingFeedback) _buildFeedback(puzzle, isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(OddOneOutPuzzle puzzle, int index, bool isDarkMode) {
    final item = puzzle.items[index];
    final isSelected = _selectedIndex == index;
    final isOddOne = index == puzzle.oddOneIndex;
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

    return GestureDetector(
      onTap: () => _handleItemTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: bgColor ??
              (isDarkMode ? AppColors.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(20),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              item.label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(OddOneOutPuzzle puzzle, bool isDarkMode) {
    final oddItem = puzzle.items[puzzle.oddOneIndex];

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
                  ? "That's right! ${oddItem.label} - ${puzzle.explanation}"
                  : "Not quite. ${oddItem.label} doesn't belong - ${puzzle.explanation}",
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
      performanceLevel = 'Sharp Eye!';
      performanceColor = AppColors.successGreen;
      emoji = '👁️';
    } else if (accuracy >= 70) {
      performanceLevel = 'Great Focus!';
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
                  '${metrics.puzzlesCorrect} out of ${metrics.puzzlesShown}',
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
