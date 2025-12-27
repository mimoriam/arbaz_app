import 'package:arbaz_app/screens/navbar/family_dashboard/family_dashboard_screen.dart';
import 'package:arbaz_app/screens/navbar/settings/safety_vault/safety_vault_screen.dart';
import 'package:arbaz_app/services/vacation_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:arbaz_app/services/auth_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Model class for a family contact
class FamilyContact {
  final String name;
  final String relationship;
  final String phone;

  FamilyContact({
    required this.name,
    required this.relationship,
    required this.phone,
  });
}

/// Settings/Preferences Screen for the SafeCheck app
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Vacation Mode is now managed by VacationModeProvider

  // Check-in Schedule
  final List<String> _checkInTimes = ['10:00 am', '03:00 pm', '08:00 pm'];

  // Step Options
  bool _healthQuizEnabled = true;

  // Identity
  final String _userName = 'Annie';
  final String _timezone = 'Asia/Karachi';

  // Escalation Alarm
  bool _escalationAlarmActive = false;

  // Family Circle
  final List<FamilyContact> _familyContacts = [
    FamilyContact(name: 'David', relationship: 'Son', phone: '555-0123'),
  ];

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
            // Header
            _buildHeader(isDarkMode),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Vacation Mode Card
                    _buildVacationModeCard(isDarkMode),

                    const SizedBox(height: 28),

                    // Check-in Schedule Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.access_time_outlined,
                      title: 'CHECK-IN SCHEDULE',
                    ),
                    const SizedBox(height: 12),
                    _buildCheckInSchedule(isDarkMode),

                    const SizedBox(height: 28),

                    // Step Options Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.grid_view_outlined,
                      title: 'STEP OPTIONS',
                    ),
                    const SizedBox(height: 12),
                    _buildStepOptions(isDarkMode),

                    const SizedBox(height: 28),

                    // Identity Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.alternate_email,
                      title: 'IDENTITY',
                    ),
                    const SizedBox(height: 12),
                    _buildIdentitySection(isDarkMode),

                    const SizedBox(height: 28),

                    // Escalation Alarm Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.notifications_outlined,
                      title: 'ESCALATION ALARM',
                    ),
                    const SizedBox(height: 12),
                    _buildEscalationAlarm(isDarkMode),

                    const SizedBox(height: 28),

                    // Family Circle Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.people_outline,
                      title: 'FAMILY CIRCLE',
                    ),
                    const SizedBox(height: 12),
                    _buildFamilyCircle(isDarkMode),

                    const SizedBox(height: 28),

                    // Family Dashboard Section
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.dashboard_outlined,
                      title: 'DASHBOARD',
                    ),
                    const SizedBox(height: 12),
                    _buildFamilyDashboardCard(isDarkMode),

                    const SizedBox(height: 24),

                    // Safety Vault Card
                    _buildSafetyVaultCard(isDarkMode),

                    const SizedBox(height: 24),

                    // Logout Button
                    _buildLogoutButton(isDarkMode),

                    const SizedBox(height: 40),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // Back Button
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
                Icons.chevron_left,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 24,
              ),
            ),
          ),

          // Title
          Expanded(
            child: Center(
              child: Text(
                'Preferences',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),

          // Save Button
          GestureDetector(
            onTap: () {
              // Save preferences
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Preferences saved!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: AppColors.successGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVacationModeCard(bool isDarkMode) {
    return Consumer<VacationModeProvider>(
      builder: (context, vacationProvider, child) {
        return Container(
          width: double.infinity,
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
                      'Vacation Mode',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pause all nudges',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Toggle
              vacationProvider.isLoading
                  ? const SizedBox(
                      width: 50,
                      height: 30,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : _buildToggle(vacationProvider.isVacationMode, (value) async {
                      final success =
                          await vacationProvider.setVacationMode(value);
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update vacation mode',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: AppColors.dangerRed,
                          ),
                        );
                      }
                    }, isLight: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(
    bool isDarkMode, {
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDarkMode
              ? AppColors.textSecondaryDark
              : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckInSchedule(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          // Time entries
          ...List.generate(_checkInTimes.length, (index) {
            return Column(
              children: [
                if (index > 0)
                  Divider(
                    height: 1,
                    color: isDarkMode
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                _buildTimeEntry(isDarkMode, _checkInTimes[index], index),
              ],
            );
          }),

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),

          // Add Time Button
          GestureDetector(
            onTap: () => _showAddTimeDialog(isDarkMode),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '+ Add Time',
                  style: GoogleFonts.inter(
                    fontSize: 15,
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
    );
  }

  Widget _buildTimeEntry(bool isDarkMode, String time, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Text(
            time,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                _checkInTimes.removeAt(index);
              });
            },
            child: Icon(
              Icons.delete_outline,
              size: 22,
              color: AppColors.dangerRed.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTimeDialog(bool isDarkMode) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(primary: AppColors.primaryBlue)
                : ColorScheme.light(primary: AppColors.primaryBlue),
          ),
          child: child!,
        );
      },    );

    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minute = picked.minute.toString().padLeft(2, '0');
      final period = picked.period == DayPeriod.am ? 'am' : 'pm';
      final formattedTime =
          '${hour.toString().padLeft(2, '0')}:$minute $period';

      setState(() {
        _checkInTimes.add(formattedTime);
      });
    }
  }

  Widget _buildStepOptions(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          // Health Quiz
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Health Quiz',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Feeling status',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildToggle(_healthQuizEnabled, (value) {
                  setState(() => _healthQuizEnabled = value);
                }),
              ],
            ),
          ),

          // Edit Quiz Questions Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () {
                // Navigate to edit quiz questions
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? AppColors.backgroundDark
                      : AppColors.inputFillLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Edit Quiz Questions',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),

          // Brain Games
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          //   child: Row(
          //     children: [
          //       Expanded(
          //         child: Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: [
          //             Text(
          //               'Brain Games',
          //               style: GoogleFonts.inter(
          //                 fontSize: 16,
          //                 fontWeight: FontWeight.w600,
          //                 color: isDarkMode
          //                     ? AppColors.textPrimaryDark
          //                     : AppColors.textPrimary,
          //               ),
          //             ),
          //             const SizedBox(height: 2),
          //             Text(
          //               'Mind sharpener',
          //               style: GoogleFonts.inter(
          //                 fontSize: 13,
          //                 fontWeight: FontWeight.w400,
          //                 color: isDarkMode
          //                     ? AppColors.textSecondaryDark
          //                     : AppColors.textSecondary,
          //               ),
          //             ),
          //           ],
          //         ),
          //       ),
          //       _buildToggle(_brainGamesEnabled, (value) {
          //         setState(() => _brainGamesEnabled = value);
          //       }),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildIdentitySection(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          // Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text(
                  _userName,
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

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),

          // Timezone
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  Icons.language,
                  size: 20,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  _timezone,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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

  Widget _buildEscalationAlarm(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ring if forgotten',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _buildToggle(_escalationAlarmActive, (value) {
              setState(() => _escalationAlarmActive = value);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCircle(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          // Contact entries
          ...List.generate(_familyContacts.length, (index) {
            final contact = _familyContacts[index];
            return Column(
              children: [
                if (index > 0)
                  Divider(
                    height: 1,
                    color: isDarkMode
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                _buildContactEntry(isDarkMode, contact),
              ],
            );
          }),

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),

          // Add Contact Button
          GestureDetector(
            onTap: () {
              // Add contact functionality
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '+ Add Contact',
                  style: GoogleFonts.inter(
                    fontSize: 15,
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
    );
  }

  Widget _buildContactEntry(bool isDarkMode, FamilyContact contact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${contact.name} (${contact.relationship})',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.phone_outlined,
                size: 16,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                contact.phone,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyVaultCard(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SafetyVaultScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.vaultCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Lock Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.lock_outline,
                color: AppColors.primaryBlue,
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
                    'Safety Vault',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Entry Codes & Medical',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),

            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyDashboardCard(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const FamilyDashboardScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
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
            // Dashboard Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.dashboard_outlined,
                color: AppColors.primaryBlue,
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
                    'Family Dashboard',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Family Status Overview',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
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
      ),
    );
  }

  Widget _buildLogoutButton(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        // Show logout confirmation
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Logout',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Are you sure you want to logout?',
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final authState = context.read<AuthState>();
                  Navigator.pop(context); // Close dialog

                  try {
                    final result = await authState.signOut();
                    if (!context.mounted) return;

                    switch (result) {
                      case AuthSuccess():
                        // Clear entire navigation stack and go to AuthGate
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      case AuthFailure(:final error):
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error.isNotEmpty ? error : 'Logout failed. Please try again.',
                              style: GoogleFonts.inter(),
                            ),
                            backgroundColor: AppColors.dangerRed,
                          ),
                        );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Logout failed. Please try again.',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: AppColors.dangerRed,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  'Logout',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppColors.dangerRed,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.dangerRed.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_outlined, size: 20, color: AppColors.dangerRed),
            const SizedBox(width: 8),
            Text(
              'Logout',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.dangerRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(
    bool value,
    ValueChanged<bool> onChanged, {
    bool isLight = false,
  }) {
    final activeColor = isLight
        ? Colors.white.withValues(alpha: 0.3)
        : AppColors.primaryBlue.withValues(alpha: 0.2);
    final thumbColor = isLight ? Colors.white : AppColors.primaryBlue;
    final inactiveColor = isLight
        ? Colors.white.withValues(alpha: 0.2)
        : AppColors.borderLight;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: value ? activeColor : inactiveColor,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value
                  ? thumbColor
                  : (isLight
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.grey.shade400),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
