import 'package:arbaz_app/screens/navbar/home/home_screen.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Screen for seniors to select their preferred daily check-in time
/// Shown after role selection in questionnaire, before home screen
class CheckInTimeSelectionScreen extends StatefulWidget {
  const CheckInTimeSelectionScreen({super.key});

  @override
  State<CheckInTimeSelectionScreen> createState() =>
      _CheckInTimeSelectionScreenState();
}

class _CheckInTimeSelectionScreenState
    extends State<CheckInTimeSelectionScreen> with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Time selection state
  int _selectedHour = 9; // Default 9 AM
  int _selectedMinute = 0;
  bool _isAM = true;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String _formatSelectedTime() {
    final hour = _selectedHour == 0 ? 12 : _selectedHour;
    final minute = _selectedMinute.toString().padLeft(2, '0');
    final period = _isAM ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _saveAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final firestoreService = context.read<FirestoreService>();
      final selectedTime = _formatSelectedTime();

      await firestoreService.completeSeniorSetup(user.uid, selectedTime);

      if (!mounted) return;

      // Navigate to Senior Home Screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SeniorHomeScreen()),
      );
    } catch (e) {
      debugPrint('Error saving check-in time: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save. Please try again.',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 40),
                
                // Clock Icon
                SlideTransition(
                  position: _slideAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.access_time_rounded,
                      size: 56,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                SlideTransition(
                  position: _slideAnimation,
                  child: Text(
                    'Set Your Check-in Time',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),

                // Subtitle
                SlideTransition(
                  position: _slideAnimation,
                  child: Text(
                    'Choose a time when you\'d like to receive\nyour daily check-in reminder.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 36),

                // Time Picker
                Expanded(
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: _buildTimePicker(isDarkMode),
                  ),
                ),

                // Selected Time Display
                // Container(
                //   padding: const EdgeInsets.symmetric(
                //     horizontal: 24,
                //     vertical: 14,
                //   ),
                //   decoration: BoxDecoration(
                //     color: isDarkMode
                //         ? AppColors.surfaceDark
                //         : AppColors.primaryBlue.withValues(alpha: 0.08),
                //     borderRadius: BorderRadius.circular(16),
                //   ),
                //   child: Row(
                //     mainAxisSize: MainAxisSize.min,
                //     children: [
                //       Icon(
                //         Icons.notifications_active_rounded,
                //         size: 20,
                //         color: AppColors.primaryBlue,
                //       ),
                //       const SizedBox(width: 10),
                //       Text(
                //         'Reminder at ${_formatSelectedTime()}',
                //         style: GoogleFonts.inter(
                //           fontSize: 16,
                //           fontWeight: FontWeight.w600,
                //           fontWeight: FontWeight.w600,
                //           color: isDarkMode
                //               ? AppColors.textPrimaryDark
                //               : AppColors.primaryBlue,
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
                const SizedBox(height: 24),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Continue',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hour Picker
          SizedBox(
            width: 80,
            child: CupertinoPicker(
              itemExtent: 50,
              scrollController: FixedExtentScrollController(
                initialItem: _selectedHour - 1,
              ),
              onSelectedItemChanged: (index) {
                setState(() {
                  _selectedHour = index + 1; // 1-12
                });
              },
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: AppColors.primaryBlue.withValues(alpha: 0.1),
              ),
              children: List.generate(12, (index) {
                return Center(
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                );
              }),
            ),
          ),

          // Colon separator
          Text(
            ':',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: isDarkMode
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),

          // Minute Picker
          SizedBox(
            width: 80,
            child: CupertinoPicker(
              itemExtent: 50,
              scrollController: FixedExtentScrollController(
                initialItem: _selectedMinute,
              ),
              onSelectedItemChanged: (index) {
                setState(() {
                  _selectedMinute = index;
                });
              },
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: AppColors.primaryBlue.withValues(alpha: 0.1),
              ),
              children: List.generate(60, (index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(width: 16),

          // AM/PM Picker
          SizedBox(
            width: 70,
            child: CupertinoPicker(
              itemExtent: 50,
              scrollController: FixedExtentScrollController(
                initialItem: _isAM ? 0 : 1,
              ),
              onSelectedItemChanged: (index) {
                setState(() {
                  _isAM = index == 0;
                });
              },
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: AppColors.primaryBlue.withValues(alpha: 0.1),
              ),
              children: ['AM', 'PM'].map((period) {
                return Center(
                  child: Text(
                    period,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
