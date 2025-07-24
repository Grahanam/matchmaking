import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackModel {
  final String id;
  final String eventId;
  final String fromUser;
  final String toUser;
  final int rating; // Using int instead of double for whole-heart rating
  final Timestamp createdAt;

  FeedbackModel({
    required this.id,
    required this.eventId,
    required this.fromUser,
    required this.toUser,
    required this.rating,
    required this.createdAt,
  });

  factory FeedbackModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedbackModel(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      fromUser: data['fromUser'] ?? '',
      toUser: data['toUser'] ?? '',
      rating: data['rating'] ?? 0,
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'fromUser': fromUser,
      'toUser': toUser,
      'rating': rating,
      'createdAt': createdAt,
    };
  }
}
