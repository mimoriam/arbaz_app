import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/custom_question_model.dart';

/// Common emojis for quick selection
const List<String> commonEmojis = [
  '😊', '😃', '😐', '😕', '😢', '😴', '🤔', '😰',
  '💪', '😷', '🤧', '😌', '😁', '🙂', '😣', '😫',
  '👍', '👎', '✅', '❌', '⭐', '💚', '💛', '❤️',
  '☀️', '🌙', '🏃', '🧘', '💊', '🍎', '💤', '🏠',
];

/// Screen to add or edit a custom question
class AddCustomQuestionScreen extends StatefulWidget {
  final CustomQuestion? existingQuestion;

  const AddCustomQuestionScreen({
    super.key,
    this.existingQuestion,
  });

  @override
  State<AddCustomQuestionScreen> createState() => _AddCustomQuestionScreenState();
}

class _AddCustomQuestionScreenState extends State<AddCustomQuestionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _questionFocusNode = FocusNode();
  List<_AnswerEntry> _answers = [];
  bool _isSaving = false;

  bool get isEditing => widget.existingQuestion != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingQuestion != null) {
      _questionController.text = widget.existingQuestion!.question;
      _answers = widget.existingQuestion!.answers
          .map((a) => _AnswerEntry(
                labelController: TextEditingController(text: a.label),
                focusNode: FocusNode(),
                emoji: a.emoji,
              ))
          .toList();
    } else {
      // Start with 3 empty answers (minimum required)
      _answers = [
        _AnswerEntry(labelController: TextEditingController(), focusNode: FocusNode(), emoji: '😊'),
        _AnswerEntry(labelController: TextEditingController(), focusNode: FocusNode(), emoji: '😐'),
        _AnswerEntry(labelController: TextEditingController(), focusNode: FocusNode(), emoji: '😕'),
      ];
    }
    
    // Listen to changes for live preview
    _questionController.addListener(() => setState(() {}));
    for (final answer in _answers) {
      answer.labelController.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _questionFocusNode.dispose();
    for (final answer in _answers) {
      answer.labelController.dispose();
      answer.focusNode.dispose();
    }
    super.dispose();
  }

  void _unfocusAll() {
    _questionFocusNode.unfocus();
    for (final answer in _answers) {
      answer.focusNode.unfocus();
    }
  }

  void _addAnswer() {
    if (_answers.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 answer options allowed')),
      );
      return;
    }
    setState(() {
      final newEntry = _AnswerEntry(
        labelController: TextEditingController(),
        focusNode: FocusNode(),
        emoji: commonEmojis[_answers.length % commonEmojis.length],
      );
      newEntry.labelController.addListener(() => setState(() {}));
      _answers.add(newEntry);
    });
  }

  void _removeAnswer(int index) {
    if (_answers.length <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 3 answer options required')),
      );
      return;
    }
    setState(() {
      _answers[index].labelController.dispose();
      _answers[index].focusNode.dispose();
      _answers.removeAt(index);
    });
  }

  void _pickEmoji(int index) async {
    _unfocusAll();
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => _EmojiPickerDialog(
        currentEmoji: _answers[index].emoji,
      ),
    );

    if (emoji != null) {
      setState(() {
        _answers[index] = _AnswerEntry(
          labelController: _answers[index].labelController,
          focusNode: _answers[index].focusNode,
          emoji: emoji,
        );
      });
    }
  }

  Future<void> _save() async {
    _unfocusAll();
    if (!_formKey.currentState!.validate()) return;

    // Validate answers - minimum 3 required
    final validAnswers = _answers
        .where((a) => a.labelController.text.trim().isNotEmpty)
        .toList();

    if (validAnswers.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide at least 3 answer options')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final firestoreService = context.read<FirestoreService>();
      
      final answers = validAnswers
          .map((a) => CustomAnswer(
                label: a.labelController.text.trim(),
                emoji: a.emoji,
              ))
          .toList();

      if (isEditing) {
        final updated = widget.existingQuestion!.copyWith(
          question: _questionController.text.trim(),
          answers: answers,
          updatedAt: DateTime.now(),
        );
        await firestoreService.updateCustomQuestion(user.uid, updated);
      } else {
        final newQuestion = CustomQuestion(
          id: '', // Will be set by Firestore
          question: _questionController.text.trim(),
          answers: answers,
          isEnabled: true,
          createdAt: DateTime.now(),
        );
        await firestoreService.saveCustomQuestion(user.uid, newQuestion);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving question: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _unfocusAll,
      child: Scaffold(
        backgroundColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.close,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isEditing ? 'Edit Question' : 'Add Question',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Save',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This question will appear in your daily check-in flow after the default questions.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDarkMode ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Question field
              Text(
                'Your Question',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _questionController,
                focusNode: _questionFocusNode,
                decoration: InputDecoration(
                  hintText: 'e.g., How are you feeling today?',
                  filled: true,
                  fillColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
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
                    borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
                  ),
                ),
                maxLength: 100,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) {
                  if (_answers.isNotEmpty) {
                    FocusScope.of(context).requestFocus(_answers[0].focusNode);
                  }
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a question';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Answers section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Answer Options',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'Minimum 3 required',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _addAnswer,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Add', style: GoogleFonts.inter()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Answer list
              ...List.generate(_answers.length, (index) {
                return _buildAnswerField(index, isDarkMode);
              }),

              const SizedBox(height: 32),

              // Preview section
              Row(
                children: [
                  Text(
                    'Preview',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'How it will look',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPreview(isDarkMode),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerField(int index, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Emoji picker button
          GestureDetector(
            onTap: () => _pickEmoji(index),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Center(
                child: Text(
                  _answers[index].emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Label text field
          Expanded(
            child: TextFormField(
              controller: _answers[index].labelController,
              focusNode: _answers[index].focusNode,
              decoration: InputDecoration(
                hintText: 'Answer ${index + 1}',
                filled: true,
                fillColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
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
                  borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              maxLength: 30,
              textInputAction: index < _answers.length - 1 ? TextInputAction.next : TextInputAction.done,
              onFieldSubmitted: (_) {
                if (index < _answers.length - 1) {
                  FocusScope.of(context).requestFocus(_answers[index + 1].focusNode);
                } else {
                  _unfocusAll();
                }
              },
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            ),
          ),
          const SizedBox(width: 8),

          // Remove button
          IconButton(
            onPressed: () => _removeAnswer(index),
            icon: Icon(
              Icons.remove_circle_outline,
              color: _answers.length > 3 ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool isDarkMode) {
    final question = _questionController.text.isEmpty
        ? 'Your question will appear here'
        : _questionController.text;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
              ? [AppColors.surfaceDark, AppColors.surfaceDark.withValues(alpha: 0.8)]
              : [Colors.white, Colors.grey.shade50],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Question text - centered like in check-in flow
          Text(
            question,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDarkMode ? Colors.white : Colors.black,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          
          // Answer options - styled like check-in flow
          ..._answers.map((answer) {
            final label = answer.labelController.text.isEmpty
                ? 'Answer'
                : answer.labelController.text;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode 
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(answer.emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDarkMode ? Colors.white38 : Colors.grey.shade400,
                    size: 22,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Internal class to hold answer data during editing
class _AnswerEntry {
  final TextEditingController labelController;
  final FocusNode focusNode;
  final String emoji;

  _AnswerEntry({
    required this.labelController,
    required this.focusNode,
    required this.emoji,
  });
}

/// Dialog for picking an emoji
class _EmojiPickerDialog extends StatelessWidget {
  final String currentEmoji;

  const _EmojiPickerDialog({required this.currentEmoji});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDarkMode ? AppColors.surfaceDark : Colors.white,
      title: Text(
        'Pick an Emoji',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.bold,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      content: SizedBox(
        width: 280,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: commonEmojis.map((emoji) {
            final isSelected = emoji == currentEmoji;
            return GestureDetector(
              onTap: () => Navigator.pop(context, emoji),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryBlue.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: AppColors.primaryBlue, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter()),
        ),
      ],
    );
  }
}
