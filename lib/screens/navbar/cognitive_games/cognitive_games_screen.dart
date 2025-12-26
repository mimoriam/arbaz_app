import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// Model for a cognitive game
class CognitiveGame {
  final String name;
  final String category;
  final int level;
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final bool isUnlocked;

  const CognitiveGame({
    required this.name,
    required this.category,
    required this.level,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    this.isUnlocked = true,
  });
}

class CognitiveGamesScreen extends StatefulWidget {
  const CognitiveGamesScreen({super.key});

  @override
  State<CognitiveGamesScreen> createState() => _CognitiveGamesScreenState();
}

class _CognitiveGamesScreenState extends State<CognitiveGamesScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // List of cognitive games based on the design
  final List<CognitiveGame> _games = const [
    CognitiveGame(
      name: 'Speed Tap',
      category: 'PROCESSING SPEED',
      level: 1,
      icon: Icons.bolt,
      iconColor: Color(0xFFFFB800),
      iconBackgroundColor: Color(0xFFFFF9E6),
    ),
    CognitiveGame(
      name: 'Memory Match',
      category: 'VISUAL MEMORY',
      level: 1,
      icon: Icons.auto_awesome,
      iconColor: Color(0xFF10B981),
      iconBackgroundColor: Color(0xFFECFDF5),
    ),
    CognitiveGame(
      name: 'Sequence Follow',
      category: 'WORKING MEMORY',
      level: 1,
      icon: Icons.grid_view_rounded,
      iconColor: Color(0xFF6366F1),
      iconBackgroundColor: Color(0xFFEEF2FF),
    ),
    CognitiveGame(
      name: 'Simple Sums',
      category: 'PROBLEM SOLVING',
      level: 1,
      icon: Icons.add_box_rounded,
      iconColor: Color(0xFF10B981),
      iconBackgroundColor: Color(0xFFECFDF5),
    ),
    CognitiveGame(
      name: 'Word Jumble',
      category: 'LANGUAGE',
      level: 1,
      icon: Icons.description_outlined,
      iconColor: Color(0xFFF472B6),
      iconBackgroundColor: Color(0xFFFDF2F8),
    ),
    CognitiveGame(
      name: 'Odd One Out',
      category: 'ATTENTION',
      level: 1,
      icon: Icons.search,
      iconColor: Color(0xFF3B82F6),
      iconBackgroundColor: Color(0xFFEFF6FF),
    ),
    CognitiveGame(
      name: 'Pattern Complete',
      category: 'REASONING',
      level: 1,
      icon: Icons.stacked_bar_chart,
      iconColor: Color(0xFF6366F1),
      iconBackgroundColor: Color(0xFFEEF2FF),
    ),
    CognitiveGame(
      name: 'Spot the Difference',
      category: 'VISUAL ATTENTION',
      level: 1,
      icon: Icons.visibility,
      iconColor: Color(0xFF8B5CF6),
      iconBackgroundColor: Color(0xFFF5F3FF),
    ),
    CognitiveGame(
      name: 'Picture Recall',
      category: 'LONG-TERM MEMORY',
      level: 1,
      icon: Icons.photo_library_outlined,
      iconColor: Color(0xFF22C55E),
      iconBackgroundColor: Color(0xFFF0FDF4),
    ),
    CognitiveGame(
      name: 'Word Categories',
      category: 'EXECUTIVE FUNCTION',
      level: 1,
      icon: Icons.folder_outlined,
      iconColor: Color(0xFFF59E0B),
      iconBackgroundColor: Color(0xFFFFFBEB),
    ),
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

  void _onGameTap(CognitiveGame game) {
    // TODO: Navigate to the specific game screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${game.name} coming soon!',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(isDarkMode),

              // Games List
              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: _games.length,
                  itemBuilder: (context, index) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 300 + (index * 50)),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: _buildGameCard(_games[index], isDarkMode),
                    );
                  },
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
          // Title Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Brain Gym',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'MENTAL EXERCISES',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Close Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Icon(
                Icons.close,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(CognitiveGame game, bool isDarkMode) {
    return GestureDetector(
      onTap: () => _onGameTap(game),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            // Game Icon Container
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? game.iconBackgroundColor.withValues(alpha: 0.2)
                    : game.iconBackgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                game.icon,
                color: game.iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // Game Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'LEVEL ${game.level} • ${game.category}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      letterSpacing: 0.5,
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
}
