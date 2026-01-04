import 'dart:async';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/activity_log.dart';
import 'package:arbaz_app/models/user_model.dart';
import 'package:arbaz_app/common/profile_avatar.dart';
import 'package:intl/intl.dart';

/// Model for family member display in dashboard
class FamilyMemberData {
  final String id;
  final String name;
  final String? relationship;
  final String status; // 'safe', 'pending', 'alert'
  final String? location;
  final DateTime? lastCheckIn;
  final bool isVacationMode;
  final String? photoUrl;

  const FamilyMemberData({
    required this.id,
    required this.name,
    this.relationship,
    required this.status,
    this.location,
    this.lastCheckIn,
    this.isVacationMode = false,
    this.photoUrl,
  });

  /// Calculate "last seen" string from lastCheckIn
  String get lastSeenText {
    if (lastCheckIn == null) return 'No check-in yet';
    
    final now = DateTime.now();
    final diff = now.difference(lastCheckIn!);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(lastCheckIn!);
  }
}

class FamilyDashboardScreen extends StatefulWidget {
  const FamilyDashboardScreen({super.key});

  @override
  State<FamilyDashboardScreen> createState() => _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  int _selectedTab = 0; // 0: Overview, 1: Activity, 2: Alerts

  // Real data state
  final List<FamilyMemberData> _familyMembers = [];
  List<ActivityLog> _recentActivity = [];
  List<ActivityLog> _alerts = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  // Stream subscriptions for real-time updates
  StreamSubscription? _connectionsSubscription;
  final Map<String, StreamSubscription<SeniorState?>> _seniorStateSubscriptions = {};
  
