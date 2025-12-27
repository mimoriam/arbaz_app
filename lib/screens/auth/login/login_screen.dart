import 'dart:io';

import 'package:arbaz_app/screens/auth/login/forgot_pass_screen.dart';
import 'package:arbaz_app/screens/auth/register/register_screen.dart';
import 'package:arbaz_app/services/auth_state.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/user_model.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;

    final authState = context.read<AuthState>();
    final firestoreService = context.read<FirestoreService>();

    final email = _formKey.currentState?.fields['email']?.value as String;
    final password = _formKey.currentState?.fields['password']?.value as String;

    final result = await authState.signInWithEmail(email, password);

    if (!mounted) return;

    switch (result) {
      case AuthSuccess(:final data):
        final user = data.user;
        if (user != null) {
          try {
            await firestoreService.updateLastLogin(user.uid);
          } catch (e) {
            // Log but don't block login - last login is informational
            debugPrint('Failed to update last login: $e');
          }
        }
        // AuthGate will handle navigation
      case AuthFailure(:final error):
        if (error.isNotEmpty) {
          _showError(error);
        }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authState = context.read<AuthState>();
    final firestoreService = context.read<FirestoreService>();

    final result = await authState.signInWithGoogle();

    if (!mounted) return;

    switch (result) {
      case AuthSuccess(:final data):
        final user = data?.user;
        if (user == null) {
          _showError('Sign-in failed. Please try again.');
          return;
        }

        try {
          // Check if user profile exists
          final existingProfile = await firestoreService.getUserProfile(user.uid);

          if (existingProfile == null) {
            // Create new profile for Google user
            final newProfile = UserProfile(
              uid: user.uid,
              email: user.email ?? '',
              displayName: user.displayName,
              photoUrl: user.photoURL,
              createdAt: DateTime.now(),
              lastLoginAt: DateTime.now(),
            );
            
            try {
              await firestoreService.createUserProfile(user.uid, newProfile);
            } catch (e) {
              // Profile creation failed - sign out to avoid inconsistent state
              debugPrint('Profile creation failed: $e');
              await authState.signOut();
              if (!mounted) return;
              _showError('Failed to create profile. Please try again.');
              return;
            }
          } else {
            try {
              await firestoreService.updateLastLogin(user.uid);
            } catch (e) {
              // Last login update failed - log but don't block
              debugPrint('Last login update failed: $e');
            }
          }
        } on FirebaseException catch (e) {
          debugPrint('Firestore error: ${e.code} - ${e.message}');
          await authState.signOut();
          if (!mounted) return;
          _showError('Database error. Please check your connection and try again.');
          return;
        } catch (e) {
          debugPrint('Unexpected error during profile setup: $e');
          await authState.signOut();
          if (!mounted) return;
          _showError('Failed to load profile. Please try again.');
          return;
        }
        // AuthGate will handle navigation
      case AuthFailure(:final error):
        if (error.isNotEmpty) {
          _showError(error);
        }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: AppColors.dangerRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AuthState>(
      builder: (context, authState, child) {
        final isLoading = authState.isLoading;

        return Scaffold(
          backgroundColor:
              isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
          body: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        // App Logo/Branding
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security,
                              size: 48,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Welcome Back',
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: isDarkMode
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Login to your account to continue',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: isDarkMode
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),

                        // Rate limit warning
                        if (authState.isRateLimited) ...[
                          const SizedBox(height: 16),
                          _buildRateLimitWarning(authState),
                        ],

                        const SizedBox(height: 30),
                        FormBuilder(
                          key: _formKey,
                          child: AutofillGroup(
                            child: Column(
                              children: [
                                // Email Field
                                FormBuilderTextField(
                                  name: 'email',
                                  enabled: !isLoading,
                                  autofillHints: const [AutofillHints.email],
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: GoogleFonts.inter(
                                    color: isDarkMode
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Email',
                                    hintStyle: GoogleFonts.inter(
                                      color: isDarkMode
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondary,
                                    ),
                                    prefixIcon:
                                        const Icon(Icons.email_outlined),
                                  ),
                                  validator: FormBuilderValidators.compose([
                                    FormBuilderValidators.required(),
                                    FormBuilderValidators.email(),
                                  ]),
                                ),
                                const SizedBox(height: 20),

                                // Password Field
                                FormBuilderTextField(
                                  name: 'password',
                                  enabled: !isLoading,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) =>
                                      isLoading ? null : _handleLogin(),
                                  style: GoogleFonts.inter(
                                    color: isDarkMode
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Password',
                                    hintStyle: GoogleFonts.inter(
                                      color: isDarkMode
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondary,
                                    ),
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: _togglePasswordVisibility,
                                    ),
                                  ),
                                  validator: FormBuilderValidators.required(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPassScreen(),
                                      ),
                                    ),
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.inter(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _handleLogin,
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Login',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider with "OR"
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: isDarkMode
                                    ? AppColors.borderDark
                                    : AppColors.borderLight,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkMode
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: isDarkMode
                                    ? AppColors.borderDark
                                    : AppColors.borderLight,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Social Sign In Buttons
                        _buildSocialButton(
                          onPressed: isLoading ? null : _handleGoogleSignIn,
                          icon: 'G',
                          label: 'Continue with Google',
                          isDarkMode: isDarkMode,
                          iconColor: Colors.red,
                        ),

                        // Apple Sign In - hidden on Android
                        if (!Platform.isAndroid) ...[
                          const SizedBox(height: 12),
                          _buildSocialButton(
                            onPressed: null, // Not implemented yet
                            icon: '',
                            label: 'Continue with Apple',
                            isDarkMode: isDarkMode,
                            iconColor: isDarkMode
                                ? Colors.white
                                : AppColors.textPrimary,
                            useAppleIcon: true,
                          ),
                        ],

                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account?",
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: isDarkMode
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RegisterScreen(),
                                        ),
                                      ),
                              child: Text(
                                'Register',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRateLimitWarning(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: AppColors.warningOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Too many attempts. Please wait ${authState.rateLimitRemaining?.inSeconds ?? 0}s',
              style: GoogleFonts.inter(
                color: AppColors.warningOrange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required VoidCallback? onPressed,
    required String icon,
    required String label,
    required bool isDarkMode,
    required Color iconColor,
    bool useAppleIcon = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (useAppleIcon)
              Icon(
                Icons.apple,
                size: 24,
                color: iconColor,
              )
            else
              Text(
                icon,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
