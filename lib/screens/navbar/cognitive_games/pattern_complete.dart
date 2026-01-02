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

/// Represents an item in a pattern sequence
class PatternItem {
  final String shape; // 'circle', 'square', 'triangle', 'star', 'heart'
  final Color color;
  final String label;
  final bool isPlaceholder;

  const PatternItem({
    required this.shape,
    required this.color,
    required this.label,
    this.isPlaceholder = false,
  });
}

/// Represents a complete pattern puzzle
class PatternPuzzle {
  final List<PatternItem> sequence;
  final List<PatternItem> choices;
  final int correctChoiceIndex;
  final String patternType;

  const PatternPuzzle({
    required this.sequence,
    required this.choices,
    required this.correctChoiceIndex,
    required this.patternType,
  });
}

/// Metrics for tracking game performance
class PatternCompleteMetrics {
  final int patternsShown;
  final int patternsCorrect;
  final int patternsIncorrect;
  final List<int> responseTimes;
  final int totalTimeMs;

  PatternCompleteMetrics({
    required this.patternsShown,
    required this.patternsCorrect,
    required this.patternsIncorrect,
    required this.responseTimes,
    required this.totalTimeMs,
  });

  double get accuracy =>
      patternsShown > 0 ? (patternsCorrect / patternsShown) * 100 : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;
}

class PatternCompleteScreen extends StatefulWidget {
  const PatternCompleteScreen({super.key});

  @override
  State<PatternCompleteScreen> createState() => _PatternCompleteScreenState();
}

