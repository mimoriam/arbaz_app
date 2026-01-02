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

/// Model for tracking Word Jumble game metrics
class WordJumbleMetrics {
  final int wordsPresented;
  final int wordsSolved;
  final int wordsSkipped;
  final int hintsUsed;
  final List<int> solveTimes; // Time per word in milliseconds
  final int letterMistakes;
  final int totalDurationMs;
  final int difficultyLevel;

  WordJumbleMetrics({
    required this.wordsPresented,
    required this.wordsSolved,
    required this.wordsSkipped,
    required this.hintsUsed,
    required this.solveTimes,
    required this.letterMistakes,
    required this.totalDurationMs,
    required this.difficultyLevel,
  });

  int get averageSolveTime => solveTimes.isNotEmpty
      ? (solveTimes.reduce((a, b) => a + b) / solveTimes.length).round()
      : 0;

  double get successRate => wordsPresented > 0
      ? (wordsSolved / wordsPresented * 100)
      : 0;
}

/// Represents a word puzzle
class WordPuzzle {
  final String word;
  final String category;
  final List<String> scrambledLetters;

  WordPuzzle({
    required this.word,
    required this.category,
    required this.scrambledLetters,
  });
}

/// Word lists organized by category and difficulty
class WordLists {
  static const Map<int, Map<String, List<String>>> byDifficulty = {
    // Level 1: 3-letter words
    1: {
      'Animals': ['CAT', 'DOG', 'PIG', 'COW', 'ANT', 'BEE', 'OWL', 'BAT', 'HEN', 'FOX'],
      'Food': ['PIE', 'JAM', 'EGG', 'HAM', 'NUT', 'PEA', 'TEA', 'ICE'],
      'Things': ['CUP', 'HAT', 'BED', 'BOX', 'KEY', 'PEN', 'BAG', 'TOY', 'SUN', 'MAP'],
    },
    // Level 2: 4-letter words
    2: {
      'Animals': ['BIRD', 'FISH', 'FROG', 'DUCK', 'BEAR', 'DEER', 'LION', 'WOLF'],
      'Food': ['CAKE', 'MILK', 'RICE', 'SOUP', 'MEAT', 'CORN', 'PLUM', 'BEAN'],
      'Things': ['BOOK', 'DOOR', 'LAMP', 'SHOE', 'TREE', 'RAIN', 'STAR', 'BELL'],
    },
    // Level 3: 5-letter words
    3: {
      'Animals': ['HORSE', 'SHEEP', 'MOUSE', 'TIGER', 'SNAKE', 'EAGLE', 'WHALE', 'ZEBRA'],
      'Food': ['BREAD', 'APPLE', 'GRAPE', 'PIZZA', 'SALAD', 'HONEY', 'LEMON', 'PEACH'],
      'Things': ['CHAIR', 'TABLE', 'CLOCK', 'PHONE', 'GLASS', 'WATER', 'HOUSE', 'CLOUD'],
    },
    // Level 4: 6-letter words (removed duplicates from Level 3)
    4: {
      'Animals': ['RABBIT', 'MONKEY', 'KITTEN', 'TURTLE', 'PARROT', 'DONKEY', 'BADGER'],
      'Food': ['BANANA', 'ORANGE', 'CARROT', 'BUTTER', 'CHEESE', 'TOMATO', 'PEPPER'],
      'Things': ['WINDOW', 'GARDEN', 'FLOWER', 'CANDLE', 'MIRROR', 'PILLOW', 'BOTTLE'],
    },
    // Level 5: 6-7 letter words
    5: {
      'Animals': ['CHICKEN', 'DOLPHIN', 'PENGUIN', 'GIRAFFE', 'HAMSTER', 'LOBSTER'],
      'Food': ['COOKIES', 'POPCORN', 'SPINACH', 'PUMPKIN', 'LETTUCE', 'BISCUIT'],
      'Things': ['KITCHEN', 'BEDROOM', 'RAINBOW', 'BLANKET', 'PICTURE', 'CEILING'],
    },
  };
}

