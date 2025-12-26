import 'package:arbaz_app/screens/navbar/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode
          ? Theme.of(context).scaffoldBackgroundColor
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 64,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'SafeCheck',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 32,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 8),

                // Tagline
                Text(
                  'Keeping seniors safe and families\nconnected.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isDarkMode
                        ? Colors.grey[400]
                        : AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Option 1: Senior
                _buildRoleCard(
                  context,
                  title: 'I am a Senior',
                  subtitle: 'Use for myself',
                  icon: Icons.home_outlined,
                  color: AppColors.primaryBlue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SeniorHomeScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Option 2: Family
                _buildRoleCard(
                  context,
                  title: 'I am Family',
                  subtitle: 'Monitoring a loved one',
                  icon: Icons.people_outline,
                  color: AppColors.successGreen,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FamilyHomeScreen(),
                      ),
                    );
                  },
                ),

                // Bottom padding for safe scrolling
                const SizedBox(height: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDarkMode ? Theme.of(context).cardColor : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Semantics(
          button: true,
          label: '$title - $subtitle',
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(icon, size: 32, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
