import 'package:arbaz_app/screens/navbar/home/home_screen.dart';
import 'package:arbaz_app/screens/navbar/family_dashboard/family_dashboard_screen.dart';
import 'package:arbaz_app/screens/navbar/settings/safety_vault/safety_vault_screen.dart';
import 'package:arbaz_app/services/role_preference_service.dart';
import 'package:arbaz_app/services/vacation_mode_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:arbaz_app/services/auth_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:arbaz_app/providers/checkin_schedule_provider.dart';
import 'package:arbaz_app/providers/brain_games_provider.dart';
import 'package:arbaz_app/providers/health_quiz_provider.dart';
import 'package:arbaz_app/providers/escalation_alarm_provider.dart';
import 'package:arbaz_app/providers/games_provider.dart';
import 'package:arbaz_app/services/contacts_service.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/services/qr_invite_service.dart';
import 'package:arbaz_app/services/storage_service.dart';
import 'package:arbaz_app/models/family_contact_model.dart';
import 'package:arbaz_app/services/auth_gate.dart';
import 'package:arbaz_app/services/location_service.dart';
import 'package:arbaz_app/common/profile_avatar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:arbaz_app/models/user_model.dart';
import 'package:arbaz_app/services/theme_provider.dart';

/// Model class for a family contact

/// Settings/Preferences Screen for the SafeCheck app
class SettingsScreen extends StatefulWidget {
  final bool isFamilyView;
  
  const SettingsScreen({super.key, this.isFamilyView = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppLifecycleListener _lifecycleListener;

  // Vacation Mode is now managed by VacationModeProvider

  // Identity
  String _userName = '';
  String _timezone = 'Local'; // Default
  String? _locationAddress;
  bool _isLocationEnabled = false;
  
  // Profile Image
  String? _profilePhotoUrl;
  bool _isUploadingPhoto = false;
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // Listen for app lifecycle changes to refresh location permission
    _lifecycleListener = AppLifecycleListener(
      onResume: () async {
        // Small delay to ensure OS permission state is fully updated
        await Future.delayed(const Duration(milliseconds: 300));
        _checkLocationPermission();
      },
    );

    // Pre-populate identity from Auth to avoid flash of default values
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _userName = user.displayName!;
      } else if (user.email != null && user.email!.isNotEmpty) {
        _userName = user.email!.split('@').first;
      }
      _timezone = DateTime.now().timeZoneName;
    }

    // Initialize providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CheckInScheduleProvider>().init();
      context.read<BrainGamesProvider>().init();
      context.read<HealthQuizProvider>().init();
      context.read<EscalationAlarmProvider>().init();
      _loadUserProfile();
      _checkLocationPermission();
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Shows a loading overlay dialog with a message
  void _showLoadingDialog(String message) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dismisses the loading dialog if it's showing
  void _dismissLoadingDialog() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Check location permission status without auto-requesting
  Future<void> _checkLocationPermission() async {
    if (!mounted) return;
    final locationService = context.read<LocationService>();
    final permission = await locationService.checkPermission();

    // Also check if system location services are enabled
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (mounted) {
      setState(() {
        _isLocationEnabled =
            isServiceEnabled &&
            (permission == LocationPermission.whileInUse ||
             permission == LocationPermission.always);
      });
    }
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Set timezone and initial photo URL from Google Sign-in
    if (mounted) {
      setState(() {
        _timezone = DateTime.now().timeZoneName;
        // Use Firebase Auth name as initial value while loading from Firestore
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          _userName = user.displayName!;
        } else if (user.email != null && user.email!.isNotEmpty) {
          // Fallback to email (first part) if no display name
          _userName = user.email!.split('@').first;
        }
        // Use Google Sign-in photo as initial value if available
        _profilePhotoUrl = _storageService.getInitialPhotoUrl(user);
      });
    }

