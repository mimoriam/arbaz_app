import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an answer option for a custom question
class CustomAnswer {
  final String label;
  final String emoji;

  const CustomAnswer({
    required this.label,
    required this.emoji,
  });

  factory CustomAnswer.fromMap(Map<String, dynamic> map) {
    return CustomAnswer(
      label: map['label'] as String? ?? '',
      emoji: map['emoji'] as String? ?? '😊',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'emoji': emoji,
    };
  }

  CustomAnswer copyWith({
    String? label,
    String? emoji,
  }) {
    return CustomAnswer(
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomAnswer &&
        other.label == label &&
        other.emoji == emoji;
  }

  @override
  int get hashCode => label.hashCode ^ emoji.hashCode;
}

/// Represents a custom question created by the senior
class CustomQuestion {
  final String id;
  final String question;
  final List<CustomAnswer> answers;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CustomQuestion({
    required this.id,
    required this.question,
    required this.answers,
    this.isEnabled = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from Firestore document
  factory CustomQuestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    final answersList = (data['answers'] as List? ?? [])
        .map((a) => CustomAnswer.fromMap(a as Map<String, dynamic>))
        .toList();
    
    return CustomQuestion(
      id: doc.id,
      question: data['question'] as String? ?? '',
      answers: answersList,
      isEnabled: data['isEnabled'] as bool? ?? true,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() {
    return {
      'question': question,
      'answers': answers.map((a) => a.toMap()).toList(),
      'isEnabled': isEnabled,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  CustomQuestion copyWith({
    String? id,
    String? question,
    List<CustomAnswer>? answers,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      answers: answers ?? this.answers,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Validates that the question has minimum requirements
  bool get isValid {
    return question.trim().isNotEmpty && 
           answers.length >= 3 &&
           answers.every((a) => a.label.trim().isNotEmpty);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomQuestion && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'CustomQuestion(id: $id, question: $question, answers: ${answers.length}, enabled: $isEnabled)';
  }
}
