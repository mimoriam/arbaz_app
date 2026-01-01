import 'dart:async';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/checkin_model.dart';
import 'package:arbaz_app/models/activity_log.dart';
import 'package:arbaz_app/providers/games_provider.dart';

/// Data class to hold check-in responses
class CheckInResponse {
  String? sleep;
  String? energy;
  String? mood;
  String? medication;
  bool? wantsBrainExercise;
  String? voiceNoteText;

  CheckInResponse();
}

/// The senior check-in flow that appears after pressing "I'm Safe"
class SeniorCheckInFlow extends StatefulWidget {
  final String userName;
  final int currentStreak;
  final VoidCallback onComplete;

  const SeniorCheckInFlow({
    super.key,
    required this.userName,
    required this.currentStreak,
    required this.onComplete,
  });

  @override
  State<SeniorCheckInFlow> createState() => _SeniorCheckInFlowState();
}

class _SeniorCheckInFlowState extends State<SeniorCheckInFlow>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  final int _totalSteps = 4; // Sleep, Energy, Mood, Medication
  final CheckInResponse _response = CheckInResponse();
  bool _showBrainExercise = false;
  bool _showSuccess = false;
  bool _transitionInProgress = false;
  bool _isPersisting = false; // Loading state while saving check-in

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    // Capture provider before async gap
    final gamesProvider = context.read<GamesProvider>();

    await _animationController.reverse();

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      // Check if games are enabled before showing brain exercise prompt
      if (gamesProvider.isEnabled) {
        setState(() => _showBrainExercise = true);
      } else {
        // Show loading state while persisting
        setState(() => _isPersisting = true);

        try {
          await _persistCheckIn();
          // Notify home screen immediately after successful persist
          widget.onComplete();
          if (mounted) {
            setState(() {
              _isPersisting = false;
              _showSuccess = true;
            });
          }
        } catch (e) {
          debugPrint('Error in check-in flow: $e');
          if (mounted) {
            setState(() => _isPersisting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save check-in. Please try again.'),
                backgroundColor: AppColors.dangerRed,
              ),
            );
            // Revert to last step on failure
            return;
          }
        }
      }
    }

    _animationController.forward();
  }

  void _previousStep() async {
    if (_currentStep > 0) {
      await _animationController.reverse();
      setState(() {
        _currentStep--;
      });
      _animationController.forward();
    } else {
      Navigator.pop(context);
    }
  }

  void _skipQuestion() {
    _nextStep();
  }

  Future<void> _onBrainExerciseDecided(bool wantsToPlay) async {
    _response.wantsBrainExercise = wantsToPlay;
    await _animationController.reverse();

    // Show loading state while persisting
    if (mounted) {
      setState(() {
        _showBrainExercise = false;
        _isPersisting = true;
      });
    }

    try {
      await _persistCheckIn();
      // Notify home screen immediately after successful persist
      widget.onComplete();
      if (mounted) {
        setState(() {
          _isPersisting = false;
          _showSuccess = true;
        });
      }
    } catch (e) {
      debugPrint('Error in check-in flow after brain exercise: $e');
      if (mounted) {
        setState(() {
          _isPersisting = false;
          _showBrainExercise =
              true; // Revert to brain exercise screen on failure
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save check-in. Please try again.'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }

    _animationController.forward();
  }

  /// Persists check-in data to Firestore with retry logic.
  /// Uses linear backoff to handle transient network failures.
  /// Throws an exception only after all retries are exhausted.
  Future<void> _persistCheckIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    // Capture services synchronously before any async operations
    final locationService = context.read<LocationService>();
    final firestoreService = context.read<FirestoreService>();

    Position? position;
    try {
      position = await locationService.getCurrentLocation().timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      debugPrint('Location request timed out');
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }

    String? address;
    if (position != null) {
      try {
        address = await locationService
            .getAddressFromPosition(position)
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        debugPrint('Address lookup timed out');
      } catch (e) {
        debugPrint('Error getting address from position: $e');
      }
    }

    // Get scheduled check-in count for accurate success rate tracking
    int scheduledCount = 1; // Default fallback
    try {
      final seniorState = await firestoreService.getSeniorState(user.uid);
      if (seniorState != null && seniorState.checkInSchedules.isNotEmpty) {
        scheduledCount = seniorState.checkInSchedules.length;
      }
    } catch (e) {
      debugPrint('Error fetching scheduled count: $e');
      // Use default of 1 if we can't get schedule
    }

    final record = CheckInRecord(
      id: '', // Generated by Firestore
      userId: user.uid,
      timestamp: DateTime.now(),
      sleep: _response.sleep,
      energy: _response.energy,
      mood: _response.mood,
      medication: _response.medication,
      brainExerciseCompleted: _response.wantsBrainExercise ?? false,
      latitude: position?.latitude,
      longitude: position?.longitude,
      locationAddress: address,
      scheduledCount: scheduledCount,
    );

    // Retry logic with exponential backoff
    const maxAttempts = 3;
    var attempt = 0;

    while (attempt < maxAttempts) {
      try {
        await firestoreService.recordCheckIn(user.uid, record);
        
        // Log the check-in activity for the family dashboard
        try {
          final activityLog = ActivityLog.checkIn(
            seniorId: user.uid,
            timestamp: record.timestamp,
            mood: _response.mood,
            sleep: _response.sleep,
            energy: _response.energy,
            brainExerciseCompleted: _response.wantsBrainExercise,
          );
          await firestoreService.logActivity(user.uid, activityLog);
        } catch (e) {
          // Don't fail the check-in if activity logging fails
          debugPrint('Activity logging failed (non-critical): $e');
        }
        
        return; // Success!
      } catch (e) {
        attempt++;
        debugPrint('Check-in attempt $attempt failed: $e');

        if (attempt >= maxAttempts) {
          // All retries exhausted - propagate the error
          throw Exception('Check-in failed after $maxAttempts attempts: $e');
        }

        // Linear backoff: 2s, 4s
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// Called when tapping BACK HOME - just navigates back
  /// onComplete callback was already called when check-in was persisted
  void _onComplete() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: _isPersisting
            ? _buildLoadingScreen(isDarkMode)
            : _showSuccess
            ? _buildSuccessScreen(isDarkMode)
            : _showBrainExercise
            ? _buildBrainExerciseScreen(isDarkMode)
            : _buildQuestionScreen(isDarkMode),
      ),
    );
  }

  Widget _buildLoadingScreen(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryBlue,
            strokeWidth: 3,
          ),
          const SizedBox(height: 24),
          Text(
            'Saving your check-in...',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionScreen(bool isDarkMode) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          children: [
            // Header with progress
            _buildHeader(isDarkMode),

            // Question Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    _buildCurrentQuestion(isDarkMode),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Skip Button
            _buildSkipButton(isDarkMode),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // Back Button
          GestureDetector(
            onTap: _previousStep,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                ),
              ),
              child: Icon(
                Icons.chevron_left,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 24,
              ),
            ),
          ),

          // Progress Indicators
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalSteps, (index) {
                final isActive = index <= _currentStep;
                final isCurrent = index == _currentStep;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isCurrent ? 32 : 24,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: isActive
                        ? AppColors.primaryBlue
                        : (isDarkMode
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                  ),
                );
              }),
            ),
          ),

          // Close Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                ),
              ),
              child: Icon(
                Icons.close,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentQuestion(bool isDarkMode) {
    switch (_currentStep) {
      case 0:
        return _buildSleepQuestion(isDarkMode);
      case 1:
        return _buildEnergyQuestion(isDarkMode);
      case 2:
        return _buildMoodQuestion(isDarkMode);
      case 3:
        return _buildMedicationQuestion(isDarkMode);
      default:
        return const SizedBox();
    }
  }

  Widget _buildSleepQuestion(bool isDarkMode) {
    return Column(
      children: [
        Text(
          "How did you sleep?",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 40),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Great",
          emoji: "😴",
          isSelected: _response.sleep == "great",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.sleep = "great");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Good",
          emoji: "🌙",
          isSelected: _response.sleep == "good",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.sleep = "good");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Okay",
          emoji: "😐",
          isSelected: _response.sleep == "okay",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.sleep = "okay");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Poorly",
          emoji: "😩",
          isSelected: _response.sleep == "poorly",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.sleep = "poorly");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
      ],
    );
  }

  Widget _buildMedicationQuestion(bool isDarkMode) {
    return Column(
      children: [
        Text(
          "Did you take your\nmeds?",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 40),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Yes",
          emoji: "💊",
          isSelected: _response.medication == "yes",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.medication = "yes");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Not yet",
          emoji: "⏰",
          isSelected: _response.medication == "not_yet",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.medication = "not_yet");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Skipped",
          emoji: "❌",
          isSelected: _response.medication == "skipped",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.medication = "skipped");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
      ],
    );
  }

  Widget _buildMoodQuestion(bool isDarkMode) {
    return Column(
      children: [
        Text(
          "How's your mood?",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 40),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Happy",
          emoji: "😄",
          isSelected: _response.mood == "happy",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.mood = "happy");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Neutral",
          emoji: "😐",
          isSelected: _response.mood == "neutral",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.mood = "neutral");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Down",
          emoji: "🥺",
          isSelected: _response.mood == "down",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.mood = "down");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Very sad",
          emoji: "😢",
          isSelected: _response.mood == "very_sad",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.mood = "very_sad");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
      ],
    );
  }

  Widget _buildEnergyQuestion(bool isDarkMode) {
    return Column(
      children: [
        Text(
          "How's your energy?",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 40),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Great",
          emoji: "⚡",
          isSelected: _response.energy == "great",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.energy = "great");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Good",
          emoji: "🙂",
          isSelected: _response.energy == "good",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.energy = "good");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Low",
          emoji: "🔋",
          isSelected: _response.energy == "low",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.energy = "low");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          isDarkMode: isDarkMode,
          label: "Very tired",
          emoji: "😴",
          isSelected: _response.energy == "very_tired",
          onTap: () async {
            if (_transitionInProgress) return;
            _transitionInProgress = true;
            setState(() => _response.energy = "very_tired");
            await Future.delayed(const Duration(milliseconds: 200));
            await _nextStep();
            if (mounted) _transitionInProgress = false;
          },
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required bool isDarkMode,
    required String label,
    required String emoji,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withValues(alpha: 0.1)
              : (isDarkMode ? AppColors.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isDarkMode
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Text(emoji, style: const TextStyle(fontSize: 28)),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipButton(bool isDarkMode) {
    return GestureDetector(
      onTap: _skipQuestion,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          "Skip for now",
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBrainExerciseScreen(bool isDarkMode) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Sparkle Icon Container
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Center(
                  child: Text("✨", style: TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                "Keep your mind\nsharp!",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                "Would you like to try a quick\nbrain exercise today?",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),

              // Yes Button
              GestureDetector(
                onTap: () => _onBrainExerciseDecided(true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryBlue,
                        AppColors.primaryBlue.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("🏆", style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Text(
                        "Yes, Let's Play!",
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Skip Button
              GestureDetector(
                onTap: () => _onBrainExerciseDecided(false),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      "Skip for today",
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(bool isDarkMode) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // Success Checkmark with Glow
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.successGreen,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.successGreen.withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 32),

              // Thank You Message
              Text(
                "Thanks ${widget.userName}!",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Your family has been updated.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              if (widget.currentStreak > 0) ...[
                const SizedBox(height: 40),
                // Streak Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFFEA580C),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${widget.currentStreak} day streak",
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 48),

              // Voice Note Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                  boxShadow: isDarkMode
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: Column(
                  children: [
                    Text(
                      "Want to leave a voice note?",
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Microphone Button
                    GestureDetector(
                      onTap: () {
                        // TODO: Implement voice recording
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        ),
                        child: const Icon(
                          Icons.mic,
                          size: 32,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sample text
                    Text(
                      '"Doctor appointment went well!"',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Back Home Button
              GestureDetector(
                onTap: _onComplete,
                child: Text(
                  "BACK HOME",
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
