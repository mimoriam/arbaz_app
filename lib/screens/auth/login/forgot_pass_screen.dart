import 'package:arbaz_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:google_fonts/google_fonts.dart';

class ForgotPassScreen extends StatefulWidget {
  const ForgotPassScreen({super.key});

  @override
  State<ForgotPassScreen> createState() => _ForgotPassScreenState();
}

class _ForgotPassScreenState extends State<ForgotPassScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isLoading = false;
  bool _emailSent = false;
  String _sentEmail = '';

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
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isLoading = true);
      try {
        final email = _formKey.currentState?.fields['email']?.value as String?;
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          await _animationController.reverse();
          setState(() {
            _emailSent = true;
            _sentEmail = email ?? '';
          });
          _animationController.forward();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}', style: GoogleFonts.inter()), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: IconThemeData(color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary)),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _emailSent ? _buildConfirmationScreen(isDarkMode) : _buildEmailForm(isDarkMode),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm(bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.lock_reset, size: 64, color: AppColors.primaryBlue),
            ),
          ),
          const SizedBox(height: 32),
          Text('Reset Password', style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800,
            color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Enter your email to receive a password reset link', style: GoogleFonts.inter(fontSize: 16,
            color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary)),
          const SizedBox(height: 40),
          FormBuilder(
            key: _formKey,
            child: FormBuilderTextField(
              name: 'email',
              enabled: !_isLoading,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleResetPassword(),
              style: GoogleFonts.inter(color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary),
              decoration: InputDecoration(hintText: 'Email', prefixIcon: const Icon(Icons.email_outlined),
                hintStyle: GoogleFonts.inter(color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary)),
              validator: FormBuilderValidators.compose([FormBuilderValidators.required(), FormBuilderValidators.email()]),
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleResetPassword,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : Text('Send Reset Link', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationScreen(bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.successGreen,
              boxShadow: [BoxShadow(color: AppColors.successGreen.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 10)]),
            child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 40),
          Text('Check Your Email', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800,
            color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary)),
          const SizedBox(height: 16),
          Text('We\'ve sent a password reset link to:', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 16,
            color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(_sentEmail, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryBlue)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: isDarkMode ? AppColors.surfaceDark : AppColors.inputFillLight,
              borderRadius: BorderRadius.circular(16), border: Border.all(color: isDarkMode ? AppColors.borderDark : AppColors.borderLight)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 20, color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Didn\'t receive the email?', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
                    color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary))),
                ]),
                const SizedBox(height: 12),
                Text('• Check your spam folder\n• Make sure email is correct\n• Wait a few minutes', style: GoogleFonts.inter(fontSize: 13,
                  color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context),
            child: Text('Back to Login', style: GoogleFonts.inter(fontWeight: FontWeight.w600)))),
        ],
      ),
    );
  }
}
