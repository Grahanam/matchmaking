import 'dart:async';
import 'dart:convert';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/models/event.dart';
import 'package:app/models/feedbackmodel.dart';
import 'package:app/models/group.dart';
import 'package:app/models/question_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/pages/chat/event_chat_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ManageEventPage extends StatefulWidget {
  final String eventId;
  const ManageEventPage({super.key, required this.eventId});

  @override
  State<ManageEventPage> createState() => _ManageEventPageState();
}

class _ManageEventPageState extends State<ManageEventPage> {
  bool _isMatching = false;
  bool _isGrouping = false;

  final ScrollController _scrollController = ScrollController();
  int _completedCount = 0;
  int _totalCheckins = 0;
  StreamSubscription? _applicantSubscription;
  StreamSubscription? _checkinSubscription;
  String get _aiApiToken => dotenv.env['AI_API_TOKEN'] ?? '';

  static const String _aiApiEndpoint =
      'https://models.github.ai/inference/chat/completions';

  // Section visibility states
  bool _showCheckinsList = false;
  bool _showMatchesList = false;
  bool _showApplicantsList = false;

  @override
  void initState() {
    super.initState();
     if (_aiApiToken.isEmpty) {
    debugPrint('WARNING: AI_API_TOKEN is not set in .env file');
  }
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

  Future<List<Map<String, dynamic>>> _prepareAIData(Event event) async {
    final List<Map<String, dynamic>> aiData = [];
    final userIds =
        (await FirebaseFirestore.instance
                .collection('checkins')
                .where('eventId', isEqualTo: event.id)
                .get())
            .docs
            .map((doc) => doc['userId'] as String)
            .toList();

    print(userIds);

    // Fetch feedback for the event
    final feedbackDocs =
        await FirebaseFirestore.instance
            .collection('feedback')
            .where('eventId', isEqualTo: event.id)
            .get();

    // Organize feedback by recipient
    final feedbackByRecipient = <String, List<int>>{};
    for (final doc in feedbackDocs.docs) {
      final feedback = FeedbackModel.fromSnapshot(doc);
      feedbackByRecipient
          .putIfAbsent(feedback.toUser, () => [])
          .add(feedback.rating);
    }

    for (final userId in userIds) {
      // Fetch user profile
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
      final userData = userDoc.data() ?? {};

      // Fetch questionnaire answers
      final answersDoc =
          await FirebaseFirestore.instance
              .collection('events')
              .doc(event.id)
              .collection('applicants')
              .doc(userId)
              .get();
      final answers =
          answersDoc.data()?['answers'] as Map<String, dynamic>? ?? {};

      // Fetch questions to map IDs to text/category
      final questions =
          await FirebaseFirestore.instance
              .collection('questionmodels')
              .where(FieldPath.documentId, whereIn: event.questionnaire)
              .get();
      final questionMap = <String, QuestionModel>{};
      for (final doc in questions.docs) {
        questionMap[doc.id] = QuestionModel.fromFirestore(doc);
      }

      // Structure answers with question details
      final structuredAnswers = <String, dynamic>{};
      answers.forEach((qId, answer) {
        final question = questionMap[qId];
        if (question != null) {
          structuredAnswers[question.text] = {
            'answer': answer,
            'category': question.category.toString().split('.').last,
            'weight': question.weight,
          };
        }
      });

      double avgRating = 0;
      final ratings = feedbackByRecipient[userId] ?? [];
      if (ratings.isNotEmpty) {
        avgRating = ratings.reduce((a, b) => a + b) / ratings.length;
      }
      final userGroups = await _getUserGroups(event);
      aiData.add({
        'userId': userId,
        'profile': {
          'name': userData['name'],
          'gender': userData['gender'],
          'hobbies': userData['hobbies'] ?? [],
          'introduction': userData['introduction'],
          'preference': userData['preference'],
        },
        'questionnaire': structuredAnswers,
        'feedback': {'avgRating': avgRating, 'count': ratings.length},
        'groupId': userGroups[userId] ?? 'nogroup',
      });
    }
    return aiData;
  }

  Future<void> _notifyGroupMembers(
    Event event,
    List<Map<String, dynamic>> groups,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = Timestamp.now();

      for (final group in groups) {
        final groupId =
            FirebaseFirestore.instance.collection('groups').doc().id;
        final groupRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId);

        batch.set(groupRef, {
          'eventId': event.id,
          'name': group['name'],
          'members': group['members'],
          'createdAt': now,
        });

        for (final memberId in group['members']) {
          final notificationRef =
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(memberId)
                  .collection('notifications')
                  .doc();

          batch.set(notificationRef, {
            'type': 'group_assignment',
            'title': 'Group Assignment',
            'body':
                'You\'ve been assigned to ${group['name']} for ${event.title}',
            'eventId': event.id,
            'groupId': groupId,
            'timestamp': now,
            'read': false,
          });
        }
      }

      await batch.commit();
      debugPrint('Notifications sent to group members');
    } catch (e) {
      debugPrint('Error notifying group members: $e');
    }
  }

  // Update the _createGroups method
  void _createGroups(Event event) async {
    setState(() => _isGrouping = true);
    try {
      // Get checked-in users
      final checkins =
          await FirebaseFirestore.instance
              .collection('checkins')
              .where('eventId', isEqualTo: event.id)
              .get();

      final userIds = checkins.docs.map((d) => d['userId'] as String).toList();

      // Validate minimum attendees
      if (userIds.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Need at least 4 attendees to form groups"),
          ),
        );
        return;
      }

      // Prepare user data for AI
      final List<Map<String, dynamic>> userDataList = [];

      for (final userId in userIds) {
        // Get applicant data (answers)
        final applicantDoc =
            await FirebaseFirestore.instance
                .collection('events')
                .doc(event.id)
                .collection('applicants')
                .doc(userId)
                .get();

        final applicantData = applicantDoc.data();
        final answers =
            applicantData?['answers'] as Map<String, dynamic>? ?? {};

        // Get user profile
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();

        final userData = userDoc.data() ?? {};

        userDataList.add({
          'userId': userId, // Use actual Firestore user ID
          'gender': userData['gender'] as String? ?? 'unknown',
          'answers': answers,
        });
      }

      // 4. Call AI for group formation
      final groups = await _callGitHubAIGroupFormation(userDataList);

      // 5. Save groups to Firestore
      final batch = FirebaseFirestore.instance.batch();
      for (final group in groups) {
        final docRef = FirebaseFirestore.instance.collection('groups').doc();
        batch.set(docRef, {
          'eventId': event.id,
          'round': 1,
          'name': group['name'],
          'members': group['members'], // Contains actual user IDs
          'genderBalance': group['genderBalance'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      await _notifyGroupMembers(event, groups);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Created ${groups.length} groups using AI")),
      );
    } catch (e, stack) {
      debugPrint('Group creation with AI error: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating groups: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGrouping = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _callGitHubAIGroupFormation(
    List<Map<String, dynamic>> users,
  ) async {
    try {
      final Map<String, String> idMapping = {};
      for (int i = 0; i < users.length; i++) {
        final realId = users[i]['userId'] as String;
        idMapping['id${i + 1}'] = realId;
        idMapping['user${i + 1}'] = realId;
        idMapping['participant${i + 1}'] = realId;
      }
      // Prepare the prompt
      // Update the prompt in _callGitHubAIGroupFormation
      final prompt = '''
You are an expert event group formation system. Create optimized groups for networking events with STRICT adherence to these rules:

NON-NEGOTIABLE GROUP RULES:
1. Group size: 4-6 members
   - ABSOLUTELY NO groups with <4 members
   - STRICTLY AVOID groups of 5 when groups of 4 and 6 are possible
   - Groups of 6 MUST be used when mathematically unavoidable OR when it enables perfect gender balance (3M/3F)
2. Gender balance requirements:
   - PRIMARY GOAL: Equal M/F ratio in every group
   - ACCEPTABLE: ±1 gender difference (3M/2F, 2M/3F)
   - UNACCEPTABLE: Groups with >2 gender imbalance or single-gender groups
3. Composition strategy:
   ${_generateGroupingStrategy(users.length)}
   - For 10 participants: ONLY create one group of 4 and one group of 6
   - NEVER create two groups of 5 for 10 participants

GROUP FORMATION PRIORITIES (in order):
1. Maintain minimum 4 members per group
2. Achieve perfect gender balance (2M/2F in group of 4, 3M/3F in group of 6)
3. Avoid groups of 5 at all costs
4. Ensure answer compatibility within groups
5. Maximize potential matches across groups

ANSWER-BASED COMPATIBILITY:
- Cluster participants with:
  * Shared values (${_extractTopTheme(users, 'values')})
  * Complementary personalities (${_extractTopTheme(users, 'personality')})
  * Interesting differences (${_extractTopTheme(users, 'interests')})
- Create conversation potential through balanced traits

OUTPUT REQUIREMENTS:
[{"name": "Group 1", "members": ["id1","id2"], "genderBalance": "2M/2F"},...]

Current event stats:
- Total participants: ${users.length}
- Gender distribution: ${_calculateGenderDistribution(users)}
- Key compatibility factors: ${_extractCompatibilityFactors(users)}
''';

      // Make API request to GitHub AI using OpenAI-compatible format
      // final response = await http.post(
      //   Uri.parse('https://models.github.ai/inference/chat/completions'),
      //   headers: {
      //     'Authorization': 'Bearer $_aiApiToken',
      //     'Content-Type': 'application/json',
      //     'Accept': 'application/json',
      //   },
      //   body: jsonEncode({
      //     "model": "openai/gpt-4.1",
      //     "messages": [
      //       {
      //         "role": "system",
      //         "content":
      //             "You are a helpful event group formation assistant. Return ONLY valid JSON arrays.",
      //       },
      //       {"role": "user", "content": prompt},
      //     ],
      //     "max_tokens": 1000,
      //     "temperature": 0.7,
      //     "response_format": {"type": "json_object"},
      //   }),
      // );

      // Create the request with explicit encoding
      // final request = http.Request(
      //   'POST',
      //   Uri.parse('https://models.github.ai/inference/chat/completions')
      // )
      //   ..headers['Authorization'] = 'Bearer $_aiApiToken'
      //   ..headers['Content-Type'] = 'application/json'
      //   ..body = jsonEncode({
      //     "model": "openai/gpt-4.1",
      //     "messages": [
      //       {
      //         "role": "system",
      //         "content":
      //             "You are a helpful event group formation assistant. Return ONLY valid JSON arrays.",
      //       },
      //       {"role": "user", "content": prompt},
      //     ],
      //     "max_tokens": 1000,
      //     "temperature": 0.7,
      //     "response_format": {"type": "json_object"},
      //   });

      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://models.github.ai',
          headers: {
            'Authorization': 'Bearer $_aiApiToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (status) => true, // Accept all status codes
        ),
      );

      final response = await dio.post(
        '/inference/chat/completions',
        data: jsonEncode({
          "model": "openai/gpt-4.1",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are a helpful event group formation assistant. Return ONLY valid JSON arrays.",
            },
            {"role": "user", "content": prompt},
          ],
          "max_tokens": 1000,
          "temperature": 0.3,
          "response_format": {"type": "json_object"},
        }),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;

        // Validate response structure
        if (data['choices'] == null || data['choices'].isEmpty) {
          throw FormatException("AI response missing 'choices' field");
        }

        // Send the request and get the response
        // final streamedResponse = await request.send();
        // final response = await http.Response.fromStream(streamedResponse);

        //   debugPrint('Response status: ${response.statusCode}');
        //   debugPrint('Response headers: ${response.headers}');
        //   debugPrint('Response body: ${response.body}');

        // if (response.statusCode == 200) {
        //   final data = jsonDecode(response.body);
        // Extract content from the correct path in the response
        final content = data['choices'][0]['message']['content'];
        debugPrint('Raw AI Response: $content');

        // Extract and parse JSON
        String jsonString = content.trim();

        // Handle code block formatting
        if (jsonString.startsWith('```json')) {
          jsonString = jsonString.substring(7, jsonString.length - 3).trim();
        } else if (jsonString.startsWith('```')) {
          jsonString = jsonString.substring(3, jsonString.length - 3).trim();
        }
        final parsedResponse = json.decode(jsonString);
        List<dynamic> groupsList = [];

        // Handle both array and object responses
        if (parsedResponse is List) {
          groupsList = parsedResponse;
        } else if (parsedResponse is Map &&
            parsedResponse.containsKey('groups')) {
          groupsList = parsedResponse['groups'] as List<dynamic>;
        } else {
          throw FormatException("Unexpected response format: $jsonString");
        }

        final fixedGroups =
            groupsList.map((group) {
              final members =
                  (group['members'] as List<dynamic>).map((id) {
                    final idStr = id.toString();
                    return idMapping[idStr] ?? idStr;
                  }).toList();

              return {
                'name': group['name'] ?? 'Unnamed Group',
                'members': members,
                'genderBalance': group['genderBalance'] ?? 'Unknown',
              };
            }).toList();

        return fixedGroups.cast<Map<String, dynamic>>();

        // final parsedResponse = json.decode(jsonString);
        // final fixedGroups =
        //     parsedResponse.map((group) {
        //       final members =
        //           (group['members'] as List<dynamic>).map((id) {
        //             final idStr = id.toString();
        //             return idMapping[idStr] ??
        //                 idStr; // Use real ID if mapping exists
        //           }).toList();

        //       return {
        //         'name': group['name'],
        //         'members': members,
        //         'genderBalance': group['genderBalance'],
        //       };
        //     }).toList();
        // return fixedGroups.cast<Map<String, dynamic>>();
      } else {
        throw Exception(
          "GitHub AI group formation failed: ${response.statusCode}\n"
          "Headers: ${response.headers}\n"
          "Body: ${response.data}",
        );
      }
    } catch (e) {
      debugPrint('GitHub AI Group Formation Error: $e');
      rethrow;
    }
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

        for (var doc in applicantsSnap.docs) {
          final data = doc.data();
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
      debugPrint('GitHub AI Group Formation Error: $e');

      // Provide more user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("AI service error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, String>> _getUserGroups(Event event) async {
    final groups =
        await FirebaseFirestore.instance
            .collection('groups')
            .where('eventId', isEqualTo: event.id)
            .get();

    final userGroups = <String, String>{};
    for (final group in groups.docs) {
      final members = group['members'] as List<dynamic>;
      for (final member in members) {
        userGroups[member as String] = group.id;
      }
    }
    return userGroups;
  }

  /// Calls the AI API for matchmaking
  Future<List<Map<String, dynamic>>> _aiMatchmaking(
    List<Map<String, dynamic>> users,
  ) async {
    try {
      final realUserIds = users.map((u) => u['userId'] as String).toList();
      // debugPrint("real user:,$users");
      // debugPrint('Raw AI Response: $realUserIds');

      if (realUserIds.any((id) => id.isEmpty || id.length < 8)) {
        throw Exception('Invalid user IDs in input data');
      }
      if (users.isEmpty) {
        throw Exception('No user data available for matching');
      }

      // Updated prompt with explicit instructions
      final prompt = '''
You are an event matchmaking assistant. Create pairs for networking using the following user data:
${jsonEncode(users)}

STRICT RULES:
- Use EXACT user IDs from the "userId" field in the input data (e.g., "2xEqXvhhKOhbtGNUcny22GdRvg23")
- Never use descriptive names like "user 8" or "user 9"
- Match users from DIFFERENT groups
- Respect gender preferences strictly
- Prioritize pairs with mutual high feedback ratings
- If groups are unbalanced, leave 1 person unmatched
- Never match same-group members

Format output STRICTLY as:
[{
  "userId": "exact_user_id_from_input", 
  "matchedWith": "exact_user_id_from_input",
  "reason": "Compatibility details",
  "groupCompatibility": "High"
}]  especially for username=user8 use its userId''';

      // Make the API request
      // final response = await http.post(
      //   Uri.parse(_aiApiEndpoint),
      //   headers: {
      //     'Authorization': 'Bearer $_aiApiToken',
      //     'Content-Type': 'application/json',
      //     'Accept': 'application/json',
      //   },
      //   body: jsonEncode({
      //     "model": "openai/gpt-4.1",
      //     "messages": [
      //       {
      //         "role": "system",
      //         "content":
      //             "You are a helpful event matchmaking assistant. Return ONLY valid JSON arrays.",
      //       },
      //       {"role": "user", "content": prompt},
      //     ],
      //     "max_tokens": 1000,
      //     "temperature": 0.3,
      //     "response_format": {"type": "json_object"},
      //   }),
      // );

      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   final content = data['choices'][0]['message']['content'];

      // debugPrint('Raw AI Response: $content');

      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://models.github.ai',
          headers: {
            'Authorization': 'Bearer $_aiApiToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (status) => true, // Accept all status codes
        ),
      );

      final response = await dio.post(
        '/inference/chat/completions',
        data: jsonEncode({
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

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;

        // Validate response structure
        if (data['choices'] == null || data['choices'].isEmpty) {
          throw FormatException("AI response missing 'choices' field");
        }

        final content = data['choices'][0]['message']['content'];
        debugPrint('Raw AI Response: $content');

        // Enhanced cleaning for common issues
        String cleanedContent = content
            .replaceAll('userld', 'userId') // Fix common typo
            .replaceAll('｛', '{') // Fix unusual braces
            .replaceAll('｝', '}')
            .replaceAllMapped(
              RegExp(r'"reason": "([^"]*)'), // Fix unclosed quotes
              (match) => '"reason": "${match.group(1)}"',
            )
            .replaceAll('""', '"') // Remove double quotes
            .replaceAll('\n', '') // Remove newlines
            .replaceAll('..', '.'); // Fix double periods

        // Try to extract JSON array from malformed responses
        final jsonStart = cleanedContent.indexOf('[');
        final jsonEnd = cleanedContent.lastIndexOf(']') + 1;

        if (jsonStart != -1 && jsonEnd != -1) {
          cleanedContent = cleanedContent.substring(jsonStart, jsonEnd);
        }

        // Parse the JSON
        final parsedResponse = json.decode(cleanedContent);
        List<dynamic> matches;

        if (parsedResponse is Map) {
          if (parsedResponse.containsKey('pairs')) {
            matches = parsedResponse['pairs'] as List<dynamic>;
          } else if (parsedResponse.containsKey('matches')) {
            matches = parsedResponse['matches'] as List<dynamic>;
          } else if (parsedResponse.containsKey('data')) {
            matches = parsedResponse['data'] as List<dynamic>;
          } else if (parsedResponse.containsKey('result')) {
            matches = parsedResponse['result'] as List<dynamic>;
          } else if (parsedResponse.containsKey('userId') &&
              parsedResponse.containsKey('matchedWith')) {
            // Handle single match object
            matches = [parsedResponse];
          } else {
            throw FormatException(
              "Unrecognized response format: $cleanedContent",
            );
          }
        } else if (parsedResponse is List) {
          matches = parsedResponse;
        } else {
          throw FormatException(
            "Unrecognized response format: $cleanedContent",
          );
        }

        // Validate and correct match IDs
        final validMatches = <Map<String, dynamic>>[];
        for (final match in matches) {
          try {
            String? userId = match['userId']?.toString();
            String? matchedWith = match['matchedWith']?.toString();

            // Validate IDs
            if (userId == null || matchedWith == null) {
              debugPrint('⚠️ Match missing IDs: $match');
              continue;
            }

            if (!realUserIds.contains(userId)) {
              debugPrint('⛔ Invalid userId: $userId in match: $match');
              continue;
            }

            if (!realUserIds.contains(matchedWith)) {
              debugPrint(
                '⛔ Invalid matchedWith: $matchedWith in match: $match',
              );
              continue;
            }

            validMatches.add({
              'userId': userId,
              'matchedWith': matchedWith,
              'reason': match['reason'] as String? ?? 'Compatible interests',
              'groupCompatibility':
                  match['groupCompatibility'] as String? ?? 'Medium',
            });
          } catch (e) {
            debugPrint('Error processing match: $e\nMatch: $match');
          }
        }

        debugPrint('Valid matches: ${validMatches.length}/${matches.length}');
        return validMatches;
      } else {
        throw Exception(
          "AI matchmaking failed: ${response.statusCode}\n"
          "Body: ${response.data}",
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
      dataToMatch = await _prepareAIData(event);

      // Get all user IDs from the prepared data
      final userIds =
          dataToMatch.map((user) => user['userId'] as String).toList();

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

      // ===== START: ADD UNMATCHED USERS HANDLING =====
      // Get all matched user IDs from both sides
      final matchedUserIds =
          matches
              .map((m) => [m['userId'], m['matchedWith']])
              .expand((pair) => pair)
              .whereType<String>()
              .toSet();

      // Find users who weren't matched
      final unmatchedUserIds =
          userIds.where((id) => !matchedUserIds.contains(id)).toList();

      for (final userId in unmatchedUserIds) {
        matches.add({
          'userId': userId,
          'matchedWith': "", // Empty string for unmatched
          'reason': 'No compatible match found',
        });
      }

      // Create entries for unmatched users
      for (final userId in unmatchedUserIds) {
        final matchRef = FirebaseFirestore.instance
            .collection('event_matches')
            .doc(event.id)
            .collection('matches')
            .doc(userId);

        batch.set(matchRef, {
          'userId': userId,
          'matchedWith': "", // Empty string indicates unmatched
          'reason': 'No compatible match found',
          'released': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // ===== END: ADD UNMATCHED USERS HANDLING =====

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Generated ${matches.length} matches and ${unmatchedUserIds.length} unmatched entries",
            ),
          ),
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
      final matchesCollection = FirebaseFirestore.instance
          .collection('event_matches')
          .doc(event.id)
          .collection('matches');

      final matchesSnapshot = await matchesCollection.get();

      if (matchesSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No matches to release")));
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      for (var doc in matchesSnapshot.docs) {
        // Update ALL documents regardless of matchedWith status
        batch.update(doc.reference, {'released': true});
      }

      await batch.commit();

      // Update event status
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({'matchesReleased': true});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Matches released to attendees!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to release matches: $e')),
        );
      }
    }
  }

  // Add this new method to build the feedback progress section
  Widget _buildFeedbackProgressSection(Event event) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('groups')
              .where('eventId', isEqualTo: event.id)
              .snapshots(),
      builder: (context, groupSnapshot) {
        // Only show feedback section if groups exist
        if (!groupSnapshot.hasData || groupSnapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('feedback')
                  .where('eventId', isEqualTo: event.id)
                  .snapshots(),
          builder: (context, feedbackSnapshot) {
            if (!feedbackSnapshot.hasData) {
              return const SizedBox.shrink();
            }

            final feedbackDocs = feedbackSnapshot.data!.docs;
            final feedbackList =
                feedbackDocs
                    .map((doc) => FeedbackModel.fromSnapshot(doc))
                    .toList();

            // Count unique users who submitted feedback
            final uniqueUsers = <String>{};
            for (final feedback in feedbackList) {
              uniqueUsers.add(feedback.fromUser);
            }

            final feedbackCount = uniqueUsers.length;
            final completionPercent =
                _totalCheckins == 0 ? 0.0 : feedbackCount / _totalCheckins;

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Feedback Progress",
                      style: GoogleFonts.raleway(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: completionPercent,
                      backgroundColor: Colors.grey[300],
                      color:
                          completionPercent > 0.7
                              ? Colors.green
                              : Colors.orange,
                      minHeight: 20,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$feedbackCount / $_totalCheckins users submitted",
                          style: GoogleFonts.raleway(),
                        ),
                        Text(
                          "${(completionPercent * 100).toStringAsFixed(1)}%",
                          style: GoogleFonts.raleway(
                            fontWeight: FontWeight.bold,
                            color:
                                completionPercent > 0.7
                                    ? Colors.green
                                    : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                ...checkins.map((doc) => _buildCheckinItem(doc, event)),
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
        final photoUrl = userData?['photoURL'] as String?;

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
                    final uniquePairs = <String, DocumentSnapshot>{};

                    for (final matchDoc in matches) {
                      final data = matchDoc.data() as Map<String, dynamic>;
                      final userId = data['userId'] as String? ?? '';
                      final matchedWith = data['matchedWith'] as String? ?? '';

                      if (userId.isNotEmpty && matchedWith.isNotEmpty) {
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
                                    title: Text('Loading...'),
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
                                      data1?['name'] as String? ?? userId;
                                }
                                if (userDocs.length > 1 && userDocs[1].exists) {
                                  final data2 =
                                      userDocs[1].data()
                                          as Map<String, dynamic>?;
                                  user2Name =
                                      data2?['name'] as String? ?? matchedWith;
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
                                    subtitle:
                                        createdAt != null
                                            ? Text(
                                              "Matched: ${DateFormat('MMM d, h:mm a').format(createdAt.toDate())}",
                                              style: GoogleFonts.raleway(
                                                fontSize: 12,
                                              ),
                                            )
                                            : null,
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
    final now = DateTime.now();
    final isEventStarted = now.isAfter(event.startTime);

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

            // Add event start time indicator
            Text(
              isEventStarted
                  ? "Groups can now be created"
                  : "Groups available after: ${DateFormat('MMM d, h:mm a').format(event.startTime)}",
              style: GoogleFonts.raleway(
                color: isEventStarted ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // AI Group Creation Button - FIXED HERE
            ElevatedButton.icon(
              icon:
                  _isGrouping
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
                _isGrouping ? "Creating groups..." : "Create Groups",
                style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isEventStarted ? Colors.deepPurple : Colors.grey,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed:
                  isEventStarted && !_isGrouping
                      ? () => _createGroups(event)
                      : null,
            ),
            const SizedBox(height: 16),

            // Groups list
            StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('groups')
                      .where('eventId', isEqualTo: event.id)
                      .orderBy('round', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Nothing yet",
                      style: GoogleFonts.raleway(color: Colors.grey),
                    ),
                  );
                }

                final groups =
                    snapshot.data!.docs
                        .map((doc) => Group.fromDocumentSnapshot(doc))
                        .toList();

                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "No groups created yet",
                      style: GoogleFonts.raleway(color: Colors.grey),
                    ),
                  );
                }

                return Column(
                  children: [
                    Text(
                      "Total Groups: ${groups.length}",
                      style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...groups.map((group) => _buildGroupItem(group)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Update the _buildGroupItem method
  Widget _buildGroupItem(Group group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(group.members.length.toString())),
        title: Text(
          "Round ${group.round}: ${group.name}",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${group.members.length} members",
          style: GoogleFonts.raleway(color: Colors.grey),
        ),
        children: [
          ...group.members.map(
            (userId) => FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Loading...'),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: const Text('Unknown User'),
                    subtitle: Text('ID: $userId'), // Show the ID
                  );
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>?;
                return ListTile(
                  leading:
                      userData?['photoURL'] != null
                          ? CircleAvatar(
                            backgroundImage: NetworkImage(
                              userData!['photoURL'],
                            ),
                          )
                          : CircleAvatar(
                            child: Text(userData?['name']?[0] ?? '?'),
                          ),
                  title: Text(userData?['name'] ?? 'Unknown User'),
                  subtitle: Text('ID: $userId'), // Show the ID for debugging
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
                stream:
                    FirebaseFirestore.instance
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
                    children:
                        applicants.map((doc) {
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
                            future:
                                FirebaseFirestore.instance
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
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: const Icon(Icons.person),
                                  ),
                                  title: const Text('User not found'),
                                  subtitle: Text('ID: $userId'),
                                );
                              }

                              final userData =
                                  userSnapshot.data!.data()
                                      as Map<String, dynamic>?;
                              final name = userData?['name'] ?? 'Unknown';
                              final photoUrl = userData?['photoURL'] as String?;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading:
                                      photoUrl != null
                                          ? CircleAvatar(
                                            backgroundImage: NetworkImage(
                                              photoUrl,
                                            ),
                                          )
                                          : CircleAvatar(
                                            backgroundColor:
                                                colorScheme.primaryContainer,
                                            child: Text(name[0]),
                                          ),
                                  title: Text(name),
                                  subtitle: Text(
                                    "Status: ${status.toUpperCase()}",
                                  ),
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

    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('groups')
              .where('eventId', isEqualTo: event.id)
              .snapshots(),
      builder: (context, groupSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('feedback')
                  .where('eventId', isEqualTo: event.id)
                  .snapshots(),
          builder: (context, feedbackSnapshot) {
            // Calculate feedback completion
            int feedbackCount = 0;
            if (feedbackSnapshot.hasData) {
              final feedbackDocs = feedbackSnapshot.data!.docs;
              final uniqueUsers = <String>{};
              for (final doc in feedbackDocs) {
                final feedback = FeedbackModel.fromSnapshot(doc);
                uniqueUsers.add(feedback.fromUser);
              }
              feedbackCount = uniqueUsers.length;
            }

            final hasGroups =
                groupSnapshot.hasData && groupSnapshot.data!.docs.isNotEmpty;
            final feedbackComplete =
                _totalCheckins > 0 && feedbackCount == _totalCheckins;
            final canRunMatching =
                isMatchingAvailable && hasGroups && feedbackComplete;

            String tooltipMessage = "Run Matching AI";
            if (!isMatchingAvailable) {
              tooltipMessage = "Matching only available during the event";
            } else if (!hasGroups) {
              tooltipMessage = "Create groups first to run matching";
            } else if (!feedbackComplete) {
              tooltipMessage =
                  "All checked-in users must submit feedback ($feedbackCount/$_totalCheckins completed)";
            }

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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

                    // Feedback completion status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Feedback Completion:",
                          style: GoogleFonts.raleway(),
                        ),
                        Text(
                          "$feedbackCount/$_totalCheckins",
                          style: GoogleFonts.raleway(
                            fontWeight: FontWeight.bold,
                            color:
                                feedbackComplete ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (isMatchingAvailable)
                      Column(
                        children: [
                          Tooltip(
                            message: tooltipMessage,
                            child: ElevatedButton.icon(
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
                                style: GoogleFonts.raleway(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    canRunMatching
                                        ? Colors.deepPurple
                                        : Colors.grey,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              onPressed:
                                  canRunMatching
                                      ? () => _runMatchingAI(event)
                                      : null,
                            ),
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
          },
        );
      },
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
        actions: [
          BlocBuilder<EventBloc, EventState>(
            builder: (context, state) {
              if (state is EventWithApplicantsLoaded) {
                return IconButton(
                  icon: const Icon(Icons.chat),
                  tooltip: "Event Chat",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) =>
                                EventChatPage(event: state.event, isHost: true),
                      ),
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
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

                  _buildApplicantsSection(event.id),

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

                  _buildGroupManagementSection(event),
                  _buildFeedbackProgressSection(event),
                  _buildMatchingSection(event),
                  _buildMatchesSection(event.id),
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

// New helper method
String _extractCompatibilityFactors(List<Map<String, dynamic>> users) {
  final factors = <String, int>{};
  for (final user in users) {
    final answers = user['answers'] as Map<String, dynamic>? ?? {};
    for (final key in answers.keys) {
      if (key.contains('interest') || key.contains('value')) {
        factors[key] = (factors[key] ?? 0) + 1;
      }
    }
  }

  return factors.isEmpty
      ? "No specific compatibility factors identified"
      : "Prioritize matches based on: ${factors.keys.join(', ')}";
}

String _calculateGenderDistribution(List<Map<String, dynamic>> users) {
  final genderCounts = <String, int>{};
  for (final user in users) {
    final gender = user['gender']?.toString().toUpperCase() ?? 'UNKNOWN';
    genderCounts[gender] = (genderCounts[gender] ?? 0) + 1;
  }

  return genderCounts.entries.map((e) => '${e.value} ${e.key}').join(', ');
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

// Helper methods
String _generateGroupingStrategy(int userCount) {
  if (userCount == 10) {
    return "MUST create one group of 4 and one group of 6 - NO groups of 5 allowed";
  }
  if (userCount <= 6) return "Single group of $userCount members";
  if (userCount <= 10) {
    return "Two groups (${(userCount / 2).round()} members each)";
  }
  if (userCount <= 15) {
    return "Three groups (${(userCount / 3).toStringAsFixed(1)} avg)";
  }
  return "${(userCount / 4).ceil()} groups of 4-6 members";
}

String _extractTopTheme(List<Map<String, dynamic>> users, String category) {
  final themes = <String, int>{};
  for (final user in users) {
    final answers = user['answers'] as Map<String, dynamic>? ?? {};
    for (final key in answers.keys.where((k) => k.contains(category))) {
      themes[key] = (themes[key] ?? 0) + 1;
    }
  }
  return themes.isNotEmpty
      ? themes.entries.reduce((a, b) => a.value > b.value ? a : b).key
      : 'general preferences';
}
