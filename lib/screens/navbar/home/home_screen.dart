import 'package:arbaz_app/screens/navbar/calendar/calendar_screen.dart';
import 'package:arbaz_app/screens/navbar/home/senior_checkin_flow.dart';
import 'package:arbaz_app/screens/navbar/settings/settings_screen.dart';
import 'package:arbaz_app/services/vacation_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Represents the different status states for the senior user
enum SafetyStatus {
  safe, // Blue theme - "I'M SAFE"
  ok, // Yellow/amber theme - "I'M OK!"
  sending, // Red alert - "SENDING HELP..."
}

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
  int _currentStreak =
      46; // Mock streak - in real app, this comes from a service
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // User info - in a real app, this would come from a user service
  final String _userName = 'Annie';

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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

  void _onStatusButtonTap() {
    // Add haptic feedback for better UX
    HapticFeedback.mediumImpact();

    // If already checked in today, just toggle the visual state
    if (_hasCheckedInToday) {
      setState(() {
        _currentStatus = _currentStatus == SafetyStatus.safe
            ? SafetyStatus.ok
            : SafetyStatus.safe;
      });
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
              _currentStatus = SafetyStatus.ok;
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

                // Emergency SOS Bar
                _buildEmergencyBar(),
              ],
            ),
          ),
        );
      },
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
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
                width: 2,
              ),
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
                  'Hi $_userName!',
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
                    color: AppColors.primaryBlue,
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderIcon(
            Icons.settings_outlined,
            isDarkMode,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(
    IconData icon,
    bool isDarkMode, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
        child: Icon(
          icon,
          size: 20,
          color: isDarkMode
              ? AppColors.textSecondaryDark
              : AppColors.textSecondary,
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
    final bool isSafe = _currentStatus == SafetyStatus.safe;
    final Color primaryColor = (isVacationMode || isLoading)
        ? Colors.grey.shade400 // Gray when vacation mode is on or loading
        : (isSafe
            ? const Color(0xFF3B9EFF) // Bright blue
            : const Color(0xFFFFBF00)); // Golden yellow
    final Color secondaryColor = (isVacationMode || isLoading)
        ? Colors.grey.shade500 // Darker gray when vacation mode is on or loading
        : (isSafe
            ? const Color(0xFF1E7AE5) // Darker blue
            : const Color(0xFFE5A800)); // Darker yellow

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isVacationMode ? 1.0 : _pulseAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: (isVacationMode || isLoading) ? null : _onStatusButtonTap,
        child: Opacity(
          opacity: (isVacationMode || isLoading) ? 0.5 : 1.0,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [primaryColor, secondaryColor],
                center: Alignment.topCenter,
                radius: 0.8,
              ),
              boxShadow: isVacationMode
                  ? [] // No shadow when disabled
                  : [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                      BoxShadow(
                        color: secondaryColor.withValues(alpha: 0.3),
                        blurRadius: 60,
                        spreadRadius: 20,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.25),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isSafe ? Icons.check : Icons.priority_high,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
                const SizedBox(height: 16),

                // Status Text
                Text(
                  isLoading ? "LOADING..." : (isSafe ? "I'M SAFE" : "I'M OK!"),
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  isLoading
                      ? "Syncing status..."
                      : (isVacationMode
                          ? "Disabled during"
                          : "Tap to tell family I'm"),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  isLoading
                      ? ""
                      : (isVacationMode ? "vacation mode" : "okay"),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthMessageSection(bool isDarkMode) {
    final bool isSafe = _currentStatus == SafetyStatus.safe;
    final Color dotColor = isSafe
        ? AppColors.successGreen
        : AppColors.warningOrange;
    final String message = isSafe
        ? 'All set for today!'
        : 'Running late for 10:00';

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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status Dot
              Container(
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
              const SizedBox(width: 12),

              // Message Text
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyBar() {
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderIcon(
            Icons.settings_outlined,
            isDarkMode,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(
    IconData icon,
    bool isDarkMode, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
        child: Icon(
          icon,
          size: 20,
          color: isDarkMode
              ? AppColors.textSecondaryDark
              : AppColors.textSecondary,
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