    final firestoreService = context.read<FirestoreService>();
    try {
      final profile = await firestoreService.getUserProfile(user.uid);
      if (mounted && profile != null) {
        setState(() {
          // Prefer Firestore displayName, then Firebase Auth, then email
          if (profile.displayName != null && profile.displayName!.isNotEmpty) {
            _userName = profile.displayName!;
          }
          _locationAddress = profile.locationAddress;
          // Prefer Firestore photoUrl, then Google Sign-in photo
          if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
            _profilePhotoUrl = profile.photoUrl;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  /// Shows a bottom sheet to pick profile image from camera or gallery
  void _showImagePickerSheet(bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Text(
              'Change Profile Photo',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            
            // Camera option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.primaryBlue,
                ),
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                'Use your camera',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            
            const SizedBox(height: 8),
            
            // Gallery option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.successGreen,
                ),
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                'Select an existing photo',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            
            // Remove photo option (only show if there's a custom photo)
            if (_profilePhotoUrl != null) ...[
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: AppColors.dangerRed,
                  ),
                ),
                title: Text(
                  'Remove Photo',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppColors.dangerRed,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfileImage();
                },
              ),
            ],
            
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  /// Picks an image from the specified source and uploads it
  Future<void> _pickAndUploadImage(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Capture service reference before async gap to avoid context.read after await
    final firestoreService = context.read<FirestoreService>();

    try {
      // Pick image with compression settings
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80, // 80% quality for good balance
      );
      
      if (image == null) return; // User cancelled
      
      // Show loading state
      if (mounted) {
        setState(() => _isUploadingPhoto = true);
      }
      
      // Upload to Firebase Storage
      final downloadUrl = await _storageService.uploadProfileImageFromXFile(
        user.uid,
        image,
      );
      
      if (downloadUrl != null) {
        // Update Firestore profile with new photo URL
        await firestoreService.updateUserProfile(user.uid, {
          'photoUrl': downloadUrl,
        });
        
        if (mounted) {
          setState(() {
            _profilePhotoUrl = downloadUrl;
            _isUploadingPhoto = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Profile photo updated!',
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
      } else {
        // Upload failed
        if (mounted) {
          setState(() => _isUploadingPhoto = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to upload photo. Please try again.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.dangerRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking/uploading image: $e');
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'An error occurred. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.dangerRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  /// Removes the profile image and falls back to Google photo or initials
  Future<void> _removeProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Capture service reference before async gap to avoid context.read after await
    final firestoreService = context.read<FirestoreService>();

    try {
      setState(() => _isUploadingPhoto = true);
      
      // Delete from Storage
      await _storageService.deleteProfileImage(user.uid);
      
      // Clear from Firestore
      await firestoreService.updateUserProfile(user.uid, {
        'photoUrl': null,
      });
      
      if (mounted) {
        setState(() {
          // Fall back to Google photo if available
          _profilePhotoUrl = _storageService.getInitialPhotoUrl(user);
          _isUploadingPhoto = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile photo removed',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.textSecondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing profile image: $e');
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to remove photo. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.dangerRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
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
            // Header
            _buildHeader(isDarkMode),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Vacation Mode Card - Senior only
                    if (!widget.isFamilyView) ...[
                      _buildVacationModeCard(isDarkMode),
                      const SizedBox(height: 18),
                    ],

                    // Check-in Schedule Section - Senior only
                    if (!widget.isFamilyView) ...[
                      _buildSectionHeader(
                        isDarkMode,
                        icon: Icons.access_time_outlined,
                        title: 'CHECK-IN SCHEDULE',
                      ),
                      const SizedBox(height: 12),
                      _buildCheckInSchedule(isDarkMode),
                      const SizedBox(height: 18),
                    ],

                    // Step Options Section - Senior only
                    if (!widget.isFamilyView) ...[
                      _buildSectionHeader(
                        isDarkMode,
                        icon: Icons.grid_view_outlined,
                        title: 'STEP OPTIONS',
                      ),
                      const SizedBox(height: 12),
                      _buildStepOptions(isDarkMode),
                      const SizedBox(height: 18),
                    ],

                    // Appearance Section (Dark Mode) - Both, moved above Identity
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.palette_outlined,
                      title: 'APPEARANCE',
                    ),
                    const SizedBox(height: 12),
                    _buildAppearanceSection(isDarkMode),

                    const SizedBox(height: 18),

                    // Identity Section - Both
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.alternate_email,
                      title: 'IDENTITY',
                    ),
                    const SizedBox(height: 12),
                    _buildIdentitySection(isDarkMode),

                    const SizedBox(height: 18),

                    // Escalation Alarm Section - Senior only
                    // if (!widget.isFamilyView) ...[
                    //   _buildSectionHeader(
                    //     isDarkMode,
                    //     icon: Icons.notifications_outlined,
                    //     title: 'ESCALATION ALARM',
                    //   ),
                    //   const SizedBox(height: 12),
                    //   _buildEscalationAlarm(isDarkMode),
                    //   const SizedBox(height: 18),
                    // ],

                    // Family Circle Section - Both
                    _buildSectionHeader(
                      isDarkMode,
                      icon: Icons.people_outline,
                      title: 'FAMILY CIRCLE',
                    ),
                    const SizedBox(height: 12),
                    _buildFamilyCircle(isDarkMode),

                    const SizedBox(height: 18),

                    // Generate Invite Code Card - Both
                    _buildGenerateInviteCodeCard(isDarkMode),

                    const SizedBox(height: 18),

                    // // Family Dashboard Section - Family only
                    // if (widget.isFamilyView) ...[
                    //   _buildSectionHeader(
                    //     isDarkMode,
                    //     icon: Icons.dashboard_outlined,
                    //     title: 'DASHBOARD',
                    //   ),
                    //   const SizedBox(height: 12),
                    //   _buildFamilyDashboardCard(isDarkMode),
                    // ],

                    // Safety Vault Card - Senior only
                    if (!widget.isFamilyView) ...[
                      const SizedBox(height: 12),
                      _buildSafetyVaultCard(isDarkMode),
                    ],

                    const SizedBox(height: 18),

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
          // GestureDetector(
          //   onTap: () {
          //     // Save preferences
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       SnackBar(
          //         content: Text(
          //           'Preferences saved!',
          //           style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          //         ),
          //         backgroundColor: AppColors.successGreen,
          //         behavior: SnackBarBehavior.floating,
          //         shape: RoundedRectangleBorder(
          //           borderRadius: BorderRadius.circular(12),
          //         ),
          //       ),
          //     );
          //   },
          //   child: Text(
          //     'Save',
          //     style: GoogleFonts.inter(
          //       fontSize: 16,
          //       fontWeight: FontWeight.w600,
          //       color: AppColors.primaryBlue,
          //     ),
          //   ),
          // ),
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
                  : _buildToggle(vacationProvider.isVacationMode, (
                      value,
                    ) async {
                      final success = await vacationProvider.setVacationMode(
                        value,
                      );
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update vacation mode',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
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
    return Consumer<CheckInScheduleProvider>(
      builder: (context, provider, child) {
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
              if (provider.isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.schedules.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    "No schedules set",
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
                )
              else
                // Time entries
                ...List.generate(provider.schedules.length, (index) {
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(
                          height: 1,
                          color: isDarkMode
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      _buildTimeEntry(
                        isDarkMode,
                        provider.schedules[index],
                        index,
                        provider,
                      ),
                    ],
                  );
                }),

              // Divider
              Divider(
                height: 1,
                color: isDarkMode
                    ? AppColors.borderDark
                    : AppColors.borderLight,
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
      },
    );
  }

  Widget _buildTimeEntry(
    bool isDarkMode,
    String time,
    int index,
    CheckInScheduleProvider provider,
  ) {
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
            onTap: () async {
              if (provider.schedules.length <= 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'You must have at least one check-in schedule.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: AppColors.warningOrange,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return;
              }

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(
                    'Delete Schedule',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    'Are you sure you want to delete the $time check-in schedule?',
                    style: GoogleFonts.inter(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'Delete',
                        style: GoogleFonts.inter(
                          color: AppColors.dangerRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                provider.removeSchedule(time);
              }
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
    final scheduleProvider = context.read<CheckInScheduleProvider>();
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
      },
    );

    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minute = picked.minute.toString().padLeft(2, '0');
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      final formattedTime = '$hour:$minute $period';

      scheduleProvider.addSchedule(formattedTime);
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Games',
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
                    'Show games after check-in',
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
            Consumer<GamesProvider>(
              builder: (context, gamesProvider, _) {
                if (gamesProvider.isLoading) {
                  return const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                return _buildToggle(
                  gamesProvider.isEnabled,
                  (value) => gamesProvider.setEnabled(value),
                );
              },
            ),
          ],
        ),
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
          // Profile Photo & Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                ProfileAvatar(
                  photoUrl: _profilePhotoUrl,
                  name: _userName,
                  radius: 28,
                  isDarkMode: isDarkMode,
                  showEditBadge: true,
                  isLoading: _isUploadingPhoto,
                  onTap: () => _showImagePickerSheet(isDarkMode),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap photo to change',
                        style: GoogleFonts.inter(
                          fontSize: 12,
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
          ),

          // // Divider
          // Divider(
          //   height: 1,
          //   color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          // ),

          // // Timezone
          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          //   child: Row(
          //     children: [
          //       Icon(
          //         Icons.language,
          //         size: 20,
          //         color: isDarkMode
          //             ? AppColors.textSecondaryDark
          //             : AppColors.textSecondary,
          //       ),
          //       const SizedBox(width: 12),
          //       Text(
          //         _timezone,
          //         style: GoogleFonts.inter(
          //           fontSize: 16,
          //           fontWeight: FontWeight.w500,
          //           color: isDarkMode
          //               ? AppColors.textPrimaryDark
          //               : AppColors.textPrimary,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

          if (_locationAddress != null) ...[
            // Divider
            Divider(
              height: 1,
              color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),

            // Location
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: isDarkMode
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _locationAddress!,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),

          // Location Permission Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:
                        (_isLocationEnabled
                                ? AppColors.successGreen
                                : AppColors.warningOrange)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isLocationEnabled ? Icons.location_on : Icons.location_off,
                    size: 18,
                    color: _isLocationEnabled
                        ? AppColors.successGreen
                        : AppColors.warningOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location Services',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        _isLocationEnabled ? 'Enabled' : 'Tap to enable',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDarkMode
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    // Opens system location settings
                    // The onResume callback will refresh permission state when user returns
                    await Geolocator.openLocationSettings();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: isDarkMode
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
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

  Widget _buildAppearanceSection(bool isDarkMode) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                // Animated icon container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeProvider.isDarkMode
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: RotationTransition(
                          turns: Tween(begin: 0.5, end: 1.0).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      themeProvider.isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      key: ValueKey(themeProvider.isDarkMode),
                      size: 22,
                      color: themeProvider.isDarkMode
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dark Mode',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          themeProvider.isDarkMode
                              ? 'Dark theme active'
                              : 'Light theme active',
                          key: ValueKey(themeProvider.isDarkMode),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: isDarkMode
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Animated custom toggle
                GestureDetector(
                  onTap: () {
                    themeProvider.toggleTheme(!themeProvider.isDarkMode);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: 56,
                    height: 32,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: themeProvider.isDarkMode
                          ? const LinearGradient(
                              colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFE5E7EB), Color(0xFFD1D5DB)],
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: themeProvider.isDarkMode
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      alignment: themeProvider.isDarkMode
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              themeProvider.isDarkMode
                                  ? Icons.nightlight_round
                                  : Icons.wb_sunny_rounded,
                              key: ValueKey(themeProvider.isDarkMode),
                              size: 16,
                              color: themeProvider.isDarkMode
                                  ? const Color(0xFF1E40AF)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            Consumer<EscalationAlarmProvider>(
              builder: (context, escalationProvider, _) {
                return _buildToggle(
                  escalationProvider.isActive,
                  (value) => escalationProvider.setActive(value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCircle(bool isDarkMode) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: StreamBuilder<List<FamilyContactModel>>(
        stream: context.read<FamilyContactsService>().getContacts(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Error loading contacts: ${snapshot.error}');
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.dangerRed,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to load contacts',
                      style: GoogleFonts.inter(color: AppColors.dangerRed),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final contacts = snapshot.data ?? [];

          return Column(
            children: [
              if (contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    "No family members active",
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
                )
              else
                ...List.generate(contacts.length, (index) {
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(
                          height: 1,
                          color: isDarkMode
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      _buildContactEntry(isDarkMode, contacts[index]),
                    ],
                  );
                }),

              // Divider
              Divider(
                height: 1,
                color: isDarkMode
                    ? AppColors.borderDark
                    : AppColors.borderLight,
              ),

              // Add Contact Button
              GestureDetector(
                onTap: () => _showAddFamilyMemberDialog(isDarkMode),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      '+ Add Family Member',
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
          );
        },
      ),
    );
  }

  Widget _buildGenerateInviteCodeCard(bool isDarkMode) {
    return GestureDetector(
      onTap: () => _showGenerateInviteCodeDialog(isDarkMode),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.successGreen,
              AppColors.successGreen.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.successGreen.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
              child: const Icon(Icons.qr_code_2, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate Invite Code',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share with family members',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.9),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _showGenerateInviteCodeDialog(bool isDarkMode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Ensure profile is loaded before generating QR
    final qrService = context.read<QrInviteService>();

    if (_userName.isEmpty) {
      await _loadUserProfile();
    }

    if (!mounted) return;

    // Get best available name for QR payload
    // Priority: Loaded name > Auth Display Name > Email prefix > "User"
    String bestName = _userName;
    if (bestName.isEmpty || bestName == 'U') {
      bestName = user.displayName ?? user.email?.split('@').first ?? 'User';
    }
    
    debugPrint('🔍 QR generation: using name "$bestName"');

    final inviteCode = qrService.generateInviteQrData(
      user.uid,
      widget.isFamilyView ? 'family' : 'senior',
      name: bestName,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Your Invite Code',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with family members so they can connect with you.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: inviteCode,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 24),

            // Share Button
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await SharePlus.instance.share(
                  ShareParams(
                    text: inviteCode,
                    subject: 'SafeCheck Family Invite',
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryBlue,
                      AppColors.primaryBlue.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Share Invite Code',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Copy Button
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: inviteCode));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Invite code copied to clipboard',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: AppColors.successGreen,
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.copy,
                      color: isDarkMode ? Colors.white70 : Colors.grey[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Copy Code',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // void _showInviteFamilyDialog(BuildContext context) {
  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     builder: (context) => Container(
  //       padding: const EdgeInsets.all(24),
  //       decoration: BoxDecoration(
  //         color: Theme.of(context).brightness == Brightness.dark
  //             ? AppColors.surfaceDark
  //             : Colors.white,
  //         borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
  //       ),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           Text(
  //             "Invite Family",
  //             style: GoogleFonts.inter(
  //               fontSize: 20,
  //               fontWeight: FontWeight.bold,
  //               color: Theme.of(context).brightness == Brightness.dark
  //                   ? Colors.white
  //                   : Colors.black87,
  //             ),
  //           ),
  //           const SizedBox(height: 16),
  //           Text(
  //             "Share your unique code so family can monitor your safety.",
  //             textAlign: TextAlign.center,
  //             style: GoogleFonts.inter(
  //               fontSize: 14,
  //               color: Theme.of(context).brightness == Brightness.dark
  //                   ? Colors.white70
  //                   : Colors.grey[600]
  //             ),
  //           ),
  //           const SizedBox(height: 24),
  //           ListTile(
  //             leading: const CircleAvatar(
  //               backgroundColor: Color(0xFFE3F2FD),
  //               child: Icon(Icons.share, color: AppColors.primaryBlue)
  //             ),
  //             title: Text(
  //               "Share Invite Code",
  //               style: GoogleFonts.inter(
  //                 color: Theme.of(context).brightness == Brightness.dark
  //                     ? Colors.white
  //                     : Colors.black87
  //               ),
  //             ),
  //             onTap: () async {
  //                final user = FirebaseAuth.instance.currentUser;
  //                if (user != null) {
  //                  final qrService = context.read<QrInviteService>();
  //                  Navigator.pop(context); // Close sheet
  //                  // Generate code for family role
  //                  final code = qrService.generateInviteQrData(user.uid, 'family');
  //                  await Share.share(code);
  //                } else {
  //                  Navigator.pop(context);
  //                }
  //             },
  //           ),
  //            const SizedBox(height: 16),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  void _showAddFamilyMemberDialog(bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _AddFamilyMemberSheet(
          isDarkMode: isDarkMode,
          onAddByPhone: (name, phone, relationship) async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;

            final contactsService = context.read<FamilyContactsService>();
            await contactsService.addContact(
              user.uid,
              FamilyContactModel(
                id: '',
                name: name,
                phone: phone,
                relationship: relationship,
                addedAt: DateTime.now(),
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
          onAddByInviteCode: (code) async {
            final qrService = context.read<QrInviteService>();
            final result = qrService.validateQrData(code);

            if (result == null) {
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid or expired invite code'),
                  ),
                );
              }
              return;
            }

            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;

            if (result.uid == user.uid) {
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You cannot add yourself')),
                );
              }
              return;
            }

            final firestoreService = context.read<FirestoreService>();
            
            // Close the bottom sheet first
            Navigator.pop(context);
            
            // Show loading dialog while connecting
            _showLoadingDialog('Connecting...');
            
            // Debug: Log what role the QR code contains
            debugPrint('📱 QR Payload: uid=${result.uid}, role=${result.role}, name=${result.name}');

            try {
              // Attempt profile fetches
              final profileFutures = await Future.wait([
                firestoreService
                    .getUserProfile(result.uid)
                    .catchError((_) => null),
                firestoreService
                    .getUserProfile(user.uid)
                    .catchError((_) => null),
              ]);
              final invitedUserProfile = profileFutures[0];
              final currentUserProfile = profileFutures[1];

              // FIX: Comprehensive name resolution logic
              // Priority: QR name > Firestore profile > Auth > fallback
              // QR name is prioritized because:
              // 1. It's embedded by the inviter (User A) when generating the code
              // 2. User B may not have Firestore read permissions for User A's
              //    profile until AFTER the connection is created (security rules)
              // 3. This prevents the "Family Member" bug during initial connection
              String resolveName(
                String? qrName,
                UserProfile? profile,
                User? auth,
                String fallback,
              ) {
                // 1. QR code name - most reliable for the INVITED user since
                //    it's embedded at code generation time
                if (qrName != null &&
                    qrName.trim().isNotEmpty &&
                    qrName.trim() != 'Family Member' &&
                    qrName.trim() != 'User') {
                  return qrName.trim();
                }
                // 2. Firestore profile display name
                if (profile?.displayName != null &&
                    profile!.displayName!.trim().isNotEmpty) {
                  return profile.displayName!.trim();
                }
                // 3. Email prefix from Firestore profile
                if (profile?.email != null && profile!.email.isNotEmpty) {
                  return profile.email.split('@').first;
                }
                // 4. Firebase Auth display name (for current user)
                if (auth?.displayName != null && auth!.displayName!.isNotEmpty) {
                  return auth.displayName!;
                }
                // 5. Firebase Auth email prefix (for current user)
                if (auth?.email != null && auth!.email!.isNotEmpty) {
                  return auth.email!.split('@').first;
                }
                return fallback;
              }

              String invitedUserName = resolveName(
                result.name,
                invitedUserProfile,
                null, // We don't have Auth object for the invited user
                'Family Member',
              );

              String currentUserName = resolveName(
                null,
                currentUserProfile,
                user,
                'Family Member',
              );

              // Step 1: Create the connection
              await firestoreService.createFamilyConnectionAtomic(
                currentUserId: user.uid,
                invitedUserId: result.uid,
                currentUserName: currentUserName,
                invitedUserName: invitedUserName,
                currentUserPhone:
                    currentUserProfile?.phoneNumber ?? user.phoneNumber ?? '',
                invitedUserPhone: invitedUserProfile?.phoneNumber ?? '',
                invitedUserRole: result.role == 'senior' ? 'Senior' : 'Family',
              );
              
              // Step 2: Update role flags (additive, not replacing)
              // Only set the new flag, keeping existing flags intact
              try {
                if (result.role == 'senior') {
                  // Current user is family, invited user is senior
                  // Only set isFamilyMember=true, keep isSenior if it exists
                  await firestoreService.setRole(
                    user.uid,
                    isFamilyMember: true,
                  );
                  // Also set active role to family to show the dashboard immediately
                  await firestoreService.updateCurrentRole(user.uid, 'family');
                } else {
                  // Current user is senior, invited user is family
                  // Only set isSenior=true, keep isFamilyMember if it exists
                  // Also mark as confirmed so their data propagates to family
                  await firestoreService.setRole(
                    user.uid,
                    isSenior: true,
                  );
                  await firestoreService.confirmSeniorRole(user.uid);
                  // Also set active role to senior to show the dashboard immediately
                  await firestoreService.updateCurrentRole(user.uid, 'senior');
                }
              } catch (roleError) {
                // Role update failed - try to rollback the connection
                debugPrint('Role update failed: $roleError. Attempting rollback...');
                try {
                  await firestoreService.deleteFamilyConnection(
                    user.uid,
                    result.uid,
                  );
                  debugPrint('Connection rolled back successfully');
                } catch (rollbackError) {
                  debugPrint('Rollback also failed: $rollbackError');
                }
                // Re-throw the original error
                rethrow;
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Successfully connected with $invitedUserName!',
                    ),
                    backgroundColor: AppColors.successGreen,
                  ),
                );
                
                // Navigate to appropriate home screen to refresh with new connection
                // Pop back to root and push the correct home screen
                if (result.role == 'senior') {
                  // User just connected to a Senior - go to FamilyHomeScreen
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const FamilyHomeScreen()),
                    (route) => false,
                  );
                } else {
                  // User just connected to a Family member - go to SeniorHomeScreen
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SeniorHomeScreen()),
                    (route) => false,
                  );
                }
              }
            } catch (e) {
              debugPrint('Error adding family member via invite: $e');
              _dismissLoadingDialog();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to connect. Please try again.'),
                    backgroundColor: AppColors.dangerRed,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildContactEntry(bool isDarkMode, FamilyContactModel contact) {
    final firestoreService = context.read<FirestoreService>();
    
    // If contactUid is available, use live profile stream for real-time updates
    // This enables real-time photo sync when family members update their profiles
    if (contact.contactUid != null && contact.contactUid!.isNotEmpty) {
      return StreamBuilder<UserProfile?>(
        stream: firestoreService.streamUserProfile(contact.contactUid!),
        builder: (context, snapshot) {
          // Determine display name: use live data if available, fall back to stored name
          String displayName = contact.name;
          String displayPhone = contact.phone;
          
          if (snapshot.hasData && snapshot.data != null) {
            final profile = snapshot.data!;
            // Use live profile name if available
            if (profile.displayName != null && profile.displayName!.isNotEmpty) {
              displayName = profile.displayName!;
            } else if (profile.email.isNotEmpty) {
              displayName = profile.email.split('@').first;
            }
            // Use live phone if available and stored phone is empty/placeholder
            if (profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty) {
              displayPhone = profile.phoneNumber!;
            }
          }
          
          return _buildContactEntryContent(
            isDarkMode: isDarkMode,
            contact: contact,
            displayName: displayName,
            displayPhone: displayPhone,
            isLoading: snapshot.connectionState == ConnectionState.waiting,
            photoUrl: snapshot.data?.photoUrl,
          );
        },
      );
    }
    
    // No contactUid - use stored name (for manually added contacts)
    return _buildContactEntryContent(
      isDarkMode: isDarkMode,
      contact: contact,
      displayName: contact.name,
      displayPhone: contact.phone,
      isLoading: false,
    );
  }
  
  /// Internal widget builder for contact entry content
  Widget _buildContactEntryContent({
    required bool isDarkMode,
    required FamilyContactModel contact,
    required String displayName,
    required String displayPhone,
    required bool isLoading,
    String? photoUrl,
  }) {
    // FIX: Prevent redundant labels like "Family Member Family"
    bool shouldShowRelationship =
        contact.relationship.isNotEmpty &&
        contact.relationship != 'Family' &&
        contact.relationship != 'Family Member' &&
        displayName != contact.relationship;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          ProfileAvatar(
            photoUrl: photoUrl,
            name: displayName, // Use displayed name for initials
            radius: 20,
            isDarkMode: isDarkMode,
            isLoading: isLoading,
            backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? 'Unknown Member' : displayName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (displayPhone.isNotEmpty)
                  Text(
                    displayPhone,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                if (shouldShowRelationship)
                  Text(
                    contact.relationship,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              return GestureDetector(
                onTap: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;

                  // Show confirmation dialog
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(
                        'Remove Contact',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                      ),
                      content: Text(
                        'Remove $displayName? This cannot be undone.',
                        style: GoogleFonts.inter(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(
                            'Remove',
                            style: GoogleFonts.inter(
                              color: AppColors.dangerRed,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) return;
                  if (!context.mounted) return;

                  // Show loading dialog
                  _showLoadingDialog('Removing contact...');

                  try {
                    // Use bidirectional delete with contactUid if available, otherwise use contact.id
                    final targetUid = contact.contactUid ?? contact.id;
                    final firestoreService = context.read<FirestoreService>();
                    await firestoreService.deleteFamilyConnection(
                      user.uid,
                      targetUid,
                    );

                    _dismissLoadingDialog();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("$displayName removed."),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error removing contact: $e');
                    _dismissLoadingDialog();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Failed to remove contact."),
                          backgroundColor: AppColors.dangerRed,
                        ),
                      );
                    }
                  }
                },
                child: Icon(
                  Icons.delete_outline,
                  size: 22,
                  color: AppColors.dangerRed.withValues(alpha: 0.7),
                ),
              );
            },
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
          MaterialPageRoute(
            builder: (context) => const FamilyDashboardScreen(),
          ),
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
                  final rolePreferenceService = context
                      .read<RolePreferenceService>();
                  final currentUid = FirebaseAuth.instance.currentUser?.uid;
                  Navigator.pop(context); // Close dialog

                  try {
                    // Clear role preference before signing out
                    if (currentUid != null) {
                      await rolePreferenceService.clearActiveRole(currentUid);
                    }

                    final result = await authState.signOut();
                    if (!context.mounted) return;

                    switch (result) {
                      case AuthSuccess():
                        // Navigate to AuthGate and remove all routes
                        // AuthGate will show LoginScreen since user is logged out
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const AuthGate()),
                          (_) => false, // Remove all routes
                        );
                      case AuthFailure(:final error):
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error.isNotEmpty
                                  ? error
                                  : 'Logout failed. Please try again.',
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

/// Bottom sheet widget for adding family members
class _AddFamilyMemberSheet extends StatefulWidget {
  final bool isDarkMode;
  final Future<void> Function(String name, String phone, String relationship)
  onAddByPhone;
  final Future<void> Function(String code) onAddByInviteCode;

  const _AddFamilyMemberSheet({
    required this.isDarkMode,
    required this.onAddByPhone,
    required this.onAddByInviteCode,
  });

  @override
  State<_AddFamilyMemberSheet> createState() => _AddFamilyMemberSheetState();
}

class _AddFamilyMemberSheetState extends State<_AddFamilyMemberSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  String _relationship = 'Family Member';
  bool _showInviteCodeInput = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Add Family Member',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.isDarkMode ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Toggle between phone and invite code
            Row(
              children: [
                Expanded(
                  child: _buildOptionButton(
                    title: 'By Phone',
                    isSelected: !_showInviteCodeInput,
                    onTap: () => setState(() => _showInviteCodeInput = false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOptionButton(
                    title: 'By Invite Code',
                    isSelected: _showInviteCodeInput,
                    onTap: () => setState(() => _showInviteCodeInput = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_showInviteCodeInput) ...[
              // Invite code input
              Text(
                'Enter the invite code shared by the senior',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inviteCodeController,
                decoration: InputDecoration(
                  hintText: 'Paste invite code here',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: widget.isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey[100],
                ),
                style: GoogleFonts.inter(
                  color: widget.isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleInviteCodeSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Connect',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ] else ...[
              // Phone number input
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                hint: 'Enter family member\'s name',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'Enter phone number',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Relationship dropdown
              Text(
                'Relationship',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // initialValue: _relationship,
                // ignore: deprecated_member_use
                value: _relationship,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: widget.isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey[100],
                ),
                items:
                    [
                          'Family Member',
                          'Son',
                          'Daughter',
                          'Spouse',
                          'Caregiver',
                          'Other',
                        ]
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _relationship = value);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handlePhoneSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Add Family Member',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue
              : (widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey[200]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (widget.isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey[100],
          ),
          style: GoogleFonts.inter(
            color: widget.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  Future<void> _handlePhoneSubmit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.onAddByPhone(name, phone, _relationship);
    } catch (e, st) {
      debugPrint('Error adding family member by phone: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add family member: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleInviteCodeSubmit() async {
    final code = _inviteCodeController.text.trim();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an invite code')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.onAddByInviteCode(code);
    } catch (e, st) {
      debugPrint('Error adding by invite code: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
