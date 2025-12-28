import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// Model for tracking game metrics
class MemoryMatchMetrics {
  final int totalPairs;
  final int moves;
  final int correctMatches;
  final int incorrectAttempts;
  final List<int> matchTimes; // Time to find each pair in milliseconds
  final int totalTimeMs;

  MemoryMatchMetrics({
    required this.totalPairs,
    required this.moves,
    required this.correctMatches,
    required this.incorrectAttempts,
    required this.matchTimes,
    required this.totalTimeMs,
  });

  double get efficiency =>
      moves > 0 ? (totalPairs / moves) * 100 : 0; // Perfect = 100%

  int get averageMatchTime => matchTimes.isNotEmpty
      ? (matchTimes.reduce((a, b) => a + b) / matchTimes.length).round()
      : 0;

  int get fastestMatch => matchTimes.isNotEmpty ? matchTimes.reduce(min) : 0;

  String get formattedTotalTime {
    final seconds = totalTimeMs ~/ 1000;
    final ms = totalTimeMs % 1000;
    return '${seconds}s ${(ms ~/ 100)}';
  }
}

/// Represents a card in the memory game
class MemoryCard {
  final int id;
  final String emoji;
  final int pairId;
  bool isFlipped;
  bool isMatched;

  MemoryCard({
    required this.id,
    required this.emoji,
    required this.pairId,
    this.isFlipped = false,
    this.isMatched = false,
  });

