import 'package:cloud_firestore/cloud_firestore.dart';

class EventApplication {
  final String id;
  final String eventId;
  final String userId;
  final String status;
  final DateTime appliedAt;
  final Map<String, dynamic>? answers;

  EventApplication({
    required this.id,
    required this.eventId,
    required this.userId,
    this.status = 'pending',
    required this.appliedAt,
    this.answers,
  });

  factory EventApplication.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventApplication(
      id: doc.id,
      eventId: data['eventId'],
      userId: data['userId'],
      status: data['status'] ?? 'pending',
      appliedAt: (data['appliedAt'] as Timestamp).toDate(),
      answers: data['answers'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'userId': userId,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'answers': answers,
    };
  }
}