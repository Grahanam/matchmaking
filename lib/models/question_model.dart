import 'package:cloud_firestore/cloud_firestore.dart';

enum QuestionType {
  scale,
  multipleChoice,
  openText,
  rank,
  multiSelect
}

enum QuestionCategory {
  coreValues,  // Changed from 'values'
  personality,
  interests,
  goals,
  dealbreakers
}

class QuestionModel {
  final String? userId;
  final String id;
  final String text;
  final QuestionType type;
  final QuestionCategory category;
  final List<String>? options;
  final int? scaleMin;
  final int? scaleMax;
  final int weight;  // For AI weighting (1-5)
  final Timestamp createdAt;

  QuestionModel({
    required this.id,
    required this.text,
    required this.type,
    required this.category,
    this.options,
    this.scaleMin,
    this.scaleMax,
    this.weight = 3,  // Default medium importance
    required this.createdAt,
    this.userId,
  });

  // Factory constructor for Firestore documents
  factory QuestionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QuestionModel(
      id: doc.id,
      text: data['text'] ?? '',
      type: QuestionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => QuestionType.multipleChoice,
      ),
      category: QuestionCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => QuestionCategory.coreValues,
      ),
      options: data['options'] != null ? List<String>.from(data['options']) : null,
      scaleMin: data['scaleMin'],
      scaleMax: data['scaleMax'],
      weight: data['weight'] ?? 3,
      createdAt: data['createdAt'] ?? Timestamp.now(),
      userId: data['userId'] as String?,
    );
  }

  // Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'type': type.name,  // Use .name instead of describeEnum()
      'category': category.name,
      if (options != null) 'options': options,
      if (scaleMin != null) 'scaleMin': scaleMin,
      if (scaleMax != null) 'scaleMax': scaleMax,
      'weight': weight,
      'createdAt': createdAt,
      if (userId != null) 'userId': userId,
    };
  }

   QuestionModel copyWith({
      String? id,
      String? text,
      QuestionType? type,
      QuestionCategory? category,
      List<String>? options,
      int? scaleMin,
      int? scaleMax,
      int? weight,
      Timestamp? createdAt,
      String? userId,
    }) {
      return QuestionModel(
        id: id ?? this.id,
        text: text ?? this.text,
        type: type ?? this.type,
        category: category ?? this.category,
        options: options ?? this.options,
        scaleMin: scaleMin ?? this.scaleMin,
        scaleMax: scaleMax ?? this.scaleMax,
        weight: weight ?? this.weight,
        createdAt: createdAt ?? this.createdAt,
        userId: userId ?? this.userId,
      );
    }
}

   

// Example questions with music integration
final sampleQuestions = [
  QuestionModel(
    id: 'q_music_experience',
    text: "Which musical experience resonates most?",
    type: QuestionType.multipleChoice,
    category: QuestionCategory.interests,
    options: [
      "Intimate concert",
      "Festival crowd",
      "Cooking with background tunes",
      "Car karaoke",
      "Silent nature walk"
    ],
    weight: 4,
    createdAt: Timestamp.now(),
  ),
  QuestionModel(
    id: 'q_creative_outlet',
    text: "Your primary creative outlet:",
    type: QuestionType.multipleChoice,
    category: QuestionCategory.interests,
    options: [
      "Music",
      "Writing",
      "Visual arts",
      "Cooking",
      "Fitness",
      "None"
    ],
    createdAt: Timestamp.now(),
  ),
  QuestionModel(  // Fixed to use QuestionModel
    id: 'q_media_importance',
    text: "Importance of shared taste in music/films:",
    type: QuestionType.scale,
    category: QuestionCategory.interests,
    scaleMin: 1,
    scaleMax: 5,
    weight: 2,
    createdAt: Timestamp.now(),
  ),
];