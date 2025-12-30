import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/security_vault.dart';

/// Security Vault Screen for storing sensitive information securely
class SafetyVaultScreen extends StatefulWidget {
  const SafetyVaultScreen({super.key});

  @override
  State<SafetyVaultScreen> createState() => _SafetyVaultScreenState();
}

class _SafetyVaultScreenState extends State<SafetyVaultScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSaving = false;
  bool _isLoading = true;
  
  // Multi-pet support
  List<PetInfo> _pets = [];
  
  // Track visibility of sensitive fields
  final Map<String, bool> _fieldVisibility = {};

  @override
  void initState() {
    super.initState();
    _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final firestoreService = context.read<FirestoreService>();
      final vault = await firestoreService.getSecurityVault(user.uid);
      
      if (vault != null && mounted) {
        setState(() {
          _pets = List.from(vault.pets);
        });
        
        // Populate form fields after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _formKey.currentState?.patchValue({
            'home_address': vault.homeAddress,
            'building_entry_code': vault.buildingEntryCode,
            'apartment_door_code': vault.apartmentDoorCode,
            'spare_key_location': vault.spareKeyLocation,
            'alarm_code': vault.alarmCode,
            'doctor_name_phone': vault.doctorNamePhone,
            'medications_list': vault.medicationsList,
            'allergies': vault.allergies,
            'medical_conditions': vault.medicalConditions,
            'other_notes': vault.otherNotes,
          });
        });
      }
    } catch (e) {
      debugPrint('Error loading vault: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDarkMode),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : FormBuilder(
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
                                title: 'PET CARE',
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
        _buildTextField(isDarkMode, name: 'home_address', hint: 'Home address'),
        _buildDivider(isDarkMode),
        _buildTextField(isDarkMode, name: 'building_entry_code', hint: 'Building entry code', obscureText: true),
        _buildDivider(isDarkMode),
        _buildTextField(isDarkMode, name: 'apartment_door_code', hint: 'Apartment/door code', obscureText: true),
        _buildDivider(isDarkMode),
        _buildTextField(isDarkMode, name: 'spare_key_location', hint: 'Spare key location'),
        _buildDivider(isDarkMode),
        _buildTextField(isDarkMode, name: 'alarm_code', hint: 'Alarm code', isLast: true, obscureText: true),
      ],
    );
  }

  Widget _buildPetCareSection(bool isDarkMode) {
    return Column(
      children: [
        // Existing pets
        ..._pets.asMap().entries.map((entry) {
          final index = entry.key;
          final pet = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildPetCard(isDarkMode, pet, index),
          );
        }),
        
        // Add pet button
        GestureDetector(
          onTap: () => _showAddPetDialog(isDarkMode),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.warningOrange.withValues(alpha: 0.3),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: AppColors.warningOrange,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Add Pet',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningOrange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPetCard(bool isDarkMode, PetInfo pet, int index) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          // Pet header with name, type, and delete button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.pets, color: AppColors.warningOrange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${pet.name} (${pet.type})',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showEditPetDialog(isDarkMode, pet, index),
                  icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.primaryBlue),
                ),
                IconButton(
                  onPressed: () => _removePet(index),
                  icon: Icon(Icons.delete_outline, size: 20, color: AppColors.dangerRed),
                ),
              ],
            ),
          ),
          
          // Pet details
          if (pet.medications != null || pet.vetNamePhone != null || 
              pet.foodInstructions != null || pet.specialNeeds != null) ...[
            _buildDivider(isDarkMode),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pet.medications != null && pet.medications!.isNotEmpty)
                    _buildPetDetailRow('Medications', pet.medications!, isDarkMode),
                  if (pet.vetNamePhone != null && pet.vetNamePhone!.isNotEmpty)
                    _buildPetDetailRow('Vet', pet.vetNamePhone!, isDarkMode),
                  if (pet.foodInstructions != null && pet.foodInstructions!.isNotEmpty)
                    _buildPetDetailRow('Food', pet.foodInstructions!, isDarkMode),
                  if (pet.specialNeeds != null && pet.specialNeeds!.isNotEmpty)
                    _buildPetDetailRow('Special Needs', pet.specialNeeds!, isDarkMode),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPetDetailRow(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPetDialog(bool isDarkMode) {
    _showPetDialog(isDarkMode, null, null);
  }

  void _showEditPetDialog(bool isDarkMode, PetInfo pet, int index) {
    _showPetDialog(isDarkMode, pet, index);
  }

  Future<void> _showPetDialog(bool isDarkMode, PetInfo? existingPet, int? editIndex) async {
    final nameController = TextEditingController(text: existingPet?.name ?? '');
    final typeController = TextEditingController(text: existingPet?.type ?? '');
    final medicationsController = TextEditingController(text: existingPet?.medications ?? '');
    final vetController = TextEditingController(text: existingPet?.vetNamePhone ?? '');
    final foodController = TextEditingController(text: existingPet?.foodInstructions ?? '');
    final specialNeedsController = TextEditingController(text: existingPet?.specialNeeds ?? '');

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                Text(
                  editIndex != null ? 'Edit Pet' : 'Add Pet',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildDialogTextField('Pet Name', nameController, isDarkMode),
                const SizedBox(height: 12),
                _buildDialogTextField('Pet Type (e.g., Dog, Cat)', typeController, isDarkMode),
                const SizedBox(height: 12),
                _buildDialogTextField('Medications & Schedule', medicationsController, isDarkMode),
                const SizedBox(height: 12),
                _buildDialogTextField('Vet Name & Phone', vetController, isDarkMode),
                const SizedBox(height: 12),
                _buildDialogTextField('Food Instructions', foodController, isDarkMode),
                const SizedBox(height: 12),
                _buildDialogTextField('Special Needs', specialNeedsController, isDarkMode),
                const SizedBox(height: 24),
                
                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (nameController.text.isEmpty || typeController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Pet name and type are required'),
                            backgroundColor: AppColors.dangerRed,
                          ),
                        );
                        return;
                      }
                      
                      final newPet = PetInfo(
                        name: nameController.text,
                        type: typeController.text,
                        medications: medicationsController.text.isNotEmpty ? medicationsController.text : null,
                        vetNamePhone: vetController.text.isNotEmpty ? vetController.text : null,
                        foodInstructions: foodController.text.isNotEmpty ? foodController.text : null,
                        specialNeeds: specialNeedsController.text.isNotEmpty ? specialNeedsController.text : null,
                      );
                      
                      setState(() {
                        if (editIndex != null) {
                          _pets[editIndex] = newPet;
                        } else {
                          _pets.add(newPet);
                        }
                      });
                      
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warningOrange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      editIndex != null ? 'Update Pet' : 'Add Pet',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    } finally {
      // Dispose controllers after the bottom sheet is closed
      nameController.dispose();
      typeController.dispose();
      medicationsController.dispose();
      vetController.dispose();
      foodController.dispose();
      specialNeedsController.dispose();
    }
  }

  Widget _buildDialogTextField(String hint, TextEditingController controller, bool isDarkMode) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(
        fontSize: 15,
        color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
        filled: true,
        fillColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  void _removePet(int index) {
    setState(() {
      _pets.removeAt(index);
    });
  }

  Widget _buildMedicalInfoSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextField(isDarkMode, name: 'doctor_name_phone', hint: "Doctor's name and phone"),
        _buildDivider(isDarkMode),
        _buildTextArea(isDarkMode, name: 'medications_list', hint: 'Medications list', maxLines: 3),
        _buildDivider(isDarkMode),
        _buildTextField(isDarkMode, name: 'allergies', hint: 'Allergies'),
        _buildDivider(isDarkMode),
        _buildTextArea(isDarkMode, name: 'medical_conditions', hint: 'Medical conditions', maxLines: 2, isLast: true),
      ],
    );
  }

  Widget _buildOtherNotesSection(bool isDarkMode) {
    return _buildFormCard(
      isDarkMode,
      children: [
        _buildTextArea(isDarkMode, name: 'other_notes', hint: 'Free text field for anything else', maxLines: 4, isLast: true),
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
  }) {
    // Initialize visibility state for this field if not exists
    _fieldVisibility[name] ??= false;
    final isVisible = _fieldVisibility[name]!;
    
    return FormBuilderTextField(
      name: name,
      obscureText: obscureText && !isVisible,
      keyboardType: keyboardType,
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
        contentPadding: EdgeInsets.fromLTRB(20, 18, obscureText ? 50 : 20, isLast ? 18 : 18),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        suffixIcon: obscureText
            ? IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility_off : Icons.visibility,
                  color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _fieldVisibility[name] = !isVisible),
              )
            : null,
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
        contentPadding: EdgeInsets.fromLTRB(20, 18, 20, isLast ? 18 : 12),
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
                    'Save Vault',
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
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please sign in to save vault data'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
      return;
    }
    // Save form values (no validation required)
    _formKey.currentState?.save();
    final formData = _formKey.currentState?.value ?? {};

    setState(() => _isSaving = true);

    try {
      final vault = SecurityVault(
        homeAddress: formData['home_address'] as String?,
        buildingEntryCode: formData['building_entry_code'] as String?,
        apartmentDoorCode: formData['apartment_door_code'] as String?,
        spareKeyLocation: formData['spare_key_location'] as String?,
        alarmCode: formData['alarm_code'] as String?,
        pets: _pets,
        doctorNamePhone: formData['doctor_name_phone'] as String?,
        medicationsList: formData['medications_list'] as String?,
        allergies: formData['allergies'] as String?,
        medicalConditions: formData['medical_conditions'] as String?,
        otherNotes: formData['other_notes'] as String?,
      );

      await context.read<FirestoreService>().saveSecurityVault(user.uid, vault);

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
    } catch (e) {
      debugPrint('Error saving vault: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving vault: $e'),
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
}
