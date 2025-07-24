// models/group.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Group {
  final String id;
  final String eventId;
  final int round;
  final String name;
  final List<String> members;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.eventId,
    required this.round,
    required this.name,
    required this.members,
    required this.createdAt,
  });

  factory Group.fromDocumentSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Group(
      id: doc.id,
      eventId: data['eventId'],
      round: data['round'],
      name: data['name'],
      members: List<String>.from(data['members']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
