import 'package:arbaz_app/screens/navbar/calendar/calendar_screen.dart';
import 'package:arbaz_app/screens/navbar/cognitive_games/cognitive_games_screen.dart';
import 'package:arbaz_app/screens/navbar/settings/settings_screen.dart';
import 'package:arbaz_app/screens/paywall/paywall_screen.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:arbaz_app/common/profile_avatar.dart';

class SeniorDrawer extends StatelessWidget {
  final String userName;
  final String? photoUrl;
  final VoidCallback onSwitchToFamily;
  final bool isDarkMode;
  final bool isPro;

  const SeniorDrawer({
    super.key,
    required this.userName,
    this.photoUrl,
    required this.onSwitchToFamily,
    required this.isDarkMode,
    this.isPro = false,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: isDarkMode ? AppColors.backgroundDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.surfaceDark
                  : AppColors.primaryBlue.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode
                      ? AppColors.borderDark
                      : AppColors.primaryBlue.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileAvatar(
                  photoUrl: photoUrl,
                  name: userName,
                  radius: 36,
                  isDarkMode: isDarkMode,
                  borderColor: AppColors.primaryBlue,
                  borderWidth: 2,
                  showEditBadge: false,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        userName.isNotEmpty ? userName : 'User',
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'PRO',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Senior View',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                 // Get Pro Item (if not pro) OR Pro Status
                if (!isPro)
                  _buildDrawerItem(
                    context,
                    icon: isPro ? Icons.verified_user_rounded : Icons.diamond_outlined,
                    label: isPro ? 'Pro Active' : 'Get Pro',
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to Paywall if not Pro, or maybe specific Pro settings?
                      // For now, always open Paywall to manage subscription
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PaywallScreen(),
                        ),
                      );
                    },
                    isHighlight: !isPro, // Highlight "Get Pro"
                    customColor: isPro
                        ? AppColors.successGreen
                        : AppColors.primaryOrange,
                  ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(),
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.calendar_today_rounded,
                  label: 'Calendar',
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.psychology_rounded,
                  label: 'Brain Gym',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CognitiveGamesScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.swap_horiz_rounded,
                  label: 'Switch to Family View',
                  onTap: () {
                    Navigator.pop(context);
                    onSwitchToFamily();
                  },
                  isHighlight: true, // Keep as highlight or standard
                  customColor: AppColors.primaryBlue,
                ),
              ],
            ),
          ),
          
          // Footer version info could go here
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'SafeCheck App',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isHighlight = false,
    Color? customColor,
  }) {
    final defaultColor = isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final color = customColor ?? (isHighlight ? AppColors.primaryBlue : defaultColor);
    
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(
        icon,
        color: color,
        size: 24,
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isDarkMode ? Colors.white38 : Colors.black26,
        size: 20,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

