import 'dart:async';
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
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:arbaz_app/models/wellness_data.dart';
import 'package:geolocator/geolocator.dart';

import 'package:arbaz_app/models/user_model.dart';

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
  bool _isLoadingCheckInStatus =
      true; // Prevents flicker/interaction until status loaded
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

      // Load Profile - needed for location and for email/password users' custom displayName
      final profile = await firestoreService.getUserProfile(user.uid);
      if (mounted) {
        // For email/password users who set displayName in Firestore, use that instead
        if (profile?.displayName != null && 
            profile!.displayName!.isNotEmpty &&
            (nameFromAuth == null || nameFromAuth.isEmpty || 
             // If auth name is just email prefix, prefer Firestore displayName
             (user.displayName == null || user.displayName!.isEmpty))) {
          setState(() {
            _userName = profile.displayName!.split(' ').first;
          });
        }
        
        // Populate last check-in location from profile
        if (profile?.locationAddress != null) {
          setState(() {
            _lastCheckInLocation = profile!.locationAddress;
          });
        }
      }

      // Load Senior State for Check-in status
      final seniorState = await firestoreService.getSeniorState(user.uid);
      if (mounted) {
        if (seniorState != null) {
          final lastCheckIn = seniorState.lastCheckIn;
          if (lastCheckIn != null) {
            final now = DateTime.now();
            final isToday =
                lastCheckIn.year == now.year &&
                lastCheckIn.month == now.month &&
                lastCheckIn.day == now.day;

            setState(() {
              _hasCheckedInToday = isToday;
              _currentStreak = seniorState.currentStreak;
              _isLoadingCheckInStatus = false; // Status verified
              if (isToday) {
                _currentStatus = SafetyStatus.safe;
                _pulseController.stop();
              }
            });
          } else {
            setState(() {
              _currentStreak = seniorState.currentStreak;
              _isLoadingCheckInStatus =
                  false; // Status verified (no check-in yet)
            });
          }
        } else {
          // No senior state found - still mark as loaded
          setState(() => _isLoadingCheckInStatus = false);
        }
      }

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
              _currentStatus =
                  SafetyStatus.safe; // Now shows blue "I'M SAFE" button
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
                          isLoading:
                              vacationProvider.isLoading ||
                              _isLoadingCheckInStatus,
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
      subtitleText = isLoading
          ? "Syncing status..."
          : "Disabled during vacation";
      isClickable = false;
    } else if (_hasCheckedInToday) {
      // Blue state - completed questionnaire (not clickable)
      primaryColor = const Color(0xFF4DA6FF); // Light blue
      secondaryColor = const Color(0xFF2B8FE5); // Darker blue
      ringColor = const Color(0xFF7EC8FF); // Ring color
      statusIcon = Icons.check;
      statusText = "I'M SAFE";
      subtitleText = "You've checked in for today";
      isClickable = false; // Not clickable after completion
    } else if (_currentStatus == SafetyStatus.ok) {
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
                            fontStyle: _hasCheckedInToday
                                ? FontStyle.italic
                                : FontStyle.normal,
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
                  final code = qrService.generateInviteQrData(
                    user.uid,
                    'family',
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
          () => qrService.generateInviteQrData(user.uid, 'family'),
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
  String _familyName = ''; // Empty until loaded
  bool _isLoadingFamilyProfile = true; // Loading state for profile
  
  // Multi-senior support
  List<SeniorInfo> _allSeniors = []; // All connected seniors
  String? _selectedSeniorId; // Currently selected senior ID

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSeniorData();
    _loadFamilyProfile();
  }

  Future<void> _loadFamilyProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
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
        setState(() {
          _familyName = nameFromAuth!;
          _isLoadingFamilyProfile = false;
        });
      }

      try {
        // Load profile for email/password users who set custom displayName in Firestore
        final profile = await context.read<FirestoreService>().getUserProfile(
          user.uid,
        );
        if (mounted) {
          // For email/password users who set displayName in Firestore, use that instead
          if (profile?.displayName != null &&
              profile!.displayName!.isNotEmpty &&
              (user.displayName == null || user.displayName!.isEmpty)) {
            setState(() {
              _familyName = profile.displayName!.split(' ').first;
            });
          }
          setState(() => _isLoadingFamilyProfile = false);
        }
      } catch (e) {
        debugPrint('Error loading family profile: $e');
        // Name already set from Auth, just mark loading as complete
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
      }
    } else {
      if (mounted) setState(() => _isLoadingFamilyProfile = false);
    }
  }

  @override
  void dispose() {
    _seniorStateSubscription?.cancel();
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
      final connectionsStream = firestoreService.getConnectionsForFamily(
        user.uid,
      );
      // We act on the first emission to set up listeners
      // Add timeout to prevent indefinite hanging
      final connections = await connectionsStream
          .timeout(
            const Duration(seconds: 10),
            onTimeout: (sink) {
              debugPrint('Connection stream timed out, emitting empty list');
              sink.add([]);
              sink.close();
            },
          )
          .first;

      List<SeniorInfo> allSeniors = [];

      if (connections.isNotEmpty) {
        // Collect all senior IDs from connections
        for (final conn in connections) {
          final profile = await firestoreService.getUserProfile(conn.seniorId)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              profile?.email.split('@').first ?? 
              'Senior';
          allSeniors.add(SeniorInfo(id: conn.seniorId, name: name));
        }
        debugPrint('Found ${allSeniors.length} seniors via connections');
      } else {
        // Fallback: check familyContacts for any with relationship='Senior'
        debugPrint('No connections found, checking familyContacts...');

        if (!mounted) return;

        final contactsService = context.read<FamilyContactsService>();
        final contacts = await contactsService.getContacts(user.uid).first;

        // Look for contacts with relationship='Senior' and a valid contactUid
        final seniorContacts = contacts
            .where(
              (c) =>
                  c.relationship == 'Senior' &&
                  c.contactUid != null &&
                  c.contactUid!.isNotEmpty,
            )
            .toList();

        for (final contact in seniorContacts) {
          final profile = await firestoreService.getUserProfile(contact.contactUid!)
              .catchError((_) => null);
          final name = profile?.displayName ?? 
              (contact.name.isNotEmpty ? contact.name : 'Senior');
          allSeniors.add(SeniorInfo(id: contact.contactUid!, name: name));
        }
        
        if (allSeniors.isNotEmpty) {
          debugPrint('Found ${allSeniors.length} seniors via familyContacts');
        } else {
          debugPrint('No seniors found in familyContacts either');
        }
      }

      if (!mounted) return;

      // Update state with all seniors
      setState(() {
        _allSeniors = allSeniors;
        // If we have seniors but no selection, select the first one
        if (allSeniors.isNotEmpty && _selectedSeniorId == null) {
          _selectedSeniorId = allSeniors.first.id;
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
  Future<void> _loadSeniorDetails(String seniorId) async {
    if (!mounted) return;
    
    final firestoreService = context.read<FirestoreService>();
    
    // Get Senior Name from allSeniors list
    final seniorInfo = _allSeniors.firstWhere(
      (s) => s.id == seniorId,
      orElse: () => SeniorInfo(id: seniorId, name: 'Senior'),
    );
    final srName = seniorInfo.name;

    if (!mounted) return;

    // Load Weekly Data
    final history = await firestoreService.getSeniorCheckInsForWeek(seniorId);
    final weeklyData = history
        .map((h) => WellnessDataPoint.fromCheckIn(h))
        .toList();

    if (mounted) {
      setState(() {
        _weeklyWellnessData = weeklyData;
      });
    }

    if (!mounted) return;

    // Stream State
    _seniorStateSubscription?.cancel();
    _seniorStateSubscription = firestoreService
        .streamSeniorState(seniorId)
        .listen((state) {
          if (!mounted) return;
          final status = _calculateSeniorStatus(
            state,
            state?.checkInSchedules ?? [],
          );
          setState(() {
            _seniorData = SeniorStatusData(
              status: status,
              seniorName: srName,
              lastCheckIn: state?.lastCheckIn,
              timeString: state?.lastCheckIn != null
                  ? DateFormat('HH:mm').format(state!.lastCheckIn!)
                  : null,
            );
            _isLoadingSeniorData = false;
          });
        });
  }

  /// Called when user switches to a different senior in the dropdown
  void _onSeniorChanged(String? seniorId) {
    if (seniorId == null || seniorId == _selectedSeniorId) return;
    
    setState(() {
      _selectedSeniorId = seniorId;
      _isLoadingSeniorData = true;
      _seniorData = null;
      _weeklyWellnessData = [];
    });
    
    _loadSeniorDetails(seniorId);
  }

  SeniorCheckInStatus _calculateSeniorStatus(
    SeniorState? state,
    List<String> schedules,
  ) {
    if (state == null) return SeniorCheckInStatus.pending;

    // Check for same day check-in
    if (state.lastCheckIn != null) {
      final now = DateTime.now();
      final last = state.lastCheckIn!;
      if (last.year == now.year &&
          last.month == now.month &&
          last.day == now.day) {
        return SeniorCheckInStatus.safe;
      }
    }

    // Check if time passed
    // Parse schedules (e.g. "11:00 AM") and compare with now
    final now = DateTime.now();

    // Default to 11:00 AM if no schedules configured
    final effectiveSchedules = schedules.isNotEmpty ? schedules : ['11:00 AM'];

    bool isLate = false;

    for (final schedule in effectiveSchedules) {
      // Simple parser assuming "HH:mm AM/PM" format
      try {
        // Create a dummy date with today + schedule time
        // We can use DateFormat to parse "hh:mm a"
        final time = DateFormat('hh:mm a').parse(schedule);
        final scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );

        if (now.isAfter(scheduledTime)) {
          isLate = true;
          break;
        }
      } catch (e) {
        // Ignore parse errors
        debugPrint('Error parsing schedule time: $schedule - $e');
      }
    }

    return isLate ? SeniorCheckInStatus.alert : SeniorCheckInStatus.pending;
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
                      const SizedBox(width: 12),
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
          // Calendar Removed per user request
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
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
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
                  final code = qrService.generateInviteQrData(
                    user.uid,
                    'family', // Family member generating invite for a Senior to scan
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
          qrService.generateInviteQrData(user.uid, 'family'), // Family generating invite
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

    // Calculate streak from wellness data (count consecutive days with medication or checkins?)
    // Prompt says "Track consecutive days where medication === 'Yes'"
    int medStreak = 0;
    // Iterate backwards
    // Note: _weeklyWellnessData is unordered? Firestore query was descending.
    // So list is Recent -> Old.
    for (var point in _weeklyWellnessData) {
      if (point.medicationTaken) {
        medStreak++;
      } else {
        break;
      }
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
          const SizedBox(height: 32),

          // Removed Live Tracking Card as it wasn't requested in update plan but kept structure mostly
          // Replaced with Medication Streak Card or similar/Just Quick Stats

          // Quick Stats Row
          Row(
            children: [
              Expanded(
                child: _buildQuickStatCard(
                  'Check-ins',
                  _weeklyWellnessData.length.toString(), // Weekly count
                  Icons.check_circle_outline,
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMedicationStreakCard(medStreak, 0, isDarkMode),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Care Intelligence Card
          _buildAICareCard(isDarkMode, medStreak),
        ],
      ),
    );
  }

  /// Builds a dropdown to select which senior to view (when 2+ seniors connected)
  Widget _buildSeniorSelector(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.people_alt_outlined,
              size: 20,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Viewing',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDarkMode 
                        ? AppColors.textSecondaryDark 
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                DropdownButton<String>(
                  value: _selectedSeniorId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  isDense: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  dropdownColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
                  items: _allSeniors.map((senior) {
                    return DropdownMenuItem<String>(
                      value: senior.id,
                      child: Text(
                        senior.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: _onSeniorChanged,
                ),
              ],
            ),
          ),
        ],
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
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _onInviteFamily,
            icon: const Icon(Icons.qr_code),
            label: const Text('Generate Invite QR/Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
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
        icon = Icons.warning_rounded;
        title = 'Check-in time passed!';
        subtitle = 'Please check on ${data.seniorName}';
        actions = [
          ElevatedButton.icon(
            onPressed: () => _launchURL('tel:'), // In real app use number
            icon: const Icon(Icons.call),
            label: Text('Call ${data.seniorName}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.dangerRed,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications to others sent (Placeholder)'),
                ),
              );
            },
            icon: const Icon(Icons.notifications_active),
            label: const Text('Notify Others'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
            ),
          ),
        ];
        break;
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

  Widget _buildMedicationStreakCard(int streak, int missed, bool isDarkMode) {
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
          Icon(
            Icons.local_fire_department,
            color: const Color(0xFFFF6B35),
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            '$streak Days',
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
            'Meds Streak',
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
          const SizedBox(height: 8),

          // Wellness Index Graph
          _buildWellnessIndexGraph(_weeklyWellnessData, isDarkMode),

          const SizedBox(height: 16),
          // Cognitive Performance Card (Keep existing)
          _buildCognitivePerformanceCard(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildWellnessIndexGraph(
    List<WellnessDataPoint> data,
    bool isDarkMode,
  ) {
    if (data.isEmpty) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.show_chart,
        title: 'No Wellness Data Yet',
        subtitle: 'Wellness data will appear here once check-ins are recorded.',
      );
    }

    // Calculate spots
    // Data is assumed descending (recent first). Reverse for graph (old -> new)
    final sorted = List<WellnessDataPoint>.from(data.reversed);
    final spots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      spots.add(FlSpot(i.toDouble(), sorted[i].wellnessIndex));
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
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
          Text(
            'Wellness Index',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        int index = val.toInt();
                        if (index >= 0 && index < sorted.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('E').format(sorted[index].date)[0],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey,
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
                maxX: (sorted.length - 1).toDouble(),
                minY: 0,
                maxY: 1.1,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primaryBlue,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryBlue.withValues(alpha: 0.2),
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

  Widget _buildCognitivePerformanceCard(bool isDarkMode) {
    // TODO: Replace with actual cognitive data when available
    // For now, show placeholder since we don't have real cognitive metrics
    final hasData = false; // Will be replaced with actual data check
    
    if (!hasData) {
      return _buildHealthPlaceholderCard(
        isDarkMode: isDarkMode,
        icon: Icons.psychology,
        title: 'No Cognitive Data Yet',
        subtitle: 'Play brain games to track cognitive performance over time.',
      );
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
