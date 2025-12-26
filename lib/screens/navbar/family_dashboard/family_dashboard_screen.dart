import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:arbaz_app/screens/navbar/calendar/calendar_screen.dart';
import 'package:arbaz_app/screens/navbar/settings/settings_screen.dart';

/// Model for family member
class FamilyMember {
  final String name;
  final String relationship;
  final String? avatarUrl;
  final bool isOnline;
  final String lastSeen;
  final String status; // 'safe', 'warning', 'alert'
  final String? location;
  final DateTime? lastCheckIn;

  const FamilyMember({
    required this.name,
    required this.relationship,
    this.avatarUrl,
    this.isOnline = false,
    required this.lastSeen,
    required this.status,
    this.location,
    this.lastCheckIn,
  });
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

  // Mock family members data
  final List<FamilyMember> _familyMembers = [
    FamilyMember(
      name: 'Grandma Annie',
      relationship: 'Parent',
      isOnline: true,
      lastSeen: 'Now',
      status: 'safe',
      location: 'Home',
      lastCheckIn: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    FamilyMember(
      name: 'Grandpa Bob',
      relationship: 'Parent',
      isOnline: false,
      lastSeen: '3h ago',
      status: 'warning',
      location: 'Park nearby',
      lastCheckIn: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  // Mock activity data
  final List<Map<String, dynamic>> _recentActivity = [
    {
      'member': 'Grandma Annie',
      'action': 'Checked in',
      'time': '2 hours ago',
      'icon': Icons.check_circle_outline,
      'color': Color(0xFF22C55E),
    },
    {
      'member': 'Grandpa Bob',
      'action': 'Completed brain game',
      'time': '4 hours ago',
      'icon': Icons.psychology,
      'color': Color(0xFF6366F1),
    },
    {
      'member': 'Grandma Annie',
      'action': 'Took medication',
      'time': '6 hours ago',
      'icon': Icons.medication,
      'color': Color(0xFF3B82F6),
    },
    {
      'member': 'Grandpa Bob',
      'action': 'Missed check-in reminder',
      'time': 'Yesterday',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFFF59E0B),
    },
  ];

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
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
          child: Column(
            children: [
              // Header
              // _buildHeader(isDarkMode),

              // Tab Bar
              _buildTabBar(isDarkMode),

              // Content based on selected tab
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildTabContent(isDarkMode),
                ),
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
              backgroundColor:
                  isDarkMode ? AppColors.surfaceDark : AppColors.inputFillLight,
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
                  _getGreeting(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Family Dashboard',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
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
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = index),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
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
    return SingleChildScrollView(
      key: const ValueKey('overview'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
              _buildActivityItem(activity, isDarkMode))),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildQuickStats(bool isDarkMode) {
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
            value: '${_familyMembers.where((m) => m.status == 'safe').length}',
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warningOrange,
            label: 'Need Attention',
            value: '${_familyMembers.where((m) => m.status != 'safe').length}',
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

  Widget _buildFamilyMemberCard(FamilyMember member, bool isDarkMode) {
    final statusColor = member.status == 'safe'
        ? AppColors.successGreen
        : (member.status == 'warning'
            ? AppColors.warningOrange
            : AppColors.dangerRed);

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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDarkMode
                      ? AppColors.backgroundDark
                      : AppColors.inputFillLight,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.person,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  size: 28,
                ),
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
                    Text(
                      member.name,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (member.isOnline) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Online',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.successGreen,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  member.location != null
                      ? '📍 ${member.location} • ${member.lastSeen}'
                      : 'Last seen: ${member.lastSeen}',
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
    return ListView.builder(
      key: const ValueKey('activity'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _recentActivity.length,
      itemBuilder: (context, index) {
        return _buildActivityItem(_recentActivity[index], isDarkMode);
      },
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (activity['color'] as Color).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              activity['icon'] as IconData,
              color: activity['color'] as Color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity['member'] as String,
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
                  activity['action'] as String,
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
            activity['time'] as String,
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
    final alerts = _recentActivity
        .where((a) => (a['color'] as Color) == const Color(0xFFF59E0B))
        .toList();

    if (alerts.isEmpty) {
      return Center(
        key: const ValueKey('alerts'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: AppColors.successGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'All Clear!',
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
              'No alerts or warnings at the moment',
              style: GoogleFonts.inter(
                fontSize: 15,
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

    return ListView.builder(
      key: const ValueKey('alerts'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        return _buildActivityItem(alerts[index], isDarkMode);
      },
    );
  }
}