class WordJumbleScreen extends StatefulWidget {
  final int difficultyLevel;
  
  const WordJumbleScreen({super.key, this.difficultyLevel = 1});

  @override
  State<WordJumbleScreen> createState() => _WordJumbleScreenState();
}

class _WordJumbleScreenState extends State<WordJumbleScreen>
    with TickerProviderStateMixin {
  // Game configuration
  static const int totalWords = 5;
  static const int maxHints = 3;
  static const int gameDurationSeconds = 60;

  // Game state
  WordPuzzle? _currentPuzzle;
  int _currentWordIndex = 0;
  List<String> _availableLetters = [];
  List<String?> _answerSlots = [];
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _showingCountdown = true;
  int _countdownValue = 3;
  Timer? _countdownTimer;
  Timer? _gameTimer;
  int _remainingSeconds = gameDurationSeconds;
  DateTime? _wordStartTime;
  DateTime? _gameStartTime;
  int _hintsRemaining = maxHints;

  // Feedback state
  bool _showingSuccess = false;
  String _feedbackMessage = '';

  // Metrics tracking
  int _wordsSolved = 0;
  int _wordsSkipped = 0;
  int _hintsUsed = 0;
  int _letterMistakes = 0;
  List<int> _solveTimes = [];

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _successController;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    debugPrint('WordJumble: initState');
    _initAnimations();
    _startCountdown();
  }

  void _initAnimations() {
    debugPrint('WordJumble: initAnimations');
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      debugPrint('WordJumble: Countdown $_countdownValue');
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
    debugPrint('WordJumble: _startGame called');
    if (!mounted) return;
    setState(() {
      _showingCountdown = false;
      _gameStarted = true;
      _gameStartTime = DateTime.now();
    });
    debugPrint('WordJumble: Starting fade animation');
    _fadeController.forward();
    debugPrint('WordJumble: Starting game timer');
    _startGameTimer();
    debugPrint('WordJumble: Generating first puzzle');
    // Delay puzzle generation to next frame to allow UI rebuild to complete
    // This prevents the freeze caused by multiple setState calls blocking rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_gameEnded) {
        _nextWord();
      }
    });
  }

  void _startGameTimer() {
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        // ... kept existing logic ...
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

  void _nextWord() {
    debugPrint('WordJumble: _nextWord');
    if (!mounted || _gameEnded) return;

    if (_currentWordIndex >= totalWords) {
      _endGame();
      return;
    }

    final puzzle = _generatePuzzle();
    debugPrint('WordJumble: Puzzle generated: ${puzzle.word}');
    
    setState(() {
      _currentPuzzle = puzzle;
      _currentWordIndex++;
      _availableLetters = List.from(puzzle.scrambledLetters);
      _answerSlots = List.filled(puzzle.word.length, null);
      _wordStartTime = DateTime.now();
      _showingSuccess = false;
      _feedbackMessage = '';
    });
  }

  WordPuzzle _generatePuzzle() {
    debugPrint('WordJumble: _generatePuzzle start');
    final level = widget.difficultyLevel.clamp(1, 5);
    final wordLists = WordLists.byDifficulty[level]!;
    
    // Select random category
    final categories = wordLists.keys.toList();
    final category = categories[_random.nextInt(categories.length)];
    
    // Select random word from category
    final words = wordLists[category]!;
    final word = words[_random.nextInt(words.length)];
    debugPrint('WordJumble: Selected word: $word');
    
    // Scramble the letters using Fisher-Yates with early exit optimization
    // For short words (<=2 chars), we may not be able to scramble differently
    List<String> scrambled = word.split('');
    
    // Only attempt scrambling if word length > 2 (otherwise no guarantees)
    if (word.length > 2) {
      int attempts = 0;
      const maxAttempts = 10; // Reduced from 100 - most words scramble in 1-2 tries
      do {
        scrambled.shuffle(_random);
        attempts++;
      } while (scrambled.join() == word && attempts < maxAttempts);
      debugPrint('WordJumble: Scrambled in $attempts attempts');
    } else {
      scrambled.shuffle(_random);
      debugPrint('WordJumble: Short word, single shuffle');
    }
    
    return WordPuzzle(
      word: word,
      category: category,
      scrambledLetters: scrambled,
    );
  }

  void _handleLetterTap(int index) {
    if (_showingSuccess || _gameEnded || _currentPuzzle == null) return;
    if (index < 0 || index >= _availableLetters.length) return;
    
    final letter = _availableLetters[index];
    if (letter.isEmpty) return; // Already used

    // Find first empty slot in answer
    final emptySlot = _answerSlots.indexWhere((slot) => slot == null);
    if (emptySlot == -1) return; // No empty slots

    setState(() {
      _answerSlots[emptySlot] = letter;
      _availableLetters[index] = ''; // Mark as used
    });

    HapticFeedback.lightImpact();

    // Check if word is complete
    if (!_answerSlots.contains(null)) {
      _checkWord();
    }
  }

  void _handleAnswerTap(int index) {
    if (_showingSuccess || _gameEnded) return;
    if (index < 0 || index >= _answerSlots.length) return;
    
    final letter = _answerSlots[index];
    if (letter == null) return; // Empty slot

    // Find first empty spot in available letters and return the letter
    final emptySpot = _availableLetters.indexWhere((l) => l.isEmpty);
    if (emptySpot != -1) {
      setState(() {
        _availableLetters[emptySpot] = letter;
        _answerSlots[index] = null;
      });
    }

    HapticFeedback.lightImpact();
  }

  void _checkWord() {
    if (_currentPuzzle == null) return;
    
    final userWord = _answerSlots.join();
    
    if (userWord == _currentPuzzle!.word) {
      // Correct!
      final solveTime = _wordStartTime != null
          ? DateTime.now().difference(_wordStartTime!).inMilliseconds
          : 0;
      if (solveTime > 0) {
        _solveTimes.add(solveTime);
      }
      
      setState(() {
        _wordsSolved++;
        _showingSuccess = true;
        _feedbackMessage = 'Perfect! 🎉';
      });
      
      _successController.forward().then((_) {
        if (mounted) _successController.reset();
      });
      
      HapticFeedback.mediumImpact();
      
      // Move to next word after brief celebration
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_gameEnded) {
          _nextWord();
        }
      });
    } else {
      // Incorrect - the word doesn't match
      // Since auto-check happens only when all slots are filled,
      // we should give feedback that it's wrong
      setState(() {
        _letterMistakes++;
        _feedbackMessage = 'Not quite, try again!';
      });
      
      HapticFeedback.heavyImpact();
      
      // Clear feedback after a moment
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _feedbackMessage = '';
          });
        }
      });
    }
  }

  void _handleClear() {
    if (_showingSuccess || _gameEnded || _currentPuzzle == null) return;
    
    setState(() {
      _availableLetters = List.from(_currentPuzzle!.scrambledLetters);
      _answerSlots = List.filled(_currentPuzzle!.word.length, null);
      _feedbackMessage = '';
    });
    
    HapticFeedback.lightImpact();
  }

  void _handleHint() {
    if (_showingSuccess || _gameEnded || _currentPuzzle == null) return;
    if (_hintsRemaining <= 0) return;
    
    // Find first empty slot
    final emptySlot = _answerSlots.indexWhere((slot) => slot == null);
    if (emptySlot == -1) return;
    
    // Get the correct letter for this position
    final correctLetter = _currentPuzzle!.word[emptySlot];
    
    // Find this letter in available letters
    final letterIndex = _availableLetters.indexWhere((l) => l == correctLetter);
    if (letterIndex == -1) return;
    
    setState(() {
      _answerSlots[emptySlot] = correctLetter;
      _availableLetters[letterIndex] = '';
      _hintsUsed++;
      _hintsRemaining--;
    });
    
    HapticFeedback.lightImpact();
    
    // Check if word is now complete
    if (!_answerSlots.contains(null)) {
      _checkWord();
    }
  }

  void _handleSkip() {
    if (_showingSuccess || _gameEnded) return;
    
    setState(() {
      _wordsSkipped++;
    });
    
    _nextWord();
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
    if (_currentWordIndex == 0) return 0;
    
    final wordsAttempted = _wordsSolved + _wordsSkipped;
    if (wordsAttempted == 0) return 0;
    
    // Words solved 60%, speed 25%, hint penalty 15%
    final solveRate = _wordsSolved / totalWords * 100;
    final avgTime = _solveTimes.isNotEmpty
        ? _solveTimes.reduce((a, b) => a + b) / _solveTimes.length
        : 30000;
    final speedScore = ((30000 - avgTime) / 300).clamp(0, 100);
    final hintPenalty = (_hintsUsed * 10).clamp(0, 30);
    
    return ((solveRate * 0.6) + (speedScore * 0.25) - hintPenalty).round().clamp(0, 100);
  }

  Future<void> _saveGameResult() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final metrics = _getMetrics();
    final score = _calculateScore();

    final result = GameResult(
      id: '',
      gameType: 'word_jumble',
      timestamp: DateTime.now(),
      score: score,
      metrics: {
        'wordsPresented': metrics.wordsPresented,
        'wordsSolved': metrics.wordsSolved,
        'wordsSkipped': metrics.wordsSkipped,
        'hintsUsed': metrics.hintsUsed,
        'averageSolveTimeMs': metrics.averageSolveTime,
        'letterMistakes': metrics.letterMistakes,
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
            gameType: 'word_jumble', // Standardized: snake_case for all game types
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

  WordJumbleMetrics _getMetrics() {
    final totalDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inMilliseconds
        : 0;

    return WordJumbleMetrics(
      wordsPresented: _currentWordIndex,
      wordsSolved: _wordsSolved,
      wordsSkipped: _wordsSkipped,
      hintsUsed: _hintsUsed,
      solveTimes: _solveTimes,
      letterMistakes: _letterMistakes,
      totalDurationMs: totalDuration,
      difficultyLevel: widget.difficultyLevel.clamp(1, 5),
    );
  }

  void _restartGame() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();

    setState(() {
      _currentPuzzle = null;
      _currentWordIndex = 0;
      _availableLetters = [];
      _answerSlots = [];
      _gameStarted = false;
      _gameEnded = false;
      _showingCountdown = true;
      _countdownValue = 3;
      _remainingSeconds = gameDurationSeconds;
      _hintsRemaining = maxHints;
      _showingSuccess = false;
      _feedbackMessage = '';
      _wordsSolved = 0;
      _wordsSkipped = 0;
      _hintsUsed = 0;
      _letterMistakes = 0;
      _solveTimes = [];
    });

    _fadeController.reset();
    _successController.reset();
    _startCountdown();
  }

  /// Flag to prevent double-saving (once in dispose, once in endGame)
  bool _resultsSaved = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();
    // Save results if game was started but not ended normally (user pressed back)
    if (_gameStarted && !_gameEnded && !_resultsSaved && _currentWordIndex > 0) {
      _resultsSaved = true;
      _saveGameResult(); // Fire-and-forget - we're disposing anyway
    }
    _fadeController.dispose();
    _successController.dispose();
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
                'WORD',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_currentWordIndex of $totalWords',
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
    if (_currentPuzzle == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Category hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Category: ${_currentPuzzle!.category}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Scrambled letters
            _buildScrambledLetters(isDarkMode),
            const SizedBox(height: 32),
            // Answer slots
            _buildAnswerSlots(isDarkMode),
            const SizedBox(height: 16),
            // Feedback message
            if (_feedbackMessage.isNotEmpty)
              AnimatedOpacity(
                opacity: _feedbackMessage.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _feedbackMessage,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _showingSuccess
                        ? AppColors.successGreen
                        : AppColors.warningOrange,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            // Helper buttons
            _buildHelperButtons(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildScrambledLetters(bool isDarkMode) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: _availableLetters.asMap().entries.map((entry) {
        final index = entry.key;
        final letter = entry.value;
        final isEmpty = letter.isEmpty;

        return GestureDetector(
          onTap: isEmpty ? null : () => _handleLetterTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isEmpty
                  ? (isDarkMode ? AppColors.surfaceDark : Colors.grey[100])
                  : AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isEmpty
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                letter,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isEmpty
                      ? Colors.transparent
                      : Colors.white,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAnswerSlots(bool isDarkMode) {
    return Column(
      children: [
        Text(
          'Your word:',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _answerSlots.asMap().entries.map((entry) {
            final index = entry.key;
            final letter = entry.value;
            final isEmpty = letter == null;

            return GestureDetector(
              onTap: isEmpty ? null : () => _handleAnswerTap(index),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isEmpty
                      ? (isDarkMode ? AppColors.surfaceDark : Colors.white)
                      : (_showingSuccess
                          ? AppColors.successGreen
                          : AppColors.primaryBlue.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEmpty
                        ? (isDarkMode ? AppColors.borderDark : AppColors.borderLight)
                        : (_showingSuccess
                            ? AppColors.successGreen
                            : AppColors.primaryBlue),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    letter ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: isEmpty
                          ? Colors.transparent
                          : (_showingSuccess
                              ? Colors.white
                              : AppColors.primaryBlue),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHelperButtons(bool isDarkMode) {
    // Using Wrap instead of Row to handle unbounded constraints from SingleChildScrollView
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        // Clear button
        OutlinedButton.icon(
          onPressed: _handleClear,
          icon: const Icon(Icons.refresh, size: 20),
          label: Text(
            'Clear',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(
              color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
        ),
        // Hint button
        ElevatedButton.icon(
          onPressed: _hintsRemaining > 0 ? _handleHint : null,
          icon: const Icon(Icons.lightbulb_outline, size: 20),
          label: Text(
            'Hint ($_hintsRemaining)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _hintsRemaining > 0
                ? AppColors.warningOrange
                : Colors.grey,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
        // Skip button
        TextButton(
          onPressed: _handleSkip,
          child: Text(
            'Skip',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsScreen(bool isDarkMode) {
    final metrics = _getMetrics();

    String performanceLevel;
    Color performanceColor;
    String emoji;

    if (metrics.successRate >= 80) {
      performanceLevel = 'Word Master!';
      performanceColor = AppColors.successGreen;
      emoji = '📚';
    } else if (metrics.successRate >= 60) {
      performanceLevel = 'Great Vocabulary!';
      performanceColor = AppColors.primaryBlue;
      emoji = '⭐';
    } else if (metrics.successRate >= 40) {
      performanceLevel = 'Excellent!';
      performanceColor = AppColors.warningOrange;
      emoji = '👍';
    } else {
      performanceLevel = 'Keep Practicing!';
      performanceColor = AppColors.dangerRed;
      emoji = '💪';
    }

    // Calculate stars
    final stars = metrics.successRate >= 80 ? 3 : (metrics.successRate >= 50 ? 2 : 1);

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
                  '${metrics.wordsSolved} out of ${metrics.wordsPresented} words solved',
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
                  'Solved',
                  '${metrics.wordsSolved}/$totalWords',
                  Icons.check_circle,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Time',
                  metrics.averageSolveTime > 0
                      ? '${(metrics.averageSolveTime / 1000).toStringAsFixed(1)}s'
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
                  'Hints Used',
                  '${metrics.hintsUsed}',
                  Icons.lightbulb_outline,
                  AppColors.warningOrange,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Skipped',
                  '${metrics.wordsSkipped}',
                  Icons.skip_next,
                  AppColors.textSecondary,
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
