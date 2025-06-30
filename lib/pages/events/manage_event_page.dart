import 'dart:async';
import 'dart:convert';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/models/event.dart';
import 'package:app/models/group.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'mock_data.dart';
import 'package:google_fonts/google_fonts.dart';

class ManageEventPage extends StatefulWidget {
  final String eventId;
  const ManageEventPage({super.key, required this.eventId});

  @override
  State<ManageEventPage> createState() => _ManageEventPageState();
}

class _ManageEventPageState extends State<ManageEventPage> {
  bool _isMatching = false;
  bool _useMockData = false;
  final ScrollController _scrollController = ScrollController();
  int _completedCount = 0;
  int _totalCheckins = 0;
  StreamSubscription? _applicantSubscription;
  StreamSubscription? _checkinSubscription;

  // Section visibility states
  bool _showCheckinsList = false;
  bool _showMatchesList = false;
  bool _showApplicantsList = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<EventBloc>().add(FetchEventWithApplicants(widget.eventId));
      _setupApplicantListener();
      _setupCheckInListener();
    });
  }

  void _setupCheckInListener() {
    _checkinSubscription = FirebaseFirestore.instance
        .collection('checkins')
        .where('eventId', isEqualTo: widget.eventId)
        .snapshots()
        .listen((_) => _updateQuestionnaireCount());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _applicantSubscription?.cancel();
    _checkinSubscription?.cancel();
    super.dispose();
  }

  void _setupApplicantListener() {
    final eventId = widget.eventId;

    // Listen for applicant updates to automatically refresh questionnaire count
    _applicantSubscription = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('applicants')
        .snapshots()
        .listen((snapshot) {
          _updateQuestionnaireCount();
        });
  }

  Future<void> _createGroups(Event event, {required bool useFeedback}) async {
  try {
    // 1. Get all checked-in users
    final checkins = await FirebaseFirestore.instance
        .collection('checkins')
        .where('eventId', isEqualTo: event.id)
        .get();
    
    final userIds = checkins.docs.map((d) => d['userId'] as String).toList();
    
    // 2. Determine group size (4-6 people per group)
    final groupSize = userIds.length > 20 ? 6 : 4;
    final groupCount = (userIds.length / groupSize).ceil();
    
    // 3. Get next round number
    final lastRound = await _getLastRoundNumber(event.id);
    final round = lastRound + 1;
    
    // 4. Create groups
    final groups = useFeedback
        ? await _createGroupsFromFeedback(event, userIds, groupCount, round)
        : await _createGroupsFromQuestionnaire(event, userIds, groupCount, round);
    
    // 5. Save to Firestore
    final batch = FirebaseFirestore.instance.batch();
    for (final group in groups) {
      final docRef = FirebaseFirestore.instance.collection('groups').doc();
      batch.set(docRef, {
        'eventId': event.id,
        'round': round,
        'name': group['name'],
        'members': group['members'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Created ${groups.length} groups for round $round")),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error creating groups: ${e.toString()}")),
    );
  }
}

String _createAnswerSignature(Map<String, dynamic> answers) {
  // Create a compact signature based on answers
  final keys = answers.keys.toList()..sort();
  final signature = StringBuffer();
  
  for (final key in keys) {
    final value = answers[key];
    if (value is String) {
      signature.write('${key.substring(0, 3)}:${value.substring(0, 15)}|');
    } else if (value != null) {
      signature.write('${key.substring(0, 3)}:${value.toString().substring(0, 15)}|');
    }
  }
  
  return signature.toString();
}

Future<int> _getLastRoundNumber(String eventId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('groups')
      .where('eventId', isEqualTo: eventId)
      .orderBy('round', descending: true)
      .limit(1)
      .get();
      
  return snapshot.docs.isNotEmpty 
      ? (snapshot.docs.first.data()['round'] as int)
      : 0;
}

Future<List<Map<String, dynamic>>> _createGroupsFromQuestionnaire(
  Event event,
  List<String> userIds,
  int groupCount,
  int round,
) async {
  try {
    // 1. Fetch all questionnaire answers
    final Map<String, Map<String, dynamic>> userAnswers = {};
    final List<Future> futures = [];
    
    for (final userId in userIds) {
      futures.add(
        FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .collection('applicants')
          .doc(userId)
          .get()
          .then((doc) {
            if (doc.exists) {
              final data = doc.data() as Map<String, dynamic>;
              userAnswers[userId] = data['answers'] as Map<String, dynamic>? ?? {};
            }
          }),
      );
    }
    
    await Future.wait(futures);

    // 2. Create answer signatures
    final Map<String, List<String>> signatureGroups = {};
    
    for (final userId in userIds) {
      final answers = userAnswers[userId] ?? {};
      final signature = _createAnswerSignature(answers);
      signatureGroups.putIfAbsent(signature, () => []).add(userId);
    }

    // 3. Form groups based on similar signatures
    final groups = <Map<String, dynamic>>[];
    int groupIndex = 1;
    
    // Process large clusters first
    final sortedSignatures = signatureGroups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    
    for (final entry in sortedSignatures) {
      final members = entry.value;
      
      // Split large clusters into multiple groups
      while (members.length > groupCount) {
        final groupMembers = members.sublist(0, groupCount);
        groups.add({
          'name': 'Group ${groupIndex++}',
          'members': groupMembers,
        });
        members.removeRange(0, groupCount);
      }
      
      // Add remaining members to existing groups
      for (final member in members) {
        if (groups.isEmpty || groups.last['members'].length >= groupCount) {
          groups.add({
            'name': 'Group ${groupIndex++}',
            'members': [member],
          });
        } else {
          groups.last['members'].add(member);
        }
      }
    }

    return groups;
  } catch (e) {
    debugPrint('Error creating groups from questionnaire: $e');
    return [];
  }
}

Future<List<Map<String, dynamic>>> _createGroupsFromFeedback(
  Event event,
  List<String> userIds,
  int groupCount,
  int round,
) async {
  try {
    // 1. Fetch all feedback from previous groups
    final Map<String, Map<String, double>> userRatings = {};
    final List<Future> futures = [];
    
    for (final userId in userIds) {
      futures.add(
        FirebaseFirestore.instance
          .collection('feedback')
          .where('eventId', isEqualTo: event.id)
          .where('fromUser', isEqualTo: userId)
          .get()
          .then((snapshot) {
            final ratings = <String, double>{};
            for (final doc in snapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final toUser = data['toUser'] as String? ?? '';
              final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
              if (toUser.isNotEmpty) {
                ratings[toUser] = rating;
              }
            }
            userRatings[userId] = ratings;
          }),
      );
    }
    
    await Future.wait(futures);

    // 2. Create compatibility matrix
    final Map<String, Map<String, double>> compatibilityMatrix = {};
    for (final userA in userIds) {
      final ratings = <String, double>{};
      for (final userB in userIds) {
        if (userA == userB) continue;
        
        // Calculate mutual compatibility score
        final ratingAB = userRatings[userA]?[userB] ?? 0.0;
        final ratingBA = userRatings[userB]?[userA] ?? 0.0;
        final compatibility = (ratingAB + ratingBA) / 2;
        
        ratings[userB] = compatibility;
      }
      compatibilityMatrix[userA] = ratings;
    }

    // 3. Form groups using greedy algorithm
    final groups = <Map<String, dynamic>>[];
    final availableUsers = userIds.toList();
    int groupIndex = 1;
    
    while (availableUsers.isNotEmpty) {
      final groupMembers = <String>[];
      
      // Start with most isolated user
      String currentUser = _findMostIsolatedUser(availableUsers, compatibilityMatrix);
      groupMembers.add(currentUser);
      availableUsers.remove(currentUser);
      
      // Add most compatible users
      while (groupMembers.length < groupCount && availableUsers.isNotEmpty) {
        final nextUser = _findMostCompatibleUser(
          currentUser, 
          availableUsers, 
          compatibilityMatrix,
          groupMembers
        );
        
        if (nextUser != null) {
          groupMembers.add(nextUser);
          availableUsers.remove(nextUser);
          currentUser = nextUser;
        } else {
          break;
        }
      }
      
      groups.add({
        'name': 'Feedback Group ${groupIndex++}',
        'members': groupMembers,
      });
    }

    return groups;
  } catch (e) {
    debugPrint('Error creating groups from feedback: $e');
    return [];
  }
}

String _findMostIsolatedUser(
  List<String> users,
  Map<String, Map<String, double>> compatibilityMatrix
) {
  String mostIsolated = users.first;
  double minScore = double.infinity;
  
  for (final user in users) {
    final ratings = compatibilityMatrix[user] ?? {};
    final totalScore = ratings.values.fold(0.0, (sum, rating) => sum + rating);
    
    if (totalScore < minScore) {
      minScore = totalScore;
      mostIsolated = user;
    }
  }
  
  return mostIsolated;
}

String? _findMostCompatibleUser(
  String currentUser,
  List<String> availableUsers,
  Map<String, Map<String, double>> compatibilityMatrix,
  List<String> existingMembers
) {
  String? mostCompatible;
  double maxScore = -1;
  
  final currentRatings = compatibilityMatrix[currentUser] ?? {};
  
  for (final candidate in availableUsers) {
    // Skip if already in group
    if (existingMembers.contains(candidate)) continue;
    
    // Calculate compatibility score
    final candidateRating = currentRatings[candidate] ?? 0.0;
    
    // Check compatibility with existing group members
    double groupCompatibility = 0.0;
    for (final member in existingMembers) {
      final memberRatings = compatibilityMatrix[member] ?? {};
      groupCompatibility += memberRatings[candidate] ?? 0.0;
    }
    
    final totalScore = candidateRating + groupCompatibility;
    
    if (totalScore > maxScore) {
      maxScore = totalScore;
      mostCompatible = candidate;
    }
  }
  
  return mostCompatible;
}

  Future<void> _updateQuestionnaireCount() async {
    final eventId = widget.eventId;

    try {
      // Get all checkins
      final checkinsSnap =
          await FirebaseFirestore.instance
              .collection('checkins')
              .where('eventId', isEqualTo: eventId)
              .get();

      final checkedInUserIds =
          checkinsSnap.docs.map((d) => d['userId'] as String).toList();

      _totalCheckins = checkedInUserIds.length;
      int completedCount = 0;

      // Check each applicant's answer status
      if (checkedInUserIds.isNotEmpty) {
        final applicantsSnap =
            await FirebaseFirestore.instance
                .collection('events')
                .doc(eventId)
                .collection('applicants')
                .where(FieldPath.documentId, whereIn: checkedInUserIds)
                .get();

        final eventSnap =
            await FirebaseFirestore.instance
                .collection('events')
                .doc(eventId)
                .get();
        final event = Event.fromDocumentSnapshot(eventSnap);
        final questionCount = event.questionnaire.length;

  
        for (var doc in applicantsSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final answers = data['answers'] as Map<String, dynamic>? ?? {};
          bool hasAllAnswers = true;
          for (var qId in event.questionnaire) {
            if (!answers.containsKey(qId)) {
              hasAllAnswers = false;
              break;
            }
          }
          if (hasAllAnswers) {
            completedCount++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _completedCount = completedCount;
        });
      }
    } catch (e) {
      debugPrint('Error updating questionnaire count: $e');
    }
  }

  // Configuration - IMPORTANT: Move these to environment variables
  static const String _aiApiToken = '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';
  static const String _aiApiEndpoint =
      'https://models.github.ai/inference/chat/completions';

  /// Calls the AI API for matchmaking
  Future<List<Map<String, dynamic>>> _aiMatchmaking(
    List<Map<String, dynamic>> users,
  ) async {
    try {
      // Prepare the prompt with clearer instructions
      final prompt = '''
You are an event matchmaking assistant. Given the following list of users and their answers, 
create pairs for networking. Return ONLY a valid JSON array of match objects.

Rules:
1. Each match object must have: 
   - "userId" (string)
   - "matchedWith" (string - another userId)
   - "released" (boolean - always false)
   - "reason" (string - a SHORT, INTERESTING explanation based on their answers, max 15 words)
2. Make reasons FUN and ENGAGING. Focus on:
   - Shared interests or values
   - Complementary personality traits
   - Interesting similarities or differences
   - Potential conversation starters
3. Return ALL users in the matches
4. If there's an odd number, include one unmatched user with "matchedWith": ""
5. Format MUST be: [{"userId": "id1", "matchedWith": "id2", "released": false, "reason": "..."}, ...]

User data: ${jsonEncode(users)}
''';

      // Make the API request
      final response = await http.post(
        Uri.parse(_aiApiEndpoint),
        headers: {
          'Authorization': 'Bearer $_aiApiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.github+json',
        },
        body: jsonEncode({
          "model": "openai/gpt-4.1",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are a helpful event matchmaking assistant. Return ONLY valid JSON arrays.",
            },
            {"role": "user", "content": prompt},
          ],
          "max_tokens": 1000,
          "temperature": 0.3,
          "response_format": {"type": "json_object"},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        debugPrint('Raw AI Response: $content');

        // Extract JSON from the response
        String jsonString = content.trim();

        // Handle code block formatting if present
        if (jsonString.startsWith('```json')) {
          jsonString = jsonString.substring(7, jsonString.length - 3).trim();
        } else if (jsonString.startsWith('```')) {
          jsonString = jsonString.substring(3, jsonString.length - 3).trim();
        }

        // Parse the JSON
        final parsedResponse = json.decode(jsonString);

        // Handle different response structures
        List<dynamic> matches;
        if (parsedResponse is List) {
          // Direct array response
          matches = parsedResponse;
        } else if (parsedResponse is Map &&
            parsedResponse.containsKey('matches')) {
          // Response with "matches" key
          matches = parsedResponse['matches'] as List<dynamic>;
        } else {
          throw FormatException("Unrecognized response format: $jsonString");
        }

        return matches.cast<Map<String, dynamic>>();
      } else {
        throw Exception(
          "AI matchmaking failed: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      debugPrint('AI Response Parsing Error: $e');
      rethrow;
    }
  }

  Future<void> _runMatchingAI(Event event) async {
    setState(() => _isMatching = true);
    try {
      // Delete existing matches before generating new ones
      try {
        final matchesCollection = FirebaseFirestore.instance
            .collection('event_matches')
            .doc(event.id)
            .collection('matches');

        final existingMatches = await matchesCollection.get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in existingMatches.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint(
          "♻️ Deleted ${existingMatches.docs.length} previous matches",
        );
      } catch (e) {
        debugPrint("Error deleting previous matches: $e");
      }

      final List<Map<String, dynamic>> dataToMatch;

      if (_useMockData) {
        // Use mock data for testing
        dataToMatch = mockUsers;
        debugPrint("✅ Using mock data with ${mockUsers.length} users");
      } else {
        // Fetch real data from Firestore

        final questionsSnapshot =
            await FirebaseFirestore.instance
                .collection('questions')
                .where(FieldPath.documentId, whereIn: event.questionnaire)
                .get();

        final questionMap = <String, String>{};
        for (var doc in questionsSnapshot.docs) {
          questionMap[doc.id] = doc['title'] as String? ?? 'Unknown question';
        }
        final checkinsSnap =
            await FirebaseFirestore.instance
                .collection('checkins')
                .where('eventId', isEqualTo: event.id)
                .get();

        final checkedInUserIds =
            checkinsSnap.docs.map((d) => d['userId'] as String).toList();

        final applicantsSnap =
            await FirebaseFirestore.instance
                .collection('events')
                .doc(event.id)
                .collection('applicants')
                .where('userId', whereIn: checkedInUserIds)
                .get();

        dataToMatch = [];

        // for (var doc in applicantsSnap.docs) {
        //   final data = doc.data() as Map<String, dynamic>;
        //   final userSnap =
        //       await FirebaseFirestore.instance
        //           .collection('users')
        //           .doc(data['userId'] as String)
        //           .get();
        //   final userData = userSnap.data() as Map<String, dynamic>? ?? {};
        //   dataToMatch.add({
        //     'userId': data['userId'] as String,
        //     'name': userData['name'] as String? ?? 'Unknown',
        //     'answers': data['answers'] as Map<String, dynamic>? ?? {},
        //   });
        for (var doc in applicantsSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final answers = data['answers'] as Map<String, dynamic>? ?? {};
          final userSnap =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(data['userId'] as String)
                  .get();
          final userData = userSnap.data() as Map<String, dynamic>? ?? {};

          // Convert question IDs to question texts
          final readableAnswers = <String, dynamic>{};
          answers.forEach((key, value) {
            final questionText = questionMap[key] ?? key;
            readableAnswers[questionText] = value;
          });

          dataToMatch.add({
            'userId': data['userId'] as String,
            'name': userData['name'] as String? ?? 'Unknown',
            'answers': readableAnswers, // Use transformed answers
          });
        }
      }

      // Run AI matching
      final matches = await _aiMatchmaking(dataToMatch);
      debugPrint('Generated Matches: ${matches.length}');

      // Save matches to Firestore
      final batch = FirebaseFirestore.instance.batch();
      for (var match in matches) {
        final userId = match['userId'] as String?;
        final matchedWith = match['matchedWith'] as String?;
        final reason = match['reason'] as String? ?? 'Compatible interests';

        if (userId == null ||
            matchedWith == null ||
            userId.isEmpty ||
            matchedWith.isEmpty) {
          debugPrint('⚠️ Invalid match entry: $match');
          continue;
        }

        // Create document for user A → user B
        final matchRefA = FirebaseFirestore.instance
            .collection('event_matches')
            .doc(event.id)
            .collection('matches')
            .doc(userId);

        batch.set(matchRefA, {
          'userId': userId,
          'matchedWith': matchedWith,
          'reason': reason,
          'released': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Create reciprocal document for user B → user A
        final matchRefB = FirebaseFirestore.instance
            .collection('event_matches')
            .doc(event.id)
            .collection('matches')
            .doc(matchedWith);

        batch.set(matchRefB, {
          'userId': matchedWith,
          'matchedWith': userId,
          'reason': reason,
          'released': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Matches generated: ${matches.length}")),
        );
      }
    } catch (e, stack) {
      debugPrint('AI matchmaking error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isMatching = false);
      }
    }
  }

  // Add this function to release matches to users
  // Updated _releaseMatches function
  Future<void> _releaseMatches(Event event) async {
    try {
      // Update all matches to released status
      final matchesCollection = FirebaseFirestore.instance
          .collection('event_matches')
          .doc(event.id)
          .collection('matches');

      final matchesSnapshot = await matchesCollection.get();
      final batch = FirebaseFirestore.instance.batch();

      for (var doc in matchesSnapshot.docs) {
        batch.update(doc.reference, {'released': true});
      }

      await batch.commit();

      // Update event status
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({'matchesReleased': true});

      for (var doc in matchesSnapshot.docs) {
        batch.update(doc.reference, {'released': true});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Matches released to attendees!")),
        );
      }
    } catch (e) {
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(content: Text('Failed to release matches: $e')),
      //   );
      // }
    }
  }

  Widget _buildEventHeader(Event event) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isEventLive =
        now.isAfter(event.startTime) && now.isBefore(event.endTime);
    final isEventPast = now.isAfter(event.endTime);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    event.title,
                    style: GoogleFonts.raleway(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isEventLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Live Now",
                      style: GoogleFonts.raleway(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  )
                else if (isEventPast)
                  Text(
                    "Completed",
                    style: GoogleFonts.raleway(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              event.description,
              style: GoogleFonts.raleway(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildDetailChip(
                  icon: Icons.group,
                  value: event.guestCount.toString(),
                  label: "Guests",
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                _buildDetailChip(
                  icon: Icons.location_on,
                  value: event.locationType.capitalize(),
                  label: "Location",
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEE, MMM d yyyy').format(event.startTime),
                  style: GoogleFonts.raleway(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('h:mm a').format(event.startTime)} - ${DateFormat('h:mm a').format(event.endTime)}',
                  style: GoogleFonts.raleway(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.raleway(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.raleway(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinsSection(QuerySnapshot snapshot, Event event) {
    final colorScheme = Theme.of(context).colorScheme;
    final checkins = snapshot.docs;
    _totalCheckins = checkins.length;
    final completionPercent =
        _totalCheckins == 0 ? 0.0 : _completedCount / _totalCheckins;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Check-ins",
                  style: GoogleFonts.raleway(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$_totalCheckins Checked-in",
                    style: GoogleFonts.raleway(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Questionnaire completion - ALWAYS VISIBLE
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Questionnaire Completion",
                  style: GoogleFonts.raleway(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: completionPercent,
                  backgroundColor: Colors.grey.shade300,
                  color: completionPercent > 0.7 ? Colors.green : Colors.orange,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 8),
                Text(
                  "$_completedCount / $_totalCheckins completed all questions",
                  style: GoogleFonts.raleway(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Checked-in users dropdown
            ExpansionTile(
              title: Text(
                "Checked-in Users",
                style: GoogleFonts.raleway(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              initiallyExpanded: _showCheckinsList,
              onExpansionChanged: (expanded) {
                setState(() => _showCheckinsList = expanded);
              },
              children: [
                ...checkins
                    .map((doc) => _buildCheckinItem(doc, event))
                    .toList(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckinItem(QueryDocumentSnapshot doc, Event event) {
    final data = doc.data() as Map<String, dynamic>;
    final userId = data['userId'];
    final checkedInAt = data['checkedInAt'] as Timestamp?;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Loading...'),
          );
        }

        if (!userSnapshot.hasData) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.person),
            ),
            title: Text('User not found'),
            subtitle: Text('ID: $userId'),
          );
        }

        final userDoc = userSnapshot.data!;
        if (!userDoc.exists) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.person),
            ),
            title: Text('User not found'),
            subtitle: Text('ID: $userId'),
          );
        }

        final userData = userDoc.data() as Map<String, dynamic>?;
        final name = userData?['name'] as String? ?? 'Unknown user';
        final photoUrl = userData?['photoUrl'] as String?;

        return ListTile(
          leading:
              photoUrl != null
                  ? CircleAvatar(backgroundImage: NetworkImage(photoUrl))
                  : CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(name[0]),
                  ),
          title: Text(name),
          subtitle: Text(
            checkedInAt != null
                ? 'Checked in: ${DateFormat('MMM d, h:mm a').format(checkedInAt.toDate())}'
                : 'Checked in: Unknown time',
          ),
        );
      },
    );
  }

  Widget _buildMatchesSection(String eventId) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Generated Matches",
              style: GoogleFonts.raleway(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            // Matches dropdown
            ExpansionTile(
              title: Text(
                "View Matches",
                style: GoogleFonts.raleway(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              initiallyExpanded: _showMatchesList,
              onExpansionChanged: (expanded) {
                setState(() => _showMatchesList = expanded);
              },
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('event_matches')
                          .doc(eventId)
                          .collection('matches')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            "No matches generated yet",
                            style: GoogleFonts.raleway(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    final matches = snapshot.data!.docs;

                    // Create a map to avoid duplicate pairs
                    final uniquePairs = <String, DocumentSnapshot>{};

                    for (var matchDoc in matches) {
                      final data = matchDoc.data() as Map<String, dynamic>;
                      final userId = data['userId'] as String? ?? '';
                      final matchedWith = data['matchedWith'] as String? ?? '';

                      if (userId.isNotEmpty && matchedWith.isNotEmpty) {
                        // Create a unique key for the pair (sorted to avoid duplicates)
                        final key = [userId, matchedWith]..sort();
                        uniquePairs[key.join('-')] = matchDoc;
                      }
                    }

                    return Column(
                      children:
                          uniquePairs.values.map((matchDoc) {
                            final data =
                                matchDoc.data() as Map<String, dynamic>;
                            final userId = data['userId'] as String? ?? '';
                            final matchedWith =
                                data['matchedWith'] as String? ?? '';
                            final reason =
                                data['reason'] as String? ??
                                'Compatible interests';
                            final createdAt = data['createdAt'] as Timestamp?;

                            return FutureBuilder(
                              future: Future.wait([
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(userId)
                                    .get(),
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(matchedWith)
                                    .get(),
                              ]),
                              builder: (context, userSnapshots) {
                                if (userSnapshots.connectionState ==
                                    ConnectionState.waiting) {
                                  return const ListTile(
                                    leading: CircularProgressIndicator(),
                                    title: Text('Loading match...'),
                                  );
                                }

                                final userDocs =
                                    userSnapshots.data
                                        as List<DocumentSnapshot>? ??
                                    [];
                                String user1Name = 'Unknown';
                                String user2Name = 'Unknown';

                                if (userDocs.isNotEmpty && userDocs[0].exists) {
                                  final data1 =
                                      userDocs[0].data()
                                          as Map<String, dynamic>?;
                                  user1Name =
                                      data1?['name'] as String? ?? 'Unknown';
                                }
                                if (userDocs.length > 1 && userDocs[1].exists) {
                                  final data2 =
                                      userDocs[1].data()
                                          as Map<String, dynamic>?;
                                  user2Name =
                                      data2?['name'] as String? ?? 'Unknown';
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.people,
                                      color: Colors.pink,
                                    ),
                                    title: Text(
                                      "$user1Name & $user2Name",
                                      style: GoogleFonts.raleway(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (createdAt != null)
                                          Text(
                                            "Matched: ${DateFormat('MMM d, h:mm a').format(createdAt.toDate())}",
                                            style: GoogleFonts.raleway(
                                              fontSize: 12,
                                            ),
                                          ),
                                        Text(
                                          "Reason: $reason",
                                          style: GoogleFonts.raleway(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            );
                          }).toList(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupManagementSection(Event event) {
  final colorScheme = Theme.of(context).colorScheme;
  return Card(
    elevation: 3,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Group Management",
            style: GoogleFonts.raleway(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          
          // Group creation buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.group_add),
                  label: const Text("Create Groups (Questionnaire)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _createGroups(event, useFeedback: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.feedback),
                  label: const Text("Regroup (Feedback)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _createGroups(event, useFeedback: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Groups list
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('groups')
                .where('eventId', isEqualTo: event.id)
                .orderBy('round', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              
              final groups = snapshot.data!.docs
                  .map((doc) => Group.fromDocumentSnapshot(doc))
                  .toList();
                  
              return Column(
                children: groups.map((group) => _buildGroupItem(group)).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

Widget _buildGroupItem(Group group) {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      title: Text(
        "Round ${group.round}: ${group.name}",
        style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
      ),
      subtitle: Text("${group.members.length} members"),
      children: [
        ...group.members.map((userId) => FutureBuilder(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const ListTile(title: Text('Loading...'));
            final user = snapshot.data!.data() as Map<String, dynamic>?;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user?['photoUrl'] != null 
                  ? NetworkImage(user!['photoUrl'])
                  : null,
                child: user?['photoUrl'] == null 
                  ? Text(user?['name']?[0] ?? '?')
                  : null,
              ),
              title: Text(user?['name'] ?? 'Unknown User'),
            );
          },
        )).toList(),
      ],
    ),
  );
}

  // Widget _buildApplicantsSection(
  //   List<Map<String, dynamic>> applicants,
  //   Event event,
  // ) {
  //   final colorScheme = Theme.of(context).colorScheme;

  //   return Card(
  //     elevation: 3,
  //     margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //     color: colorScheme.surfaceContainer,
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //             children: [
  //               Text(
  //                 "Applicants",
  //                 style: GoogleFonts.raleway(
  //                   fontSize: 18,
  //                   fontWeight: FontWeight.bold,
  //                   color: colorScheme.onSurface,
  //                 ),
  //               ),
  //               Text(
  //                 "${applicants.length} Applicants",
  //                 style: GoogleFonts.raleway(
  //                   fontWeight: FontWeight.w600,
  //                   color: colorScheme.onSurfaceVariant,
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 16),

  //           // Applicants dropdown
  //           ExpansionTile(
  //             title: Text(
  //               "View Applicants",
  //               style: GoogleFonts.raleway(
  //                 fontWeight: FontWeight.w600,
  //                 color: colorScheme.onSurfaceVariant,
  //               ),
  //             ),
  //             initiallyExpanded: _showApplicantsList,
  //             onExpansionChanged: (expanded) {
  //               setState(() => _showApplicantsList = expanded);
  //             },
  //             children: [
  //               applicants.isEmpty
  //                   ? Center(
  //                     child: Padding(
  //                       padding: const EdgeInsets.symmetric(vertical: 16),
  //                       child: Text(
  //                         "No one has applied yet",
  //                         style: GoogleFonts.raleway(
  //                           color: colorScheme.onSurfaceVariant,
  //                         ),
  //                       ),
  //                     ),
  //                   )
  //                   : Column(
  //                     children:
  //                         applicants.map((data) {
  //                           String status = data['status'] ?? 'pending';
  //                           Color statusColor;
  //                           switch (status) {
  //                             case 'accepted':
  //                               statusColor = Colors.green;
  //                               break;
  //                             case 'rejected':
  //                               statusColor = Colors.red;
  //                               break;
  //                             default:
  //                               statusColor = Colors.orange;
  //                           }

  //                           return FutureBuilder<DocumentSnapshot>(
  //                             future:
  //                                 FirebaseFirestore.instance
  //                                     .collection('users')
  //                                     .doc(data['userId'])
  //                                     .get(),
  //                             builder: (context, userSnapshot) {
  //                               if (userSnapshot.connectionState ==
  //                                   ConnectionState.waiting) {
  //                                 return const ListTile(
  //                                   leading: CircularProgressIndicator(),
  //                                   title: Text('Loading...'),
  //                                 );
  //                               }

  //                               if (!userSnapshot.hasData) {
  //                                 return const SizedBox.shrink();
  //                               }

  //                               final userDoc = userSnapshot.data!;
  //                               if (!userDoc.exists) {
  //                                 return ListTile(
  //                                   leading: CircleAvatar(
  //                                     backgroundColor:
  //                                         colorScheme.primaryContainer,
  //                                     child: const Icon(Icons.person),
  //                                   ),
  //                                   title: Text('User not found'),
  //                                   subtitle: Text('ID: ${data['userId']}'),
  //                                 );
  //                               }

  //                               final userData =
  //                                   userDoc.data() as Map<String, dynamic>?;
  //                               final name =
  //                                   userData?['name'] as String? ?? 'Unknown';
  //                               final photoUrl =
  //                                   userData?['photoUrl'] as String?;

  //                               return Card(
  //                                 margin: const EdgeInsets.only(bottom: 12),
  //                                 elevation: 1,
  //                                 shape: RoundedRectangleBorder(
  //                                   borderRadius: BorderRadius.circular(12),
  //                                 ),
  //                                 child: ListTile(
  //                                   leading:
  //                                       photoUrl != null
  //                                           ? CircleAvatar(
  //                                             backgroundImage: NetworkImage(
  //                                               photoUrl,
  //                                             ),
  //                                           )
  //                                           : CircleAvatar(
  //                                             backgroundColor:
  //                                                 colorScheme.primaryContainer,
  //                                             child: Text(name[0]),
  //                                           ),
  //                                   title: Text(name),
  //                                   subtitle: Text(
  //                                     "Status: ${status.toUpperCase()}",
  //                                   ),
  //                                   trailing: Container(
  //                                     padding: const EdgeInsets.symmetric(
  //                                       horizontal: 12,
  //                                       vertical: 6,
  //                                     ),
  //                                     decoration: BoxDecoration(
  //                                       color: statusColor.withOpacity(0.2),
  //                                       borderRadius: BorderRadius.circular(20),
  //                                     ),
  //                                     child: DropdownButton<String>(
  //                                       value: status,
  //                                       underline: const SizedBox(),
  //                                       icon: const Icon(Icons.arrow_drop_down),
  //                                       style: GoogleFonts.raleway(
  //                                         color: statusColor,
  //                                         fontWeight: FontWeight.bold,
  //                                       ),
  //                                       items: const [
  //                                         DropdownMenuItem(
  //                                           value: 'pending',
  //                                           child: Text('PENDING'),
  //                                         ),
  //                                         DropdownMenuItem(
  //                                           value: 'accepted',
  //                                           child: Text('ACCEPTED'),
  //                                         ),
  //                                         DropdownMenuItem(
  //                                           value: 'rejected',
  //                                           child: Text('REJECTED'),
  //                                         ),
  //                                       ],
  //                                       onChanged: (newStatus) {
  //                                         if (newStatus != null) {
  //                                           context.read<EventBloc>().add(
  //                                             UpdateApplicantStatus(
  //                                               eventId: widget.eventId,
  //                                               userId: data['userId'],
  //                                               newStatus: newStatus,
  //                                             ),
  //                                           );
  //                                         }
  //                                       },
  //                                     ),
  //                                   ),
  //                                 ),
  //                               );
  //                             },
  //                           );
  //                         }).toList(),
  //                   ),
  //             ],
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

//   Widget _buildApplicantsSection(String eventId) {
//   final colorScheme = Theme.of(context).colorScheme;
//   return Card(
//     elevation: 3,
//     margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//     color: colorScheme.surfaceContainer,
//     child: Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Dropdown header row
//           GestureDetector(
//             onTap: () {
//               setState(() {
//                 _showApplicantsList = !_showApplicantsList;
//               });
//             },
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   "Applicants",
//                   style: GoogleFonts.raleway(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: colorScheme.onSurface,
//                   ),
//                 ),
//                 Icon(
//                   _showApplicantsList
//                       ? Icons.keyboard_arrow_up
//                       : Icons.keyboard_arrow_down,
//                   color: colorScheme.onSurface,
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 12),
//           // Only show the list if dropdown is expanded
//           if (_showApplicantsList)
//             StreamBuilder<QuerySnapshot>(
//               stream: FirebaseFirestore.instance
//                   .collection('events')
//                   .doc(eventId)
//                   .collection('applicants')
//                   .snapshots(),
//               builder: (context, snapshot) {
//                 if (snapshot.connectionState == ConnectionState.waiting) {
//                   return const Center(child: CircularProgressIndicator());
//                 }
//                 if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
//                   return const Text("No applicants yet.");
//                 }
//                 final applicants = snapshot.data!.docs;
//                 return ListView.builder(
//                   shrinkWrap: true,
//                   physics: const NeverScrollableScrollPhysics(),
//                   itemCount: applicants.length,
//                   itemBuilder: (context, index) {
//                     final data =
//                         applicants[index].data() as Map<String, dynamic>;
//                     final userId = applicants[index].id;
//                     final name = data['name'] ?? 'Unknown';
//                     return ListTile(
//                       leading: const Icon(Icons.person),
//                       title: Text(name),
//                       subtitle: Text('User ID: $userId'),
//                     );
//                   },
//                 );
//               },
//             ),
//         ],
//       ),
//     ),
//   );
// }

Widget _buildApplicantsSection(String eventId) {
  final colorScheme = Theme.of(context).colorScheme;
  return Card(
    elevation: 3,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Applicants",
                style: GoogleFonts.raleway(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: Icon(
                  _showApplicantsList
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: colorScheme.onSurface,
                ),
                onPressed: () {
                  setState(() => _showApplicantsList = !_showApplicantsList);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showApplicantsList)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('events')
                  .doc(eventId)
                  .collection('applicants')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "No one has applied yet",
                      style: GoogleFonts.raleway(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final applicants = snapshot.data!.docs;
                return Column(
                  children: applicants.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final userId = doc.id;
                    final status = data['status'] ?? 'pending';
                    Color statusColor;
                    switch (status) {
                      case 'accepted':
                        statusColor = Colors.green;
                        break;
                      case 'rejected':
                        statusColor = Colors.red;
                        break;
                      default:
                        statusColor = Colors.orange;
                    }

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .get(),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const ListTile(
                            leading: CircularProgressIndicator(),
                            title: Text('Loading...'),
                          );
                        }
                        if (!userSnapshot.hasData ||
                            !userSnapshot.data!.exists) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: const Icon(Icons.person),
                            ),
                            title: const Text('User not found'),
                            subtitle: Text('ID: $userId'),
                          );
                        }

                        final userData =
                            userSnapshot.data!.data() as Map<String, dynamic>?;
                        final name = userData?['name'] ?? 'Unknown';
                        final photoUrl = userData?['photoUrl'] as String?;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: photoUrl != null
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(photoUrl),
                                  )
                                : CircleAvatar(
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: Text(name[0]),
                                  ),
                            title: Text(name),
                            subtitle: Text("Status: ${status.toUpperCase()}"),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: DropdownButton<String>(
                                value: status,
                                underline: const SizedBox(),
                                icon: const Icon(Icons.arrow_drop_down),
                                style: GoogleFonts.raleway(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'pending',
                                    child: Text('PENDING'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'accepted',
                                    child: Text('ACCEPTED'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rejected',
                                    child: Text('REJECTED'),
                                  ),
                                ],
                                onChanged: (newStatus) {
                                  if (newStatus != null) {
                                    context.read<EventBloc>().add(
                                          UpdateApplicantStatus(
                                            eventId: eventId,
                                            userId: userId,
                                            newStatus: newStatus,
                                          ),
                                        );
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    ),
  );
}



  Widget _buildQRSection(bool showQRCode, Event event) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isEventLive =
        now.isAfter(event.startTime) && now.isBefore(event.endTime);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Event QR Code",
              style: GoogleFonts.raleway(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            if (isEventLive)
              Text(
                "Scan this QR code for guest check-in:",
                style: GoogleFonts.raleway(color: colorScheme.onSurfaceVariant),
              )
            else
              Text(
                "QR code will be available when the event starts",
                style: GoogleFonts.raleway(color: Colors.orange),
              ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code),
                label: Text(showQRCode ? "Hide QR Code" : "Show QR Code"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                onPressed:
                    isEventLive
                        ? () {
                          context.read<EventBloc>().add(
                            ToggleQRCodeVisibility(show: !showQRCode),
                          );
                        }
                        : null,
              ),
            ),
            if (showQRCode && isEventLive) ...[
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: widget.eventId,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMatchingSection(Event event) {
    final now = DateTime.now();
    final isMatchingAvailable =
        now.isAfter(event.startTime) && now.isBefore(event.endTime);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Matchmaking",
              style: GoogleFonts.raleway(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _useMockData
                  ? "Using mock data for testing"
                  : "Using real attendee data",
              style: GoogleFonts.raleway(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            if (isMatchingAvailable)
              Column(
                children: [
                  ElevatedButton.icon(
                    icon:
                        _isMatching
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.auto_fix_high),
                    label: Text(
                      _isMatching
                          ? "Running Matching AI..."
                          : "Run Matching AI",
                      style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: _isMatching ? null : () => _runMatchingAI(event),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text("Release Matches to Attendees"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => _releaseMatches(event),
                  ),
                ],
              )
            else
              Text(
                "Matching only available during the event",
                style: GoogleFonts.raleway(color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Manage Event",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocBuilder<EventBloc, EventState>(
        builder: (context, state) {
          if (state is EventLoading || state is EventInitial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is EventFailure) {
            return Center(
              child: Text(
                "Error: ${state.error}",
                style: GoogleFonts.raleway(),
              ),
            );
          }

          if (state is EventWithApplicantsLoaded) {
            final event = state.event;
            final applicants = state.applicants;

            return RefreshIndicator(
              onRefresh: () async {
                context.read<EventBloc>().add(
                  FetchEventWithApplicants(widget.eventId),
                );
                await _updateQuestionnaireCount();
              },
              child: ListView(
                controller: _scrollController,
                children: [
                  _buildEventHeader(event),

                  // Check-ins StreamBuilder
                  StreamBuilder<QuerySnapshot>(
                    stream:
                        FirebaseFirestore.instance
                            .collection('checkins')
                            .where('eventId', isEqualTo: event.id)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: GoogleFonts.raleway(),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Card(
                          margin: const EdgeInsets.all(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                "No check-ins yet",
                                style: GoogleFonts.raleway(),
                              ),
                            ),
                          ),
                        );
                      }

                      return _buildCheckinsSection(snapshot.data!, event);
                    },
                  ),

                  _buildMatchingSection(event),
                  _buildMatchesSection(event.id),
                  // _buildApplicantsSection(applicants, event),

                   _buildGroupManagementSection(event), // ADD THIS LINE
              _buildMatchingSection(event),
                  _buildApplicantsSection(event.id),
                  _buildQRSection(state.showQRCode, event),

                  // Add some bottom padding
                  const SizedBox(height: 40),
                ],
              ),
            );
          }

          return Center(
            child: Text("Unknown state", style: GoogleFonts.raleway()),
          );
        },
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
