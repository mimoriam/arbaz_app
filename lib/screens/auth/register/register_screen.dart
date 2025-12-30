import 'dart:io';

import 'package:arbaz_app/services/auth_state.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/user_model.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:arbaz_app/utils/timezone_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  String _password = '';
  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';
  Color _passwordStrengthColor = Colors.grey;

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

  void _toggleConfirmPasswordVisibility() {
    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
  }

  void _updatePasswordStrength(String password) {
    _password = password;
    double strength = 0;

    if (password.length >= 8) strength += 0.25;
    if (password.length >= 12) strength += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength += 0.2;
    if (RegExp(r'[a-z]').hasMatch(password)) strength += 0.1;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 0.15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength += 0.15;

    setState(() {
      _passwordStrength = strength.clamp(0.0, 1.0);
      if (_passwordStrength < 0.3) {
        _passwordStrengthLabel = 'Weak';
        _passwordStrengthColor = AppColors.dangerRed;
      } else if (_passwordStrength < 0.6) {
        _passwordStrengthLabel = 'Fair';
        _passwordStrengthColor = AppColors.warningOrange;
      } else if (_passwordStrength < 0.8) {
        _passwordStrengthLabel = 'Good';
        _passwordStrengthColor = AppColors.primaryBlue;
      } else {
        _passwordStrengthLabel = 'Strong';
        _passwordStrengthColor = AppColors.successGreen;
      }
    });
  }

  Future<void> _handleRegister() async {
    if (!_acceptedTerms) {
      _showMessage('Please accept Terms & Conditions to continue.',
          AppColors.warningOrange);
      return;
    }

    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;

    final authState = context.read<AuthState>();
    final firestoreService = context.read<FirestoreService>();

    final name = _formKey.currentState?.fields['name']?.value as String;
    final email = _formKey.currentState?.fields['email']?.value as String;
    final password =
        _formKey.currentState?.fields['password']?.value as String;

    final result =
        await authState.registerWithEmail(email, password, name);

    if (!mounted) return;

    switch (result) {
      case AuthSuccess(:final data):
        final user = data.user;
        if (user == null) {
          _showMessage('Registration failed. Please try again.', AppColors.dangerRed);
          return;
        }

        // Create user profile and default roles
        final profile = UserProfile(
          uid: user.uid,
          email: user.email ?? email,
          displayName: name,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          timezone: TimezoneHelper.getDeviceTimezone(),
        );
        final roles = UserRoles();

        try {
          await firestoreService.createUserWithRoles(user.uid, profile, roles);

          if (!mounted) return;
          _showMessage('Account created successfully!', AppColors.successGreen);
          // Pop back to AuthGate which will redirect to QuestionnaireScreen
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (e) {
          // Rollback: delete the Firebase Auth user on Firestore failure
          try {
            await user.delete();
          } catch (_) {
            // Rollback failed - user may need to contact support
          }
          if (!mounted) return;
          _showMessage(
            'Failed to create profile. Please try again.',
            AppColors.dangerRed,
          );
        }
      case AuthFailure(:final error):
        if (error.isNotEmpty) {
          _showMessage(error, AppColors.dangerRed);
        }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_acceptedTerms) {
      _showMessage('Please accept Terms & Conditions to continue.',
          AppColors.warningOrange);
      return;
    }

    final authState = context.read<AuthState>();
    final firestoreService = context.read<FirestoreService>();

    final result = await authState.signInWithGoogle();

    if (!mounted) return;

    switch (result) {
      case AuthSuccess(:final data):
        final user = data?.user;
        if (user == null) {
          _showMessage('Sign-in failed. Please try again.', AppColors.dangerRed);
          return;
        }

        try {
          // Check if profile exists
          final existingProfile = await firestoreService.getUserProfile(user.uid);

          if (existingProfile == null) {
            // Create new profile
            final profile = UserProfile(
              uid: user.uid,
              email: user.email ?? '',
              displayName: user.displayName,
              photoUrl: user.photoURL,
              createdAt: DateTime.now(),
              lastLoginAt: DateTime.now(),
              timezone: TimezoneHelper.getDeviceTimezone(),
            );
            final roles = UserRoles();
            await firestoreService.createUserWithRoles(user.uid, profile, roles);
          }

          if (!mounted) return;
          // Pop back to AuthGate which will redirect to QuestionnaireScreen
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (e) {
          // Rollback: sign out to avoid leaving user authenticated without profile
          debugPrint('Profile creation/lookup failed during Google sign-in: $e');
          try {
            await authState.signOut();
          } catch (signOutError) {
            debugPrint('Rollback sign-out failed: $signOutError');
          }
          if (!mounted) return;
          _showMessage(
            'Failed to create profile. Please try again.',
            AppColors.dangerRed,
          );
        }
      case AuthFailure(:final error):
        if (error.isNotEmpty) {
          _showMessage(error, AppColors.dangerRed);
        }
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: color,
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
          backgroundColor: isDarkMode
              ? AppColors.backgroundDark
              : AppColors.backgroundLight,
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
                        Text(
                          'Create Account',
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
                          'Sign up to get started',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: isDarkMode
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Social Sign In Buttons
                        _buildSocialButton(
                          onPressed: isLoading ? null : _handleGoogleSignIn,
                          icon: 'G',
                          label: 'Sign up with Google',
                          isDarkMode: isDarkMode,
                          iconColor: Colors.red,
                        ),

                        // Apple Sign In - hidden on Android
                        if (!Platform.isAndroid) ...[
                          const SizedBox(height: 12),
                          _buildSocialButton(
                            onPressed: null, // Not implemented yet
                            icon: '',
                            label: 'Sign up with Apple',
                            isDarkMode: isDarkMode,
                            iconColor: isDarkMode
                                ? Colors.white
                                : AppColors.textPrimary,
                            useAppleIcon: true,
                          ),
                        ],
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

                        FormBuilder(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Full Name Field
                              FormBuilderTextField(
                                name: 'name',
                                enabled: !isLoading,
                                autofillHints: const [AutofillHints.name],
                                keyboardType: TextInputType.name,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                style: GoogleFonts.inter(
                                  color: isDarkMode
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Full Name',
                                  hintStyle: GoogleFonts.inter(
                                    color: isDarkMode
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondary,
                                  ),
                                  prefixIcon:
                                      const Icon(Icons.person_outline),
                                ),
                                validator: FormBuilderValidators.required(),
                              ),
                              const SizedBox(height: 16),

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
                                  prefixIcon: const Icon(Icons.email_outlined),
                                ),
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  FormBuilderValidators.email(),
                                ]),
                              ),
                              const SizedBox(height: 16),

                              // Password Field
                              FormBuilderTextField(
                                name: 'password',
                                enabled: !isLoading,
                                obscureText: _obscurePassword,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                textInputAction: TextInputAction.next,
                                style: GoogleFonts.inter(
                                  color: isDarkMode
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                                onChanged: (value) =>
                                    _updatePasswordStrength(value ?? ''),
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
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  FormBuilderValidators.minLength(
                                    8,
                                    errorText:
                                        'Password must be at least 8 characters',
                                  ),
                                ]),
                              ),

                              // Password Strength Meter
                              if (_password.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildPasswordStrengthMeter(isDarkMode),
                              ],
                              const SizedBox(height: 16),

                              // Confirm Password Field
                              FormBuilderTextField(
                                name: 'confirm_password',
                                enabled: !isLoading,
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) =>
                                    isLoading ? null : _handleRegister(),
                                style: GoogleFonts.inter(
                                  color: isDarkMode
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Confirm Password',
                                  hintStyle: GoogleFonts.inter(
                                    color: isDarkMode
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondary,
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed:
                                        _toggleConfirmPasswordVisibility,
                                  ),
                                ),
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  (value) {
                                    if (value != _password) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Terms and Conditions Checkbox
                        _buildTermsCheckbox(isDarkMode, isLoading),

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _handleRegister,
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Register',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
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

  Widget _buildPasswordStrengthMeter(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password Strength',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            Text(
              _passwordStrengthLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _passwordStrengthColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _passwordStrength,
            backgroundColor:
                isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            valueColor: AlwaysStoppedAnimation<Color>(_passwordStrengthColor),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use 8+ characters with uppercase, numbers & symbols',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: isDarkMode
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTermsCheckbox(bool isDarkMode, bool isLoading) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _acceptedTerms,
            onChanged: isLoading
                ? null
                : (value) {
                    setState(() => _acceptedTerms = value ?? false);
                  },
            activeColor: AppColors.primaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: isLoading
                ? null
                : () => setState(() => _acceptedTerms = !_acceptedTerms),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDarkMode
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
