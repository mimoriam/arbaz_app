import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// Model for tracking game metrics
class SpeedTapMetrics {
  final int totalRounds;
  final int correctTaps;
  final int incorrectTaps;
  final List<int> responseTimes; // in milliseconds
  final int missedTargets;

  SpeedTapMetrics({
    required this.totalRounds,
    required this.correctTaps,
    required this.incorrectTaps,
    required this.responseTimes,
    required this.missedTargets,
  });

  double get accuracy =>
      totalRounds > 0 ? (correctTaps / totalRounds) * 100 : 0;

  int get averageResponseTime => responseTimes.isNotEmpty
      ? (responseTimes.reduce((a, b) => a + b) / responseTimes.length).round()
      : 0;

  int get fastestResponseTime =>
      responseTimes.isNotEmpty ? responseTimes.reduce(min) : 0;

  int get slowestResponseTime =>
      responseTimes.isNotEmpty ? responseTimes.reduce(max) : 0;
}

/// Represents a color option in the game
class ColorOption {
  final Color color;
  final String pattern; // 'solid', 'dotted', 'striped'
  final String name;

  const ColorOption({
    required this.color,
    required this.pattern,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorOption &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          pattern == other.pattern;

  @override
  int get hashCode => color.hashCode ^ pattern.hashCode;
}

class SpeedTapScreen extends StatefulWidget {
  const SpeedTapScreen({super.key});

  @override
  State<SpeedTapScreen> createState() => _SpeedTapScreenState();
}

class _SpeedTapScreenState extends State<SpeedTapScreen>
    with TickerProviderStateMixin {
  // Game configuration
  static const int totalRounds = 10;
  static const int timePerRound = 5000; // 5 seconds per round

  // Available colors with patterns
  final List<ColorOption> _allColors = const [
    ColorOption(color: Color(0xFF3B82F6), pattern: 'dotted', name: 'Blue'),
    ColorOption(color: Color(0xFFEF4444), pattern: 'striped', name: 'Red'),
    ColorOption(color: Color(0xFFFACC15), pattern: 'solid', name: 'Yellow'),
    ColorOption(color: Color(0xFF22C55E), pattern: 'dotted', name: 'Green'),
    ColorOption(color: Color(0xFFEF4444), pattern: 'solid', name: 'Red Solid'),
    ColorOption(color: Color(0xFF3B82F6), pattern: 'solid', name: 'Blue Solid'),
    ColorOption(
      color: Color(0xFF22C55E),
      pattern: 'striped',
      name: 'Green Striped',
    ),
    ColorOption(
      color: Color(0xFFFACC15),
      pattern: 'striped',
      name: 'Yellow Striped',
    ),
  ];

  // Game state
  int _currentRound = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  ColorOption? _targetColor;
  List<ColorOption> _currentOptions = [];
  DateTime? _roundStartTime;
  Timer? _roundTimer;
  Timer? _countdownTimer;

  // Metrics tracking
  int _correctTaps = 0;
  int _incorrectTaps = 0;
  int _missedTargets = 0;
  List<int> _responseTimes = [];

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Feedback state
  bool _showCorrectFeedback = false;
  bool _showIncorrectFeedback = false;

  @override
  void initState() {
    super.initState();
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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
      } else {
        timer.cancel();
        setState(() {
          _showingCountdown = false;
          _gameStarted = true;
        });
        _fadeController.forward();
        _startNewRound();
      }
    });
  }

  void _startNewRound() {
    if (_currentRound >= totalRounds) {
      _endGame();
      return;
    }

    setState(() {
      _currentRound++;
      _targetColor = _getRandomTarget();
      _currentOptions = _generateOptions(_targetColor!);
      _roundStartTime = DateTime.now();
      _showCorrectFeedback = false;
      _showIncorrectFeedback = false;
    });

    // Start pulse animation for target
    _pulseController.repeat(reverse: true);

    // Start round timer
    _roundTimer?.cancel();
    _roundTimer = Timer(const Duration(milliseconds: timePerRound), () {
      _handleMissedTarget();
    });
  }

  ColorOption _getRandomTarget() {
    final random = Random();
    return _allColors[random.nextInt(_allColors.length)];
  }

  List<ColorOption> _generateOptions(ColorOption target) {
    final random = Random();
    final options = <ColorOption>[target];

    // Add 5 more unique options
    final availableColors = List<ColorOption>.from(_allColors)
      ..removeWhere((c) => c == target);
    availableColors.shuffle(random);

    for (int i = 0; i < 5 && i < availableColors.length; i++) {
      options.add(availableColors[i]);
    }

    // Shuffle the final options
    options.shuffle(random);
    return options;
  }

  void _handleTap(ColorOption tappedColor) {
    if (!_gameStarted || _gameEnded) return;

    _roundTimer?.cancel();
    final responseTime = DateTime.now()
        .difference(_roundStartTime!)
        .inMilliseconds;

    if (tappedColor == _targetColor) {
      // Correct tap
      setState(() {
        _correctTaps++;
        _responseTimes.add(responseTime);
        _showCorrectFeedback = true;
      });
      _pulseController.stop();
      _pulseController.reset();

      // Show feedback briefly then continue
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _startNewRound();
      });
    } else {
      // Incorrect tap
      setState(() {
        _incorrectTaps++;
        _showIncorrectFeedback = true;
      });
      _shakeController.forward().then((_) => _shakeController.reset());

      // Show feedback briefly then continue (don't end round on wrong tap)
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
          _showIncorrectFeedback = false;
        });
        }
      });
    }
  }

  void _handleMissedTarget() {
    setState(() {
      _missedTargets++;
    });
    _startNewRound();
  }

  void _endGame() {
    _roundTimer?.cancel();
    _pulseController.stop();

    setState(() {
      _gameEnded = true;
    });
  }

  SpeedTapMetrics _getMetrics() {
    return SpeedTapMetrics(
      totalRounds: totalRounds,
      correctTaps: _correctTaps,
      incorrectTaps: _incorrectTaps,
      responseTimes: _responseTimes,
      missedTargets: _missedTargets,
    );
  }

  void _restartGame() {
    setState(() {
      _currentRound = 0;
      _gameStarted = false;
      _gameEnded = false;
      _showingCountdown = true;
      _countdownValue = 3;
      _targetColor = null;
      _currentOptions = [];
      _correctTaps = 0;
      _incorrectTaps = 0;
      _missedTargets = 0;
      _responseTimes = [];
      _showCorrectFeedback = false;
      _showIncorrectFeedback = false;
    });

    _fadeController.reset();
    _pulseController.reset();
    _shakeController.reset();
    _startCountdown();
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    _countdownTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
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
      child: Column(
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
            'Round $_currentRound/$totalRounds',
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
    // Build static content that doesn't change every frame
    final staticContent = Column(
      children: [
        // Target display card
        _buildTargetCard(isDarkMode),
        const SizedBox(height: 32),
        // Color options grid
        _buildOptionsGrid(isDarkMode),
      ],
    );
    
    return FadeTransition(
      opacity: _fadeAnimation,
      // AnimatedBuilder with child parameter - child is built once,
      // only the Transform is recalculated each frame
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              sin(_shakeController.value * pi * 4) * _shakeAnimation.value,
              0,
            ),
            child: child, // Pre-built widget, not rebuilt 60 times per second
          );
        },
        child: staticContent, // Built once, passed to builder as child
      ),
    );
  }

  Widget _buildTargetCard(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _showCorrectFeedback
              ? AppColors.successGreen
              : _showIncorrectFeedback
              ? AppColors.dangerRed
              : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
          width: _showCorrectFeedback || _showIncorrectFeedback ? 3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _showCorrectFeedback
                ? AppColors.successGreen.withValues(alpha: 0.3)
                : _showIncorrectFeedback
                ? AppColors.dangerRed.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'FIND AND TAP:',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          if (_targetColor != null)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: _buildColorCircle(
                    _targetColor!,
                    size: 80,
                    showShadow: true,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _currentOptions.length,
        itemBuilder: (context, index) {
          final option = _currentOptions[index];
          return GestureDetector(
            onTap: () => _handleTap(option),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 200 + (index * 50)),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: _buildColorCircle(option, size: 90),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorCircle(
    ColorOption option, {
    double size = 80,
    bool showShadow = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: option.pattern == 'solid' ? option.color : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: option.color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: option.pattern != 'solid'
          ? ClipOval(
              child: CustomPaint(
                size: Size(size, size),
                painter: PatternPainter(
                  color: option.color,
                  pattern: option.pattern,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (metrics.accuracy >= 90) {
      performanceLevel = 'Excellent!';
      performanceColor = AppColors.successGreen;
      emoji = '🎯';
    } else if (metrics.accuracy >= 70) {
      performanceLevel = 'Good Job!';
      performanceColor = AppColors.primaryBlue;
      emoji = '👍';
    } else if (metrics.accuracy >= 50) {
      performanceLevel = 'Keep Practicing';
      performanceColor = AppColors.warningOrange;
      emoji = '💪';
    } else {
      performanceLevel = 'Try Again';
      performanceColor = AppColors.dangerRed;
      emoji = '🔄';
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
                  'Accuracy',
                  '${metrics.accuracy.toStringAsFixed(1)}%',
                  Icons.gps_fixed,
                  AppColors.primaryBlue,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Speed',
                  '${metrics.averageResponseTime}ms',
                  Icons.speed,
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
                  'Correct',
                  '${metrics.correctTaps}/$totalRounds',
                  Icons.check_circle,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Errors',
                  '${metrics.incorrectTaps}',
                  Icons.cancel,
                  AppColors.dangerRed,
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
                  'Fastest',
                  '${metrics.fastestResponseTime}ms',
                  Icons.bolt,
                  AppColors.warningOrange,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Slowest',
                  '${metrics.slowestResponseTime}ms',
                  Icons.hourglass_bottom,
                  AppColors.textSecondary,
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
    return SafeArea(
      top: false,
      child: Padding(
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
      ),
    );
  }
}

/// Custom painter for creating patterns on circles
class PatternPainter extends CustomPainter {
  final Color color;
  final String pattern;

  PatternPainter({required this.color, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw base circle
    canvas.drawCircle(center, radius, paint);

    if (pattern == 'dotted') {
      // Draw dots pattern
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      const dotRadius = 4.0;
      const spacing = 14.0;

      for (double x = dotRadius; x < size.width; x += spacing) {
        for (double y = dotRadius; y < size.height; y += spacing) {
          final dx = x - center.dx;
          final dy = y - center.dy;
          if (dx * dx + dy * dy < (radius - dotRadius) * (radius - dotRadius)) {
            canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
          }
        }
      }
    } else if (pattern == 'striped') {
      // Draw diagonal stripes
      final stripePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;

      for (double i = -size.width; i < size.width * 2; i += 12) {
        canvas.save();
        canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
        );
        canvas.drawLine(
          Offset(i, 0),
          Offset(i + size.height, size.height),
          stripePaint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(PatternPainter oldDelegate) =>
      color != oldDelegate.color || pattern != oldDelegate.pattern;
}
