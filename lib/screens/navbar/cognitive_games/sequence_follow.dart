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

/// Model for tracking Sequence Follow game metrics
class SequenceFollowMetrics {
  final int roundsCompleted;
  final int maxSequenceLength;
  final int sequenceErrors;
  final List<int> tapIntervals; // Time between taps in milliseconds
  final int totalDurationMs;
  final int difficultyLevel;

  SequenceFollowMetrics({
    required this.roundsCompleted,
    required this.maxSequenceLength,
    required this.sequenceErrors,
    required this.tapIntervals,
    required this.totalDurationMs,
    required this.difficultyLevel,
  });

  int get averageTapInterval => tapIntervals.isNotEmpty
      ? (tapIntervals.reduce((a, b) => a + b) / tapIntervals.length).round()
      : 0;

  String get formattedDuration {
    final seconds = totalDurationMs ~/ 1000;
    return '${seconds}s';
  }
}

/// Represents a colored square in the sequence game
class SequenceSquare {
  final int id;
  final Color color;
  final Color glowColor;
  final String name;
  final double frequency; // Sound frequency in Hz

  const SequenceSquare({
    required this.id,
    required this.color,
    required this.glowColor,
    required this.name,
    required this.frequency,
  });
}

/// Difficulty configuration for Sequence Follow
class SequenceDifficulty {
  final int startLength;
  final int maxLength;
  final int itemDurationMs;
  final int pauseDurationMs;

  const SequenceDifficulty({
    required this.startLength,
    required this.maxLength,
    required this.itemDurationMs,
    required this.pauseDurationMs,
  });

  static const Map<int, SequenceDifficulty> levels = {
    1: SequenceDifficulty(startLength: 2, maxLength: 4, itemDurationMs: 1000, pauseDurationMs: 500),
    2: SequenceDifficulty(startLength: 2, maxLength: 5, itemDurationMs: 800, pauseDurationMs: 400),
    3: SequenceDifficulty(startLength: 3, maxLength: 5, itemDurationMs: 800, pauseDurationMs: 400),
    4: SequenceDifficulty(startLength: 3, maxLength: 6, itemDurationMs: 800, pauseDurationMs: 400),
    5: SequenceDifficulty(startLength: 3, maxLength: 7, itemDurationMs: 600, pauseDurationMs: 300),
  };
}

class SequenceFollowScreen extends StatefulWidget {
  final int difficultyLevel;
  
  const SequenceFollowScreen({super.key, this.difficultyLevel = 1});

  @override
  State<SequenceFollowScreen> createState() => _SequenceFollowScreenState();
}