  MemoryCard copyWith({bool? isFlipped, bool? isMatched}) {
    return MemoryCard(
      id: id,
      emoji: emoji,
      pairId: pairId,
      isFlipped: isFlipped ?? this.isFlipped,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}

class MemoryMatchScreen extends StatefulWidget {
  const MemoryMatchScreen({super.key});

  @override
  State<MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

class _MemoryMatchScreenState extends State<MemoryMatchScreen>
    with TickerProviderStateMixin {
  // Available emojis for the game
  final List<String> _availableEmojis = const [
    '🍌',
    '🐶',
    '🎈',
    '⭐',
    '🌈',
    '🍎',
    '🌸',
    '🎵',
    '🦋',
    '🌻',
    '🍕',
    '⚽',
    '🚀',
    '🎁',
    '🌙',
    '🔥',
  ];

  // Game configuration - 4 pairs (8 cards) in a 3-column grid

  // Game state
  List<MemoryCard> _cards = [];
  final List<int> _flippedIndices = [];
  bool _canFlip = true;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _lastMatchStartTime;

  // Metrics tracking
  int _moves = 0;
  int _correctMatches = 0;
  int _incorrectAttempts = 0;
  List<int> _matchTimes = [];

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final Map<int, AnimationController> _cardFlipControllers = {};
  final Map<int, Animation<double>> _cardFlipAnimations = {};

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeGame();
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
  }

  void _initCardAnimations() {
    for (int i = 0; i < _cards.length; i++) {
      _cardFlipControllers[i] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      _cardFlipAnimations[i] = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _cardFlipControllers[i]!,
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  void _initializeGame() {
    final random = Random();
    final selectedEmojis = List<String>.from(_availableEmojis)..shuffle(random);

    // For a 3x3 grid (9 cards), we'll use 4 pairs + 1 unique card
    // Or better: let's just use pairs and make the grid fit
    // Let's use 6 cards (3 pairs) for a 2x3 grid or 9 cards (4 pairs + 1 unique)
    // Going with the screenshot: appears to be 3x3

    // Create pairs
    _cards = [];
    int cardId = 0;

    // Use 4 pairs for the game (8 cards total - we'll display in a grid)
    // Actually looking at screenshot, it's 3 cols, multiple rows
    // Let's use 6 cards (3 unique pairs) for simplicity

    final numPairs = 4;
    for (int i = 0; i < numPairs; i++) {
      final emoji = selectedEmojis[i];
      // Add two cards with the same emoji
      _cards.add(MemoryCard(id: cardId++, emoji: emoji, pairId: i));
      _cards.add(MemoryCard(id: cardId++, emoji: emoji, pairId: i));
    }

    // Shuffle cards
    _cards.shuffle(random);

    // Initialize card animations after cards are created
    _disposeCardAnimations();
    _initCardAnimations();
  }

  void _disposeCardAnimations() {
    for (final controller in _cardFlipControllers.values) {
      controller.dispose();
    }
    _cardFlipControllers.clear();
    _cardFlipAnimations.clear();
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
      _gameStarted = true;
      _lastMatchStartTime = DateTime.now();
    });

    _fadeController.forward();

    // Start game timer
    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedMs += 100;
      });
    });
  }

  void _handleCardTap(int index) {
    if (!_canFlip ||
        !_gameStarted ||
        _gameEnded ||
        _cards[index].isFlipped ||
        _cards[index].isMatched ||
        _flippedIndices.contains(index)) {
      return;
    }

    setState(() {
      _cards[index].isFlipped = true;
      _flippedIndices.add(index);
    });

    _cardFlipControllers[index]?.forward();

    if (_flippedIndices.length == 2) {
      _moves++;
      _canFlip = false;
      _checkForMatch();
    }
  }

  void _checkForMatch() {
    final first = _cards[_flippedIndices[0]];
    final second = _cards[_flippedIndices[1]];

    if (first.pairId == second.pairId) {
      // Match found!
      final matchTime = DateTime.now()
          .difference(_lastMatchStartTime!)
          .inMilliseconds;
      _matchTimes.add(matchTime);

      setState(() {
        _cards[_flippedIndices[0]].isMatched = true;
        _cards[_flippedIndices[1]].isMatched = true;
        _correctMatches++;
        _flippedIndices.clear();
        _canFlip = true;
        _lastMatchStartTime = DateTime.now();
      });

      // Check if game is complete
      if (_cards.every((card) => card.isMatched)) {
        _endGame();
      }
    } else {
      // No match
      setState(() {
        _incorrectAttempts++;
      });

      // Flip cards back after delay
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          for (final index in _flippedIndices) {
            _cardFlipControllers[index]?.reverse();
          }

          setState(() {
            for (final index in _flippedIndices) {
              _cards[index].isFlipped = false;
            }
            _flippedIndices.clear();
            _canFlip = true;
          });
        }
      });
    }
  }

  void _endGame() {
    _gameTimer?.cancel();
    setState(() {
      _gameEnded = true;
    });
  }

  MemoryMatchMetrics _getMetrics() {
    return MemoryMatchMetrics(
      totalPairs: _cards.length ~/ 2,
      moves: _moves,
      correctMatches: _correctMatches,
      incorrectAttempts: _incorrectAttempts,
      matchTimes: _matchTimes,
      totalTimeMs: _elapsedMs,
    );
  }

  void _restartGame() {
    _gameTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _flippedIndices.clear();
      _canFlip = true;
      _gameStarted = false;
      _gameEnded = false;
      _showingCountdown = true;
      _countdownValue = 3;
      _elapsedMs = 0;
      _moves = 0;
      _correctMatches = 0;
      _incorrectAttempts = 0;
      _matchTimes = [];
    });

    _fadeController.reset();
    _initializeGame();
    _startCountdown();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _countdownTimer?.cancel();
    _fadeController.dispose();
    _disposeCardAnimations();
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
    final seconds = _elapsedMs ~/ 1000;

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
                'Round 1/1',
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
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${seconds}s',
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
        child: Center(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: _cards.length,
            itemBuilder: (context, index) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 300 + (index * 50)),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: _buildCard(index, isDarkMode),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(int index, bool isDarkMode) {
    final card = _cards[index];

    return GestureDetector(
      onTap: () => _handleCardTap(index),
      child: AnimatedBuilder(
        animation: _cardFlipControllers[index] ?? _fadeController,
        builder: (context, child) {
          final animValue = _cardFlipControllers[index]?.value ?? 0.0;
          final angle = animValue * pi;
          final isShowingFront = angle < pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: Container(
              decoration: BoxDecoration(
                color: card.isMatched
                    ? Colors.white
                    : isShowingFront
                    ? AppColors.primaryBlue
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: card.isMatched
                      ? AppColors.successGreen
                      : AppColors.primaryBlue,
                  width: card.isMatched ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: card.isMatched
                        ? AppColors.successGreen.withValues(alpha: 0.2)
                        : AppColors.primaryBlue.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: isShowingFront && !card.isMatched
                    ? Icon(
                        Icons.question_mark_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 32,
                      )
                    : Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(pi),
                        child: Text(
                          card.emoji,
                          style: const TextStyle(fontSize: 40),
                        ),
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

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (metrics.efficiency >= 80) {
      performanceLevel = 'Perfect Memory!';
      performanceColor = AppColors.successGreen;
      emoji = '🧠';
    } else if (metrics.efficiency >= 60) {
      performanceLevel = 'Great Job!';
      performanceColor = AppColors.primaryBlue;
      emoji = '⭐';
    } else if (metrics.efficiency >= 40) {
      performanceLevel = 'Good Try!';
      performanceColor = AppColors.warningOrange;
      emoji = '👍';
    } else {
      performanceLevel = 'Keep Practicing';
      performanceColor = AppColors.dangerRed;
      emoji = '💪';
    }

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
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Time',
                  metrics.formattedTotalTime,
                  Icons.timer,
                  AppColors.primaryBlue,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Moves',
                  '${metrics.moves}',
                  Icons.touch_app,
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
                  'Efficiency',
                  '${metrics.efficiency.toStringAsFixed(0)}%',
                  Icons.speed,
                  AppColors.warningOrange,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Match',
                  '${(metrics.averageMatchTime / 1000).toStringAsFixed(1)}s',
                  Icons.psychology,
                  AppColors.infoCyan,
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
                  'Matches',
                  '${metrics.correctMatches}/${metrics.totalPairs}',
                  Icons.check_circle,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Errors',
                  '${metrics.incorrectAttempts}',
                  Icons.cancel,
                  AppColors.dangerRed,
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Play again button
          SizedBox(
            width: double.infinity,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
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
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode
                  ? AppColors.borderDark
                  : AppColors.borderLight,
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
