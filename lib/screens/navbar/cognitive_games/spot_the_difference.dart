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

/// Represents an element in a scene
class SceneElement {
  final String id;
  final String content; // emoji or icon name
  final double x; // relative position 0-1
  final double y; // relative position 0-1
  final double size;
  final Color? color;
  final bool isIcon;

  const SceneElement({
    required this.id,
    required this.content,
    required this.x,
    required this.y,
    this.size = 40,
    this.color,
    this.isIcon = false,
  });

  SceneElement copyWith({
    String? content,
    double? x,
    double? y,
    double? size,
    Color? color,
  }) {
    return SceneElement(
      id: id,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
      size: size ?? this.size,
      color: color ?? this.color,
      isIcon: isIcon,
    );
  }
}

/// Represents a difference between two scenes
class SceneDifference {
  final String elementId;
  final String type; // 'missing', 'moved', 'changed', 'color'
  final dynamic originalValue;
  final dynamic newValue;

  const SceneDifference({
    required this.elementId,
    required this.type,
    this.originalValue,
    this.newValue,
  });
}

/// Represents a complete Spot the Difference scene
class SpotTheDifferenceScene {
  final String name;
  final List<SceneElement> elements;
  final List<SceneDifference> differences;
  final Color backgroundColor;

  const SpotTheDifferenceScene({
    required this.name,
    required this.elements,
    required this.differences,
    required this.backgroundColor,
  });
}

/// Metrics for tracking game performance
class SpotTheDifferenceMetrics {
  final int scenesCompleted;
  final int differencesFound;
  final int differencesMissed;
  final int incorrectTaps;
  final int hintsUsed;
  final int totalTimeMs;

  SpotTheDifferenceMetrics({
    required this.scenesCompleted,
    required this.differencesFound,
    required this.differencesMissed,
    required this.incorrectTaps,
    required this.hintsUsed,
    required this.totalTimeMs,
  });
}

class SpotTheDifferenceScreen extends StatefulWidget {
  const SpotTheDifferenceScreen({super.key});

  @override
  State<SpotTheDifferenceScreen> createState() => _SpotTheDifferenceScreenState();
}

