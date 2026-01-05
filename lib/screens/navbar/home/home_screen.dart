import 'dart:async';
import 'package:arbaz_app/screens/navbar/calendar/calendar_screen.dart';
import 'package:arbaz_app/screens/navbar/cognitive_games/cognitive_games_screen.dart';
import 'package:arbaz_app/screens/navbar/home/senior_checkin_flow.dart';
import 'package:arbaz_app/screens/navbar/settings/settings_screen.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/services/notification_service.dart';
import 'package:arbaz_app/services/role_preference_service.dart';
import 'package:arbaz_app/services/vacation_mode_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:arbaz_app/services/quotes_service.dart';
import 'package:arbaz_app/services/location_service.dart';
import 'package:arbaz_app/services/contacts_service.dart';
import 'package:arbaz_app/models/family_contact_model.dart';
import 'package:arbaz_app/services/qr_invite_service.dart'; // For invite
import 'package:share_plus/share_plus.dart'; // For sharing invites
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:arbaz_app/models/wellness_data.dart';
import 'package:arbaz_app/models/checkin_model.dart';
import 'package:arbaz_app/models/game_result.dart';
import 'package:arbaz_app/models/security_vault.dart';
import 'package:geolocator/geolocator.dart';

import 'package:arbaz_app/models/user_model.dart';
import 'package:arbaz_app/common/profile_avatar.dart';

/// Represents the different status states for the senior user
enum SafetyStatus {
  safe, // Blue theme - "I'M SAFE"
  ok, // Yellow/amber theme - "I'M OK!"
  sending, // Red alert - "SENDING HELP..."
}

enum HomeAction { none, calendar, settings, roleSwitch, brainGym }

class SeniorHomeScreen extends StatefulWidget {
  const SeniorHomeScreen({super.key});

