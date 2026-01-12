import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/custom_question_model.dart';
import 'add_custom_question_screen.dart';

/// Screen to manage custom check-in questions
class CustomQuestionsScreen extends StatefulWidget {
  const CustomQuestionsScreen({super.key});

  @override
  State<CustomQuestionsScreen> createState() => _CustomQuestionsScreenState();
}

class _CustomQuestionsScreenState extends State<CustomQuestionsScreen> {
  StreamSubscription<List<CustomQuestion>>? _subscription;
  List<CustomQuestion> _questions = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _subscribeToQuestions();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribeToQuestions() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final firestoreService = context.read<FirestoreService>();
    _subscription = firestoreService.streamCustomQuestions(user.uid).listen(
      (questions) {
        if (mounted) {
          setState(() {
            _questions = questions;
            _isLoading = false;
            _hasError = false;
          });
        }
      },
      onError: (e) {
        debugPrint('Error streaming custom questions: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
      },
    );
  }

  Future<void> _toggleQuestion(CustomQuestion question) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Optimistic update - toggle immediately in UI
    final newEnabled = !question.isEnabled;
    setState(() {
      final index = _questions.indexWhere((q) => q.id == question.id);
      if (index != -1) {
        _questions[index] = question.copyWith(isEnabled: newEnabled);
      }
    });

    try {
      final firestoreService = context.read<FirestoreService>();
      await firestoreService.toggleCustomQuestion(
        user.uid,
        question.id,
        newEnabled,
      );
      // Stream will update the UI automatically
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          final index = _questions.indexWhere((q) => q.id == question.id);
          if (index != -1) {
            _questions[index] = question.copyWith(isEnabled: !newEnabled);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating question: $e')),
        );
      }
    }
  }

  Future<void> _deleteQuestion(CustomQuestion question) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Question?',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently remove this question from your check-in flow.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Optimistic delete
    final deletedQuestion = question;
    final deletedIndex = _questions.indexOf(question);
    setState(() {
      _questions.removeWhere((q) => q.id == question.id);
    });

    try {
      final firestoreService = context.read<FirestoreService>();
      await firestoreService.deleteCustomQuestion(user.uid, question.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question deleted')),
        );
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (deletedIndex >= 0 && deletedIndex <= _questions.length) {
            _questions.insert(deletedIndex, deletedQuestion);
          } else {
            _questions.add(deletedQuestion);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting question: $e')),
        );
      }
    }
  }

  void _addQuestion() async {
    if (_questions.length >= FirestoreService.maxCustomQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum of ${FirestoreService.maxCustomQuestions} custom questions allowed',
          ),
        ),
      );
      return;
    }

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const AddCustomQuestionScreen(),
      ),
    );
    // Stream will automatically update when new question is added
  }

  void _editQuestion(CustomQuestion question) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddCustomQuestionScreen(existingQuestion: question),
      ),
    );
    // Stream will automatically update when question is edited
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Custom Questions',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? _buildErrorState(isDarkMode)
              : _questions.isEmpty
                  ? _buildEmptyState(isDarkMode)
                  : _buildQuestionsList(isDarkMode),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestion,
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add Question',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load questions',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _subscription?.cancel();
                _subscribeToQuestions();
              },
              child: Text('Retry', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.quiz_outlined,
                size: 48,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Custom Questions',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add your own questions to make check-ins more personal. These will appear after the default questions.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionsList(bool isDarkMode) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final question = _questions[index];
        return _buildQuestionCard(question, isDarkMode);
      },
    );
  }

  Widget _buildQuestionCard(CustomQuestion question, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header with toggle
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    question.question,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Switch(
                  value: question.isEnabled,
                  onChanged: (_) => _toggleQuestion(question),
                  activeColor: AppColors.primaryBlue,
                ),
              ],
            ),
          ),
          
          // Answer previews
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: question.answers.map((answer) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${answer.emoji} ${answer.label}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDarkMode ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editQuestion(question),
                  icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.primaryBlue),
                  label: Text(
                    'Edit',
                    style: GoogleFonts.inter(color: AppColors.primaryBlue),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _deleteQuestion(question),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: Text(
                    'Delete',
                    style: GoogleFonts.inter(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