  // Cached data for building FamilyMemberData when streams update
  final Map<String, UserProfile?> _cachedProfiles = {};
  final Map<String, dynamic> _cachedConnections = {}; // seniorId -> connection


  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _connectionsSubscription?.cancel();
    // Cancel all senior state subscriptions
    for (final sub in _seniorStateSubscriptions.values) {
      sub.cancel();
    }
    _seniorStateSubscriptions.clear();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Not logged in';
        });
      }
      return;
    }

    try {
      final firestoreService = context.read<FirestoreService>();
      
      // Cancel existing senior state subscriptions before reloading
      for (final sub in _seniorStateSubscriptions.values) {
        sub.cancel();
      }
      _seniorStateSubscriptions.clear();
      _cachedProfiles.clear();
      _cachedConnections.clear();
      
      // Get connections where current user is family member (one-time fetch)
      List<dynamic> connections;
      try {
        connections = await firestoreService
            .getConnectionsForFamily(user.uid)
            .first
            .timeout(const Duration(seconds: 10));
      } catch (e, stack) {
        debugPrint('Error fetching connections for user ${user.uid}: $e\n$stack');
        connections = [];
      }

      List<String> seniorIds = [];

      // Load static data (profiles, roles) and set up streams for dynamic data
      for (final conn in connections) {
        // Check if senior has confirmed their role
        final seniorRoles = await firestoreService
            .getUserRoles(conn.seniorId)
            .catchError((e, stack) {
          debugPrint('Failed to getUserRoles for seniorId: ${conn.seniorId}: $e');
          return null;
        });
        
        if (seniorRoles?.hasConfirmedSeniorRole != true) {
          continue; // Skip unconfirmed seniors
        }

        seniorIds.add(conn.seniorId);
        
        // Get senior profile (static - doesn't change often)
        final profile = await firestoreService
            .getUserProfile(conn.seniorId)
            .catchError((e, stack) {
          debugPrint('Failed to getUserProfile for seniorId: ${conn.seniorId}: $e');
          return null;
        });
        
        // Cache profile and connection for later use in stream updates
        _cachedProfiles[conn.seniorId] = profile;
        _cachedConnections[conn.seniorId] = conn;
        
        // Subscribe to real-time senior state updates
        _subscribeSeniorState(conn.seniorId, firestoreService);
      }

      // Load activities for all connected seniors (one-time, can pull-to-refresh)
      List<ActivityLog> activities = [];
      List<ActivityLog> alerts = [];
      
      if (seniorIds.isNotEmpty) {
        activities = await firestoreService.getActivitiesForSeniors(
          seniorIds,
          limitPerSenior: 10,
        );
        alerts = await firestoreService.getAlertsForSeniors(
          seniorIds,
          limitPerSenior: 10,
        );
      }

      if (mounted) {
        setState(() {
          _recentActivity = activities;
          _alerts = alerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load data. Pull to refresh.';
        });
      }
    }
  }
  
  /// Subscribe to real-time senior state updates for a specific senior
  void _subscribeSeniorState(String seniorId, FirestoreService firestoreService) {
    // Cancel existing subscription if any
    _seniorStateSubscriptions[seniorId]?.cancel();
    
    _seniorStateSubscriptions[seniorId] = firestoreService
        .streamSeniorState(seniorId)
        .listen(
      (seniorState) {
        if (!mounted) return;
        _updateFamilyMemberFromState(seniorId, seniorState);
      },
      onError: (error) {
        debugPrint('Error streaming senior state for $seniorId: $error');
      },
    );
  }
  
  /// Update or create a FamilyMemberData entry based on real-time senior state
  void _updateFamilyMemberFromState(String seniorId, SeniorState? seniorState) {
    final profile = _cachedProfiles[seniorId];
    final conn = _cachedConnections[seniorId];
    
    if (conn == null) return; // No connection data cached
    
    // Calculate status
    String status = 'pending';
    if (seniorState != null) {
      if (seniorState.vacationMode) {
        status = 'safe'; // Vacation mode counts as safe
      } else if (seniorState.lastCheckIn != null) {
        final now = DateTime.now();
        final lastCheckIn = seniorState.lastCheckIn!;
        final isSameDay = lastCheckIn.year == now.year &&
            lastCheckIn.month == now.month &&
            lastCheckIn.day == now.day;
        status = isSameDay ? 'safe' : 'pending';
        
        // Check for missed check-ins (has schedules passed today with no check-in)
        // Day 1 logic: skip ONLY for default 11:00 AM schedule
        final isDay1 = seniorState.seniorCreatedAt != null &&
            seniorState.seniorCreatedAt!.year == now.year &&
            seniorState.seniorCreatedAt!.month == now.month &&
            seniorState.seniorCreatedAt!.day == now.day;
        
        // Check if using only the default schedule
        final hasOnlyDefaultSchedule = seniorState.checkInSchedules.length == 1 &&
            seniorState.checkInSchedules.first.trim().toUpperCase() == '11:00 AM';
        
        // Only skip on Day 1 if using only the default schedule
        final skipDay1Default = isDay1 && hasOnlyDefaultSchedule;
        
        if (!isSameDay && seniorState.checkInSchedules.isNotEmpty && !skipDay1Default) {
          for (final schedule in seniorState.checkInSchedules) {
            final scheduledTime = _parseScheduleTime(schedule, now);
            if (scheduledTime != null && now.isAfter(scheduledTime)) {
              status = 'alert';
              break;
            }
          }
        }
      }
    }

    final updatedMember = FamilyMemberData(
      id: seniorId,
      name: profile?.displayName ?? 
            conn.seniorName ??
            profile?.email.split('@').first ?? 
            'Senior',
      relationship: conn.relationshipType ?? 'Family',
      status: status,
      location: profile?.locationAddress,
      lastCheckIn: seniorState?.lastCheckIn,
      isVacationMode: seniorState?.vacationMode ?? false,
      photoUrl: profile?.photoUrl,
    );

    setState(() {
      // Find and update existing member, or add new one
      final existingIndex = _familyMembers.indexWhere((m) => m.id == seniorId);
      if (existingIndex >= 0) {
        _familyMembers[existingIndex] = updatedMember;
      } else {
        _familyMembers.add(updatedMember);
      }
    });
  }

  /// Parse schedule time (e.g., "11:00 AM") to DateTime for today
  DateTime? _parseScheduleTime(String schedule, DateTime now) {
    try {
      final format = DateFormat('h:mm a');
      final time = format.parse(schedule.toUpperCase());
      return DateTime(now.year, now.month, now.day, time.hour, time.minute);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: Column(
              children: [
                // Tab Bar
                _buildTabBar(isDarkMode),

                // Content based on selected tab
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState(isDarkMode)
                      : _errorMessage != null
                          ? _buildErrorState(isDarkMode)
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _buildTabContent(isDarkMode),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading family data...',
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

  Widget _buildErrorState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.warningOrange,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'An error occurred',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDashboardData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: Text('Retry', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDarkMode) {
    final tabs = ['Overview', 'Activity', 'Alerts'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      height: 50,
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Sliding Background Indicator
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutExpo,
            alignment: Alignment(
              -1.0 + (_selectedTab * (2.0 / (tabs.length - 1))),
              0.0,
            ),
            child: FractionallySizedBox(
              widthFactor: 1 / tabs.length,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDarkMode ? AppColors.backgroundDark : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tab Items
          Row(
            children: List.generate(tabs.length, (index) {
              final isSelected = _selectedTab == index;
              // Show alert badge on Alerts tab if there are alerts
              final showBadge = index == 2 && _alerts.isNotEmpty;
              
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = index),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primaryBlue
                                : (isDarkMode
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary),
                          ),
                          child: Text(tabs[index]),
                        ),
                        if (showBadge) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.dangerRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_alerts.length}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(bool isDarkMode) {
    switch (_selectedTab) {
      case 0:
        return _buildOverviewTab(isDarkMode);
      case 1:
        return _buildActivityTab(isDarkMode);
      case 2:
        return _buildAlertsTab(isDarkMode);
      default:
        return _buildOverviewTab(isDarkMode);
    }
  }

  Widget _buildOverviewTab(bool isDarkMode) {
    if (_familyMembers.isEmpty) {
      return _buildEmptyState(
        isDarkMode,
        icon: Icons.people_outline,
        title: 'No Seniors Connected',
        subtitle: 'Connect with seniors to see their status here',
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('overview'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Quick Stats Row
          _buildQuickStats(isDarkMode),

          const SizedBox(height: 24),

          // Family Members Section
          Text(
            'FAMILY MEMBERS',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Family Member Cards
          ..._familyMembers.map((member) => _buildFamilyMemberCard(member, isDarkMode)),

          const SizedBox(height: 24),

          // Recent Activity Preview
          if (_recentActivity.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RECENT ACTIVITY',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selectedTab = 1),
                  child: Text(
                    'See All',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Activity Preview (first 2 items)
            ...(_recentActivity.take(2).map((activity) =>
                _buildActivityLogItem(activity, isDarkMode))),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildQuickStats(bool isDarkMode) {
    final safeCount = _familyMembers.where((m) => m.status == 'safe').length;
    final needAttentionCount = _familyMembers.where((m) => m.status != 'safe').length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.people_outline,
            iconColor: AppColors.primaryBlue,
            label: 'Family Members',
            value: '${_familyMembers.length}',
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.successGreen,
            label: 'Safe Today',
            value: '$safeCount',
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warningOrange,
            label: 'Need Attention',
            value: '$needAttentionCount',
            isDarkMode: isDarkMode,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color:
                  isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
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

  Widget _buildFamilyMemberCard(FamilyMemberData member, bool isDarkMode) {
    final statusColor = member.status == 'safe'
        ? AppColors.successGreen
        : (member.status == 'alert'
            ? AppColors.dangerRed
            : AppColors.warningOrange);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          // Avatar with status indicator
          Stack(
            children: [
              ProfileAvatar(
                photoUrl: member.photoUrl,
                name: member.name,
                radius: 28,
                isDarkMode: isDarkMode,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    border: Border.all(
                      color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Member Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isVacationMode) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '🌴 Vacation',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  member.location != null && member.location!.isNotEmpty
                      ? '📍 ${member.location} • ${member.lastSeenText}'
                      : 'Last seen: ${member.lastSeenText}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Arrow
          Icon(
            Icons.chevron_right,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab(bool isDarkMode) {
    if (_recentActivity.isEmpty) {
      return _buildEmptyState(
        isDarkMode,
        icon: Icons.history,
        title: 'No Activity Yet',
        subtitle: 'Activity from your family members will appear here',
      );
    }

    return ListView.builder(
      key: const ValueKey('activity'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _recentActivity.length,
      itemBuilder: (context, index) {
        return _buildActivityLogItem(_recentActivity[index], isDarkMode);
      },
    );
  }

  Widget _buildActivityLogItem(ActivityLog activity, bool isDarkMode) {
    // Get icon and color based on activity type
    IconData icon;
    Color color;
    
    switch (activity.activityType) {
      case 'check_in':
        icon = Icons.check_circle_outline;
        color = AppColors.successGreen;
        break;
      case 'brain_game':
        icon = Icons.psychology;
        color = const Color(0xFF6366F1);
        break;
      case 'missed_check_in':
        icon = Icons.warning_amber_rounded;
        color = AppColors.warningOrange;
        break;
      default:
        icon = Icons.info_outline;
        color = AppColors.primaryBlue;
    }

    // Get member name from activity
    final memberName = _familyMembers
        .where((m) => m.id == activity.seniorId)
        .map((m) => m.name)
        .firstOrNull ?? 'Senior';

    // Format time
    final now = DateTime.now();
    final activityTime = activity.timestamp;
    String timeText;
    
    if (activityTime.year == now.year &&
        activityTime.month == now.month &&
        activityTime.day == now.day) {
      timeText = DateFormat('h:mm a').format(activityTime);
    } else if (now.difference(activityTime).inDays == 1) {
      timeText = 'Yesterday';
    } else {
      timeText = DateFormat('MMM d').format(activityTime);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activity.isAlert
              ? AppColors.warningOrange.withValues(alpha: 0.3)
              : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memberName,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.actionDescription,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeText,
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

  Widget _buildAlertsTab(bool isDarkMode) {
    if (_alerts.isEmpty) {
      return _buildEmptyState(
        isDarkMode,
        icon: Icons.check_circle_outline,
        iconColor: AppColors.successGreen,
        title: 'All Clear!',
        subtitle: 'No alerts or warnings at the moment',
      );
    }

    return ListView.builder(
      key: const ValueKey('alerts'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        return _buildActivityLogItem(_alerts[index], isDarkMode);
      },
    );
  }

  Widget _buildEmptyState(
    bool isDarkMode, {
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.primaryBlue).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.primaryBlue,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
