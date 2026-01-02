import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/checkin_model.dart';

/// Represents a check-in entry with details about the day

class CalendarScreen extends StatefulWidget {
  /// Optional senior ID for family members to view a senior's calendar.
  /// If null, uses current user's ID (senior viewing their own calendar).
  final String? seniorId;
  
  /// Optional senior name for display when viewing as family member.
  final String? seniorName;
  
  const CalendarScreen({
    super.key,
    this.seniorId,
    this.seniorName,
  });
  
  /// Check if this is a family member viewing a senior's calendar
  bool get isFamilyView => seniorId != null;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  // Lowercase for case-insensitive comparison
  static const _negativeMoods = {'awful', 'bad', 'sad', 'down', 'very_sad'};
  static const _poorSleepQualities = {'poor', 'fair', 'poorly'};

  late DateTime _currentMonth;
  late DateTime _selectedDate;
  late AnimationController _animationController;

  bool _isLoading = true;
  DateTime? _userStartDate;

  // Derived map for easy lookup by day
  Map<int, List<CheckInRecord>> _checkInsByDay = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedDate = now;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMonthlyData();
    });
  }

  Future<void> _fetchMonthlyData() async {
    // Determine which user's data to load
    // If seniorId is provided (family view), use that; else use current user
    final String? targetUserId;
    if (widget.seniorId != null) {
      targetUserId = widget.seniorId;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      targetUserId = user.uid;
    }

    if (!_isLoading) {
      if (mounted) setState(() => _isLoading = true);
    }
    try {
      if (!mounted) return;
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      // Load senior state to get startDate and streak
      final seniorState = await firestoreService.getSeniorState(targetUserId!);

      final checkIns = await firestoreService.getCheckInsForMonth(
        targetUserId,
        _currentMonth.year,
        _currentMonth.month,
      );
      if (!mounted) return;

      setState(() {
        _userStartDate = seniorState?.startDate;

        // Group by day
        _checkInsByDay = {};
        for (var record in checkIns) {
          final day = record.timestamp.day;
          if (!_checkInsByDay.containsKey(day)) {
            _checkInsByDay[day] = [];
          }
          _checkInsByDay[day]!.add(record);
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching calendar data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Checks if a check-in record has issues (negative mood or poor sleep)
  bool _hasIssuesForRecord(CheckInRecord record) {
    final moodIdx = record.mood?.toLowerCase();
    final sleepIdx = record.sleep?.toLowerCase();
    return (moodIdx != null && _negativeMoods.contains(moodIdx)) ||
        (sleepIdx != null && _poorSleepQualities.contains(sleepIdx));
  }

  void _goToPreviousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      // Reset selected date to first day of new month
      _selectedDate = _currentMonth;
    });
    _fetchMonthlyData();
  }

  void _goToNextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      // Reset selected date to first day of new month
      _selectedDate = _currentMonth;
    });
    _fetchMonthlyData();
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
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
            // Custom App Bar
            _buildCustomAppBar(isDarkMode),

            const SizedBox(height: 12),

            // Compact Streak Counter Card
            _buildStreakCard(isDarkMode),

            const SizedBox(height: 12),

            // Calendar Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: isDarkMode
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.surfaceDark,
                            AppColors.surfaceDark.withValues(alpha: 0.8),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            Colors.white.withValues(alpha: 0.95),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.borderDark.withValues(alpha: 0.3)
                        : AppColors.borderLight.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: isDarkMode
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.08,
                            ),
                            blurRadius: 30,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Column(
                  children: [
                    // Month Navigation
                    _buildMonthNavigation(isDarkMode),
                    const SizedBox(height: 16),

                    // Weekday Headers
                    _buildWeekdayHeaders(isDarkMode),
                    const SizedBox(height: 8),

                    // Calendar Grid
                    Expanded(child: _buildCalendarGrid(isDarkMode)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Bottom Action Button
            _buildActionButton(isDarkMode),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back Button
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode
                    ? AppColors.borderDark
                    : AppColors.borderLight,
              ),
              boxShadow: isDarkMode
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(14),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Title - show senior's name if viewing as family member
          Text(
            widget.isFamilyView 
                ? "${widget.seniorName ?? 'Senior'}'s Progress"
                : 'My Progress',
            style: GoogleFonts.inter(
              fontSize: widget.isFamilyView ? 18 : 22,
              fontWeight: FontWeight.w800,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Placeholder for symmetry
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildStreakCard(bool isDarkMode) {
    // Calculate hybrid success rate: avg of daily (checkIns/scheduled) percentages
    final today = DateTime.now();
    final monthStart = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final monthEnd =
        (_currentMonth.year == today.year && _currentMonth.month == today.month)
        ? today
        : DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    // Determine the effective start for this month
    DateTime effectiveStart = monthStart;
    if (_userStartDate != null && _userStartDate!.isAfter(monthStart)) {
      effectiveStart = _userStartDate!;
    }

    final effectiveStartDay =
        effectiveStart.year == _currentMonth.year &&
            effectiveStart.month == _currentMonth.month
        ? effectiveStart.day
        : 1;

    // Count total check-ins for display
    int totalCheckIns = 0;
    for (var records in _checkInsByDay.values) {
      totalCheckIns += records.length;
    }

    // Calculate hybrid success rate: avg(min(checkIns, scheduled) / scheduled)
    double totalCompletion = 0.0;

    for (var entry in _checkInsByDay.entries) {
      final day = entry.key;
      if (day < effectiveStartDay) continue; // Skip days before user started
      
      final dayRecords = entry.value;
      if (dayRecords.isEmpty) continue;
      
      // Get scheduled count from the first record of that day
      // (all records on same day should have same scheduledCount)
      final scheduledCount = dayRecords.first.scheduledCount;
      final checkInCount = dayRecords.length;
      
      // Calculate daily completion: min(actual, scheduled) / scheduled
      // Cap at 100% (extra check-ins don't boost score)
      final dailyCompletion = scheduledCount > 0
          ? (checkInCount.clamp(0, scheduledCount) / scheduledCount)
          : 1.0;
      
      totalCompletion += dailyCompletion;
    }

    // Calculate days user should have checked in (from effective start to now/month end)
    int daysToCount = 0;
    if (!effectiveStart.isAfter(monthEnd)) {
      daysToCount = monthEnd.difference(effectiveStart).inDays + 1;
    }

    // For days with no check-ins at all, they count as 0% completion
    // Average = (sum of daily completions) / (total days expected)
    final successRate = daysToCount > 0
        ? ((totalCompletion / daysToCount) * 100).toInt().clamp(0, 100)
        : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStreakStat('✅', '$totalCheckIns', 'Check-ins'),
          Container(
            width: 1,
            height: 28,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          _buildStreakStat(
            '📊',
            '$successRate%',
            'Success Rate',
          ),
        ],
      ),
    );
  }

  Widget _buildStreakStat(String emoji, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.8),
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthNavigation(bool isDarkMode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Previous Month Button
        _buildNavButton(
          icon: Icons.chevron_left,
          onTap: _goToPreviousMonth,
          isDarkMode: isDarkMode,
        ),

        // Month and Year
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.1),
                  AppColors.primaryBlue.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Center(
              child: Text(
                '${_getMonthName(_currentMonth.month)} ${_currentMonth.year}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),

        // Next Month Button
        _buildNavButton(
          icon: Icons.chevron_right,
          onTap: _goToNextMonth,
          isDarkMode: isDarkMode,
        ),
      ],
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  AppColors.backgroundDark,
                  AppColors.backgroundDark.withValues(alpha: 0.8),
                ]
              : [
                  AppColors.inputFillLight,
                  AppColors.inputFillLight.withValues(alpha: 0.5),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Icon(
            icon,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekdayHeaders(bool isDarkMode) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: weekdays.map((day) {
          return Expanded(
            child: Center(
              child: Text(
                day,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(bool isDarkMode) {
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    );
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    final today = DateTime.now();
    final isCurrentMonth =
        _currentMonth.year == today.year && _currentMonth.month == today.month;

    // Calculate the number of rows needed
    final totalCells = firstWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final itemCount = rows * 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate cell size based on available space
        final availableWidth = constraints.maxWidth - 8; // Account for padding
        final availableHeight = constraints.maxHeight;
        final cellWidth = (availableWidth - (6 * 4)) / 7; // 6 gaps of 4px
        final cellHeight =
            (availableHeight - ((rows - 1) * 4)) / rows; // gaps of 4px
        final cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: (cellWidth / cellSize.clamp(32.0, 44.0)).clamp(
              0.8,
              1.2,
            ),
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final dayNumber = index - firstWeekday + 1;

            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }

            final isToday = isCurrentMonth && dayNumber == today.day;
            final isSelected =
                _selectedDate.year == _currentMonth.year &&
                _selectedDate.month == _currentMonth.month &&
                _selectedDate.day == dayNumber;

            final dayRecords = _checkInsByDay[dayNumber];
            final hasCheckIn = dayRecords != null && dayRecords.isNotEmpty;

            // Determine if there were any issues in the day's records
            bool hasIssues = false;
            if (hasCheckIn) {
              for (var record in dayRecords) {
                if (_hasIssuesForRecord(record)) {
                  hasIssues = true;
                  break;
                }
              }
            }

            return _buildDayCell(
              day: dayNumber,
              isToday: isToday,
              isSelected: isSelected,
              hasCheckIn: hasCheckIn,
              hasIssues: hasIssues,
              isDarkMode: isDarkMode,
              onTap: () => _selectDate(
                DateTime(_currentMonth.year, _currentMonth.month, dayNumber),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayCell({
    required int day,
    required bool isToday,
    required bool isSelected,
    required bool hasCheckIn,
    required bool hasIssues,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    // Determine the accent color based on status
    Color accentColor = hasCheckIn
        ? (hasIssues ? AppColors.warningOrange : AppColors.successGreen)
        : AppColors.textSecondary;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryBlue,
                      AppColors.primaryBlue.withValues(alpha: 0.8),
                    ],
                  )
                : hasCheckIn
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: 0.15),
                      accentColor.withValues(alpha: 0.08),
                    ],
                  )
                : null,
            color: isSelected || hasCheckIn
                ? null
                : (isToday
                      ? AppColors.primaryBlue.withValues(alpha: 0.05)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlue
                  : (isToday
                        ? AppColors.primaryBlue.withValues(alpha: 0.3)
                        : (hasCheckIn
                              ? accentColor.withValues(alpha: 0.3)
                              : Colors.transparent)),
              width: isSelected ? 2 : (isToday || hasCheckIn ? 1.5 : 0),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : hasCheckIn
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  day.toString(),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: isToday || isSelected || hasCheckIn
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (isToday
                              ? AppColors.primaryBlue
                              : (hasCheckIn
                                    ? accentColor
                                    : (isDarkMode
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimary))),
                  ),
                ),
              ),
              // Issue indicator (small warning dot)
              if (hasCheckIn && hasIssues && !isSelected)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.warningOrange,
                      border: Border.all(
                        color: isDarkMode
                            ? AppColors.surfaceDark
                            : Colors.white,
                        width: 1,
                      ),
                    ),
                  ),
                ),
              // Check-in indicator
              if (hasCheckIn && !hasIssues && !isSelected)
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.successGreen,
                      ),
                    ),
                  ),
                ),
              if (isSelected && hasCheckIn)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasIssues ? AppColors.warningOrange : Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showDateDetails();
          },
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'View Details',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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

  void _showDateDetails() {
    // Validate that selected date is in the current month
    final lookupDate =
        (_selectedDate.year == _currentMonth.year &&
            _selectedDate.month == _currentMonth.month)
        ? _selectedDate
        : _currentMonth; // Fallback to first day of month

    final dayRecords = _checkInsByDay[lookupDate.day];
    final hasCheckIn = dayRecords != null && dayRecords.isNotEmpty;
    
    // Sort records by timestamp (oldest first) for display
    List<CheckInRecord> sortedRecords = [];
    if (hasCheckIn) {
      sortedRecords = List<CheckInRecord>.from(dayRecords);
      sortedRecords.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final checkInCount = sortedRecords.length;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: isDarkMode
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surfaceDark,
                    AppColors.surfaceDark.withValues(alpha: 0.95),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white.withValues(alpha: 0.98)],
                ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date title with check-in count
            Center(
              child: Column(
                children: [
                  Text(
                    DateFormat('MMMM d, y').format(lookupDate),
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (checkInCount > 1) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$checkInCount check-ins',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successGreen,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Status Card (overview)
            _buildStatusCard(hasCheckIn, sortedRecords.isNotEmpty ? sortedRecords.last : null, isDarkMode),

            // Show all check-ins if any exist
            if (hasCheckIn) ...[
              const SizedBox(height: 16),
              
              // Scrollable list of check-ins
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedRecords.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = sortedRecords[index];
                    return _buildCheckInCard(record, index + 1, isDarkMode);
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Builds a compact card for a single check-in record
  Widget _buildCheckInCard(CheckInRecord record, int number, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDarkMode
            ? AppColors.backgroundDark
            : AppColors.inputFillLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: check-in number, time, mood
          Row(
            children: [
              // Check-in number badge
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Time
              Icon(
                Icons.access_time_rounded,
                size: 14,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('h:mm a').format(record.timestamp),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  // Show which schedules were satisfied
                  if (record.scheduledFor.isNotEmpty)
                    Text(
                      '✓ ${record.scheduledFor.join(', ')}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.successGreen,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              // Mood if available
              if (record.mood != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getMoodColor(record.mood!).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _capitalize(record.mood!),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _getMoodColor(record.mood!),
                    ),
                  ),
                ),
            ],
          ),
          
          // Details row (compact)
          if (record.sleep != null || record.energy != null || record.medication != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (record.sleep != null)
                  _buildMiniChip('💤', _capitalize(record.sleep!), isDarkMode),
                if (record.energy != null)
                  _buildMiniChip('⚡', _capitalize(record.energy!), isDarkMode),
                if (record.medication != null)
                  _buildMiniChip(
                    '💊',
                    record.medication == 'yes' ? 'Taken' 
                        : record.medication == 'not_yet' ? 'Not yet'
                        : record.medication == 'skipped' ? 'Skipped'
                        : _capitalize(record.medication!),
                    isDarkMode,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Builds a mini chip for compact display of check-in details
  Widget _buildMiniChip(String emoji, String label, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode
            ? AppColors.surfaceDark
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            label,
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

  /// Returns a color based on mood type
  Color _getMoodColor(String mood) {
    switch (mood.toLowerCase()) {
      case 'great':
      case 'good':
      case 'happy':
        return AppColors.successGreen;
      case 'okay':
      case 'neutral':
        return AppColors.warningOrange;
      case 'sad':
      case 'bad':
      case 'awful':
      case 'down':
      case 'very_sad':
        return AppColors.dangerRed;
      default:
        return AppColors.primaryBlue;
    }
  }

  /// Capitalizes the first letter of a string and handles underscores
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    // Replace underscores with spaces and capitalize first letter
    final formatted = text.replaceAll('_', ' ');
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  Widget _buildStatusCard(
    bool hasCheckIn,
    CheckInRecord? record,
    bool isDarkMode,
  ) {
    bool hasIssues = false;
    if (record != null) {
      hasIssues = _hasIssuesForRecord(record);
    }

    final statusColor = hasCheckIn
        ? (hasIssues ? AppColors.warningOrange : AppColors.successGreen)
        : AppColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor.withValues(alpha: 0.12),
            statusColor.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              hasCheckIn
                  ? (hasIssues ? Icons.warning_rounded : Icons.check_circle)
                  : Icons.cancel,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCheckIn
                      ? (hasIssues
                            ? 'Check-in with challenges'
                            : 'Check-in completed')
                      : 'No check-in recorded',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                if (hasCheckIn)
                  Text(
                    hasIssues
                        ? 'Some health metrics need attention'
                        : 'Everything went smoothly!',
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
        ],
      ),
    );
  }
}