  @override
  State<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends State<SeniorHomeScreen>
    with SingleTickerProviderStateMixin {
  SafetyStatus _currentStatus = SafetyStatus.safe;
  bool _isSendingHelp = false;
  bool _hasCheckedInToday = false; // Legacy - kept for backward compat during refactor
  bool _allSchedulesCompleted = false; // True when ALL scheduled check-ins are done
  List<String> _completedSchedulesToday = []; // Schedules satisfied today
  List<String> _allSchedules = ['11:00 AM']; // All scheduled check-in times
  bool _isLoadingCheckInStatus =
      true; // Prevents flicker/interaction until status loaded
  HomeAction _activeAction = HomeAction.none;
  int _currentStreak = 0; // Dynamic streak - loaded from Firestore
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // User info
  String _userName = '';
  String? _photoUrl;
  String? _lastCheckInLocation;
  String? _todayQuote;
  
  // Real-time stream subscription for senior state updates
  StreamSubscription<SeniorState?>? _seniorStateSubscription;
  
  // Real-time stream subscription for profile updates (photo sync)
  StreamSubscription<UserProfile?>? _profileSubscription;
  
  // Timer to trigger status update when nextExpectedCheckIn is reached
  Timer? _checkInDeadlineTimer;
  DateTime? _nextExpectedCheckIn;
  
  // Track missed check-ins for notification triggering
  int _previousMissedCheckInsToday = 0;
  bool _wasRunningLate = false; // Track running late state for notification triggering
  bool _isFirstStreamEmission = true; // Prevent notification on first load
  
  /// Atomically initializes missed check-in baseline on first stream emission.
  /// Returns true if this was the first emission (baseline set), false otherwise.
  /// This prevents a race condition where rapid stream emissions could both pass
  /// the _isFirstStreamEmission check before the flag is set to false.
  bool _tryInitializeMissedCount(int count) {
    if (!_isFirstStreamEmission) return false;
    _isFirstStreamEmission = false;
    _previousMissedCheckInsToday = count;
    return true; // Was first emission - don't trigger notification
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize data after the widget is fully inserted in the tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
    });
  }

  Future<void> _initData() async {
    try {
      // Check if app was launched from notification to prevent duplicate local notification
      final launchDetails = await NotificationService().getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true && mounted) {
        debugPrint('App launched from notification - suppressing initial local alert');
        setState(() {
          _wasRunningLate = true; // Pretend we already alerted to suppress new one
        });
      }

      await _loadUserData();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      // Ensure loading state is cleared on error to prevent stuck button
      if (mounted) {
        setState(() => _isLoadingCheckInStatus = false);
      }
    }

    try {
      await _checkLocationPermission();
    } catch (e) {
      debugPrint('Error checking location permission: $e');
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final firestoreService = context.read<FirestoreService>();
      final quotesService = context.read<DailyQuotesService>();

      // OPTIMIZATION: Try to get name from Auth first (no Firestore read needed)
      // This saves Firestore reads for Google/Apple sign-in users
      String? nameFromAuth;
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        nameFromAuth = user.displayName!.split(' ').first;
      } else if (user.email != null && user.email!.isNotEmpty) {
        nameFromAuth = user.email!.split('@').first;
      }
      
      // Set name immediately from Auth if available
      if (nameFromAuth != null && nameFromAuth.isNotEmpty && mounted) {
        setState(() => _userName = nameFromAuth!);
      }

      // Subscribe to profile for real-time photo and name updates
      _profileSubscription?.cancel();
      _profileSubscription = firestoreService.streamUserProfile(user.uid).listen(
        (profile) {
          if (!mounted) return;
          if (profile != null) {
            setState(() {
              // Update photo URL for real-time sync
              _photoUrl = profile.photoUrl;
              
              // For email/password users who set displayName in Firestore, use that
              if (profile.displayName != null && 
                  profile.displayName!.isNotEmpty &&
                  (user.displayName == null || user.displayName!.isEmpty)) {
                _userName = profile.displayName!.split(' ').first;
              }
              
              // Populate last check-in location from profile
              if (profile.locationAddress != null) {
                _lastCheckInLocation = profile.locationAddress;
              }
            });
          }
        },
        onError: (e) {
          debugPrint('Error streaming profile: $e');
        },
      );

      // Subscribe to Senior State for real-time check-in status updates
      // This ensures the UI updates when nextExpectedCheckIn changes (e.g., from Settings)
      _seniorStateSubscription?.cancel();
      _seniorStateSubscription = firestoreService.streamSeniorState(user.uid).listen(
         (seniorState) {
          if (!mounted) return;
          
          if (seniorState != null) {
            final lastCheckIn = seniorState.lastCheckIn;
            final now = DateTime.now();
            
            // Multi check-in tracking: get schedules and completed list from Firestore
            final schedules = seniorState.checkInSchedules;
            final completedToday = seniorState.completedSchedulesToday;
            
            // Day boundary check: reset completed if lastScheduleResetDate is from a previous day
            List<String> effectiveCompleted = completedToday;
            final resetDate = seniorState.lastScheduleResetDate;
            if (resetDate == null || 
                resetDate.year != now.year ||
                resetDate.month != now.month ||
                resetDate.day != now.day) {
              effectiveCompleted = [];
            }
            
            // Check if ALL past-due schedules are completed
            final allCompleted = areAllSchedulesCompleted(
              schedules,
              effectiveCompleted,
              now,
            );
            
            // Legacy: Check if at least one check-in was done today
            final isToday = lastCheckIn != null &&
                lastCheckIn.year == now.year &&
                lastCheckIn.month == now.month &&
                lastCheckIn.day == now.day;
            
            // Day 1 logic: skip "running late" ONLY for the default 11:00 AM schedule
            // If user adds custom schedules on Day 1, those SHOULD work normally
            final isDay1 = seniorState.seniorCreatedAt != null &&
                seniorState.seniorCreatedAt!.year == now.year &&
                seniorState.seniorCreatedAt!.month == now.month &&
                seniorState.seniorCreatedAt!.day == now.day;
            
            // Check if using only the default schedule (11:00 AM)
            // If user added custom schedules, those should trigger yellow even on Day 1
            final hasOnlyDefaultSchedule = schedules.length == 1 &&
                schedules.first.toUpperCase() == '11:00 AM';
            
            // Skip "running late" only if it's Day 1 AND using only the default schedule
            final skipDay1Default = isDay1 && hasOnlyDefaultSchedule;
            
            // Check if running late: any past-due schedule not completed
            bool isRunningLate = false;
            if (!allCompleted && !skipDay1Default) {
              // There are pending schedules that have passed - running late
              final pendingSchedules = getPendingSchedules(
                schedules,
                effectiveCompleted,
                now,
              );
              isRunningLate = pendingSchedules.isNotEmpty;
            }
            
            // Schedule a timer to update status when nextExpectedCheckIn is reached
            _scheduleCheckInDeadlineTimer(seniorState.nextExpectedCheckIn, allCompleted || skipDay1Default);

            // Get vacation mode state BEFORE setState for notification logic
            final vacationMode = context.read<VacationModeProvider>().isVacationMode;
            final currentMissedCount = seniorState.missedCheckInsToday;

            setState(() {
              _hasCheckedInToday = isToday; // Legacy compat
              _allSchedulesCompleted = allCompleted;
              _completedSchedulesToday = effectiveCompleted;
              _allSchedules = schedules;
              _currentStreak = seniorState.currentStreak;
              _isLoadingCheckInStatus = false; // Status verified
              _nextExpectedCheckIn = seniorState.nextExpectedCheckIn;
              
              if (allCompleted) {
                // ALL schedules completed - show safe blue (disabled) state
                _currentStatus = SafetyStatus.safe;
                _pulseController.stop();
                // Cancel any pending missed check-in notification
                NotificationService().cancelMissedCheckInNotification();
                _wasRunningLate = false; // Reset tracking
              } else if (isRunningLate) {
                // Show yellow "I'M OK!" button when running late
                _currentStatus = SafetyStatus.ok;
                
                // Trigger notification only on first detection of running late
                if (!_wasRunningLate && !vacationMode) {
                  NotificationService().showMissedCheckInNotification(
                    missedCount: 1,
                    isVacationMode: false,
                  );
                }
                _wasRunningLate = true;
              } else {
                // Not running late - waiting for next schedule
                // Keep safe status but button still enabled for early check-in
                _currentStatus = SafetyStatus.safe;
                _wasRunningLate = false;
              }
            });
            
            // Trigger notification if missedCheckInsToday increased (from Firestore)
            // Use atomic helper to prevent race condition on rapid stream emissions
            final wasFirstEmission = _tryInitializeMissedCount(currentMissedCount);
            if (!wasFirstEmission && currentMissedCount > _previousMissedCheckInsToday && currentMissedCount > 0) {
              NotificationService().showMissedCheckInNotification(
                missedCount: currentMissedCount,
                isVacationMode: vacationMode,
              );
              _previousMissedCheckInsToday = currentMissedCount;
            }
          } else {
            // No senior state found - still mark as loaded
            setState(() => _isLoadingCheckInStatus = false);
          }
        },
        onError: (error) {
          debugPrint('Error streaming senior state: $error');
          if (mounted) {
            setState(() => _isLoadingCheckInStatus = false);
          }
        },
      );

      // Cache daily quote
      final quote = quotesService.getQuoteForToday(user.uid, DateTime.now());
      if (mounted) {
        setState(() => _todayQuote = quote);
      }
    }
  }

  /// Check and request location permission if needed
  /// Shows explanation dialog before requesting to meet app requirements
  Future<void> _checkLocationPermission() async {
    if (!mounted) return;
    final locationService = context.read<LocationService>();
    final permission = await locationService.checkPermission();

    debugPrint('Location permission status: $permission');
    
    if (permission == LocationPermission.denied) {
      // Show explanation dialog before requesting
      if (!mounted) return;
      
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Location Access',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'SafeCheck needs your location to include in your daily check-ins. '
            'This helps your family know you\'re safe at home.',
            style: GoogleFonts.inter(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Not Now',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Allow',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
      
      if (shouldRequest == true && mounted) {
        await locationService.requestPermission();
      }
    } else if (permission == LocationPermission.deniedForever) {
      // Show settings dialog for permanently denied permission
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warningOrange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off,
                  color: AppColors.warningOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Location Required',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Location permission was previously denied. Please enable it in Settings '
            'to use SafeCheck\'s full features.',
            style: GoogleFonts.inter(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Later',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Open Settings',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _checkInDeadlineTimer?.cancel();
    _seniorStateSubscription?.cancel();
    _profileSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }
  
  /// Schedules a timer to fire when the nextExpectedCheckIn time is reached,
  /// automatically updating the status to "running late" (yellow).
  void _scheduleCheckInDeadlineTimer(DateTime? nextExpectedCheckIn, bool hasCheckedInToday) {
    _checkInDeadlineTimer?.cancel();
    
    // Don't schedule if already checked in today or no expected time
    if (hasCheckedInToday || nextExpectedCheckIn == null) return;
    
    final now = DateTime.now();
    
    // If already past the deadline, status is already handled
    if (now.isAfter(nextExpectedCheckIn)) return;
    
    // Calculate delay until nextExpectedCheckIn (add 1 second buffer to ensure we're past it)
    final delay = nextExpectedCheckIn.difference(now) + const Duration(seconds: 1);
    
    // Store the scheduled time the timer was created for (for TOCTOU validation)
    final DateTime scheduledFor = nextExpectedCheckIn;
    
    // Capture vacation mode state BEFORE scheduling timer to avoid context access in callback
    bool isVacationModeAtSchedule;
    try {
      isVacationModeAtSchedule = context.read<VacationModeProvider>().isVacationMode;
    } catch (e) {
      // Context might already be invalid in edge cases
      debugPrint('Error reading vacation mode: $e');
      isVacationModeAtSchedule = false;
    }
    
    _checkInDeadlineTimer = Timer(delay, () {
      if (!mounted) return;
      
      try {
        // TOCTOU Check: Validate the scheduled time hasn't changed since timer creation
        // This prevents notification if user changed schedule while timer was pending
        if (!_hasCheckedInToday && _nextExpectedCheckIn != null && 
            _nextExpectedCheckIn!.isAtSameMomentAs(scheduledFor)) {
          final currentTime = DateTime.now();
          if (currentTime.isAfter(_nextExpectedCheckIn!)) {
            setState(() {
              _currentStatus = SafetyStatus.ok; // Yellow - running late
            });
            
            // Trigger local notification immediately when running late
            // Use captured vacation mode to avoid context access
            if (!isVacationModeAtSchedule && !_wasRunningLate) {
              NotificationService().showMissedCheckInNotification(
                missedCount: 1,
                isVacationMode: false,
              );
              // Update flag to prevent duplicate notification from stream listener
              setState(() {
                _wasRunningLate = true;
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Error in check-in deadline timer callback: $e');
      }
    });
  }

  /// Unified role switching helper with loading state and error handling
  Future<void> _switchRole({
    required String targetRole,
    required Future<void> Function(String uid) setRoleInFirestore,
    required Widget targetScreen,
  }) async {
    // Prevent concurrent switches
    if (_activeAction != HomeAction.none) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('Cannot switch role: No authenticated user');
      return;
    }

    setState(() => _activeAction = HomeAction.roleSwitch);

    final rolePreferenceService = context.read<RolePreferenceService>();
    final firestoreService = context.read<FirestoreService>();

    try {
      // Step 1: Grant role in Firestore first
      await setRoleInFirestore(user.uid);

      if (!mounted) return;

      // Step 2: Persist current role to Firestore for cross-session persistence
      await firestoreService.updateCurrentRole(user.uid, targetRole);

      // Step 3: Update local preference
      await rolePreferenceService.setActiveRole(user.uid, targetRole);

      if (!mounted) return;

      // Step 3: Navigate only after both operations succeed
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => targetScreen));
    } catch (e, stackTrace) {
      debugPrint('Error switching to $targetRole: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _activeAction = HomeAction.none);

        // Show contextual error message
        String errorMessage = 'Failed to switch roles.';
        if (e.toString().contains('permission')) {
          errorMessage = 'Permission denied. Please try again later.';
        } else if (e.toString().contains('network') ||
            e.toString().contains('connection')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('unavailable')) {
          errorMessage = 'Service unavailable. Please try again later.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: GoogleFonts.inter()),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  void _switchToFamily() {
    final firestoreService = context.read<FirestoreService>();
    _switchRole(
      targetRole: 'family',
      setRoleInFirestore: (uid) => firestoreService.setAsFamilyMember(uid),
      targetScreen: const FamilyHomeScreen(),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) {
      return 'GOOD NIGHT';
    } else if (hour < 12) {
      return 'GOOD MORNING';
    } else if (hour < 17) {
      return 'GOOD AFTERNOON';
    } else if (hour < 21) {
      return 'GOOD EVENING';
    } else {
      return 'GOOD NIGHT';
    }
  }

  void _onStatusButtonTap() {
    // Add haptic feedback for better UX
    HapticFeedback.mediumImpact();

    // Button is not clickable after all schedules completed
    if (_allSchedulesCompleted) {
      return;
    }

    // Show the check-in questionnaire flow
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SeniorCheckInFlow(
          userName: _userName,
          currentStreak: _currentStreak,
          onComplete: () {
            // State will be updated by Firestore stream when check-in is recorded
            // No need to manually update _hasCheckedInToday here
            // Stop pulse animation after successful check-in
            setState(() {
              _pulseController.stop();
              _pulseController.value = 1.0;
            });
          },
        ),
      ),
    );
  }

  void _onEmergencyTap() {
    // Add heavy haptic feedback for emergency action
    HapticFeedback.heavyImpact();

    // Show confirmation dialog to prevent accidental triggers
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.dangerRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.dangerRed,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Emergency Alert',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'This will immediately alert your family members. Are you sure you want to send an emergency alert?',
            style: GoogleFonts.inter(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _sendEmergencyAlert();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Send Alert',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _sendEmergencyAlert() async {
    setState(() {
      _isSendingHelp = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isSendingHelp = false);
      }
      return;
    }

    try {
      // Persist SOS alert to Firestore - this triggers FCM notification via Cloud Function
      await context.read<FirestoreService>().triggerSOS(user.uid);
      
      if (mounted) {
        setState(() {
          _isSendingHelp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Family has been alerted!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error triggering SOS: $e');
      if (mounted) {
        setState(() => _isSendingHelp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send alert. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.dangerRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer<VacationModeProvider>(
      builder: (context, vacationProvider, child) {
        final isVacationMode = vacationProvider.isVacationMode;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldExit = await _showExitConfirmationDialog(context);
            if (shouldExit == true && context.mounted) {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: isDarkMode
                ? AppColors.backgroundDark
                : AppColors.backgroundLight,
            body: SafeArea(
              child: Column(
                children: [
                  // Header Section
                  _buildHeader(isDarkMode),

                  // Vacation Mode Card (if enabled)
                  if (isVacationMode) _buildVacationModeCard(isDarkMode),

                  // Main Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.03),

                          // Large Status Circle Button
                          _buildStatusButton(
                            isVacationMode: isVacationMode,
                            isLoading:
                                vacationProvider.isLoading ||
                                _isLoadingCheckInStatus,
                          ),

                          SizedBox(height: screenHeight * 0.05),

                          // Daily Health Message Section
                          _buildHealthMessageSection(
                            isDarkMode,
                            isLoading: vacationProvider.isLoading || _isLoadingCheckInStatus,
                          ),

                          SizedBox(height: screenHeight * 0.05),
                        ],
                      ),
                    ),
                  ),

                  // Emergency SOS Bar (Smart)
                  _buildSmartEmergencyBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows a styled exit confirmation dialog
  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  size: 32,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Exit SafeCheck?',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'Are you sure you want to exit the app?',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              
              // Buttons
              Row(
                children: [
                  // Exit Button (Red Outlined)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dangerRed,
                        side: const BorderSide(color: AppColors.dangerRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Exit',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Stay Button (Primary Blue)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Stay',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              // User Avatar
              ProfileAvatar(
                photoUrl: _photoUrl,
                name: _userName,
                radius: 26, // 52 width / 2
                isDarkMode: isDarkMode,
                borderColor: AppColors.primaryBlue.withValues(alpha: 0.3),
                borderWidth: 2,
                showEditBadge: false,
              ),
              const SizedBox(width: 16),

              // Greeting Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName.isNotEmpty ? 'Hi $_userName!' : 'Welcome!',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      _getGreeting(),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick Action Bar
          Row(
            children: [
              _buildHeaderAction(
                Icons.calendar_today_rounded,
                'Calendar',
                isDarkMode,
                isLoading: _activeAction == HomeAction.calendar,
                onTap: () async {
                  setState(() => _activeAction = HomeAction.calendar);
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                    if (mounted) {
                      setState(() => _activeAction = HomeAction.none);
                    }
                  }
                },
              ),
              const SizedBox(width: 12),
              _buildHeaderAction(
                Icons.psychology_rounded,
                'Brain Gym',
                isDarkMode,
                isLoading: _activeAction == HomeAction.brainGym,
                onTap: () async {
                  setState(() => _activeAction = HomeAction.brainGym);
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CognitiveGamesScreen(),
                      ),
                    );
                    if (mounted) {
                      setState(() => _activeAction = HomeAction.none);
                    }
                  }
                },
              ),
              const SizedBox(width: 12),
              _buildHeaderAction(
                Icons.settings_rounded,
                'Settings',
                isDarkMode,
                isLoading: _activeAction == HomeAction.settings,
                onTap: () async {
                  setState(() => _activeAction = HomeAction.settings);
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    if (mounted) {
                      setState(() => _activeAction = HomeAction.none);
                      // Profile changes are handled by stream subscription - no reload needed
                    }
                  }
                },
              ),
              const SizedBox(width: 12),
              _buildHeaderAction(
                Icons.swap_horiz_rounded,
                'Family View',
                isDarkMode,
                isLoading: _activeAction == HomeAction.roleSwitch,
                onTap: _switchToFamily,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(
    IconData icon,
    String label,
    bool isDarkMode, {
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppColors.surfaceDark
                : AppColors.primaryBlue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode
                  ? AppColors.borderDark
                  : AppColors.primaryBlue.withValues(alpha: 0.1),
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDarkMode
                          ? Colors.white70
                          : AppColors.primaryBlue,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: AppColors.primaryBlue),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 11,
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
      ),
    );
  }

  Widget _buildVacationModeCard(bool isDarkMode) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [const Color(0xFF6366F1), const Color(0xFF818CF8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        // Sun Icon
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.wb_sunny_outlined,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),

        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vacation Mode On',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Check-ins are paused',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),

        // Info Icon
        Icon(
          Icons.info_outline,
          color: Colors.white.withValues(alpha: 0.9),
          size: 20,
        ),
      ],
    ),
  );
}
  Widget _buildStatusButton({
    bool isVacationMode = false,
    bool isLoading = false,
  }) {
    // Determine the button state and colors based on check-in status
    // Green: Waiting for next schedule (not all past-due checked in)
    // Blue: ALL schedules completed - NOT clickable
    // Yellow: Running late (missed a schedule)

    Color primaryColor;
    Color secondaryColor;
    Color ringColor;
    IconData statusIcon;
    String statusText;
    String subtitleText;
    bool isClickable;

    if (isVacationMode || isLoading) {
      // Disabled state
      primaryColor = Colors.grey.shade400;
      secondaryColor = Colors.grey.shade500;
      ringColor = Colors.grey.shade300;
      statusIcon = Icons.check;
      statusText = isLoading ? "LOADING..." : "I'M OK";
      subtitleText = isLoading
          ? "Syncing status..."
          : "Disabled during vacation";
      isClickable = false;
    } else if (_allSchedulesCompleted) {
      // Blue state - all schedules completed (not clickable)
      primaryColor = const Color(0xFF4DA6FF); // Light blue
      secondaryColor = const Color(0xFF2B8FE5); // Darker blue
      ringColor = const Color(0xFF7EC8FF); // Ring color
      statusIcon = Icons.check;
      statusText = "I'M SAFE";
      // Build subtitle showing completed schedules
      if (_completedSchedulesToday.isNotEmpty) {
        final times = _completedSchedulesToday.map((s) => s).join(', ');
        subtitleText = "✓ $times";
      } else {
        subtitleText = "All check-ins complete";
      }
      isClickable = false; // Not clickable after all schedules completed
    } else if (_currentStatus == SafetyStatus.ok) {
      // Yellow state - running late
      primaryColor = const Color(0xFFFFBF00); // Golden yellow
      secondaryColor = const Color(0xFFE5A800); // Darker yellow
      ringColor = const Color(0xFFFFD966); // Light yellow ring
      statusIcon = Icons.priority_high;
      statusText = "I'M OK!";
      subtitleText = "Tap to check in now";
      isClickable = true;
    } else {
      // Green state - waiting for check-in (may be early)
      primaryColor = const Color(0xFF2ECC71); // Vibrant green
      secondaryColor = const Color(0xFF27AE60); // Darker green
      ringColor = const Color(0xFF58D68D); // Light green ring
      statusIcon = Icons.favorite;
      statusText = "I'M OK";
      // Show next check-in time if available
      if (_nextExpectedCheckIn != null) {
        final nextTime = DateFormat('h:mm a').format(_nextExpectedCheckIn!);
        subtitleText = "Next: $nextTime";
      } else {
        subtitleText = "Tap to check in";
      }
      isClickable = true;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          // Only pulse if clickable and not in vacation mode
          scale: (isVacationMode || !isClickable) ? 1.0 : _pulseAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: isClickable ? _onStatusButtonTap : null,
        child: Opacity(
          opacity: (isVacationMode || isLoading) ? 0.5 : 1.0,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Outer ring effect
              border: Border.all(
                color: ringColor.withValues(alpha: 0.6),
                width: 8,
              ),
              boxShadow: (isVacationMode || !isClickable)
                  ? [] // No shadow when disabled or after completion
                  : [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: secondaryColor.withValues(alpha: 0.2),
                        blurRadius: 60,
                        spreadRadius: 15,
                      ),
                    ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primaryColor, secondaryColor],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status Icon in white circle
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.95),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: primaryColor,
                            ),
                          )
                        : Icon(statusIcon, color: primaryColor, size: 28),
                  ),
                  const SizedBox(height: 16),

                  // Status Text
                  Text(
                    statusText,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      subtitleText,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthMessageSection(bool isDarkMode, {bool isLoading = false}) {
    // Determine message and state
    String message;
    Color dotColor;
    String? subMessage;

    if (_hasCheckedInToday) {
      dotColor = AppColors.successGreen;
      // Use cached daily quote
      message = _todayQuote ?? "Have a wonderful day!";

      if (_lastCheckInLocation != null) {
        subMessage = "Checked in from $_lastCheckInLocation";
      }
    } else {
      dotColor = AppColors.warningOrange;
      message = isLoading ? "Syncing your status..." : "You haven't checked in yet today";
      subMessage = isLoading ? null : "Please take a moment to let us know you're okay.";
    }

    // Show loading indicator when loading and not checked in
    final showLoadingIndicator = isLoading && !_hasCheckedInToday;

    return Column(
      children: [
        // Section Title
        Text(
          'DAILY HEALTH MESSAGE',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        // Message Card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
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
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quote Icon, Status Dot, or Loading Indicator
                if (showLoadingIndicator)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.warningOrange,
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 14),

                // Message Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          height: 1.4,
                          fontStyle: _hasCheckedInToday
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                      if (subMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subMessage,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDarkMode
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ],
    );
  }

  void _onInviteFamily() {
    // Show invite options
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Invite Family Members",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Share your unique code so family can monitor your safety.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.share, color: AppColors.primaryBlue),
              ),
              title: const Text("Share Invite Code"),
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final qrService = context.read<QrInviteService>();
                  Navigator.pop(context); // Close sheet
                  // Generate code for family role
                  // Get best available name for QR payload
                  String bestName = user.displayName ?? 
                      user.email?.split('@').first ?? 
                      'User';
                  final code = qrService.generateInviteQrData(
                    user.uid,
                    'senior', // Senior generating invite - scanner becomes family
                    name: bestName,
                  );
                  await SharePlus.instance.share(ShareParams(text: code));
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.qr_code, color: AppColors.primaryBlue),
              ),
              title: const Text("Show QR Code"),
              onTap: () {
                Navigator.pop(context);
                _showQrDialog();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showQrDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User session not found. Please log in again."),
        ),
      );
      return;
    }

    final qrService = context.read<QrInviteService>();

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<String>(
        // Simulating a small delay to show the loading state as requested,
        // although QR generation is synchronous.
        future: Future.delayed(
          const Duration(milliseconds: 500),
          () {
            // Get best available name for QR payload
            String bestName = user.displayName ?? 
                user.email?.split('@').first ?? 
                'User';
            // Role 'senior' indicates the INVITER is a senior
            // Scanner will become 'family' member
            return qrService.generateInviteQrData(
              user.uid, 
              'senior',
              name: bestName,
            );
          },
        ),
        builder: (context, snapshot) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              "Scan to Join",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Your family can scan this code to join your safety circle.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  height: 200,
                  child: _buildQrContent(snapshot),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Close",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQrContent(AsyncSnapshot<String> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.dangerRed,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              "Failed to generate QR",
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.dangerRed,
              ),
            ),
          ],
        ),
      );
    }

    if (!snapshot.hasData || snapshot.data!.isEmpty) {
      return const Center(child: Text("No data"));
    }

    return QrImageView(
      data: snapshot.data!,
      version: QrVersions.auto,
      size: 200.0,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.primaryBlue,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.primaryBlue,
      ),
    );
  }

  Widget _buildSmartEmergencyBar() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<FamilyContactModel>>(
      stream: context.read<FamilyContactsService>().getContacts(user.uid),
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? [];
        final hasContacts = contacts.isNotEmpty;

        // If no contacts, show "Invite Family" instead of SOS
        if (!hasContacts) {
          return GestureDetector(
            onTap: _onInviteFamily,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
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
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: const Icon(
                      Icons.person_add,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CONNECT FAMILY',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Add contacts to enable SOS',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          );
        }

        // Standard SOS Bar
        final Color barColor = _isSendingHelp
            ? AppColors.dangerRed
            : const Color(0xFFFF6B35); // Orange-red for emergency

        return GestureDetector(
          onTap: _isSendingHelp ? null : _onEmergencyTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // SOS Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: _isSendingHelp
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.sos_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 16),

                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isSendingHelp ? 'SENDING HELP...' : 'EMERGENCY SOS',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isSendingHelp
                            ? 'FAMILY WILL BE ALERTED NOW'
                            : 'NOTIFY FAMILY IMMEDIATELY',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow indicator (only when not sending)
                if (!_isSendingHelp)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 16,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Family Home Screen with Tabs (Status, Health, Vault) ---
class FamilyHomeScreen extends StatefulWidget {
  const FamilyHomeScreen({super.key});

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  HomeAction _activeAction = HomeAction.none;

  // Senior Data State
  SeniorStatusData? _seniorData;
  bool _isLoadingSeniorData = true;
  List<WellnessDataPoint> _weeklyWellnessData = [];
  StreamSubscription? _seniorStateSubscription;
  StreamSubscription? _connectionsSubscription; // Listen for new connections
  StreamSubscription? _checkInsSubscription; // Listen for new check-ins (real-time wellness)
  StreamSubscription<UserProfile?>? _ownProfileSubscription; // Listen for own profile changes (photo sync)
  StreamSubscription? _vaultSubscription; // Listen for security vault changes (real-time)
  String _familyName = ''; // Empty until loaded
  String? _photoUrl;
  bool _isLoadingFamilyProfile = true; // Loading state for profile
  
  // Multi-senior support
  List<SeniorInfo> _allSeniors = []; // All connected seniors
  String? _selectedSeniorId; // Currently selected senior ID
  
  // Cognitive index data
  List<GameResult> _gameResults = [];
  CognitiveMetrics? _cognitiveMetrics;
  
  // Month selection for health tab
  DateTime _selectedMonth = DateTime.now();
  
  // Security vault data
  SecurityVault? _vaultData;
  bool _showSensitiveData = false; // Toggle for showing sensitive vault data
  
  // Multi check-in tracking - store current senior state for schedule info
  SeniorState? _currentSeniorState;
  
  // Tracking for local notification triggers (detect state changes)
  bool _previousSosActive = false;
  int _previousMissedCheckInsToday = 0;
  SeniorCheckInStatus? _previousStatus; // Track status changes for immediate notification
  bool _isFirstStreamEmission = true; // Prevent notification on first load
  DateTime? _previousLastCheckIn; // Track check-in changes for real-time wellness updates
  
  /// Atomically initializes missed check-in baseline on first stream emission.
  /// Returns true if this was the first emission (baseline set), false otherwise.
  bool _tryInitializeFamilyMissedCount(int count) {
    if (!_isFirstStreamEmission) return false;
    _isFirstStreamEmission = false;
    _previousMissedCheckInsToday = count;
    return true; // Was first emission - don't trigger notification
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSeniorData();
    _subscribeToOwnProfile();
    _listenToConnectionChanges(); // Start listening for connection changes
  }
  
  /// Listen for connection changes to auto-refresh when new connections are added
  void _listenToConnectionChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final firestoreService = context.read<FirestoreService>();
    
    // Listen to family connections stream (user is family member)
    _connectionsSubscription = firestoreService
        .getConnectionsForFamily(user.uid)
        .skip(1) // Skip initial value (already loaded in _loadSeniorData)
        .listen((connections) {
      debugPrint('📡 Connection stream updated: ${connections.length} connections');
      // Reload senior data when connections change
      _loadSeniorData();
    });
  }

  /// Subscribe to own profile for real-time photo and name updates
  void _subscribeToOwnProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingFamilyProfile = false);
      return;
    }

    // OPTIMIZATION: Set initial values from Auth immediately
    String? nameFromAuth;
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      nameFromAuth = user.displayName!.split(' ').first;
    } else if (user.email != null && user.email!.isNotEmpty) {
      nameFromAuth = user.email!.split('@').first;
    }

    if (nameFromAuth != null && nameFromAuth.isNotEmpty && mounted) {
      setState(() {
        _familyName = nameFromAuth!;
      });
    }

    // Subscribe to profile stream for real-time updates
    final firestoreService = context.read<FirestoreService>();
    _ownProfileSubscription?.cancel();
    _ownProfileSubscription = firestoreService.streamUserProfile(user.uid).listen(
      (profile) {
        if (!mounted) return;
        setState(() {
          // Update photo URL for real-time sync
          _photoUrl = profile?.photoUrl;
          
          // For email/password users who set displayName in Firestore, use that
          if (profile?.displayName != null &&
              profile!.displayName!.isNotEmpty &&
              (user.displayName == null || user.displayName!.isEmpty)) {
            _familyName = profile.displayName!.split(' ').first;
          }
          
          _isLoadingFamilyProfile = false;
        });
      },
      onError: (e) {
        debugPrint('Error streaming own profile: $e');
        if (mounted) {
          setState(() {
            if (_familyName.isEmpty) {
              _familyName =
                  user.displayName?.split(' ').first ??
                  user.email?.split('@').first ??
                  'Family Member';
            }
            _isLoadingFamilyProfile = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _connectionsSubscription?.cancel();
    _seniorStateSubscription?.cancel();
    _checkInsSubscription?.cancel();
    _ownProfileSubscription?.cancel();
    _vaultSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSeniorData() async {
    if (!mounted) return;
    setState(() => _isLoadingSeniorData = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingSeniorData = false);
      return;
    }

    try {
      final firestoreService = context.read<FirestoreService>();
      
      // FIX: Check both directions for bidirectional access
      // 1. User is family member looking at seniors (familyId = user.uid)
      // 2. User is senior looking at family members (seniorId = user.uid)
      final familyConnectionsStream = firestoreService.getConnectionsForFamily(
        user.uid,
      );
      final seniorConnectionsStream = firestoreService.getConnectionsForSenior(
        user.uid,
      );
      
      // Fetch both streams with timeout
      final results = await Future.wait([
        familyConnectionsStream
            .timeout(
              const Duration(seconds: 10),
              onTimeout: (sink) {
                sink.add([]);
                sink.close();
              },
            )
            .first,
        seniorConnectionsStream
            .timeout(
              const Duration(seconds: 10),
              onTimeout: (sink) {
                sink.add([]);
                sink.close();
              },
            )
            .first,
      ]);
      
      final familyConnections = results[0]; // User is family member
      final seniorConnections = results[1]; // User is senior

      debugPrint('🔍 Raw Family Connections: ${familyConnections.length}');
      for (var c in familyConnections) {
        debugPrint('  - ID: ${c.id}, Senior: ${c.seniorId}, Status: ${c.status}');
      }
      debugPrint('🔍 Raw Senior Connections: ${seniorConnections.length}');

      List<SeniorInfo> allSeniors = [];

      // From family connections: get seniors (user is family member)
      // Only include seniors who have explicitly confirmed their senior role
      if (familyConnections.isNotEmpty) {
        for (final conn in familyConnections) {
          // Check if senior has confirmed their role
          final seniorRoles = await firestoreService.getUserRoles(conn.seniorId)
              .catchError((_) => null);
          if (seniorRoles?.hasConfirmedSeniorRole != true) {
            debugPrint('Skipping unconfirmed senior: ${conn.seniorId}');
            continue;
          }
          
          final profile = await firestoreService.getUserProfile(conn.seniorId)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              conn.seniorName ??
              profile?.email.split('@').first ?? 
              'Senior';
          allSeniors.add(SeniorInfo(id: conn.seniorId, name: name, photoUrl: profile?.photoUrl));
        }
        debugPrint('Found ${allSeniors.length} confirmed seniors via getConnectionsForFamily');
      }
      
      // From senior connections: get family members (user is senior)
      // This allows bidirectional viewing, but only show those who confirmed senior role
      if (seniorConnections.isNotEmpty) {
        for (final conn in seniorConnections) {
          // Here familyId is the other person (family member)
          // Check if they have confirmed their senior role (only show confirmed seniors)
          final familyRoles = await firestoreService.getUserRoles(conn.familyId)
              .catchError((_) => null);
          if (familyRoles?.hasConfirmedSeniorRole != true) {
            debugPrint('Skipping unconfirmed family member: ${conn.familyId}');
            continue;
          }
          
          final profile = await firestoreService.getUserProfile(conn.familyId)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              profile?.email.split('@').first ?? 
              'Family Member';
          // Add as "senior" info for display purposes (we're viewing their data)
          allSeniors.add(SeniorInfo(id: conn.familyId, name: name, photoUrl: profile?.photoUrl));
        }
        debugPrint('Found ${allSeniors.length} confirmed members via getConnectionsForSenior');
      }
      
      if (allSeniors.isEmpty) {
        // Fallback: check familyContacts for any with relationship='Senior'
        debugPrint('No connections found, checking familyContacts...');

        if (!mounted) return;

        final contactsService = context.read<FamilyContactsService>();
        final contacts = await contactsService.getContacts(user.uid).first;

        // Look for contacts with relationship='Senior' (case-insensitive) and a valid contactUid
        final seniorContacts = contacts
            .where(
              (c) =>
                  c.relationship.toLowerCase() == 'senior' &&
                  c.contactUid != null &&
                  c.contactUid!.isNotEmpty,
            )
            .toList();

        for (final contact in seniorContacts) {
          // Check if senior has confirmed their role
          final contactRoles = await firestoreService.getUserRoles(contact.contactUid!)
              .catchError((_) => null);
          if (contactRoles?.hasConfirmedSeniorRole != true) {
            debugPrint('Skipping unconfirmed contact: ${contact.contactUid}');
            continue;
          }
          
          final profile = await firestoreService.getUserProfile(contact.contactUid!)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              (contact.name.isNotEmpty ? contact.name : 'Senior');
          allSeniors.add(SeniorInfo(id: contact.contactUid!, name: name, photoUrl: profile?.photoUrl));
        }
        
        // Also check for family contacts (for seniors viewing family view)
        final familyContacts = contacts
            .where(
              (c) =>
                  c.relationship.toLowerCase() == 'family' &&
                  c.contactUid != null &&
                  c.contactUid!.isNotEmpty,
            )
            .toList();

        for (final contact in familyContacts) {
          // Check if family member has confirmed senior role
          final contactRoles = await firestoreService.getUserRoles(contact.contactUid!)
              .catchError((_) => null);
          if (contactRoles?.hasConfirmedSeniorRole != true) {
            debugPrint('Skipping unconfirmed family contact: ${contact.contactUid}');
            continue;
          }
          
          final profile = await firestoreService.getUserProfile(contact.contactUid!)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              (contact.name.isNotEmpty ? contact.name : 'Family Member');
          allSeniors.add(SeniorInfo(id: contact.contactUid!, name: name, photoUrl: profile?.photoUrl));
        }
        
        if (allSeniors.isNotEmpty) {
          debugPrint('Found ${allSeniors.length} members via familyContacts');
        } else {
          debugPrint('No members found in familyContacts either');
        }
      }

      if (!mounted) return;

      // Update state with all seniors
      setState(() {
        _allSeniors = allSeniors;
        
        // Validate that selected senior still exists in the updated list
        // This handles the case where a senior is deleted from settings
        final selectedStillExists = allSeniors.any((s) => s.id == _selectedSeniorId);
        
        if (allSeniors.isNotEmpty && (_selectedSeniorId == null || !selectedStillExists)) {
          // Select first available senior if no selection or current selection is invalid
          _selectedSeniorId = allSeniors.first.id;
          debugPrint('🔄 Auto-selecting senior: ${allSeniors.first.name}');
        } else if (allSeniors.isEmpty) {
          // No seniors available, clear selection
          _selectedSeniorId = null;
          _seniorData = null;
        }
      });

      if (allSeniors.isEmpty) {
        if (mounted) setState(() => _isLoadingSeniorData = false);
        return;
      }

      // Load data for the selected senior
      await _loadSeniorDetails(_selectedSeniorId!);
    } catch (e) {
      debugPrint('Error loading senior data: $e');
      if (mounted) setState(() => _isLoadingSeniorData = false);
    }
  }

  /// Load data for a specific senior by ID
  /// Uses check-in history instead of seniorState for status (removes asymmetric dependency)
  Future<void> _loadSeniorDetails(String seniorId) async {
    if (!mounted) return;
    
    debugPrint('🔍 Loading senior details for: $seniorId');
    
    final firestoreService = context.read<FirestoreService>();
    
    // Get Senior Name from allSeniors list
    final seniorInfo = _allSeniors.firstWhere(
      (s) => s.id == seniorId,
      orElse: () => SeniorInfo(id: seniorId, name: 'Senior'),
    );
    final srName = seniorInfo.name;
    
    debugPrint('🔍 Senior name resolved: $srName');

    if (!mounted) return;

    // Load Weekly Data (check-in history)
    List<CheckInRecord> history = [];
    try {
      history = await firestoreService.getSeniorCheckInsForWeek(seniorId);
      debugPrint('🔍 Found ${history.length} check-ins');
    } catch (e) {
      debugPrint('⚠️ Error loading check-in history: $e');
    }

    if (!mounted) return;

    // Calculate status from check-in history (no seniorState needed)
    SeniorCheckInStatus status;
    DateTime? lastCheckIn;
    String? timeString;
    
    if (history.isNotEmpty) {
      // Sort by timestamp descending to get most recent
      history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final mostRecent = history.first;
      lastCheckIn = mostRecent.timestamp;
      timeString = DateFormat('HH:mm').format(lastCheckIn);
      
      // Check if checked in today
      final now = DateTime.now();
      if (lastCheckIn.year == now.year &&
          lastCheckIn.month == now.month &&
          lastCheckIn.day == now.day) {
        status = SeniorCheckInStatus.safe;
      } else {
        // Has history but not today - pending
        status = SeniorCheckInStatus.pending;
      }
    } else {
      // No check-in history at all - still show as pending (not "no connection")
      status = SeniorCheckInStatus.pending;
    }

    // Cancel any existing subscription before creating a new one
    _seniorStateSubscription?.cancel();
    
    // Subscribe to real-time senior state updates (vacation mode, lastCheckIn, etc.)
    // This ensures the UI updates immediately when senior toggles vacation mode or checks in
    _seniorStateSubscription = firestoreService
        .streamSeniorState(seniorId)
        .listen(
      (seniorState) {
        if (!mounted) return;
        
        // Recalculate status from the latest senior state
        SeniorCheckInStatus newStatus;
        DateTime? newLastCheckIn = seniorState?.lastCheckIn;
        String? newTimeString;
        
        // SOS alert takes highest priority - override everything
        if (seniorState?.sosActive == true) {
          newStatus = SeniorCheckInStatus.alert;
        } else if (seniorState?.vacationMode == true) {
          // Vacation mode - show as safe
          newStatus = SeniorCheckInStatus.safe;
        } else {
          // Always use _calculateSeniorStatus to check pending schedules
          // This ensures family view matches senior view (yellow when pending)
          newStatus = _calculateSeniorStatus(seniorState, seniorState?.checkInSchedules ?? []);
          
          // Set time string from lastCheckIn if available
          if (newLastCheckIn != null) {
            newTimeString = DateFormat('HH:mm').format(newLastCheckIn);
          }
        }
        
        // Trigger local notifications for state changes (before updating state)
        // SOS Alert: Notify if just became active
        final bool currentSosActive = seniorState?.sosActive ?? false;
        if (currentSosActive && !_previousSosActive) {
          NotificationService().showFamilySOSNotification(
            seniorId: seniorId,
            seniorName: srName,
          );
        }
        _previousSosActive = currentSosActive;
        
        // Missed Check-in: Notify if count increased
        // Use atomic helper to prevent notification on first stream emission
        final int currentMissed = seniorState?.missedCheckInsToday ?? 0;
        final wasFirstEmission = _tryInitializeFamilyMissedCount(currentMissed);
        if (!wasFirstEmission && currentMissed > _previousMissedCheckInsToday && currentMissed > 0) {
          NotificationService().showFamilyMissedCheckInNotification(
            missedCount: currentMissed,
            seniorId: seniorId,
            seniorName: srName,
          );
        }
        _previousMissedCheckInsToday = currentMissed;
        
        // Status Change to Alert: Notify immediately when check-in time passes
        // This provides faster notification than waiting for Cloud Function to update missedCheckInsToday
        // Only trigger if status changed TO alert (not SOS, which has separate handling)
        final bool statusChangedToAlert = newStatus == SeniorCheckInStatus.alert && 
            _previousStatus != null && 
            _previousStatus != SeniorCheckInStatus.alert &&
            !(seniorState?.sosActive ?? false); // Don't double-notify for SOS
        if (statusChangedToAlert) {
          debugPrint('📢 Family notification: Status changed to alert (check-in time passed)');
          NotificationService().showFamilyMissedCheckInNotification(
            missedCount: 1, // At least 1 missed
            seniorId: seniorId,
            seniorName: srName,
          );
        }
        _previousStatus = newStatus;
        
        setState(() {
          _currentSeniorState = seniorState;
          _seniorData = SeniorStatusData(
            status: newStatus,
            seniorName: srName,
            lastCheckIn: newLastCheckIn,
            timeString: newTimeString,
            vacationMode: seniorState?.vacationMode ?? false,
            sosActive: seniorState?.sosActive ?? false,
          );
        });
        
        // Real-time wellness data update: Reload when lastCheckIn changes
        // This ensures Status/Health tabs update immediately when senior checks in
        // Also reload on first detection of lastCheckIn (not just changes)
        final bool isCurrentMonth = _selectedMonth.year == DateTime.now().year &&
            _selectedMonth.month == DateTime.now().month;
        final bool lastCheckInChanged = newLastCheckIn != null && 
            (_previousLastCheckIn == null || newLastCheckIn != _previousLastCheckIn);
        
        if (lastCheckInChanged && isCurrentMonth) {
          debugPrint('📊 New check-in detected, reloading wellness data...');
          _reloadWellnessData(seniorId);
        }
        _previousLastCheckIn = newLastCheckIn;
        
        debugPrint('📡 Senior state stream update: vacation=${seniorState?.vacationMode}, lastCheckIn=$newLastCheckIn, status=$newStatus, sos=$currentSosActive, missed=$currentMissed');
      },
      onError: (error) {
        debugPrint('⚠️ Error streaming senior state: $error');
      },
    );

    // Load game results for cognitive index (filtered by selected month)
    List<GameResult> gameResults = [];
    try {
      gameResults = await firestoreService.getGameResultsForSenior(
        seniorId,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );
      debugPrint('🔍 Found ${gameResults.length} game results for ${_selectedMonth.month}/${_selectedMonth.year}');
    } catch (e) {
      debugPrint('⚠️ Error loading game results: $e');
    }
    
    // Load wellness data for the selected month
    List<WellnessDataPoint> monthlyWellnessData = [];
    try {
      final checkIns = await firestoreService.getCheckInsForMonth(
        seniorId,
        _selectedMonth.year,
        _selectedMonth.month,
      );
      monthlyWellnessData = checkIns
          .map((c) => WellnessDataPoint.fromCheckIn(c))
          .toList();
      debugPrint('🔍 Found ${monthlyWellnessData.length} wellness data points for ${_selectedMonth.month}/${_selectedMonth.year}');
    } catch (e) {
      debugPrint('⚠️ Error loading monthly wellness data: $e');
    }

    // Subscribe to Security Vault stream for real-time updates
    // This ensures family view updates immediately when senior modifies their vault
    _vaultSubscription?.cancel();
    _vaultSubscription = firestoreService
        .streamSecurityVault(seniorId)
        .listen((vaultData) {
          if (!mounted) return;
          setState(() {
            _vaultData = vaultData;
          });
          debugPrint('📦 Vault data updated via stream: ${vaultData != null}');
        });

    if (mounted) {
      setState(() {
        _weeklyWellnessData = monthlyWellnessData;
        // Initial status data will be populated by the stream listener above
        // If stream hasn't emitted yet, use data from history
        if (_seniorData == null) {
          _seniorData = SeniorStatusData(
            status: status,
            seniorName: srName,
            lastCheckIn: lastCheckIn,
            timeString: timeString,
            vacationMode: false,
          );
        }
        _gameResults = gameResults;
        _cognitiveMetrics = CognitiveMetrics.fromResults(gameResults);
        _isLoadingSeniorData = false;
      });
    }
    
    debugPrint('✅ Senior data loaded: $srName, games: ${gameResults.length}');
  }

  /// Called when user switches to a different senior in the dropdown
  void _onSeniorChanged(String? seniorId) {
    if (seniorId == null || seniorId == _selectedSeniorId) return;
    
    setState(() {
      _selectedSeniorId = seniorId;
      _isLoadingSeniorData = true;
      _seniorData = null;
      _weeklyWellnessData = [];
      _gameResults = [];
      _cognitiveMetrics = null;
      _vaultData = null;
      // Reset notification tracking for new senior
      _previousMissedCheckInsToday = 0;
      _previousSosActive = false;
      _previousStatus = null;
      _isFirstStreamEmission = true;
      _previousLastCheckIn = null;
    });
    
    _loadSeniorDetails(seniorId);
  }

  /// Reloads wellness data for the current month when a new check-in is detected
  /// This enables real-time updates on the Health tab without full data reload
  Future<void> _reloadWellnessData(String seniorId) async {
    if (!mounted) return;
    
    final firestoreService = context.read<FirestoreService>();
    
    try {
      final checkIns = await firestoreService.getCheckInsForMonth(
        seniorId,
        _selectedMonth.year,
        _selectedMonth.month,
      );
      final newWellnessData = checkIns
          .map((c) => WellnessDataPoint.fromCheckIn(c))
          .toList();
      
      if (mounted) {
        setState(() {
          _weeklyWellnessData = newWellnessData;
        });
        debugPrint('📊 Wellness data reloaded: ${newWellnessData.length} data points');
      }
    } catch (e) {
      debugPrint('⚠️ Error reloading wellness data: $e');
    }
  }

  SeniorCheckInStatus _calculateSeniorStatus(
    SeniorState? state,
    List<String> schedules,
  ) {
    if (state == null) return SeniorCheckInStatus.pending;

    final now = DateTime.now();
    
    // Multi check-in tracking: get completed schedules from Firestore
    List<String> completedToday = state.completedSchedulesToday;
    
    // Day boundary check: reset if lastScheduleResetDate is from a previous day
    final resetDate = state.lastScheduleResetDate;
    if (resetDate == null ||
        resetDate.year != now.year ||
        resetDate.month != now.month ||
        resetDate.day != now.day) {
      completedToday = [];
    }
    
    // Check if ALL past-due schedules are completed
    final allCompleted = areAllSchedulesCompleted(
      schedules.isNotEmpty ? schedules : ['11:00 AM'],
      completedToday,
      now,
    );
    
    if (allCompleted) {
      return SeniorCheckInStatus.safe;
    }

    // Day 1 logic: skip alerting ONLY for default 11:00 AM schedule
    // If user adds custom schedules on Day 1, those SHOULD work normally
    if (state.seniorCreatedAt != null) {
      final createdDate = state.seniorCreatedAt!;
      final isDay1 = createdDate.year == now.year &&
          createdDate.month == now.month &&
          createdDate.day == now.day;
      
      // Check if using only the default schedule
      final hasOnlyDefaultSchedule = schedules.length == 1 &&
          schedules.first.toUpperCase() == '11:00 AM';
      
      // Only skip if Day 1 AND using only default schedule
      if (isDay1 && hasOnlyDefaultSchedule) {
        return SeniorCheckInStatus.pending;
      }
    }

    // Check if any schedule is past due and not completed
    final pendingSchedules = getPendingSchedules(
      schedules.isNotEmpty ? schedules : ['11:00 AM'],
      completedToday,
      now,
    );
    
    if (pendingSchedules.isNotEmpty) {
      return SeniorCheckInStatus.alert;
    }

    return SeniorCheckInStatus.pending;
  }

  /// Unified role switching helper with loading state and error handling
  Future<void> _switchRole({
    required String targetRole,
    required Future<void> Function(String uid) setRoleInFirestore,
    required Widget targetScreen,
  }) async {
    // Prevent concurrent switches
    if (_activeAction != HomeAction.none) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('Cannot switch role: No authenticated user');
      return;
    }

    setState(() => _activeAction = HomeAction.roleSwitch);

    final rolePreferenceService = context.read<RolePreferenceService>();
    final firestoreService = context.read<FirestoreService>();

    try {
      // Step 1: Grant role in Firestore first
      await setRoleInFirestore(user.uid);

      if (!mounted) return;

      // Step 2: Update persisted current role for cross-device/logout persistence
      await firestoreService.updateCurrentRole(user.uid, targetRole);

      // Step 3: Update local preference
      await rolePreferenceService.setActiveRole(user.uid, targetRole);

      if (!mounted) return;

      // Step 4: Navigate only after both operations succeed
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => targetScreen));
    } catch (e, stackTrace) {
      debugPrint('Error switching to $targetRole: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _activeAction = HomeAction.none);

        // Show contextual error message
        String errorMessage = 'Failed to switch roles.';
        if (e.toString().contains('permission')) {
          errorMessage = 'Permission denied. Please try again later.';
        } else if (e.toString().contains('network') ||
            e.toString().contains('connection')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('unavailable')) {
          errorMessage = 'Service unavailable. Please try again later.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: GoogleFonts.inter()),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _switchToSenior() async {
    final firestoreService = context.read<FirestoreService>();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('Cannot switch role: No authenticated user');
      return;
    }

    // Check if user has already confirmed senior role
    final roles = await firestoreService.getUserRoles(user.uid);
    final alreadyConfirmed = roles?.hasConfirmedSeniorRole ?? false;

    if (!alreadyConfirmed) {
      // Show confirmation dialog for first-time senior switch
      final confirmed = await _showSeniorConfirmationDialog();
      if (confirmed != true) return; // User cancelled

      // Persist confirmation
      await firestoreService.confirmSeniorRole(user.uid);
    }

    // Proceed with existing role switch logic
    _switchRole(
      targetRole: 'senior',
      setRoleInFirestore: (uid) => firestoreService.setAsSenior(uid),
      targetScreen: const SeniorHomeScreen(),
    );
  }

  /// Shows confirmation dialog when user switches to Senior View for the first time.
  /// Returns true if user confirms, false if cancelled.
  Future<bool?> _showSeniorConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.primaryBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Become a Senior?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Switching to Senior View will make your check-ins, health data, and location visible to connected family members. This allows them to monitor your safety.\n\nYou can always switch views later, but your data will remain visible to family members.',
          style: GoogleFonts.inter(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colors.grey,
            ),
            child: Text(
              'I Understand, Continue',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerRed,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }


  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) {
      return 'GOOD NIGHT';
    } else if (hour < 12) {
      return 'GOOD MORNING';
    } else if (hour < 17) {
      return 'GOOD AFTERNOON';
    } else if (hour < 21) {
      return 'GOOD EVENING';
    } else {
      return 'GOOD NIGHT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: isDarkMode
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            children: [
              // Custom Header
              _buildHeader(isDarkMode),

              const SizedBox(height: 6),

              // Main Content Card with Tabs
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: isDarkMode
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 24,
                              offset: const Offset(0, -4),
                            ),
                          ],
                  ),
                  child: Column(
                    children: [
                      // Tab Bar
                      _buildTabBar(isDarkMode),

                      // Tab Content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildStatusTab(isDarkMode),
                            _buildHealthTab(isDarkMode),
                            _buildVaultTab(isDarkMode),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a styled exit confirmation dialog
  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  size: 32,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Exit SafeCheck?',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'Are you sure you want to exit the app?',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              
              // Buttons
              Row(
                children: [
                  // Exit Button (Red Outlined)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dangerRed,
                        side: const BorderSide(color: AppColors.dangerRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Exit',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Stay Button (Primary Blue)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Stay',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // User Avatar
          ProfileAvatar(
            photoUrl: _photoUrl,
            name: _familyName,
            radius: 24, // 48 width / 2
            isDarkMode: isDarkMode,
            borderColor: AppColors.successGreen.withValues(alpha: 0.3),
            borderWidth: 2,
            icon: Icons.family_restroom,
          ),
          const SizedBox(width: 6),

          // Greeting Text
          Expanded(
            child: _isLoadingFamilyProfile
                ? Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDarkMode
                              ? Colors.white70
                              : AppColors.successGreen,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Loading...',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi $_familyName!',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _getGreeting(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.successGreen,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
          ),

          // Action Icons
          // Calendar button - only show when a senior is connected
          if (_selectedSeniorId != null) ...[
            _buildHeaderIcon(
              Icons.calendar_month_outlined,
              isDarkMode,
              isLoading: _activeAction == HomeAction.calendar,
              onTap: () async {
                if (_selectedSeniorId == null) return;
                setState(() => _activeAction = HomeAction.calendar);
                await Future.delayed(const Duration(milliseconds: 200));
                if (mounted) {
                  // Get the selected senior's name
                  final seniorName = _allSeniors
                      .where((s) => s.id == _selectedSeniorId)
                      .map((s) => s.name)
                      .firstOrNull ?? 'Senior';
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CalendarScreen(
                        seniorId: _selectedSeniorId,
                        seniorName: seniorName,
                      ),
                    ),
                  );
                  if (mounted) {
                    setState(() => _activeAction = HomeAction.none);
                  }
                }
              },
            ),
            const SizedBox(width: 8),
          ],
          _buildHeaderIcon(
            Icons.settings_outlined,
            isDarkMode,
            isLoading: _activeAction == HomeAction.settings,
            onTap: () async {
              setState(() => _activeAction = HomeAction.settings);
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(isFamilyView: true),
                  ),
                );
                if (mounted) {
                  setState(() => _activeAction = HomeAction.none);
                  // Profile changes are handled by stream subscription - no reload needed
                }
              }
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderIcon(
            Icons.swap_horiz_rounded,
            isDarkMode,
            isLoading: _activeAction == HomeAction.roleSwitch,
            onTap: _switchToSenior,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(
    IconData icon,
    bool isDarkMode, {
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDarkMode ? Colors.white70 : AppColors.successGreen,
                  ),
                )
              : Icon(
                  icon,
                  size: 20,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textPrimary,
                ),
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      height: 48,
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : AppColors.inputFillLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.successGreen,
              AppColors.successGreen.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.successGreen.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.white,
        unselectedLabelColor: isDarkMode
            ? AppColors.textSecondaryDark
            : AppColors.textSecondary,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Status'),
          Tab(text: 'Health'),
          Tab(text: 'Vault'),
        ],
      ),
    );
  }

  // Invite Family Method
  void _onInviteFamily() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Invite Family Members",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Share your unique code so family can monitor your safety.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.share, color: AppColors.primaryBlue),
              ),
              title: const Text("Share Invite Code"),
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final qrService = context.read<QrInviteService>();
                  Navigator.pop(context); // Close sheet
                  // Generate code (assuming senior inviting family? Or family inviting other family/senior?
                  // Prompt says "Empty State Testing... Generate Invite QR/Code button".
                  // If this is Family View, they are probably inviting a Senior to connect?
                  // But QR Service logic depends on role.
                  // Let's assume inviting a Senior.
                  // Get best available name for QR payload
                  String bestName = user.displayName ?? 
                      user.email?.split('@').first ?? 
                      'User';
                  final code = qrService.generateInviteQrData(
                    user.uid,
                    'family', // Family member generating invite - scanner becomes senior
                    name: bestName,
                  );
                  await SharePlus.instance.share(ShareParams(text: code));
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.qr_code, color: AppColors.primaryBlue),
              ),
              title: const Text("Show QR Code"),
              onTap: () {
                Navigator.pop(context);
                _showQrDialog();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showQrDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final qrService = context.read<QrInviteService>();
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<String>(
        future: Future.value(
          () {
            // Get best available name for QR payload
            String bestName = user.displayName ?? 
                user.email?.split('@').first ?? 
                'User';
            return qrService.generateInviteQrData(
              user.uid, 
              'family',
              name: bestName,
            );
          }(),
        ),
        builder: (context, snapshot) {
          // Handle error state
          if (snapshot.hasError) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.dangerRed),
                  const SizedBox(width: 8),
                  Text(
                    'QR Generation Failed',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Text(
                'Unable to generate QR code. Please try again.',
                style: GoogleFonts.inter(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(color: AppColors.primaryBlue),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showQrDialog(); // Retry
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                ),
              ],
            );
          }
          
          // Handle loading state
          if (!snapshot.hasData) {
            return AlertDialog(
              content: SizedBox(
                width: 200,
                height: 200,
                child: const Center(child: CircularProgressIndicator()),
              ),
            );
          }
          
          // Validate data before rendering QR
          final qrData = snapshot.data!;
          if (qrData.isEmpty) {
            return AlertDialog(
              title: Text(
                'Invalid QR Data',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
              content: Text(
                'QR code data is empty. Please try again.',
                style: GoogleFonts.inter(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(color: AppColors.primaryBlue),
                  ),
                ),
              ],
            );
          }
          
          // Render valid QR code
          return AlertDialog(
            content: SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(data: qrData),
            ),
          );
        },
      ),
    );
  }

  // ==================== STATUS TAB ====================
  Widget _buildStatusTab(bool isDarkMode) {
    if (_isLoadingSeniorData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_seniorData == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildInviteCard(isDarkMode),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Senior Selector Dropdown (only show if 2+ seniors)
          if (_allSeniors.length >= 2) ...[
            _buildSeniorSelector(isDarkMode),
            const SizedBox(height: 16),
          ],
          
          const SizedBox(height: 8),

          // Dynamic Status Card
          _buildDynamicStatusCard(_seniorData!, isDarkMode),
          const SizedBox(height: 16),

          // Check-in Progress Cards (only show when there are multiple schedules)
          if (_currentSeniorState != null &&
              _currentSeniorState!.checkInSchedules.length > 1) ...[
            _buildCheckInProgressCards(isDarkMode),
            const SizedBox(height: 16),
          ],

          // Removed Live Tracking Card as it wasn't requested in update plan but kept structure mostly
          // Replaced with Medication Streak Card or similar/Just Quick Stats

          // Quick Stats - Check-ins only (Success Rate removed)
          // _buildQuickStatCard(
          //   'Check-ins',
          //   _weeklyWellnessData.length.toString(), // Weekly count
          //   Icons.check_circle_outline,
          //   isDarkMode,
          // ),
          const SizedBox(height: 16),

          // AI Care Intelligence Card
          // _buildAICareCard(isDarkMode, medStreak),
        ],
      ),
    );
  }

  /// Builds a dropdown to select which senior to view (when 2+ seniors connected)
  Widget _buildSeniorSelector(bool isDarkMode) {
    // Find current senior name
    final currentSenior = _allSeniors.firstWhere(
      (s) => s.id == _selectedSeniorId,
      orElse: () => _allSeniors.first,
    );
    
    return GestureDetector(
      onTap: () => _showSeniorSelectorSheet(isDarkMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),
          boxShadow: isDarkMode ? null : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.15),
                    AppColors.primaryBlue.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.people_alt_outlined,
                size: 22,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Viewing',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode 
                          ? AppColors.textSecondaryDark 
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentSenior.name,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? Colors.white.withValues(alpha: 0.1) 
                    : AppColors.inputFillLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a pretty bottom sheet for selecting a senior
  void _showSeniorSelectorSheet(bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.successGreen.withValues(alpha: 0.2),
                          AppColors.successGreen.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.family_restroom,
                      size: 22,
                      color: AppColors.successGreen,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Senior',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${_allSeniors.length} family members connected',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDarkMode 
                                ? AppColors.textSecondaryDark 
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            Divider(
              height: 1,
              color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
            
            // Senior list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _allSeniors.length,
                itemBuilder: (context, index) {
                  final senior = _allSeniors[index];
                  final isSelected = senior.id == _selectedSeniorId;
                  
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        if (senior.id != _selectedSeniorId) {
                          _onSeniorChanged(senior.id);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, 
                          vertical: 14,
                        ),
                        decoration: isSelected ? BoxDecoration(
                          color: AppColors.successGreen.withValues(alpha: 0.1),
                        ) : null,
                        child: Row(
                          children: [
                            // Avatar
                            ProfileAvatar(
                              photoUrl: senior.photoUrl,
                              name: senior.name,
                              radius: 22,
                              isDarkMode: isDarkMode,
                              gradientColors: isSelected 
                                  ? [
                                      AppColors.successGreen,
                                      AppColors.successGreen.withValues(alpha: 0.8),
                                    ]
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            
                            // Name & subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    senior.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: isSelected 
                                          ? FontWeight.w700 
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? AppColors.successGreen
                                          : (isDarkMode ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                  Text(
                                    'Senior',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: isDarkMode 
                                          ? AppColors.textSecondaryDark 
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Selected indicator
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.successGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Bottom padding for safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }


  Widget _buildInviteCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.person_add_alt_1, size: 60, color: AppColors.primaryBlue),
          const SizedBox(height: 16),
          Text(
            'No Seniors Connected',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Invite a senior family member to start monitoring their wellness.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.grey),
          ),
          // ElevatedButton.icon(
          //   onPressed: _onInviteFamily,
          //   icon: const Icon(Icons.qr_code),
          //   label: const Text('Generate Invite QR/Code'),
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: AppColors.primaryBlue,
          //     foregroundColor: Colors.white,
          //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          //     shape: RoundedRectangleBorder(
          //       borderRadius: BorderRadius.circular(12),
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildDynamicStatusCard(SeniorStatusData data, bool isDarkMode) {
    Color cardColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;
    List<Widget> actions = [];

    // Override for Vacation Mode
    if (data.vacationMode) {
      cardColor = const Color(0xFF6366F1); // Indigo
      iconColor = Colors.white;
      icon = Icons.wb_sunny_rounded;
      title = '${data.seniorName} is on Vacation';
      subtitle = 'Check-ins are paused';
    } else {
      switch (data.status) {
        case SeniorCheckInStatus.safe:
          cardColor = AppColors.successGreen;
          iconColor = Colors.white;
          icon = Icons.check_circle;
          title = '${data.seniorName} is Safe';
          subtitle = data.timeString != null 
              ? 'Last check-in at ${data.timeString}' 
              : 'No recent check-in';
          break;
        case SeniorCheckInStatus.pending:
          cardColor = const Color(0xFFFFBF00); // Amber
          iconColor = Colors.white;
          icon = Icons.access_time_filled;
          title = 'Pending check-in';
          subtitle = 'Waiting for update...';
          break;
        case SeniorCheckInStatus.alert:
          cardColor = AppColors.dangerRed;
          iconColor = Colors.white;
          
          // Differentiate between SOS alert and missed check-in
          if (data.sosActive) {
            icon = Icons.sos_outlined;
            title = '🚨 SOS Alert from ${data.seniorName}!';
            subtitle = 'Emergency assistance requested';
            actions = [
              // ElevatedButton.icon(
              //   onPressed: () => _launchURL('tel:'), // In real app use number
              //   icon: const Icon(Icons.call),
              //   label: Text('Call ${data.seniorName}'),
              //   style: ElevatedButton.styleFrom(
              //     backgroundColor: Colors.white,
              //     foregroundColor: AppColors.dangerRed,
              //   ),
              // ),
              // const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _resolveSOS(),
                icon: const Icon(Icons.check_circle),
                label: const Text('Resolve Alert'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ];
          } else {
            icon = Icons.warning_rounded;
            title = 'Check-in time passed!';
            subtitle = 'Please check on ${data.seniorName}';
            // actions = [
            //   ElevatedButton.icon(
            //     onPressed: () => _launchURL('tel:'), // In real app use number
            //     icon: const Icon(Icons.call),
            //     label: Text('Call ${data.seniorName}'),
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: Colors.white,
            //       foregroundColor: AppColors.dangerRed,
            //     ),
            //   ),
            //   const SizedBox(height: 8),
            //   // OutlinedButton.icon(
            //   //   onPressed: () {
            //   //     ScaffoldMessenger.of(context).showSnackBar(
            //   //       const SnackBar(
            //   //         content: Text('Notifications to others sent (Placeholder)'),
            //   //       ),
            //   //     );
            //   //   },
            //   //   icon: const Icon(Icons.notifications_active),
            //   //   label: const Text('Notify Others'),
            //   //   style: OutlinedButton.styleFrom(
            //   //     foregroundColor: Colors.white,
            //   //     side: const BorderSide(color: Colors.white),
            //   //   ),
            //   // ),
            // ];
          }
          break;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            child: Icon(icon, size: 48, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          if (actions.isNotEmpty) ...[const SizedBox(height: 24), ...actions],
        ],
      ),
    );
  }

  void _launchURL(String url) async {
    // Placeholder for url launcher
    debugPrint('Launching $url');
  }

  /// Resolve SOS alert - marks the alert as handled
  void _resolveSOS() async {
    if (_selectedSeniorId == null) return;
    
    try {
      await context.read<FirestoreService>().resolveSOS(_selectedSeniorId!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Alert resolved',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error resolving SOS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to resolve alert. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.dangerRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  /// Build check-in progress cards showing finished and pending check-ins
  /// Only displayed when senior has multiple scheduled check-ins
  Widget _buildCheckInProgressCards(bool isDarkMode) {
    final state = _currentSeniorState;
    if (state == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final allSchedules = state.checkInSchedules;
    
    // Get completed schedules (check day boundary)
    List<String> completedToday = state.completedSchedulesToday;
    final resetDate = state.lastScheduleResetDate;
    if (resetDate == null ||
        resetDate.year != now.year ||
        resetDate.month != now.month ||
        resetDate.day != now.day) {
      completedToday = [];
    }

    // Calculate finished (green) and pending/overdue (amber) check-ins
    final finishedCheckIns = <String>[];
    final pendingCheckIns = <String>[];

    for (final schedule in allSchedules) {
      final scheduleUpper = schedule.toUpperCase();
      
      if (completedToday.contains(scheduleUpper) ||
          completedToday.contains(schedule)) {
        // Already completed
        finishedCheckIns.add(schedule);
      } else {
        // Check if the time has passed (overdue/pending)
        final parsed = _parseScheduleTimeForCheckIn(schedule);
        if (parsed != null) {
          final scheduleTime = DateTime(now.year, now.month, now.day,
              parsed.hour, parsed.minute);
          if (now.isAfter(scheduleTime)) {
            // Time has passed - overdue
            pendingCheckIns.add(schedule);
          }
          // Future times are not shown
        }
      }
    }

    return Row(
      children: [
        // Finished Check-ins Card (Green)
        Expanded(
          child: _buildCheckInCard(
            title: 'Finished',
            count: finishedCheckIns.length,
            total: allSchedules.length,
            times: finishedCheckIns,
            color: AppColors.successGreen,
            icon: Icons.check_circle,
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 12),
        // Pending Check-ins Card (Amber/Orange)
        Expanded(
          child: _buildCheckInCard(
            title: 'Pending',
            count: pendingCheckIns.length,
            total: allSchedules.length,
            times: pendingCheckIns,
            color: pendingCheckIns.isEmpty
                ? AppColors.textSecondary
                : const Color(0xFFFFBF00), // Amber
            icon: pendingCheckIns.isEmpty
                ? Icons.check_circle_outline
                : Icons.access_time_filled,
            isDarkMode: isDarkMode,
          ),
        ),
      ],
    );
  }

  /// Parse schedule time string to TimeOfDay
  DateTime? _parseScheduleTimeForCheckIn(String schedule) {
    try {
      final format = DateFormat('h:mm a');
      return format.parse(schedule.toUpperCase());
    } catch (e) {
      return null;
    }
  }

  /// Build a single check-in status card
  Widget _buildCheckInCard({
    required String title,
    required int count,
    required int total,
    required List<String> times,
    required Color color,
    required IconData icon,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: isDarkMode ? null : [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                title,
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
          const SizedBox(height: 12),
          // Count display
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$count',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                // TextSpan(
                //   text: ' / $total',
                //   style: GoogleFonts.inter(
                //     fontSize: 16,
                //     fontWeight: FontWeight.w500,
                //     color: isDarkMode
                //         ? AppColors.textSecondaryDark
                //         : AppColors.textSecondary,
                //   ),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Times list
          if (times.isNotEmpty)
            Text(
              times.join(', '),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              title == 'Pending' ? 'All caught up!' : 'None yet',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(
    String label,
    String value,
    IconData icon,
    bool isDarkMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : AppColors.inputFillLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primaryBlue, size: 28),
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
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAICareCard(bool isDarkMode, [int streak = 0]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user,
                  color: AppColors.successGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AI Care Intelligence',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Insight Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.successGreen.withValues(alpha: 0.08),
                  AppColors.successGreen.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.successGreen.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: AppColors.successGreen,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    streak >= 7
                        ? 'Consistent medication adherence! Great job maintaining routine.'
                        : (streak == 0
                              ? 'Medication missed recently. Check in on them.'
                              : 'Monitoring daily routine patterns.'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HEALTH TAB ====================
  Widget _buildHealthTab(bool isDarkMode) {
    if (_isLoadingSeniorData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_seniorData == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildHealthPlaceholderCard(
          isDarkMode: isDarkMode,
          icon: Icons.favorite_border,
          title: 'No Health Data Available',
          subtitle: 'Connect with a senior family member to view their wellness data and health insights.',
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Month Selector
          _buildMonthSelector(isDarkMode),
          
          const SizedBox(height: 16),

          // Wellness Index Graph
          _buildWellnessIndexGraph(_weeklyWellnessData, isDarkMode),

          const SizedBox(height: 16),
          // Cognitive Performance Card
          _buildCognitivePerformanceCard(isDarkMode),
        ],
      ),
    );
  }

  /// Handles month selection change - reloads data for new month
  void _onMonthChanged(int delta) {
    final newMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    
    // Don't allow future months
    final now = DateTime.now();
    if (newMonth.year > now.year || 
        (newMonth.year == now.year && newMonth.month > now.month)) {
      return;
    }
    
    setState(() {
      _selectedMonth = newMonth;
      _isLoadingSeniorData = true;
      _weeklyWellnessData = [];
      _gameResults = [];
      _cognitiveMetrics = null;
    });
    
    if (_selectedSeniorId != null) {
      _loadSeniorDetails(_selectedSeniorId!);
    }
  }

  /// Builds the month selector UI
  Widget _buildMonthSelector(bool isDarkMode) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && 
        _selectedMonth.month == now.month;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Month Button
          IconButton(
            onPressed: () => _onMonthChanged(-1),
            icon: Icon(
              Icons.chevron_left,
              color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          
          // Month/Year Display
          Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          
          // Next Month Button (disabled if current month)
          IconButton(
            onPressed: isCurrentMonth ? null : () => _onMonthChanged(1),
            icon: Icon(
              Icons.chevron_right,
              color: isCurrentMonth 
                  ? (isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary).withValues(alpha: 0.3)
                  : (isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary),
            ),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildWellnessIndexGraph(
    List<WellnessDataPoint> data,
    bool isDarkMode,
  ) {
    // Require minimum 3 data points for meaningful chart
    const int minDataPoints = 3;
    
    if (data.isEmpty) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.show_chart,
        title: 'No Wellness Data Yet',
        subtitle: 'Wellness data will appear here once check-ins are recorded.',
      );
    }
    
    if (data.length < minDataPoints) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.show_chart,
        title: 'Building Wellness Index',
        subtitle: '${minDataPoints - data.length} more check-ins needed to display the wellness chart.',
      );
    }

    // Calculate spots
    // Data is assumed descending (recent first). Reverse for graph (old -> new)
    final sorted = List<WellnessDataPoint>.from(data.reversed);
    
    // Limit to last 14 data points for better readability
    final displayData = sorted.length > 14 ? sorted.sublist(sorted.length - 14) : sorted;
    
    final wellnessSpots = <FlSpot>[];
    final moodSpots = <FlSpot>[];
    final sleepSpots = <FlSpot>[];
    final energySpots = <FlSpot>[];
    
    for (int i = 0; i < displayData.length; i++) {
      final point = displayData[i];
      wellnessSpots.add(FlSpot(i.toDouble(), point.wellnessIndex));
      if (point.mood != null) moodSpots.add(FlSpot(i.toDouble(), point.mood!));
      if (point.sleep != null) sleepSpots.add(FlSpot(i.toDouble(), point.sleep!));
      if (point.energy != null) energySpots.add(FlSpot(i.toDouble(), point.energy!));
    }
    
    // Calculate date interval for X-axis labels (show every 2-4 labels depending on data count)
    final int labelInterval = displayData.length <= 7 ? 1 : (displayData.length <= 10 ? 2 : 3);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wellness Trends',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              // Data count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.length} check-ins',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem('Wellness', AppColors.primaryBlue, isDarkMode),
              _buildLegendItem('Mood', AppColors.successGreen, isDarkMode),
              _buildLegendItem('Sleep', Colors.purple, isDarkMode),
              _buildLegendItem('Energy', AppColors.warningOrange, isDarkMode),
            ],
          ),
          const SizedBox(height: 16),
          
          // Chart
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.25,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDarkMode 
                        ? AppColors.borderDark.withValues(alpha: 0.5) 
                        : Colors.grey.withValues(alpha: 0.2),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 0.25,
                      getTitlesWidget: (val, meta) {
                        if (val == 0 || val == 0.25 || val == 0.5 || val == 0.75 || val == 1.0) {
                          return Text(
                            '${(val * 100).toInt()}%',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: isDarkMode ? AppColors.textSecondaryDark : Colors.grey,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) {
                        int index = val.toInt();
                        // Show label based on interval to avoid crowding
                        if (index >= 0 && index < displayData.length && index % labelInterval == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('M/d').format(displayData[index].date),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: isDarkMode ? AppColors.textSecondaryDark : Colors.grey,
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (displayData.length - 1).toDouble(),
                minY: 0,
                maxY: 1.05,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => isDarkMode 
                        ? AppColors.surfaceDark.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.9),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        String label;
                        if (spot.barIndex == 0) {
                          label = 'Wellness';
                        } else if (spot.barIndex == 1) {
                          label = 'Mood';
                        } else if (spot.barIndex == 2) {
                          label = 'Sleep';
                        } else {
                          label = 'Energy';
                        }
                        return LineTooltipItem(
                          '$label: ${(spot.y * 100).toInt()}%',
                          GoogleFonts.inter(
                            fontSize: 12,
                            color: spot.bar.color ?? Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // Wellness Index (main line - thicker)
                  LineChartBarData(
                    spots: wellnessSpots,
                    isCurved: true,
                    color: AppColors.primaryBlue,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    ),
                  ),
                  // Mood (green)
                  if (moodSpots.isNotEmpty)
                    LineChartBarData(
                      spots: moodSpots,
                      isCurved: true,
                      color: AppColors.successGreen,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      dashArray: [5, 5],
                    ),
                  // Sleep (purple)
                  if (sleepSpots.isNotEmpty)
                    LineChartBarData(
                      spots: sleepSpots,
                      isCurved: true,
                      color: Colors.purple,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      dashArray: [5, 5],
                    ),
                  // Energy (orange)
                  if (energySpots.isNotEmpty)
                    LineChartBarData(
                      spots: energySpots,
                      isCurved: true,
                      color: AppColors.warningOrange,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      dashArray: [5, 5],
                    ),
                ],
              ),
            ),
          ),
          
          // Summary
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode 
                  ? AppColors.primaryBlue.withValues(alpha: 0.1)
                  : AppColors.primaryBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wellness Index = Average of Mood, Sleep & Energy scores',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCognitivePerformanceCard(bool isDarkMode) {
    // Use actual game results data (now fetched in _loadSeniorDetails)
    const int minDataPoints = 5;
    final cognitiveDataCount = _gameResults.length;
    
    if (cognitiveDataCount == 0) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.psychology,
        title: 'No Cognitive Data Yet',
        subtitle: 'Play brain games to track cognitive performance over time.',
      );
    }
    
    if (cognitiveDataCount < minDataPoints) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.psychology,
        title: 'Building Cognitive Index',
        subtitle: '${minDataPoints - cognitiveDataCount} more games needed to display the cognitive chart.',
      );
    }
    
    // Get cognitive metrics from calculated values
    final metrics = _cognitiveMetrics ?? CognitiveMetrics.fromResults(_gameResults);
    
    // Determine trend color and message
    Color trendColor;
    String trendMessage;
    switch (metrics.trend) {
      case 'improving':
        trendColor = AppColors.successGreen;
        trendMessage = 'Overall performance trending positive ↑';
      case 'declining':
        trendColor = AppColors.warningOrange;
        trendMessage = 'Performance may need attention ↓';
      default:
        trendColor = AppColors.primaryBlue;
        trendMessage = 'Performance is stable →';
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cognitive Performance',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${metrics.gamesPlayed} games played',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDarkMode
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Performance Metrics - using real calculated values
          _buildPerformanceMetric('Memory Recall', metrics.memoryRecall, isDarkMode),
          const SizedBox(height: 12),
          _buildPerformanceMetric('Reaction Speed', metrics.reactionSpeed, isDarkMode),
          const SizedBox(height: 12),
          _buildPerformanceMetric('Overall Score', metrics.overallScore, isDarkMode),

          const SizedBox(height: 16),
          Center(
            child: Text(
              trendMessage,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: trendColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Builds a styled placeholder card for health data sections
  Widget _buildHealthPlaceholderCard({
    required bool isDarkMode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode 
              ? AppColors.borderDark 
              : AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDarkMode 
                  ? AppColors.textSecondaryDark 
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetric(String label, double value, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: isDarkMode
                ? AppColors.borderDark
                : AppColors.inputFillLight,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.primaryBlue,
            ),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  // ==================== VAULT TAB ====================
  Widget _buildVaultTab(bool isDarkMode) {
    if (_isLoadingSeniorData) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // No vault data yet
    if (_vaultData == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.lock_outline,
              size: 64,
              color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Vault Data',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The senior has not set up their security vault yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final vault = _vaultData!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Home Access Section
          _buildVaultSectionTitle('HOME ACCESS', isDarkMode),
          const SizedBox(height: 12),
          _buildHomeAccessCard(isDarkMode),
          const SizedBox(height: 24),

          // Pet Care Section (if any pets)
          if (vault.pets.isNotEmpty) ...[
            _buildVaultSectionTitle('PET CARE (${vault.pets.length})', isDarkMode),
            const SizedBox(height: 12),
            ...vault.pets.map((pet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPetCard(pet, isDarkMode),
            )),
            const SizedBox(height: 12),
          ],

          // Medical Info Section
          _buildVaultSectionTitle('MEDICAL INFO', isDarkMode),
          const SizedBox(height: 12),
          _buildMedicalInfoCard(isDarkMode),
          const SizedBox(height: 24),

          // Other Notes Section
          if (vault.otherNotes != null && vault.otherNotes!.isNotEmpty) ...[
            _buildVaultSectionTitle('OTHER NOTES', isDarkMode),
            const SizedBox(height: 12),
            _buildEmptyStateCard(vault.otherNotes!, isDarkMode),
            const SizedBox(height: 24),
          ],

          // Privacy Notice
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.successGreen.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: AppColors.successGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This information is only visible to verified family members and is used during emergencies.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDarkMode
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultSectionTitle(String title, bool isDarkMode) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryBlue,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildHomeAccessCard(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.vaultCard,
            AppColors.vaultCard.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.vaultCard.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _vaultData?.homeAddress ?? 'No address set',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          
          // Details
          if (_vaultData != null) ...[
            const SizedBox(height: 16),
            if (_vaultData!.buildingEntryCode != null && _vaultData!.buildingEntryCode!.isNotEmpty)
              _buildVaultDetailRow('Building Code', _vaultData!.buildingEntryCode!, true),
            if (_vaultData!.apartmentDoorCode != null && _vaultData!.apartmentDoorCode!.isNotEmpty)
              _buildVaultDetailRow('Door Code', _vaultData!.apartmentDoorCode!, true),
            if (_vaultData!.spareKeyLocation != null && _vaultData!.spareKeyLocation!.isNotEmpty)
              _buildVaultDetailRow('Spare Key', _vaultData!.spareKeyLocation!, false),
            if (_vaultData!.alarmCode != null && _vaultData!.alarmCode!.isNotEmpty)
              _buildVaultDetailRow('Alarm Code', _vaultData!.alarmCode!, true),
          ],
        ],
      ),
    );
  }

  Widget _buildVaultDetailRow(String label, String value, bool isSensitive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Text(
            isSensitive && !_showSensitiveData ? '••••' : value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (isSensitive) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _showSensitiveData = !_showSensitiveData),
              child: Icon(
                _showSensitiveData ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withValues(alpha: 0.7),
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPetCard(PetInfo pet, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warningOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pets, color: AppColors.warningOrange, size: 20),
              const SizedBox(width: 10),
              Text(
                '${pet.name} (${pet.type})',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (pet.medications != null || pet.vetNamePhone != null || 
              pet.foodInstructions != null || pet.specialNeeds != null) ...[
            const SizedBox(height: 12),
            if (pet.medications != null && pet.medications!.isNotEmpty)
              _buildPetDetailRow('Medications', pet.medications!, isDarkMode),
            if (pet.vetNamePhone != null && pet.vetNamePhone!.isNotEmpty)
              _buildPetDetailRow('Vet', pet.vetNamePhone!, isDarkMode),
            if (pet.foodInstructions != null && pet.foodInstructions!.isNotEmpty)
              _buildPetDetailRow('Food', pet.foodInstructions!, isDarkMode),
            if (pet.specialNeeds != null && pet.specialNeeds!.isNotEmpty)
              _buildPetDetailRow('Special Needs', pet.specialNeeds!, isDarkMode),
          ],
        ],
      ),
    );
  }

  Widget _buildPetDetailRow(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalInfoCard(bool isDarkMode) {
    final vault = _vaultData;
    final hasData = vault != null && (
      (vault.doctorNamePhone != null && vault.doctorNamePhone!.isNotEmpty) ||
      (vault.medicationsList != null && vault.medicationsList!.isNotEmpty) ||
      (vault.allergies != null && vault.allergies!.isNotEmpty) ||
      (vault.medicalConditions != null && vault.medicalConditions!.isNotEmpty)
    );

    if (!hasData) {
      return _buildEmptyStateCard('No medical info added', isDarkMode);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.dangerRed.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vault.doctorNamePhone != null && vault.doctorNamePhone!.isNotEmpty) ...[
            _buildMedicalRow('Doctor', vault.doctorNamePhone!, isDarkMode),
            const SizedBox(height: 8),
          ],
          if (vault.allergies != null && vault.allergies!.isNotEmpty) ...[
            _buildMedicalRow('Allergies', vault.allergies!, isDarkMode, isImportant: true),
            const SizedBox(height: 8),
          ],
          if (vault.medicationsList != null && vault.medicationsList!.isNotEmpty) ...[
            _buildMedicalRow('Medications', vault.medicationsList!, isDarkMode),
            const SizedBox(height: 8),
          ],
          if (vault.medicalConditions != null && vault.medicalConditions!.isNotEmpty)
            _buildMedicalRow('Conditions', vault.medicalConditions!, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildMedicalRow(String label, String value, bool isDarkMode, {bool isImportant = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isImportant ? AppColors.dangerRed : (isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateCard(String text, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : AppColors.inputFillLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          style: BorderStyle.solid,
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 15,
          color: isDarkMode
              ? AppColors.textSecondaryDark
              : AppColors.textSecondary,
        ),
      ),
    );
  }
}
