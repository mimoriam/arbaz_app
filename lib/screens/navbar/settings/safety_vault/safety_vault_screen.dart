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
  final String? userId; // Optional: View another user's vault
  final bool isReadOnly; // Optional: Disable editing

  const SafetyVaultScreen({
    super.key,
    this.userId,
    this.isReadOnly = false,
  });

  @override
  State<SafetyVaultScreen> createState() => _SafetyVaultScreenState();
}

class _SafetyVaultScreenState extends State<SafetyVaultScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSaving = false;
  bool _isLoading = true;
  
  // Multi-pet support
  List<PetInfo> _pets = [];
  SecurityVault? _vault; // Store full vault object for checking empty fields
  
  // Track visibility of sensitive fields
  final Map<String, bool> _fieldVisibility = {};

  @override
  void initState() {
    super.initState();
    _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    // Use provided userId or fallback to current user
    final targetUserId = widget.userId ?? currentUser?.uid;

    if (targetUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final firestoreService = context.read<FirestoreService>();
      final vault = await firestoreService.getSecurityVault(targetUserId);
      
      if (vault != null && mounted) {
        setState(() {
          _vault = vault;
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
                            physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling works
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                
                                // Read-only Banner
                                if (widget.isReadOnly) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.primaryBlue.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.info_outline, 
                                          color: AppColors.primaryBlue,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'View-only mode during emergency',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.primaryBlue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

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

                                // Done Button - Hide in Read-Only
                                if (!widget.isReadOnly)
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
                widget.isReadOnly ? 'Emergency Vault' : 'Security Vault',
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
    if (_vault == null && widget.isReadOnly) return const SizedBox.shrink();

    final fields = <Widget>[];

    void addField(String name, String hint, String? value, {bool obscure = false}) {
      if (!widget.isReadOnly || (value != null && value.isNotEmpty)) {
        fields.add(_buildTextField(
          isDarkMode,
          name: name,
          hint: hint,
          obscureText: obscure,
        ));
      }
    }

    addField('home_address', 'Home address', _vault?.homeAddress);
    addField('building_entry_code', 'Building entry code', _vault?.buildingEntryCode, obscure: true);
    addField('apartment_door_code', 'Apartment/door code', _vault?.apartmentDoorCode, obscure: true);
    addField('spare_key_location', 'Spare key location', _vault?.spareKeyLocation);
    addField('alarm_code', 'Alarm code', _vault?.alarmCode, obscure: true);

    if (fields.isEmpty) {
        if (widget.isReadOnly) return _buildEmptyStateMessage(isDarkMode);
        return const SizedBox.shrink(); // Should not happen in edit mode
    }

    // Join with dividers
    final children = <Widget>[];
    for (int i = 0; i < fields.length; i++) {
        children.add(fields[i]);
        if (i < fields.length - 1) {
            children.add(_buildDivider(isDarkMode));
        }
    }

    return _buildFormCard(isDarkMode, children: children);
  }

  Widget _buildEmptyStateMessage(bool isDarkMode) {
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDarkMode ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Text(
            'No information provided.',
            style: GoogleFonts.inter(
                fontSize: 14,
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
        ),
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
        
        // Add pet button - Hide in Read-Only
        if (!widget.isReadOnly)
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: [
          if (!isDarkMode)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          // Pet Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warningOrange.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    pet.type.toLowerCase().contains('cat') 
                        ? Icons.cruelty_free 
                        : Icons.pets,
                    color: AppColors.warningOrange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pet.name,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        pet.type,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isReadOnly) ...[
                  IconButton(
                    onPressed: () => _showEditPetDialog(isDarkMode, pet, index),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primaryBlue),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _removePet(index),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.delete_rounded, size: 18, color: AppColors.dangerRed),
                  ),
                ],
              ],
            ),
          ),
          
          // Pet Details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (pet.medications != null && pet.medications!.isNotEmpty)
                  _buildPetDetailRow(Icons.medication, 'Medications', pet.medications!, isDarkMode),
                if (pet.vetNamePhone != null && pet.vetNamePhone!.isNotEmpty)
                  _buildPetDetailRow(Icons.local_hospital, 'Vet Info', pet.vetNamePhone!, isDarkMode),
                if (pet.foodInstructions != null && pet.foodInstructions!.isNotEmpty)
                  _buildPetDetailRow(Icons.restaurant, 'Food', pet.foodInstructions!, isDarkMode),
                if (pet.specialNeeds != null && pet.specialNeeds!.isNotEmpty)
                  _buildPetDetailRow(Icons.warning_amber_rounded, 'Special Needs', pet.specialNeeds!, isDarkMode, isAlert: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetDetailRow(IconData icon, String label, String value, bool isDarkMode, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: isAlert 
                ? AppColors.dangerRed 
                : (isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.4,
                    color: isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary,
                    fontWeight: isAlert ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
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
        builder: (sheetContext) {
          // Use StatefulBuilder for local state management of validation errors
          String? nameError;
          String? typeError;
          
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
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
                      
                      // Pet Name with inline error
                      _buildDialogTextField('Pet Name', nameController, isDarkMode, 
                        errorText: nameError,
                        onChanged: (_) {
                          if (nameError != null) {
                            setSheetState(() => nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // Pet Type with inline error
                      _buildDialogTextField('Pet Type (e.g., Dog, Cat)', typeController, isDarkMode,
                        errorText: typeError,
                        onChanged: (_) {
                          if (typeError != null) {
                            setSheetState(() => typeError = null);
                          }
                        },
                      ),
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
                            // Inline validation - show errors below fields, not in SnackBar
                            bool hasError = false;
                            
                            if (nameController.text.isEmpty) {
                              setSheetState(() => nameError = 'Pet name is required');
                              hasError = true;
                            }
                            if (typeController.text.isEmpty) {
                              setSheetState(() => typeError = 'Pet type is required');
                              hasError = true;
                            }
                            
                            if (hasError) return;
                            
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
              );
            },
          );
        },
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

  Widget _buildDialogTextField(
    String hint, 
    TextEditingController controller, 
    bool isDarkMode, {
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          // Hide textfield from accepting input if strictly read-only mode for safety (though dialog shouldn't open)
          enabled: !widget.isReadOnly,  
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
                color: hasError ? AppColors.dangerRed : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.dangerRed : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.dangerRed : AppColors.primaryBlue,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        // Inline error message
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.dangerRed,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  void _removePet(int index) {
    setState(() {
      _pets.removeAt(index);
    });
  }

  Widget _buildMedicalInfoSection(bool isDarkMode) {
    if (_vault == null && widget.isReadOnly) return const SizedBox.shrink();

    final fields = <Widget>[];

    void addField(String name, String hint, String? value, {bool isTextArea = false, int maxLines = 1}) {
      if (!widget.isReadOnly || (value != null && value.isNotEmpty)) {
        if (isTextArea) {
             fields.add(_buildTextArea(isDarkMode, name: name, hint: hint, maxLines: maxLines));
        } else {
             fields.add(_buildTextField(isDarkMode, name: name, hint: hint));
        }
      }
    }

    addField('doctor_name_phone', "Doctor's name and phone", _vault?.doctorNamePhone);
    addField('medications_list', 'Medications list', _vault?.medicationsList, isTextArea: true, maxLines: 3);
    addField('allergies', 'Allergies', _vault?.allergies);
    addField('medical_conditions', 'Medical conditions', _vault?.medicalConditions, isTextArea: true, maxLines: 2);

    if (fields.isEmpty) {
        if (widget.isReadOnly) return _buildEmptyStateMessage(isDarkMode);
    }
    
    final children = <Widget>[];
    for (int i = 0; i < fields.length; i++) {
        children.add(fields[i]);
        if (i < fields.length - 1) {
            children.add(_buildDivider(isDarkMode));
        }
    }

    return _buildFormCard(isDarkMode, children: children);
  }

  Widget _buildOtherNotesSection(bool isDarkMode) {
    if ((_vault?.otherNotes == null || _vault!.otherNotes!.isEmpty) && widget.isReadOnly) {
        return _buildEmptyStateMessage(isDarkMode);
    }
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
      // Use readOnly instead of enabled for "View Only" mode to allow scrolling and prefix/suffix interaction
      readOnly: widget.isReadOnly, 
      enabled: true, 
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
      readOnly: widget.isReadOnly,
      enabled: true,
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
