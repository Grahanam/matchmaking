import 'dart:math';
import 'package:app/models/question.dart';
import 'package:app/models/question_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event.dart';
import '../models/eventapplication.dart';
import '../models/chat.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // Get applications for an event
  Stream<List<EventApplication>> getEventApplications(String eventId) {
    return FirebaseFirestore.instance
        .collection('event_applications')
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => EventApplication.fromDocument(doc))
                  .toList(),
        );
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  

  // Apply to event
  Future<void> applyToEvent({
    required String eventId,
    required String userId,
    required Map<String, dynamic> answers,
  }) async {
    final applicationRef =
        FirebaseFirestore.instance.collection('event_applications').doc();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // Create application
      transaction.set(applicationRef, {
        'eventId': eventId,
        'userId': userId,
        'status': 'pending',
        'appliedAt': FieldValue.serverTimestamp(),
        'answers': answers,
      });

      // Update application count in event
      final eventRef = FirebaseFirestore.instance
          .collection('events')
          .doc(eventId);
      transaction.update(eventRef, {
        'applicationCount': FieldValue.increment(1),
      });
    });
  }

  // Check if user has applied
  Future<bool> hasApplied(String eventId, String userId) async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('event_applications')
            .where('eventId', isEqualTo: eventId)
            .where('userId', isEqualTo: userId)
            .limit(1)
            .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<List<Event>> getEventsByCreator(String userId) async {
    final snapshot =
        await _db
            .collection('events')
            .where('createdBy', isEqualTo: userId)
            .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return Event.fromMap(data); // ✅ convert to Event object
    }).toList();
  }

  Future<Map<String, dynamic>> getEventWithApplicants(String eventId) async {
    final doc = await _db.collection('events').doc(eventId).get();
    final event = Event.fromDocumentSnapshot(doc);

    final applicantsSnap =
        await _db
            .collection('events')
            .doc(eventId)
            .collection('applicants')
            .get();
    final applicants = await Future.wait(
      applicantsSnap.docs.map((doc) async {
        final data = doc.data();
        final userSnap =
            await _db.collection('users').doc(data['userId']).get();
        data['userName'] = userSnap['name'] ?? 'Unknown';
        return data;
      }),
    );

    return {'event': event, 'applicants': applicants};
  }

  Future<void> updateApplicantStatus(
    String eventId,
    String userId,
    String newStatus,
  ) async {
    final eventRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId);
    final applicantsRef = eventRef.collection('applicants');

    // Find the applicant doc by userId
    final snap = await applicantsRef.where('userId', isEqualTo: userId).get();
    for (final doc in snap.docs) {
      await doc.reference.update({'status': newStatus});
    }

    // Update status in central event_applications collection
    final appSnap =
        await FirebaseFirestore.instance
            .collection('event_applications')
            .where('eventId', isEqualTo: eventId)
            .where('userId', isEqualTo: userId)
            .get();

    for (final doc in appSnap.docs) {
      await doc.reference.update({'status': newStatus});
    }
  }

  Future<void> checkInUser({
    required String userId,
    required String eventId,
  }) async {
    final applicantDoc =
        await _db
            .collection('events')
            .doc(eventId)
            .collection('applicants')
            .doc(userId)
            .get();

    if (!applicantDoc.exists || applicantDoc.data()?['status'] != 'accepted') {
      throw Exception("You are not accepted for this event.");
    }

    final checkinId = "${eventId}_$userId";
    final checkinRef = _db.collection('checkins').doc(checkinId);

    final existingCheckin = await checkinRef.get();
    if (existingCheckin.exists) {
      throw Exception("You've already checked in.");
    }

    await checkinRef.set({
      'userId': userId,
      'eventId': eventId,
      'checkedInAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> checkInToEvent(String eventId, String userId) async {
    final appSnap =
        await FirebaseFirestore.instance
            .collection('event_applications')
            .where('eventId', isEqualTo: eventId)
            .where('userId', isEqualTo: userId)
            .where('status', isEqualTo: 'accepted')
            .get();

    if (appSnap.docs.isEmpty) throw Exception("Not accepted for this event");

    final checkinRef = FirebaseFirestore.instance
        .collection('checkins')
        .doc('$eventId-$userId');

    await checkinRef.set({
      'userId': userId,
      'eventId': eventId,
      'checkedInAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isProfileComplete(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    return doc.exists &&
        (data?['profileComplete'] == true) &&
        (data?['name'] != null) &&
        (data?['dob'] != null);
  }

  Future<void> completeProfile(
    String uid,
    Map<String, dynamic> profileData,
  ) async {
    await _db.collection('users').doc(uid).update({
      ...profileData,
      'profileComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Event>> getNearbyEvents(
    double? userLat,
    double? userLng, {
    double radiusInKm = 10,
    String? city,
  }) async {
    final now = Timestamp.fromDate(DateTime.now());
    Query query = _db.collection('events').where('endTime', isGreaterThan: now);

    if (city != null && city.isNotEmpty) {
      // Filter by city only
      // query = query.where('city', isEqualTo: city);
      query = query.where('cityKeywords', arrayContains: city.toLowerCase().trim());
      final snapshot = await query.get();
      List<Event> events =
          snapshot.docs.map((doc) => Event.fromDocumentSnapshot(doc)).toList();

      // print("Queried by city: $city");
      // for (var event in events) {
      //   print(event);
      // }
      return events;
    }

    // No city, fetch all and filter by location
    final snapshot = await query.get();
    List<Event> events =
        snapshot.docs.map((doc) => Event.fromDocumentSnapshot(doc)).toList();

    if (userLat != null && userLng != null) {
      events =
          events.where((event) {
            final dist = _calculateDistance(
              userLat,
              userLng,
              event.location.latitude,
              event.location.longitude,
            );
            return dist <= radiusInKm;
          }).toList();
    }

    // print("Queried by location near: ($userLat, $userLng)");
    // for (var event in events) {
    //   print(event);
    // }
    return events;
  }


  double _calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * pi / 180;

  //Get applicant document
  Future<DocumentSnapshot> getApplicantDocument(
    String eventId,
    String userId,
  ) async {
    return await _db
        .collection('events')
        .doc(eventId)
        .collection('applicants')
        .doc(userId)
        .get();
  }

  // Update applicant answers
  Future<void> updateApplicantAnswers(
    String eventId,
    String userId,
    Map<String, dynamic> answers,
  ) async {
    await _db
        .collection('events')
        .doc(eventId)
        .collection('applicants')
        .doc(userId)
        .update({'answers': answers});
  }

  // Get Questions by eventIDs
  Future<List<Question>> getQuestions(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];
    final snapshot =
        await _db
            .collection('questions')
            .where(FieldPath.documentId, whereIn: questionIds)
            .get();

    return snapshot.docs.map((doc) => Question.fromDocument(doc)).toList();
  }

  // 1. Get check-in status
  Future<Map<String, dynamic>> getCheckInStatus({
    required String eventId,
    required String userId,
  }) async {
    try {
      final docRef = _db.collection('checkins').doc('$eventId-$userId');
      final checkinDoc = await docRef.get();
      if (checkinDoc.exists) {
        final data = checkinDoc.data();
        if (data != null && data.containsKey('checkedInAt')) {
          return {
            'isCheckedIn': true,
            'checkInTime': (data['checkedInAt'] as Timestamp).toDate(),
          };
        }
      }
      return {'isCheckedIn': false};
    } catch (e) {
      debugPrint('Error fetching check-in status: $e');
      return {'isCheckedIn': false};
    }
  }

  // 3. Get match document
  Future<DocumentSnapshot> getMatchDocument(
    String eventId,
    String userId,
  ) async {
    return await _db
        .collection('event_matches')
        .doc(eventId)
        .collection('matches')
        .doc(userId)
        .get();
  }

  // 4. Additional helper method needed for BLoC
  Future<DocumentSnapshot> getEventDocument(String eventId) async {
    return await _db.collection('events').doc(eventId).get();
  }

  // Get user document
  Future<DocumentSnapshot> getUserDocument(String userId) async {
    return await _db.collection('users').doc(userId).get();
  }

  // --- CHAT FEATURE ---

  /// Get all chat threads for a user
  Stream<List<Chat>> getUserChats(String userId) {
    return _db
        .collection('chats')
        .where('users', arrayContains: userId)
        .orderBy('lastTimestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Chat.fromDocument(doc)).toList(),
        );
  }

  /// Get or create a chat between two users (sorted by userId)
  Future<String> getOrCreateChat(String userId1, String userId2) async {
    final users = [userId1, userId2]..sort();
    final chatId = users.join('_');
    final chatRef = _db.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();
    if (!chatDoc.exists) {
      await chatRef.set({
        'users': users,
        'lastMessage': '',
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    }
    return chatId;
  }

  /// Send a message in a chat
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final messageRef =
        _db.collection('chats').doc(chatId).collection('messages').doc();
    final now = Timestamp.now();
    await messageRef.set({
      'senderId': senderId,
      'text': text,
      'timestamp': now,
    });
    // Update last message in chat doc
    await _db.collection('chats').doc(chatId).update({
      'lastMessage': text,
      'lastTimestamp': now,
    });
  }

  /// Stream messages in a chat (ordered by timestamp)
  Stream<List<Message>> streamMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false) // Ascending order
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map(
                    (doc) => Message.fromMap(
                      doc.data(),
                      doc.id,
                    ),
                  )
                  .toList(),
        );
  }

  // Future<void> saveQuestion(QuestionModel question) async {
  //   try {
  //     print(question);
  //     final data = question.toFirestore();

  //     // Handle createdAt properly
  //     if (question.id.isEmpty) {
  //       data['createdAt'] = FieldValue.serverTimestamp();
  //     } else {
  //       // Keep existing createdAt when updating
  //       if (!data.containsKey('createdAt')) {
  //         data['createdAt'] = question.createdAt;
  //       }
  //     }

  //     if (question.id.isEmpty) {
  //       DocumentReference docRef = await _db
  //           .collection('questionmodels')
  //           .add(data);
  //       print('Question added with ID: ${docRef.id}');
  //     } else {
  //       await _db.collection('questionmodels').doc(question.id).update(data);
  //       print('Question updated: ${question.id}');
  //     }
  //   } catch (e, stack) {
  //     print('Error saving question: $e');
  //     print(stack);
  //     rethrow;
  //   }
  // }


Future<void> saveQuestion(QuestionModel question) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('User not authenticated');
  
  // For custom questions, set userId
  final questionWithUserId = question.copyWith(userId: user.uid);
  
  if (question.id.isEmpty) {
    await _firestore
        .collection('questionmodels')
        .add(questionWithUserId.toFirestore());
  } else {
    await _firestore
        .collection('questionmodels')
        .doc(question.id)
        .update(questionWithUserId.toFirestore());
  }
}
}
