import 'package:arbaz_app/screens/navbar/home/home_screen.dart';
import 'package:arbaz_app/services/fcm_service.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/services/role_preference_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _titleController;
  late AnimationController _card1Controller;
  late AnimationController _card2Controller;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _card1Fade;
  late Animation<Offset> _card1Slide;
  late Animation<double> _card2Fade;
  late Animation<Offset> _card2Slide;

  String? _selectingRole;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startStaggeredAnimations();
  }

  void _setupAnimations() {
    // Logo animation
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    // Title animation
    _titleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _titleController, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _titleController, curve: Curves.easeOutCubic),
    );

    // Card 1 animation
    _card1Controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _card1Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _card1Controller, curve: Curves.easeOut),
    );
    _card1Slide = Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _card1Controller, curve: Curves.easeOutCubic),
    );

    // Card 2 animation
    _card2Controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _card2Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _card2Controller, curve: Curves.easeOut),
    );
    _card2Slide = Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _card2Controller, curve: Curves.easeOutCubic),
    );
  }

  void _startStaggeredAnimations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _titleController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _card1Controller.forward();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _card2Controller.forward();
  }

  Future<void> _selectRole(String role) async {
    // Guard against repeated taps
    if (_selectingRole != null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _selectingRole = role);

    final firestoreService = context.read<FirestoreService>();
    final rolePreferenceService = context.read<RolePreferenceService>();

    try {
      // Save role to Firestore
      if (role == 'senior') {
        await firestoreService.setAsSenior(user.uid);
      } else {
        await firestoreService.setAsFamilyMember(user.uid);
      }

      // Save active role preference locally
    await rolePreferenceService.setActiveRole(user.uid, role);
    
    // Register FCM token immediately for push notifications
    // This ensures notifications work right away for new users
    try {
      await FcmService().registerToken(user.uid);
    } catch (fcmError) {
      debugPrint('FCM registration failed (non-fatal): $fcmError');
    }

    if (!mounted) return;

      // Navigate to appropriate home screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => role == 'senior'
              ? const SeniorHomeScreen()
              : const FamilyHomeScreen(),
        ),
      );
    } catch (e) {
      debugPrint('Error saving role: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save role. Please try again.', style: GoogleFonts.inter()),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _selectingRole = null);
      }
    }
  }
  @override
  void dispose() {
    _logoController.dispose();
    _titleController.dispose();
    _card1Controller.dispose();
    _card2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Logo
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.security, size: 64, color: AppColors.primaryBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Animated Title
                FadeTransition(
                  opacity: _titleFade,
                  child: SlideTransition(
                    position: _titleSlide,
                    child: Column(
                      children: [
                        Text(
                          'SafeCheck',
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.0,
                            color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keeping seniors safe and families\nconnected.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Animated Card 1: Senior
                FadeTransition(
                  opacity: _card1Fade,
                  child: SlideTransition(
                    position: _card1Slide,
                    child: _buildRoleCard(
                      context,
                      title: 'I am a Senior',
                      subtitle: 'Use for myself',
                      icon: Icons.home_outlined,
                      color: AppColors.primaryBlue,
                      onTap: () => _selectRole('senior'),
                      isLoading: _selectingRole == 'senior',
                      isDisabled: _selectingRole != null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Animated Card 2: Family
                FadeTransition(
                  opacity: _card2Fade,
                  child: SlideTransition(
                    position: _card2Slide,
                    child: _buildRoleCard(
                      context,
                      title: 'I am Family',
                      subtitle: 'Monitoring a loved one',
                      icon: Icons.people_outline,
                      color: AppColors.successGreen,
                      onTap: () => _selectRole('family'),
                      isLoading: _selectingRole == 'family',
                      isDisabled: _selectingRole != null,
                    ),
                  ),
                ),
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
    bool isLoading = false,
    bool isDisabled = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: isDisabled ? 0.6 : 1.0,
      child: Material(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: InkWell(
          onTap: isDisabled ? null : onTap,
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
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: color,
                            ),
                          )
                        : Icon(icon, size: 28, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