class _SequenceFollowScreenState extends State<SequenceFollowScreen>
    with TickerProviderStateMixin {
  // The four colored squares
  static const List<SequenceSquare> _squares = [
    SequenceSquare(id: 0, color: Color(0xFFEF4444), glowColor: Color(0xFFFF6B6B), name: 'Red', frequency: 200),
    SequenceSquare(id: 1, color: Color(0xFF3B82F6), glowColor: Color(0xFF60A5FA), name: 'Blue', frequency: 300),
    SequenceSquare(id: 2, color: Color(0xFF22C55E), glowColor: Color(0xFF4ADE80), name: 'Green', frequency: 400),
    SequenceSquare(id: 3, color: Color(0xFFFACC15), glowColor: Color(0xFFFDE047), name: 'Yellow', frequency: 500),
  ];

  // Game configuration
  static const int maxRounds = 5;
  static const int maxFailures = 2;

  // Game state
  List<int> _sequence = [];
  int _userInputIndex = 0;
  int _currentRound = 0;
  int _failureCount = 0;
  bool _isWatchPhase = true;
  bool _isUserTurn = false;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  int _highlightedSquare = -1;
  String _statusText = "Watch carefully...";
  Timer? _countdownTimer;
  Timer? _sequenceTimer;
  DateTime? _gameStartTime;
  DateTime? _lastTapTime;

  // Metrics tracking
  int _roundsCompleted = 0;
  int _maxSequenceLength = 0;
  int _sequenceErrors = 0;
  List<int> _tapIntervals = [];

  // Difficulty settings
  late SequenceDifficulty _difficulty;

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final Map<int, AnimationController> _squareControllers = {};
  final Map<int, Animation<double>> _squareAnimations = {};

  @override
  void initState() {
    super.initState();
    // Clamp difficulty level to valid range
    final level = widget.difficultyLevel.clamp(1, 5);
    _difficulty = SequenceDifficulty.levels[level]!;
    _initAnimations();
    _startCountdown();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    // Initialize square highlight animations
    for (int i = 0; i < 4; i++) {
      _squareControllers[i] = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _difficulty.itemDurationMs ~/ 2),
      );
      _squareAnimations[i] = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _squareControllers[i]!, curve: Curves.easeInOut),
      );
    }
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
    _startNewRound();
  }

  void _startNewRound() {
    if (!mounted || _gameEnded) return;

    if (_currentRound >= maxRounds || _failureCount >= maxFailures) {
      _endGame();
      return;
    }

    setState(() {
      _currentRound++;
      _userInputIndex = 0;
      _isWatchPhase = true;
      _isUserTurn = false;
      _statusText = "Watch carefully...";
    });

    // Generate sequence for this round
    final sequenceLength = _difficulty.startLength + _currentRound - 1;
    _generateSequence(sequenceLength.clamp(2, _difficulty.maxLength));

    // Start showing the sequence after a brief delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _playSequence();
    });
  }

  void _generateSequence(int length) {
    final random = Random();
    _sequence = List.generate(length, (_) => random.nextInt(4));
    
    // Track max sequence length
    if (length > _maxSequenceLength) {
      _maxSequenceLength = length;
    }
  }

  void _playSequence() async {
    if (!mounted || _gameEnded) return;

    for (int i = 0; i < _sequence.length; i++) {
      if (!mounted || _gameEnded) return;

      final squareIndex = _sequence[i];
      
      // Highlight the square
      setState(() {
        _highlightedSquare = squareIndex;
      });
      _squareControllers[squareIndex]?.forward();
      
      // Play haptic feedback (simulates tone)
      HapticFeedback.lightImpact();

      // Wait for display duration
      await Future.delayed(Duration(milliseconds: _difficulty.itemDurationMs));
      
      if (!mounted) return;
      
      // Turn off highlight
      setState(() {
        _highlightedSquare = -1;
      });
      _squareControllers[squareIndex]?.reverse();

      // Pause between items (except after last item)
      if (i < _sequence.length - 1) {
        await Future.delayed(Duration(milliseconds: _difficulty.pauseDurationMs));
      }
    }

    // Switch to user input phase
    if (mounted && !_gameEnded) {
      setState(() {
        _isWatchPhase = false;
        _isUserTurn = true;
        _statusText = "Your turn! Tap the sequence";
        _lastTapTime = DateTime.now();
      });
    }
  }

  void _handleSquareTap(int squareIndex) {
    if (!_isUserTurn || _gameEnded || _isWatchPhase) return;

    // Validate square index
    if (squareIndex < 0 || squareIndex >= 4) return;

    // Track tap interval
    if (_lastTapTime != null) {
      final interval = DateTime.now().difference(_lastTapTime!).inMilliseconds;
      if (interval > 0 && interval < 10000) { // Sanity check: ignore very long intervals
        _tapIntervals.add(interval);
      }
    }
    _lastTapTime = DateTime.now();

    // Visual feedback
    _squareControllers[squareIndex]?.forward().then((_) {
      if (mounted) _squareControllers[squareIndex]?.reverse();
    });
    HapticFeedback.lightImpact();

    // Check if correct
    if (_sequence.isEmpty || _userInputIndex >= _sequence.length) {
      // Edge case: sequence is empty or already completed
      return;
    }

    if (squareIndex == _sequence[_userInputIndex]) {
      // Correct tap
      setState(() {
        _userInputIndex++;
      });

      // Check if sequence is complete
      if (_userInputIndex >= _sequence.length) {
        _handleRoundComplete();
      }
    } else {
      // Incorrect tap
      _handleIncorrectTap();
    }
  }

  void _handleRoundComplete() {
    if (!mounted) return;
    
    setState(() {
      _roundsCompleted++;
      _isUserTurn = false;
      _statusText = "Perfect! 🎉";
    });

    // Brief celebration, then next round
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_gameEnded) {
        _startNewRound();
      }
    });
  }

  void _handleIncorrectTap() {
    if (!mounted) return;
    
    setState(() {
      _sequenceErrors++;
      _failureCount++;
      _isUserTurn = false;
      _statusText = "Not quite! Let's try a new pattern";
    });

    // Shake animation feedback
    HapticFeedback.mediumImpact();

    // Check if game should end
    if (_failureCount >= maxFailures) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _endGame();
      });
    } else {
      // Continue with new pattern
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_gameEnded) {
          _startNewRound();
        }
      });
    }
  }

  Future<void> _endGame() async {
    if (_gameEnded) return; // Prevent double-ending
    
    _sequenceTimer?.cancel();
    setState(() {
      _gameEnded = true;
    });
    await _saveGameResult();
  }

  int _calculateScore() {
    // Max sequence weighted 60%, rounds 30%, errors -10% each
    final sequenceScore = (_maxSequenceLength / _difficulty.maxLength * 100).clamp(0.0, 100.0);
    final roundScore = (_roundsCompleted / maxRounds * 100).clamp(0.0, 100.0);
    final errorPenalty = (_sequenceErrors * 10).clamp(0, 50);
    return ((sequenceScore * 0.6) + (roundScore * 0.3) - errorPenalty).round().clamp(0, 100);
  }

  Future<void> _saveGameResult() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final metrics = _getMetrics();
    final score = _calculateScore();

    final result = GameResult(
      id: '',
      gameType: 'sequence_follow',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'roundsCompleted': metrics.roundsCompleted,
        'maxSequenceLength': metrics.maxSequenceLength,
        'sequenceErrors': metrics.sequenceErrors,
        'averageTapIntervalMs': metrics.averageTapInterval,
        'totalDurationMs': metrics.totalDurationMs,
        'difficultyLevel': metrics.difficultyLevel,
      },
    );

    try {
      if (mounted) {
        final firestoreService = context.read<FirestoreService>();
        await firestoreService.saveGameResult(user.uid, result);

        // Log the brain game activity
        try {
          final activityLog = ActivityLog.brainGame(
            seniorId: user.uid,
            timestamp: result.timestamp,
            gameType: 'sequence_follow', // Standardized: snake_case for all game types
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

  SequenceFollowMetrics _getMetrics() {
    final totalDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inMilliseconds
        : 0;

    return SequenceFollowMetrics(
      roundsCompleted: _roundsCompleted,
      maxSequenceLength: _maxSequenceLength,
      sequenceErrors: _sequenceErrors,
      tapIntervals: _tapIntervals,
      totalDurationMs: totalDuration,
      difficultyLevel: widget.difficultyLevel.clamp(1, 5),
    );
  }

  void _restartGame() {
    _countdownTimer?.cancel();
    _sequenceTimer?.cancel();

    setState(() {
      _sequence = [];
      _userInputIndex = 0;
      _currentRound = 0;
      _failureCount = 0;
      _isWatchPhase = true;
      _isUserTurn = false;
      _gameStarted = false;
      _gameEnded = false;
      _showingCountdown = true;
      _countdownValue = 3;
      _highlightedSquare = -1;
      _statusText = "Watch carefully...";
      _roundsCompleted = 0;
      _maxSequenceLength = 0;
      _sequenceErrors = 0;
      _tapIntervals = [];
    });

    _fadeController.reset();
    for (final controller in _squareControllers.values) {
      controller.reset();
    }
    _startCountdown();
  }

  /// Flag to prevent double-saving (once in dispose, once in endGame)
  bool _resultsSaved = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sequenceTimer?.cancel();
    // Save results if game was started but not ended normally (user pressed back)
    if (_gameStarted && !_gameEnded && !_resultsSaved && _currentRound > 0) {
      _resultsSaved = true;
      _saveGameResult(); // Fire-and-forget - we're disposing anyway
    }
    _fadeController.dispose();
    for (final controller in _squareControllers.values) {
      controller.dispose();
    }
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
                'EXERCISE PROGRESS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Round $_currentRound of $maxRounds',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isUserTurn ? AppColors.successGreen : AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isUserTurn ? 'YOUR TURN' : 'WATCH',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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

  Widget _buildGameArea(bool isDarkMode) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _statusText,
                key: ValueKey(_statusText),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // 2x2 Grid of squares
            _buildSquaresGrid(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildSquaresGrid(bool isDarkMode) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      child: GridView.builder(
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
          return _buildSquare(index, isDarkMode);
        },
      ),
    );
  }

  Widget _buildSquare(int index, bool isDarkMode) {
    final square = _squares[index];
    final isHighlighted = _highlightedSquare == index;

    return GestureDetector(
      onTap: () => _handleSquareTap(index),
      child: AnimatedBuilder(
        animation: _squareControllers[index] ?? _fadeController,
        builder: (context, child) {
          final animValue = _squareAnimations[index]?.value ?? 0.0;
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: Color.lerp(
                square.color,
                square.glowColor,
                isHighlighted ? 0.5 + (animValue * 0.5) : animValue * 0.3,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isHighlighted ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: isHighlighted
                      ? square.glowColor.withValues(alpha: 0.6)
                      : square.color.withValues(alpha: 0.3),
                  blurRadius: isHighlighted ? 30 : 15,
                  spreadRadius: isHighlighted ? 5 : 2,
                ),
              ],
            ),
            child: Center(
              child: Opacity(
                opacity: _isUserTurn && !isHighlighted ? 0.7 : 1.0,
                child: Icon(
                  Icons.circle,
                  size: 24,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();
    final score = _calculateScore();

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (score >= 80) {
      performanceLevel = 'Great Memory!';
      performanceColor = AppColors.successGreen;
      emoji = '🧠';
    } else if (score >= 60) {
      performanceLevel = 'Impressive!';
      performanceColor = AppColors.primaryBlue;
      emoji = '⭐';
    } else if (score >= 40) {
      performanceLevel = 'Well Done!';
      performanceColor = AppColors.warningOrange;
      emoji = '👍';
    } else {
      performanceLevel = 'Keep Practicing!';
      performanceColor = AppColors.dangerRed;
      emoji = '💪';
    }

    // Calculate stars (1-3)
    final stars = score >= 80 ? 3 : (score >= 50 ? 2 : 1);

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
                  'Longest sequence: ${metrics.maxSequenceLength} items',
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
                  'Rounds',
                  '${metrics.roundsCompleted}/$maxRounds',
                  Icons.flag,
                  AppColors.primaryBlue,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Max Sequence',
                  '${metrics.maxSequenceLength}',
                  Icons.format_list_numbered,
                  AppColors.successGreen,
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
                  'Errors',
                  '${metrics.sequenceErrors}',
                  Icons.close,
                  AppColors.dangerRed,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Tap Speed',
                  metrics.averageTapInterval > 0
                      ? '${metrics.averageTapInterval}ms'
                      : '-',
                  Icons.speed,
                  AppColors.warningOrange,
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