class _SpotTheDifferenceScreenState extends State<SpotTheDifferenceScreen>
    with TickerProviderStateMixin {
  
  // Available scenes
  static final List<SpotTheDifferenceScene> _allScenes = [
    // Scene 1: Garden
    SpotTheDifferenceScene(
      name: 'Sunny Garden',
      backgroundColor: const Color(0xFFE0F2F1), // Light Teal
      elements: [
        SceneElement(id: 'tree1', content: '🌳', x: 0.1, y: 0.2, size: 80),
        SceneElement(id: 'sun', content: '☀️', x: 0.8, y: 0.1, size: 60),
        SceneElement(id: 'flower1', content: '🌻', x: 0.15, y: 0.7, size: 40),
        SceneElement(id: 'flower2', content: '🌷', x: 0.3, y: 0.75, size: 40),
        SceneElement(id: 'flower3', content: '🌹', x: 0.45, y: 0.7, size: 40),
        SceneElement(id: 'bird', content: '🐦', x: 0.25, y: 0.15, size: 30),
        SceneElement(id: 'butterfly', content: '🦋', x: 0.6, y: 0.4, size: 25),
        SceneElement(id: 'cloud1', content: '☁️', x: 0.5, y: 0.1, size: 50),
        SceneElement(id: 'bench', content: '🪑', x: 0.7, y: 0.65, size: 60),
        SceneElement(id: 'dog', content: '🐕', x: 0.8, y: 0.75, size: 40),
      ],
      differences: [
        SceneDifference(elementId: 'sun', type: 'moved', originalValue: 0.8, newValue: 0.85), // Sun moved right
        SceneDifference(elementId: 'flower2', type: 'changed', originalValue: '🌷', newValue: '🌻'), // Tulip to Sunflower
        SceneDifference(elementId: 'butterfly', type: 'missing'), // Butterfly missing
      ],
    ),
    // Scene 2: Living Room
    SpotTheDifferenceScene(
      name: 'Cozy Living Room',
      backgroundColor: const Color(0xFFFFF3E0), // Light Orange
      elements: [
        SceneElement(id: 'couch', content: '🛋️', x: 0.5, y: 0.6, size: 80),
        SceneElement(id: 'lamp', content: '💡', x: 0.15, y: 0.5, size: 60),
        SceneElement(id: 'tv', content: '📺', x: 0.5, y: 0.3, size: 60),
        SceneElement(id: 'plant', content: '🪴', x: 0.85, y: 0.6, size: 50),
        SceneElement(id: 'clock', content: '🕰️', x: 0.2, y: 0.2, size: 40),
        SceneElement(id: 'cat', content: '🐈', x: 0.6, y: 0.65, size: 35),
        SceneElement(id: 'rug', content: '🛑', x: 0.5, y: 0.8, size: 40), // Placeholder for rug
        SceneElement(id: 'picture', content: '🖼️', x: 0.8, y: 0.3, size: 45),
        SceneElement(id: 'book', content: '📚', x: 0.35, y: 0.62, size: 25),
      ],
      differences: [
        SceneDifference(elementId: 'cat', type: 'changed', originalValue: '🐈', newValue: '🐕'), // Cat to Dog
        SceneDifference(elementId: 'clock', type: 'missing'), // Clock missing
        SceneDifference(elementId: 'plant', type: 'moved', originalValue: 0.85, newValue: 0.1), // Plant moved
      ],
    ),
    // Scene 3: Space
    SpotTheDifferenceScene(
      name: 'Outer Space',
      backgroundColor: const Color(0xFF1A237E), // Deep Indigo
      elements: [
        SceneElement(id: 'earth', content: '🌍', x: 0.5, y: 0.5, size: 80),
        SceneElement(id: 'moon', content: '🌙', x: 0.2, y: 0.2, size: 40),
        SceneElement(id: 'rocket', content: '🚀', x: 0.8, y: 0.8, size: 50),
        SceneElement(id: 'star1', content: '⭐', x: 0.1, y: 0.8, size: 25),
        SceneElement(id: 'star2', content: '🌟', x: 0.9, y: 0.1, size: 30),
        SceneElement(id: 'alien', content: '👾', x: 0.3, y: 0.6, size: 35),
        SceneElement(id: 'satellite', content: '🛰️', x: 0.7, y: 0.3, size: 40),
        SceneElement(id: 'comet', content: '☄️', x: 0.4, y: 0.1, size: 45),
      ],
      differences: [
        SceneDifference(elementId: 'rocket', type: 'changed', originalValue: '🚀', newValue: '🛸'), // Rocket to UFO
        SceneDifference(elementId: 'star1', type: 'changed', originalValue: '⭐', newValue: '❤️'), // Star to heart
        SceneDifference(elementId: 'alien', type: 'missing'), // Alien missing
      ],
    ),
  ];

  // Game state
  List<SpotTheDifferenceScene> _sessionScenes = [];
  int _currentSceneIndex = 0;
  bool _showingCountdown = true;
  bool _showingInstructions = true;
  int _countdownValue = 3;
  bool _gameEnded = false;
  
  // Current scene state
  final Set<String> _foundDifferenceIds = {};
  int _hintsUsedInScene = 0;
  
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _elapsedMs = 0;
  DateTime? _sceneStartTime;
  bool _resultsSaved = false;

  // Metrics
  int _totalDifferencesFound = 0;
  int _totalIncorrectTaps = 0;
  int _totalHintsUsed = 0;

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
    _sessionScenes = List.from(_allScenes);
    // Shuffle if we had more
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
      _sceneStartTime = DateTime.now();
    });

    _fadeController.forward();

    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedMs += 100;
        
        // Auto-skip after 90 seconds
        final sceneElapsed = DateTime.now().difference(_sceneStartTime!).inSeconds;
        if (sceneElapsed >= 90) {
          _moveToNextScene();
        }
      });
    });
  }

  void _handleSceneTap(TapUpDetails details, BoxConstraints constraints, bool isTopImage) {
    if (_gameEnded) return;

    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;

    final scene = _sessionScenes[_currentSceneIndex];
    
    // Check if tap hits a difference
    bool hitDifference = false;
    
    for (final diff in scene.differences) {
      if (_foundDifferenceIds.contains(diff.elementId)) continue;
      
      // Get element position (safely handle missing elements)
      final element = scene.elements.cast<SceneElement?>().firstWhere(
        (e) => e?.id == diff.elementId,
        orElse: () => null,
      );
      if (element == null) {
        debugPrint('Warning: Element not found for diff elementId: ${diff.elementId}');
        continue;
      }
      
      // If moved, check based on which image (top/bottom)
      double targetX = element.x;
      double targetY = element.y;
      
      if (!isTopImage && diff.type == 'moved') {
        targetX = diff.newValue is double ? diff.newValue : targetX;
      }
      
      // Hit detection (simple radius check)
      // Convert size to relative 

      
      final distance = sqrt(pow(x - targetX, 2) + pow(y - targetY, 2));
      
      // Generous hit box
      if (distance < 0.15) { // ~15% of screen width
        setState(() {
          _foundDifferenceIds.add(diff.elementId);
          _totalDifferencesFound++;
          hitDifference = true;
        });
        
        // Check if all found
        if (_foundDifferenceIds.length == scene.differences.length) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _moveToNextScene();
          });
        }
        break;
      }
    }
    
    if (!hitDifference) {
      setState(() {
        _totalIncorrectTaps++;
      });
    }
  }

  void _useHint() {
    if (_hintsUsedInScene >= 2) return;
    
    final scene = _sessionScenes[_currentSceneIndex];
    final unfound = scene.differences.where((d) => !_foundDifferenceIds.contains(d.elementId)).toList();
    
    if (unfound.isEmpty) return;
    
    setState(() {
      _totalHintsUsed++;
      _hintsUsedInScene++;
      
      // Reveal the first unfound difference
      _foundDifferenceIds.add(unfound.first.elementId);
      _totalDifferencesFound++;
      
      if (_foundDifferenceIds.length == scene.differences.length) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _moveToNextScene();
        });
      }
    });
  }

  void _moveToNextScene() {
    if (_currentSceneIndex < _sessionScenes.length - 1) {
      setState(() {
        _currentSceneIndex++;
        _foundDifferenceIds.clear();
        _hintsUsedInScene = 0;
        _sceneStartTime = DateTime.now();
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
    final score = GameResult.calculateSpotTheDifferenceScore(
      foundedDifferences: metrics.differencesFound,
      totalDifferences: 3 * 3, // 3 scenes * 3 diffs
      hintsUsed: metrics.hintsUsed,
      incorrectTaps: metrics.incorrectTaps,
    );

    final result = GameResult(
      id: '',
      gameType: 'spot_the_difference',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'scenesCompleted': metrics.scenesCompleted,
        'differencesFound': metrics.differencesFound,
        'incorrectTaps': metrics.incorrectTaps,
        'hintsUsed': metrics.hintsUsed,
        'totalTimeMs': metrics.totalTimeMs,
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
            gameType: 'spot_the_difference',
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

  SpotTheDifferenceMetrics _getMetrics() {
    int totalDifferences = 0;
    for (var scene in _sessionScenes) {
      totalDifferences += scene.differences.length;
    }
    
    // If not all scenes completed, calculate handled diffs
    // Simplified: Just use totals tracked
    
    return SpotTheDifferenceMetrics(
      scenesCompleted: _currentSceneIndex + (_gameEnded ? 1 : 0),
      differencesFound: _totalDifferencesFound,
      differencesMissed: totalDifferences - _totalDifferencesFound,
      incorrectTaps: _totalIncorrectTaps,
      hintsUsed: _totalHintsUsed,
      totalTimeMs: _elapsedMs,
    );
  }

  void _restartGame() {
    _gameTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _currentSceneIndex = 0;
      _showingCountdown = true;
      _showingInstructions = true;
      _countdownValue = 3;
      _gameEnded = false;
      _foundDifferenceIds.clear();
      _hintsUsedInScene = 0;
      _elapsedMs = 0;
      _totalDifferencesFound = 0;
      _totalIncorrectTaps = 0;
      _totalHintsUsed = 0;
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
      backgroundColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
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
            if (!_showingInstructions && !_showingCountdown && !_gameEnded) _buildControls(isDarkMode),
            if (!_showingInstructions) _buildExitButton(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    final scene = _currentSceneIndex < _sessionScenes.length ? _sessionScenes[_currentSceneIndex] : null;
    final foundCount = _foundDifferenceIds.length;
    final totalCount = scene?.differences.length ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPOT THE DIFFERENCE',
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
                    : 'Image ${_currentSceneIndex + 1} of ${_sessionScenes.length}',
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
                  color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: AppColors.primaryBlue),
                  const SizedBox(width: 6),
                  Text(
                    '$foundCount / $totalCount',
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
                const Text('👀', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'Find the differences between the two pictures!',
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
                // Instruction visual
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Top', style: TextStyle(fontSize: 12)),
                          const Text('🍎', style: TextStyle(fontSize: 32)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.compare_arrows, color: Colors.grey),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Bottom', style: TextStyle(fontSize: 12)),
                          const Text('🍏', style: TextStyle(fontSize: 32)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap on the bottom picture where it looks different!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
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
    final scene = _sessionScenes[_currentSceneIndex];

    return FadeTransition(
      opacity: _fadeAnimation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate height for each image half
          final imageH = constraints.maxHeight * 0.45;
          final w = constraints.maxWidth * 0.9;
          
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Top Image (Original)
              _buildSceneImage(
                scene, 
                w, 
                imageH, 
                isTop: true,
                isDarkMode: isDarkMode,
              ),
              
              const SizedBox(height: 8),
              
              // Divider
              Container(
                height: 2,
                width: w,
                color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
              ),
              
              const SizedBox(height: 8),
              
              // Bottom Image (Modified - Tappable)
              _buildSceneImage(
                scene, 
                w, 
                imageH, 
                isTop: false,
                isDarkMode: isDarkMode,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSceneImage(SpotTheDifferenceScene scene, double width, double height, {required bool isTop, required bool isDarkMode}) {
    return GestureDetector(
      onTapUp: (details) => _handleSceneTap(details, BoxConstraints(maxWidth: width, maxHeight: height), isTop),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scene.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            ...scene.elements.map((element) {
              // Determine if this element is modified
              final diff = scene.differences.firstWhere(
                (d) => d.elementId == element.id, 
                orElse: () => const SceneDifference(elementId: '', type: 'none'),
              );
              
              if (diff.type == 'none') {
                // Normal element
                return Positioned(
                  left: element.x * width,
                  top: element.y * height,
                  child: Text(
                    element.content, 
                    style: TextStyle(fontSize: element.size),
                  ),
                );
              }
              
              // Diff element
              if (isTop) {
                // Top image shows original unless type is ... well original is always original
                return Positioned(
                  left: element.x * width,
                  top: element.y * height,
                  child: Text(
                    element.content, 
                    style: TextStyle(fontSize: element.size),
                  ),
                );
              } else {
                // Bottom image shows modifications
                if (diff.type == 'missing') {
                  return const SizedBox.shrink(); // Element is gone
                } else if (diff.type == 'moved') {
                  double newX = diff.newValue is double ? diff.newValue : element.x;
                  return Positioned(
                    left: newX * width,
                    top: element.y * height,
                    child: Text(
                      element.content, 
                      style: TextStyle(fontSize: element.size),
                    ),
                  );
                } else if (diff.type == 'changed') {
                  String newContent = diff.newValue is String ? diff.newValue : element.content;
                  return Positioned(
                    left: element.x * width,
                    top: element.y * height,
                    child: Text(
                      newContent, 
                      style: TextStyle(fontSize: element.size),
                    ),
                  );
                }
                 else if (diff.type == 'color') {
                   // Can't change emoji color easily, ignore for simplistic v1
                   return Positioned(
                    left: element.x * width,
                    top: element.y * height,
                    child: Text(
                      element.content, 
                      style: TextStyle(fontSize: element.size),
                    ),
                  );
                 }
                return const SizedBox.shrink();
              }
            }),
            
            // Markers for found differences
            ...scene.differences.map((diff) {
              if (_foundDifferenceIds.contains(diff.elementId)) {
                // Get element position (use top image logic as reference point mostly)
                final element = scene.elements.cast<SceneElement?>().firstWhere(
                  (e) => e?.id == diff.elementId,
                  orElse: () => null,
                );
                if (element == null) {
                  return const SizedBox.shrink();
                }
                
                // For moved items on bottom, we circle the NEW position
                double x = element.x;
                double y = element.y;
                
                if (!isTop && diff.type == 'moved') {
                  x = diff.newValue is double ? diff.newValue : x;
                }
                
                return Positioned(
                  left: x * width - 5, // offset purely visual adjustment
                  top: y * height - 5,
                  child: Container(
                    width: element.size + 10,
                    height: element.size + 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.successGreen, width: 3),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControls(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Hint Button
          ElevatedButton.icon(
            onPressed: _hintsUsedInScene < 2 ? _useHint : null,
            icon: const Icon(Icons.lightbulb_outline),
            label: Text('Hint (${2 - _hintsUsedInScene})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warningOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size(0, 48), // Fix: Allow shrinking within Row
            ),
          ),
          
          // Skip Button
          TextButton(
            onPressed: () {
              final elapsed = DateTime.now().difference(_sceneStartTime!).inSeconds;
              // Can only skip after 10 seconds to prevent accidental
              if (elapsed > 5) {
                _moveToNextScene();
              }
            },
            child: Text(
              'Skip',
              style: TextStyle(
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();
    final foundCount = metrics.differencesFound;
    final totalDiffs = _allScenes.fold<int>(0, (sum, scene) => sum + scene.differences.length); // Simplified total
    final percent = (foundCount / totalDiffs * 100).clamp(0, 100);

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (percent >= 80) {
      performanceLevel = 'Eagle Eye!';
      performanceColor = AppColors.successGreen;
      emoji = '🦅';
    } else if (percent >= 50) {
      performanceLevel = 'Sharp Observer!';
      performanceColor = AppColors.primaryBlue;
      emoji = '👀';
    } else {
      performanceLevel = 'Good Practice!';
      performanceColor = AppColors.warningOrange;
      emoji = '👓';
    }

    int stars = percent >= 80 ? 3 : (percent >= 50 ? 2 : 1);

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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '$foundCount',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.successGreen,
                      ),
                    ),
                    Text(
                      'Found',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${metrics.hintsUsed}',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warningOrange,
                      ),
                    ),
                    Text(
                      'Hints',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${metrics.incorrectTaps}',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dangerRed,
                      ),
                    ),
                    Text(
                      'Misses',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
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
