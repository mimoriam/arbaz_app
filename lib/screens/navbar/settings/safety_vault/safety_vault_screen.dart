import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:arbaz_app/utils/app_colors.dart';

/// Security Vault Screen for storing sensitive information securely
class SafetyVaultScreen extends StatefulWidget {
  const SafetyVaultScreen({super.key});

  @override
  State<SafetyVaultScreen> createState() => _SafetyVaultScreenState();
}

class _SafetyVaultScreenState extends State<SafetyVaultScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      // Unfocus fields when tapping outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(isDarkMode),

              // Content
              Expanded(
                child: FormBuilder(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),

                        // Home Access Section
                        _buildSectionHeader(
                          isDarkMode,
                          icon: Icons.home_outlined,
                          title: 'HOME ACCESS',
                          iconColor: AppColors.primaryBlue,
                        ),
                        const SizedBox(height: 12),
                        _buildHomeAccessSection(isDarkMode),

                        const SizedBox(height: 28),

                        // Pet Care Section
                        _buildSectionHeader(
                          isDarkMode,
                          icon: Icons.pets_outlined,
                          title: 'PET CARE (IF APPLICABLE)',
                          iconColor: AppColors.warningOrange,
                        ),
                        const SizedBox(height: 12),
                        _buildPetCareSection(isDarkMode),

                        const SizedBox(height: 28),

                        // Medical Info Section
                        _buildSectionHeader(
                          isDarkMode,
                          icon: Icons.favorite_outline,
                          title: 'MEDICAL INFO',
                          iconColor: AppColors.dangerRed,
                        ),
                        const SizedBox(height: 12),
                        _buildMedicalInfoSection(isDarkMode),

                        const SizedBox(height: 28),

                        // Other Notes Section
                        _buildSectionHeader(
                          isDarkMode,
                          icon: Icons.edit_note_outlined,
                          title: 'OTHER NOTES',
                          iconColor: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        _buildOtherNotesSection(isDarkMode),

                        const SizedBox(height: 32),

                        // Done Button
                        _buildDoneButton(isDarkMode),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
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
                'Security Vault',
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

          // Spacer to balance the back button
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    bool isDarkMode, {
    required IconData icon,
    required String title,
    Color? iconColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: iconColor ??
              (isDarkMode
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: iconColor ??
                (isDarkMode
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeAccessSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextField(
          isDarkMode,
          name: 'home_address',
          hint: 'Home address',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'building_entry_code',
          hint: 'Building entry code',
          obscureText: true,
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.numeric(),
          ]),
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'apartment_door_code',
          hint: 'Apartment/door code',
          obscureText: true,
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.numeric(),
          ]),
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'spare_key_location',
          hint: 'Spare key location',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'alarm_code',
          hint: 'Alarm code',
          isLast: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.numeric(),
          ]),
        ),
      ],
    );
  }

  Widget _buildPetCareSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextField(
          isDarkMode,
          name: 'pet_name_type',
          hint: 'Pet name and type',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'medications_schedule',
          hint: 'Medications and schedule',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'vet_name_phone',
          hint: 'Vet name and phone',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'food_instructions',
          hint: 'Food instructions',
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'special_needs',
          hint: 'Special needs',
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildMedicalInfoSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextField(
          isDarkMode,
          name: 'doctor_name_phone',
          hint: "Doctor's name and phone",
        ),
        _buildDivider(isDarkMode),
        _buildTextArea(
          isDarkMode,
          name: 'medications_list',
          hint: 'Medications list',
          maxLines: 3,
        ),
        _buildDivider(isDarkMode),
        _buildTextField(
          isDarkMode,
          name: 'allergies',
          hint: 'Allergies',
        ),
        _buildDivider(isDarkMode),
        _buildTextArea(
          isDarkMode,
          name: 'medical_conditions',
          hint: 'Medical conditions',
          maxLines: 2,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildOtherNotesSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextArea(
          isDarkMode,
          name: 'other_notes',
          hint: 'Free text field for anything else',
          maxLines: 4,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildFormCard(bool isDarkMode, {required List<Widget> children}) {
    return Container(
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
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTextField(
    bool isDarkMode, {
    required String name,
    required String hint,
    bool isLast = false,
    bool obscureText = false,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
  }) {
    return FormBuilderTextField(
      name: name,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: isDarkMode
              ? AppColors.textSecondaryDark.withValues(alpha: 0.7)
              : AppColors.textSecondary.withValues(alpha: 0.8),
        ),
        filled: false,
        contentPadding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          isLast ? 18 : 18,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
  }

  Widget _buildTextArea(
    bool isDarkMode, {
    required String name,
    required String hint,
    int maxLines = 3,
    bool isLast = false,
  }) {
    return FormBuilderTextField(
      name: name,
      maxLines: maxLines,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: isDarkMode
              ? AppColors.textSecondaryDark.withValues(alpha: 0.7)
              : AppColors.textSecondary.withValues(alpha: 0.8),
        ),
        filled: false,
        contentPadding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          isLast ? 18 : 12,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
  }

  Widget _buildDivider(bool isDarkMode) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDarkMode
          ? AppColors.borderDark.withValues(alpha: 0.5)
          : AppColors.borderLight,
    );
  }

  Widget _buildDoneButton(bool isDarkMode) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.vaultCard,
            AppColors.vaultCard.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.vaultCard.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSaving ? null : _saveVault,
          borderRadius: BorderRadius.circular(30),
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Done',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveVault() async {
    // Unfocus any active field
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSaving = true);

      // Simulate saving
      await Future.delayed(const Duration(milliseconds: 800));

      final formData = _formKey.currentState?.value;
      debugPrint('Vault Data: $formData');

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vault saved securely!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

        Navigator.pop(context);
      }
    }
  }
}
