import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:arbaz_app/utils/app_colors.dart';

/// Reusable profile avatar widget that displays:
/// 1. Profile image if photoUrl is available
/// 2. Initials-based avatar as fallback
/// 
/// Supports different sizes and an optional edit badge overlay.
class ProfileAvatar extends StatelessWidget {
  /// URL of the profile image (can be from Firebase Storage or Google Sign-in)
  final String? photoUrl;
  
  /// Name to extract initials from (fallback when no image)
  final String name;
  
  /// Radius of the avatar
  final double radius;
  
  /// Whether to show a camera/edit badge overlay
  final bool showEditBadge;
  
  /// Callback when avatar is tapped
  final VoidCallback? onTap;
  
  /// Whether the avatar is in dark mode (affects fallback colors)
  final bool isDarkMode;
  
  /// Whether the avatar is currently loading (shows spinner)
  final bool isLoading;
  
  /// Background color for initials avatar (optional, uses default gradient if null)
  final Color? backgroundColor;
  
  /// Custom gradient colors for initials avatar
  final List<Color>? gradientColors;

  /// Optional border color
  final Color? borderColor;

  /// Border width (default 0)
  final double borderWidth;

  /// Optional icon to show instead of initials (e.g. for family role)
  final IconData? icon;
  
  const ProfileAvatar({
    super.key,
    this.photoUrl,
    required this.name,
    this.radius = 24,
    this.showEditBadge = false,
    this.onTap,
    this.isDarkMode = false,
    this.isLoading = false,
    this.backgroundColor,
    this.gradientColors,
    this.borderColor,
    this.borderWidth = 0,
    this.icon,
  });
  
  /// Extract initials from name (first letter, or first two if space-separated)
  String get _initials {
    if (name.isEmpty) return '?';
    
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    
    // Handle whitespace-only names or empty after trim
    if (parts.isEmpty) return '?';
    
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
  
  @override
  Widget build(BuildContext context) {
    Widget avatar = _buildAvatar();
    
    if (showEditBadge) {
      avatar = Stack(
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt,
                size: radius * 0.35,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }
    
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }
    
    return avatar;
  }
  
  Widget _buildAvatar() {
    // Show loading spinner
    if (isLoading) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: isDarkMode 
              ? Colors.white.withValues(alpha: 0.1) 
              : AppColors.primaryBlue.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: SizedBox(
            width: radius * 0.8,
            height: radius * 0.8,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }
    
    // Show image if URL is available
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Only add border if borderWidth > 0 (matches _buildInitialsAvatar behavior)
          border: borderWidth > 0
              ? Border.all(
                  color: borderColor ?? (isDarkMode 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : AppColors.borderLight),
                  width: borderWidth,
                )
              : null,
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            // Loading placeholder
            placeholder: (context, url) => Container(
              color: isDarkMode 
                  ? Colors.white.withValues(alpha: 0.1) 
                  : AppColors.primaryBlue.withValues(alpha: 0.1),
              child: Center(
                child: SizedBox(
                  width: radius * 0.5,
                  height: radius * 0.5,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
            // Error fallback - show initials
            errorWidget: (context, url, error) => _buildInitialsAvatar(),
          ),
        ),
      );
    }
    
    // Fallback to initials
    return _buildInitialsAvatar();
  }
  
  Widget _buildInitialsAvatar() {
    final defaultGradient = [
      AppColors.primaryBlue.withValues(alpha: 0.15),
      AppColors.primaryBlue.withValues(alpha: 0.05),
    ];
    
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        gradient: gradientColors != null || backgroundColor == null
            ? LinearGradient(
                colors: gradientColors ?? defaultGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: backgroundColor,
        shape: BoxShape.circle,
        border: (borderColor != null || borderWidth > 0)
            ? Border.all(
                color: borderColor ?? Colors.transparent,
                width: borderWidth,
              )
            : null,
      ),
      child: Center(
        child: icon != null 
            ? Icon(
                icon,
                color: AppColors.primaryBlue,
                size: radius,
              )
            : Text(
                _initials,
                style: GoogleFonts.inter(
                  fontSize: radius * 0.7,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
      ),
    );
  }
}

/// Extension to create ProfileAvatar with common configurations
extension ProfileAvatarFactory on ProfileAvatar {
  /// Small avatar (radius 18) - for lists and compact UIs
  static ProfileAvatar small({
    String? photoUrl,
    required String name,
    bool isDarkMode = false,
    VoidCallback? onTap,
  }) {
    return ProfileAvatar(
      photoUrl: photoUrl,
      name: name,
      radius: 18,
      isDarkMode: isDarkMode,
      onTap: onTap,
    );
  }
  
  /// Medium avatar (radius 24) - for cards and standard UIs
  static ProfileAvatar medium({
    String? photoUrl,
    required String name,
    bool isDarkMode = false,
    VoidCallback? onTap,
    bool showEditBadge = false,
  }) {
    return ProfileAvatar(
      photoUrl: photoUrl,
      name: name,
      radius: 24,
      isDarkMode: isDarkMode,
      onTap: onTap,
      showEditBadge: showEditBadge,
    );
  }
  
  /// Large avatar (radius 40) - for profile headers
  static ProfileAvatar large({
    String? photoUrl,
    required String name,
    bool isDarkMode = false,
    VoidCallback? onTap,
    bool showEditBadge = false,
    bool isLoading = false,
  }) {
    return ProfileAvatar(
      photoUrl: photoUrl,
      name: name,
      radius: 40,
      isDarkMode: isDarkMode,
      onTap: onTap,
      showEditBadge: showEditBadge,
      isLoading: isLoading,
    );
  }
}
