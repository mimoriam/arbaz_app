import 'package:arbaz_app/screens/navbar/calendar/calendar_screen.dart';
import 'package:arbaz_app/screens/navbar/cognitive_games/cognitive_games_screen.dart';
import 'package:arbaz_app/screens/navbar/home/senior_checkin_flow.dart';
import 'package:arbaz_app/screens/navbar/settings/settings_screen.dart';
import 'package:arbaz_app/services/firestore_service.dart';
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
  bool _hasCheckedInToday = false;
  HomeAction _activeAction = HomeAction.none;
  int _currentStreak = 0; // Dynamic streak - loaded from Firestore
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // User info
  String _userName = '';
  String? _lastCheckInLocation;
  String? _todayQuote;

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
      await _loadUserData();
    } catch (e) {
      debugPrint('Error loading user data: $e');
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
      
      // Load Profile for Name
      final profile = await firestoreService.getUserProfile(user.uid);
      if (mounted) {
        String nameToUse = '';
        if (profile?.displayName != null && profile!.displayName!.isNotEmpty) {
          nameToUse = profile.displayName!.split(' ').first;
        } else if (user.displayName != null && user.displayName!.isNotEmpty) {
          // Fallback to Firebase Auth displayName (e.g., from Google Sign-In)
          nameToUse = user.displayName!.split(' ').first;
        }
        setState(() {
          _userName = nameToUse;
        });
      }

      // Load Senior State for Check-in status
      final seniorState = await firestoreService.getSeniorState(user.uid);
      if (mounted && seniorState != null) {
        final lastCheckIn = seniorState.lastCheckIn;
        if (lastCheckIn != null) {
          final now = DateTime.now();
          final isToday = lastCheckIn.year == now.year && 
                          lastCheckIn.month == now.month && 
                          lastCheckIn.day == now.day;
          
          setState(() {
            _hasCheckedInToday = isToday;
            _currentStreak = seniorState.currentStreak;
            if (isToday) {
               _currentStatus = SafetyStatus.safe;
               _pulseController.stop();
            }
          });
        } else {
          setState(() {
            _currentStreak = seniorState.currentStreak;
          });
        }
        
        // Populate last check-in location from profile (stored during check-in)
        if (profile?.locationAddress != null) {
          setState(() {
            _lastCheckInLocation = profile!.locationAddress;
          });
        }
      }
      
      // Cache daily quote
      final quote = quotesService.getQuoteForToday(user.uid, DateTime.now());
      if (mounted) {
        setState(() => _todayQuote = quote);
      }
      
    }
  }

  /// Check location permission status (no auto-request)
  Future<void> _checkLocationPermission() async {
    if (!mounted) return;
    final locationService = context.read<LocationService>();
    final permission = await locationService.checkPermission();
    
    // Just log the status - don't auto-request to respect user choice
    debugPrint('Location permission status: $permission');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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

    try {
      // Step 1: Grant role in Firestore first
      await setRoleInFirestore(user.uid);

      // Step 2: Update local preference
      await rolePreferenceService.setActiveRole(user.uid, targetRole);

      if (!mounted) return;

      // Step 3: Navigate only after both operations succeed
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    } catch (e, stackTrace) {
      debugPrint('Error switching to $targetRole: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() => _activeAction = HomeAction.none);
        
        // Show contextual error message
        String errorMessage = 'Failed to switch roles.';
        if (e.toString().contains('permission')) {
          errorMessage = 'Permission denied. Please try again later.';
        } else if (e.toString().contains('network') || e.toString().contains('connection')) {
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

    // Button is not clickable after check-in, so no toggle needed
    // This check is redundant now but kept for safety
    if (_hasCheckedInToday) {
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
            setState(() {
              _hasCheckedInToday = true;
              _currentStatus = SafetyStatus.safe; // Now shows blue "I'M SAFE" button
              _currentStreak++; // Increment streak on successful check-in
              // Stop pulse animation after successful check-in
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.dangerRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.dangerRed, size: 24),
              ),
              const SizedBox(width: 12),
              Text('Emergency Alert', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Text(
            'This will immediately alert your family members. Are you sure you want to send an emergency alert?',
            style: GoogleFonts.inter(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _sendEmergencyAlert();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Send Alert', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _sendEmergencyAlert() {
    setState(() {
      _isSendingHelp = true;
    });

    // Simulate sending help - in real app, this would trigger actual alerts
    Future.delayed(const Duration(seconds: 3), () {
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer<VacationModeProvider>(
      builder: (context, vacationProvider, child) {
        final isVacationMode = vacationProvider.isVacationMode;

        return Scaffold(
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
                          isLoading: vacationProvider.isLoading,
                        ),

                        SizedBox(height: screenHeight * 0.05),

                        // Daily Health Message Section
                        _buildHealthMessageSection(isDarkMode),

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
        );
      },
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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: isDarkMode
                      ? AppColors.surfaceDark
                      : AppColors.inputFillLight,
                  child: Icon(
                    Icons.person_outline,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    size: 26,
                  ),
                ),
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
                          builder: (context) => const CalendarScreen()),
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
                      MaterialPageRoute(builder: (context) => const CognitiveGamesScreen()),
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
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                    if (mounted) {
                      setState(() => _activeAction = HomeAction.none);
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
                      color: isDarkMode ? Colors.white70 : AppColors.primaryBlue,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: AppColors.primaryBlue,
                      ),
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
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF6366F1), const Color(0xFF818CF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sun Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.wb_sunny_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vacation Mode On',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check-ins are paused',
                  style: GoogleFonts.inter(
                    fontSize: 13,
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
            size: 24,
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
    // Green: Default (not checked in) - clickable
    // Blue: After questionnaire completed - NOT clickable
    // Yellow: Running late (SafetyStatus.ok without questionnaire completion)
    
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
      subtitleText = isLoading ? "Syncing status..." : "Disabled during vacation";
      isClickable = false;
    } else if (_hasCheckedInToday) {
      // Blue state - completed questionnaire (not clickable)
      primaryColor = const Color(0xFF4DA6FF); // Light blue
      secondaryColor = const Color(0xFF2B8FE5); // Darker blue
      ringColor = const Color(0xFF7EC8FF); // Ring color
      statusIcon = Icons.check;
      statusText = "I'M SAFE";
      subtitleText = "You've checked in for today";
      isClickable = false; // Not clickable after completion    } else if (_currentStatus == SafetyStatus.ok) {
      // Yellow state - running late
      primaryColor = const Color(0xFFFFBF00); // Golden yellow
      secondaryColor = const Color(0xFFE5A800); // Darker yellow
      ringColor = const Color(0xFFFFD966); // Light yellow ring
      statusIcon = Icons.priority_high;
      statusText = "I'M OK!";
      subtitleText = "Tap to tell family I'm okay";
      isClickable = true;
    } else {
      // Green state - default (not checked in)
      primaryColor = const Color(0xFF2ECC71); // Vibrant green
      secondaryColor = const Color(0xFF27AE60); // Darker green
      ringColor = const Color(0xFF58D68D); // Light green ring
      statusIcon = Icons.favorite;
      statusText = "I'M OK";
      subtitleText = "Tap to tell family I'm okay";
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
                        : Icon(
                            statusIcon,
                            color: primaryColor,
                            size: 28,
                          ),
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

  Widget _buildHealthMessageSection(bool isDarkMode) {
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
      message = "You haven't checked in yet today";
      subMessage = "Please take a moment to let us know you're okay.";
    }

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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(28),
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
                  // Quote Icon or Status Dot
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 12,
                    height: 12,
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
                  const SizedBox(width: 16),

                  // Message Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            height: 1.4,
                            fontStyle: _hasCheckedInToday ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        if (subMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subMessage,
                            style: GoogleFonts.inter(
                              fontSize: 13,
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
               style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
             ),
             const SizedBox(height: 16),
             Text(
               "Share your unique code so family can monitor your safety.",
               textAlign: TextAlign.center,
               style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
             ),
             const SizedBox(height: 24),
             ListTile(
               leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.share, color: AppColors.primaryBlue)),
               title: const Text("Share Invite Code"),
               onTap: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    final qrService = context.read<QrInviteService>();
                    Navigator.pop(context); // Close sheet
                    // Generate code for family role
                    final code = qrService.generateInviteQrData(user.uid, 'family');
                    await SharePlus.instance.share(ShareParams(text: code));
                  } else {
                    Navigator.pop(context);
                  }
               },             ),
             ListTile(
               leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.qr_code, color: AppColors.primaryBlue)),
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
         const SnackBar(content: Text("User session not found. Please log in again."))
       );
       return;
     }

     final qrService = context.read<QrInviteService>();
     
     showDialog(
       context: context,
       builder: (context) => FutureBuilder<String>(
         // Simulating a small delay to show the loading state as requested, 
         // although QR generation is synchronous.
         future: Future.delayed(const Duration(milliseconds: 500), 
           () => qrService.generateInviteQrData(user.uid, 'family')
         ),
         builder: (context, snapshot) {
           return AlertDialog(
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                   style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
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
                       color: AppColors.primaryBlue
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
            const Icon(Icons.error_outline, color: AppColors.dangerRed, size: 40),
            const SizedBox(height: 8),
            Text(
              "Failed to generate QR",
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.dangerRed),
            ),          ],
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
                    child: const Icon(Icons.person_add, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CONNECT FAMILY',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text(
                          'Add contacts to enable SOS',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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

  // Mock data - in a real app, this comes from a service
  final String _seniorName = 'Annie';
  final String _familyName = 'John';
  final String _lastCheckIn = '22:13';
  final String _coordinates = '30.1511, 71.4277';
  final bool _isRecentlyActive = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

    try {
      // Step 1: Grant role in Firestore first
      await setRoleInFirestore(user.uid);

      // Step 2: Update local preference
      await rolePreferenceService.setActiveRole(user.uid, targetRole);

      if (!mounted) return;

      // Step 3: Navigate only after both operations succeed
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    } catch (e, stackTrace) {
      debugPrint('Error switching to $targetRole: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() => _activeAction = HomeAction.none);
        
        // Show contextual error message
        String errorMessage = 'Failed to switch roles.';
        if (e.toString().contains('permission')) {
          errorMessage = 'Permission denied. Please try again later.';
        } else if (e.toString().contains('network') || e.toString().contains('connection')) {
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

  void _switchToSenior() {
    final firestoreService = context.read<FirestoreService>();
    _switchRole(
      targetRole: 'senior',
      setRoleInFirestore: (uid) => firestoreService.setAsSenior(uid),
      targetScreen: const SeniorHomeScreen(),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'GOOD MORNING';
    } else if (hour < 17) {
      return 'GOOD AFTERNOON';
    } else {
      return 'GOOD EVENING';
    }
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
            // Custom Header
            _buildHeader(isDarkMode),

            const SizedBox(height: 16),

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
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // User Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.successGreen.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              backgroundColor: isDarkMode
                  ? AppColors.surfaceDark
                  : AppColors.inputFillLight,
              child: Icon(
                Icons.family_restroom,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Greeting Text
          Expanded(
            child: Column(
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
          _buildHeaderIcon(
            Icons.calendar_today_outlined,
            isDarkMode,
            isLoading: _activeAction == HomeAction.calendar,
            onTap: () async {
              setState(() => _activeAction = HomeAction.calendar);
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CalendarScreen()),
                );
                if (mounted) {
                  setState(() => _activeAction = HomeAction.none);
                }
              }
            },
          ),
          const SizedBox(width: 8),
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
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
                if (mounted) {
                  setState(() => _activeAction = HomeAction.none);
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

  // ==================== STATUS TAB ====================
  Widget _buildStatusTab(bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Safe Status Badge
          _buildSafeStatusBadge(isDarkMode),
          const SizedBox(height: 32),

          // Live Tracking Card
          _buildLiveTrackingCard(isDarkMode),
          const SizedBox(height: 16),

          // Quick Stats Row
          Row(
            children: [
              Expanded(
                child: _buildQuickStatCard(
                  'Check-ins',
                  '47',
                  Icons.check_circle_outline,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickStatCard(
                  'Streak',
                  '7 days',
                  Icons.local_fire_department,
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Care Intelligence Card
          _buildAICareCard(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildSafeStatusBadge(bool isDarkMode) {
    return Column(
      children: [
        // Green circle with checkmark
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.successGreen,
                AppColors.successGreen.withValues(alpha: 0.8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.successGreen.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.check_circle, color: Colors.white, size: 52),
        ),
        const SizedBox(height: 24),

        // Status text
        Text(
          '$_seniorName is Safe',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDarkMode
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.successGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.successGreen,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Last check-in at $_lastCheckIn',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successGreen,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildLiveTrackingCard(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.08),
            AppColors.primaryBlue.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Location icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue,
                  AppColors.primaryBlue.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),

          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE TRACKING',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRecentlyActive ? 'Recently active' : 'Inactive',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _isRecentlyActive
                        ? AppColors.successGreen
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _coordinates,
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
          ),

          // Pulse indicator
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecentlyActive
                  ? AppColors.successGreen
                  : AppColors.textSecondary,
              boxShadow: _isRecentlyActive
                  ? [
                      BoxShadow(
                        color: AppColors.successGreen.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAICareCard(bool isDarkMode) {
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
                    'All vitals look great! Keep maintaining the daily routine.',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Health Metrics Row
          Row(
            children: [
              Expanded(
                child: _buildHealthMetricCard(
                  'Heart Rate',
                  '72',
                  'bpm',
                  Icons.favorite,
                  AppColors.dangerRed,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHealthMetricCard(
                  'Steps',
                  '8.2k',
                  'today',
                  Icons.directions_walk,
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
                child: _buildHealthMetricCard(
                  'Sleep',
                  '7.5',
                  'hours',
                  Icons.bedtime,
                  AppColors.successGreen,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHealthMetricCard(
                  'Energy',
                  'Good',
                  'level',
                  Icons.bolt,
                  const Color(0xFFFFBF00),
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Weekly Trends Chart
          _buildWeeklyTrendsCard(isDarkMode),
          const SizedBox(height: 16),

          // Cognitive Performance Card
          _buildCognitivePerformanceCard(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildHealthMetricCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
    bool isDarkMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.backgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
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
  }

  Widget _buildWeeklyTrendsCard(bool isDarkMode) {
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
          Text(
            'Weekly Trends',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Chart area with improved design
          SizedBox(
            height: 160,
            child: CustomPaint(
              size: const Size(double.infinity, 160),
              painter: ModernHealthChartPainter(isDarkMode: isDarkMode),
            ),
          ),
          const SizedBox(height: 20),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChartLegendItem('Sleep Quality', AppColors.successGreen),
              const SizedBox(width: 24),
              _buildChartLegendItem('Energy Level', AppColors.primaryBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCognitivePerformanceCard(bool isDarkMode) {
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
            ],
          ),
          const SizedBox(height: 20),

          // Performance Metrics
          _buildPerformanceMetric('Memory Recall', 0.85, isDarkMode),
          const SizedBox(height: 12),
          _buildPerformanceMetric('Reaction Speed', 0.92, isDarkMode),
          const SizedBox(height: 12),
          _buildPerformanceMetric('Focus Duration', 0.78, isDarkMode),

          const SizedBox(height: 16),
          Center(
            child: Text(
              'Overall stability trending positive',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.successGreen,
                fontWeight: FontWeight.w600,
              ),
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

          // Primary Doctor Section
          _buildVaultSectionTitle('PRIMARY DOCTOR', isDarkMode),
          const SizedBox(height: 12),
          _buildEmptyStateCard('Not specified', isDarkMode),
          const SizedBox(height: 24),

          // Medical Notes Section
          _buildVaultSectionTitle('MEDICAL NOTES', isDarkMode),
          const SizedBox(height: 12),
          _buildEmptyStateCard('None listed', isDarkMode),
          const SizedBox(height: 40),

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
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No address set',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Code: N/A',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

// Modern Health Chart Painter with cleaner design
class ModernHealthChartPainter extends CustomPainter {
  final bool isDarkMode;

  ModernHealthChartPainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    // Paint for grid lines
    final gridPaint = Paint()
      ..color = (isDarkMode ? AppColors.borderDark : AppColors.borderLight)
          .withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Paint for Sleep Quality line (green)
    final sleepPaint = Paint()
      ..color = AppColors.successGreen
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Paint for Energy Level line (blue)
    final energyPaint = Paint()
      ..color = AppColors.primaryBlue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Sample data points (7 days)
    final sleepData = [0.6, 0.8, 0.7, 0.9, 0.8, 0.75, 0.85];
    final energyData = [0.7, 0.6, 0.8, 0.7, 0.9, 0.85, 0.8];

    // Draw Sleep Quality curve
    final sleepPath = Path();
    for (int i = 0; i < sleepData.length; i++) {
      final x = (size.width / (sleepData.length - 1)) * i;
      final y = size.height - (size.height * sleepData[i]);
      if (i == 0) {
        sleepPath.moveTo(x, y);
      } else {
        sleepPath.lineTo(x, y);
      }

      // Draw data point circle
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()
          ..color = AppColors.successGreen
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(sleepPath, sleepPaint);

    // Draw Energy Level curve
    final energyPath = Path();
    for (int i = 0; i < energyData.length; i++) {
      final x = (size.width / (energyData.length - 1)) * i;
      final y = size.height - (size.height * energyData[i]);
      if (i == 0) {
        energyPath.moveTo(x, y);
      } else {
        energyPath.lineTo(x, y);
      }

      // Draw data point circle
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()
          ..color = AppColors.primaryBlue
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(energyPath, energyPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Keep the old painter for reference (can be deleted later)
class HealthChartPainter extends CustomPainter {
  final bool isDarkMode;

  HealthChartPainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final greenPaint = Paint()
      ..color = AppColors.successGreen
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final bluePaint = Paint()
      ..color = AppColors.primaryBlue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw green curve (sleep quality)
    final greenPath = Path();
    greenPath.moveTo(0, size.height * 0.5);
    greenPath.cubicTo(
      size.width * 0.2,
      size.height * 0.6,
      size.width * 0.4,
      size.height * 0.2,
      size.width * 0.5,
      size.height * 0.4,
    );
    greenPath.cubicTo(
      size.width * 0.6,
      size.height * 0.6,
      size.width * 0.8,
      size.height * 0.8,
      size.width,
      size.height * 0.5,
    );
    canvas.drawPath(greenPath, greenPaint);

    // Draw blue curve (energy level)
    final bluePath = Path();
    bluePath.moveTo(0, size.height * 0.4);
    bluePath.cubicTo(
      size.width * 0.15,
      size.height * 0.3,
      size.width * 0.3,
      size.height * 0.1,
      size.width * 0.45,
      size.height * 0.15,
    );
    bluePath.cubicTo(
      size.width * 0.55,
      size.height * 0.2,
      size.width * 0.65,
      size.height * 0.5,
      size.width * 0.75,
      size.height * 0.4,
    );
    bluePath.cubicTo(
      size.width * 0.85,
      size.height * 0.3,
      size.width * 0.95,
      size.height * 0.4,
      size.width,
      size.height * 0.35,
    );
    canvas.drawPath(bluePath, bluePaint);

    // Draw data tooltip box
    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.6, size.height * 0.3, 70, 60),
      const Radius.circular(8),
    );
    final tooltipPaint = Paint()
      ..color = isDarkMode ? AppColors.surfaceDark : Colors.white
      ..style = PaintingStyle.fill;
    final tooltipBorderPaint = Paint()
      ..color = isDarkMode ? AppColors.borderDark : AppColors.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(tooltipRect, tooltipPaint);
    canvas.drawRRect(tooltipRect, tooltipBorderPaint);

    // Draw tooltip text
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Day number
    textPainter.text = TextSpan(
      text: '09',
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.62, size.height * 0.34));

    // Energy label
    textPainter.text = TextSpan(
      text: 'energy : 3',
      style: GoogleFonts.inter(fontSize: 10, color: AppColors.successGreen),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.62, size.height * 0.48));

    // Sleep label
    textPainter.text = TextSpan(
      text: 'sleep : 3',
      style: GoogleFonts.inter(fontSize: 10, color: AppColors.primaryBlue),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.62, size.height * 0.58));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