class _PatternCompleteScreenState extends State<PatternCompleteScreen>
    with TickerProviderStateMixin {
  // Colors for patterns
  static const Color _red = Color(0xFFEF4444);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _green = Color(0xFF22C55E);
  static const Color _yellow = Color(0xFFFBBF24);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _orange = Color(0xFFF97316);

  // Placeholder color
  static const Color _placeholder = Color(0xFFE5E7EB);

  // All puzzles - Level 1-2 (simple alternating and repeating)
  static final List<PatternPuzzle> _allPuzzles = [
    // Alternating AB patterns
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _green, label: 'Green'),
      ],
      correctChoiceIndex: 0,
      patternType: 'alternating',
    ),
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'square', color: _green, label: 'Green'),
        const PatternItem(shape: 'square', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'square', color: _green, label: 'Green'),
        const PatternItem(shape: 'square', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'square', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'square', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'square', color: _green, label: 'Green'),
        const PatternItem(shape: 'square', color: _red, label: 'Red'),
      ],
      correctChoiceIndex: 1,
      patternType: 'alternating',
    ),
    // Alternating shape patterns
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'circle', color: _blue, label: 'Circle'),
        const PatternItem(shape: 'square', color: _blue, label: 'Square'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Circle'),
        const PatternItem(shape: 'square', color: _blue, label: 'Square'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'triangle', color: _blue, label: 'Triangle'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Circle'),
        const PatternItem(shape: 'square', color: _blue, label: 'Square'),
      ],
      correctChoiceIndex: 1,
      patternType: 'alternating',
    ),
    // Repeating ABC patterns
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _green, label: 'Green'),
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'circle', color: _green, label: 'Green'),
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
      ],
      correctChoiceIndex: 2,
      patternType: 'repeating',
    ),
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'triangle', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'triangle', color: _orange, label: 'Orange'),
        const PatternItem(shape: 'triangle', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'triangle', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'triangle', color: _orange, label: 'Orange'),
        const PatternItem(shape: 'triangle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'triangle', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'triangle', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'triangle', color: _orange, label: 'Orange'),
      ],
      correctChoiceIndex: 1,
      patternType: 'repeating',
    ),
    // Shape repeating pattern
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'circle', color: _red, label: 'Circle'),
        const PatternItem(shape: 'square', color: _red, label: 'Square'),
        const PatternItem(shape: 'triangle', color: _red, label: 'Triangle'),
        const PatternItem(shape: 'circle', color: _red, label: 'Circle'),
        const PatternItem(shape: 'square', color: _red, label: 'Square'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'circle', color: _red, label: 'Circle'),
        const PatternItem(shape: 'square', color: _red, label: 'Square'),
        const PatternItem(shape: 'triangle', color: _red, label: 'Triangle'),
      ],
      correctChoiceIndex: 2,
      patternType: 'repeating',
    ),
    // Growing pattern - dots
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'dot1', color: _blue, label: '●'),
        const PatternItem(shape: 'dot2', color: _blue, label: '●●'),
        const PatternItem(shape: 'dot3', color: _blue, label: '●●●'),
        const PatternItem(shape: 'dot4', color: _blue, label: '●●●●'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'dot3', color: _blue, label: '●●●'),
        const PatternItem(shape: 'dot5', color: _blue, label: '●●●●●'),
        const PatternItem(shape: 'dot4', color: _blue, label: '●●●●'),
      ],
      correctChoiceIndex: 1,
      patternType: 'growing',
    ),
    // Size pattern
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'small', color: _green, label: 'Small'),
        const PatternItem(shape: 'medium', color: _green, label: 'Medium'),
        const PatternItem(shape: 'large', color: _green, label: 'Large'),
        const PatternItem(shape: 'small', color: _green, label: 'Small'),
        const PatternItem(shape: 'medium', color: _green, label: 'Medium'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'small', color: _green, label: 'Small'),
        const PatternItem(shape: 'large', color: _green, label: 'Large'),
        const PatternItem(shape: 'medium', color: _green, label: 'Medium'),
      ],
      correctChoiceIndex: 1,
      patternType: 'repeating',
    ),
    // Two-attribute pattern (color + position)
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _green, label: 'Green'),
        const PatternItem(shape: 'circle', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'circle', color: _red, label: 'Red'),
        const PatternItem(shape: 'circle', color: _blue, label: 'Blue'),
        const PatternItem(shape: 'circle', color: _green, label: 'Green'),
      ],
      correctChoiceIndex: 2,
      patternType: 'two-attribute',
    ),
    // Simple color alternating
    PatternPuzzle(
      sequence: [
        const PatternItem(shape: 'star', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'star', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'star', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'star', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'star', color: _placeholder, label: '?', isPlaceholder: true),
      ],
      choices: [
        const PatternItem(shape: 'star', color: _purple, label: 'Purple'),
        const PatternItem(shape: 'star', color: _yellow, label: 'Yellow'),
        const PatternItem(shape: 'star', color: _orange, label: 'Orange'),
      ],
      correctChoiceIndex: 1,
      patternType: 'alternating',
    ),
  ];

  // Game state
  List<PatternPuzzle> _sessionPuzzles = [];
  int _currentPuzzleIndex = 0;
  bool _showingCountdown = true;
  bool _showingInstructions = true;
  int _countdownValue = 3;
  bool _gameEnded = false;
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;
  int? _selectedChoiceIndex;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _puzzleStartTime;
  bool _resultsSaved = false;

  // Metrics tracking
  int _patternsCorrect = 0;
  int _patternsIncorrect = 0;
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
    final shuffled = List<PatternPuzzle>.from(_allPuzzles)..shuffle(random);
    _sessionPuzzles = shuffled.take(6).toList();
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

    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedMs += 100;
      });
    });
  }

  void _handleChoiceTap(int index) {
    if (_showingFeedback || _gameEnded) return;

    final puzzle = _sessionPuzzles[_currentPuzzleIndex];
    final responseTime =
        DateTime.now().difference(_puzzleStartTime!).inMilliseconds;
    _responseTimes.add(responseTime);

    final isCorrect = index == puzzle.correctChoiceIndex;

    setState(() {
      _selectedChoiceIndex = index;
      _showingFeedback = true;
      _lastAnswerCorrect = isCorrect;
      if (isCorrect) {
        _patternsCorrect++;
      } else {
        _patternsIncorrect++;
      }
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
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
        _selectedChoiceIndex = null;
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
    final score = GameResult.calculatePatternCompleteScore(
      accuracy: metrics.accuracy,
      averageResponseTimeMs: metrics.averageResponseTime,
    );

    final result = GameResult(
      id: '',
      gameType: 'pattern_complete',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'patternsShown': metrics.patternsShown,
        'patternsCorrect': metrics.patternsCorrect,
        'patternsIncorrect': metrics.patternsIncorrect,
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
            gameType: 'pattern_complete',
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

  PatternCompleteMetrics _getMetrics() {
    return PatternCompleteMetrics(
      patternsShown: _currentPuzzleIndex + 1,
      patternsCorrect: _patternsCorrect,
      patternsIncorrect: _patternsIncorrect,
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
      _selectedChoiceIndex = null;
      _elapsedMs = 0;
      _patternsCorrect = 0;
      _patternsIncorrect = 0;
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
                'PATTERN COMPLETE',
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
                    : 'Pattern ${_currentPuzzleIndex + 1} of ${_sessionPuzzles.length}',
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
                  Icon(Icons.check_circle, size: 18, color: AppColors.successGreen),
                  const SizedBox(width: 6),
                  Text(
                    '$_patternsCorrect',
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
                color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                const Text('🧩', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'What comes next in the pattern?',
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
                // Example pattern
                _buildExamplePattern(isDarkMode),
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
                      Icon(Icons.lightbulb, color: AppColors.successGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Red comes next!',
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

  Widget _buildExamplePattern(bool isDarkMode) {
    return Column(
      children: [
        // Sequence
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPatternShape('circle', _red, false),
            const SizedBox(width: 8),
            _buildPatternShape('circle', _blue, false),
            const SizedBox(width: 8),
            _buildPatternShape('circle', _red, false),
            const SizedBox(width: 8),
            _buildPatternShape('circle', _blue, false),
            const SizedBox(width: 8),
            _buildPatternShape('circle', _placeholder, true),
          ],
        ),
        const SizedBox(height: 16),
        // Choices
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.successGreen, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _buildPatternShape('circle', _red, false),
            ),
            const SizedBox(width: 12),
            _buildPatternShape('circle', _blue, false),
            const SizedBox(width: 12),
            _buildPatternShape('circle', _green, false),
          ],
        ),
      ],
    );
  }

  Widget _buildPatternShape(String shape, Color color, bool isPlaceholder) {
    double size = 40;

    if (shape.startsWith('dot')) {
      final dotCount = int.tryParse(shape.substring(3)) ?? 1;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isPlaceholder ? _placeholder : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isPlaceholder ? Colors.grey : color, width: 2),
        ),
        child: Center(
          child: Text(
            '●' * dotCount,
            style: TextStyle(
              fontSize: dotCount > 3 ? 8 : 10,
              color: color,
            ),
          ),
        ),
      );
    }

    if (shape == 'small' || shape == 'medium' || shape == 'large') {
      double circleSize = shape == 'small' ? 16 : (shape == 'medium' ? 24 : 32);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isPlaceholder ? _placeholder : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Center(
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    Widget shapeWidget;
    switch (shape) {
      case 'circle':
        shapeWidget = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isPlaceholder ? _placeholder : color,
            shape: BoxShape.circle,
          ),
          child: isPlaceholder
              ? Center(
                  child: Text(
                    '?',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                )
              : null,
        );
        break;
      case 'square':
        shapeWidget = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isPlaceholder ? _placeholder : color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: isPlaceholder
              ? Center(
                  child: Text(
                    '?',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                )
              : null,
        );
        break;
      case 'triangle':
        shapeWidget = CustomPaint(
          size: const Size(28, 28),
          painter: TrianglePainter(color: isPlaceholder ? _placeholder : color),
        );
        break;
      case 'star':
        shapeWidget = Icon(
          Icons.star,
          size: 28,
          color: isPlaceholder ? _placeholder : color,
        );
        break;
      case 'heart':
        shapeWidget = Icon(
          Icons.favorite,
          size: 28,
          color: isPlaceholder ? _placeholder : color,
        );
        break;
      default:
        shapeWidget = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isPlaceholder ? _placeholder : color,
            shape: BoxShape.circle,
          ),
        );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Center(child: shapeWidget),
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
              'What comes next?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Pattern sequence
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: puzzle.sequence.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildPatternShape(item.shape, item.color, item.isPlaceholder),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Choose the answer:',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            // Choices
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(puzzle.choices.length, (index) {
                final choice = puzzle.choices[index];
                final isSelected = _selectedChoiceIndex == index;
                final isCorrect = index == puzzle.correctChoiceIndex;
                final showResult = _showingFeedback;

                Color? borderColor;
                if (showResult) {
                  if (isCorrect) {
                    borderColor = AppColors.successGreen;
                  } else if (isSelected && !isCorrect) {
                    borderColor = AppColors.dangerRed;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () => _handleChoiceTap(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor ??
                              (isDarkMode
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                          width: borderColor != null ? 3 : 1,
                        ),
                        boxShadow: isDarkMode
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Column(
                        children: [
                          _buildPatternShape(choice.shape, choice.color, false),
                          const SizedBox(height: 8),
                          Text(
                            choice.label,
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
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            if (_showingFeedback)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lastAnswerCorrect
                      ? AppColors.successGreen.withValues(alpha: 0.1)
                      : AppColors.dangerRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _lastAnswerCorrect ? Icons.check_circle : Icons.cancel,
                      color: _lastAnswerCorrect
                          ? AppColors.successGreen
                          : AppColors.dangerRed,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _lastAnswerCorrect ? 'Correct!' : 'Not quite!',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _lastAnswerCorrect
                            ? AppColors.successGreen
                            : AppColors.dangerRed,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
      performanceLevel = 'Pattern Pro!';
      performanceColor = AppColors.successGreen;
      emoji = '🧠';
    } else if (accuracy >= 70) {
      performanceLevel = 'Great Logic!';
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

    int stars = accuracy >= 90 ? 3 : (accuracy >= 70 ? 2 : 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${metrics.patternsCorrect} out of ${metrics.patternsShown}',
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

/// Custom painter for triangle shapes
class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is TrianglePainter) {
      return oldDelegate.color != color;
    }
    return true;
  }
}
