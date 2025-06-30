// import 'package:cloud_firestore/cloud_firestore.dart';

// class Question {
//   final String id;
//   final String title;
//   final String type;
//   final DateTime createdAt;
//   final DateTime updatedAt;

//   Question({
//     required this.id,
//     required this.title,
//     required this.type,
//     required this.createdAt,
//     required this.updatedAt,
//   });

//   factory Question.fromDocument(DocumentSnapshot doc) {
//   final data = doc.data() as Map<String, dynamic>;
//   return Question(
//     id: doc.id,
//     title: data['title'] ?? '',
//     type: data['type'] ?? 'text',
//     createdAt: (data['createdAt'] as Timestamp).toDate(),
//     updatedAt: (data['updatedAt'] as Timestamp).toDate(),
//   );
// }

//   factory Question.fromMap(String id, Map<String, dynamic> data) {
//     return Question(
//       id: id,
//       title: data['title'] ?? '',
//       type: data['type'] ?? 'text',
//       createdAt: (data['createdAt'] as Timestamp).toDate(),
//       updatedAt: (data['updatedAt'] as Timestamp).toDate(),
//     );
//   }

//   Map<String, dynamic> toMap() {
//     return {
//       'title': title,
//       'type': type,
//       'createdAt': createdAt,
//       'updatedAt': updatedAt,
//     };
//   }
// }


import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String id;
  final String title;
  final String type; // 'range', 'mcq', 'spotify_track', etc.
  final List<String>? options; // for mcq
  final int? min; // for range
  final int? max; // for range
  final String? musicType; // 'track', 'artist', 'genre' (if music-based)
  final String eventType; // 'dating', 'friendship', or 'both'
  final DateTime createdAt;
  final DateTime updatedAt;

  Question({
    required this.id,
    required this.title,
    required this.type,
    this.options,
    this.min,
    this.max,
    this.musicType,
    required this.eventType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Question.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Question(
      id: doc.id,
      title: data['title'] ?? '',
      type: data['type'] ?? 'text',
      options: (data['options'] as List?)?.map((e) => e.toString()).toList(),
      min: data['min'],
      max: data['max'],
      musicType: data['musicType'],
      eventType: data['eventType'] ?? 'both',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  factory Question.fromMap(String id, Map<String, dynamic> data) {
    return Question(
      id: id,
      title: data['title'] ?? '',
      type: data['type'] ?? 'text',
      options: (data['options'] as List?)?.map((e) => e.toString()).toList(),
      min: data['min'],
      max: data['max'],
      musicType: data['musicType'],
      eventType: data['eventType'] ?? 'both',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      if (options != null) 'options': options,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (musicType != null) 'musicType': musicType,
      'eventType': eventType,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
