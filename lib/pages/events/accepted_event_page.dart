import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:app/models/group.dart';
import 'package:app/models/question_model.dart';
import 'package:app/pages/qr/scan_qr_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import 'package:app/pages/chat/chat_page.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:app/pages/chat/event_chat_page.dart';

class ChartData {
  final String category;
  final int value;

  ChartData(this.category, this.value);
}

class AcceptedEventDetailPage extends StatefulWidget {
  final Event event;
  const AcceptedEventDetailPage({super.key, required this.event});

  @override
  State<AcceptedEventDetailPage> createState() =>
      _AcceptedEventDetailPageState();
}

class _AcceptedEventDetailPageState extends State<AcceptedEventDetailPage> {
  final Map<String, dynamic> _answers = {};
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _groupMembers = [];
  bool _isLoading = true;
  bool _hasSubmittedAnswers = false;
  bool _isCheckedIn = false;
  Map<String, dynamic>? _existingAnswers;
  DocumentSnapshot? _matchData;
  String? _matchedUserName;
  bool _eventHasStarted = false;
  DateTime? _checkInTime;
  Group? _userGroup;

  List<Map<String, dynamic>> _feedbackUsers = [];
  Timer? _feedbackTimer;
  bool _showFeedback = false;
  DateTime? _feedbackTime;
  bool _timerStarted = false;

  // Timer? _matchTimer;
  // bool _showMatch = false;
  bool _matchReleased = false;

  StreamSubscription<DocumentSnapshot>? _eventSubscription;
  StreamSubscription<DocumentSnapshot>? _matchSubscription;
  // List<Question>? _cachedQuestions;
  List<QuestionModel>? _cachedQuestions;

  Duration? _timeRemaining;
  Timer? _countdownTimer;
  bool _feedbackSubmitted = false;
  bool _hasSubmittedFeedback = false;

  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupListeners();
    _checkEventStatus();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  bool _isAnswerValid(QuestionModel q, dynamic answer) {
    if (answer == null) return false;

    switch (q.type) {
      case QuestionType.scale:
        return answer >= q.scaleMin! && answer <= q.scaleMax!;

      case QuestionType.multipleChoice:
        return q.options!.contains(answer);

      case QuestionType.multiSelect:
        if (answer is! List) return false;
        return answer.every((item) => q.options!.contains(item));

      case QuestionType.openText:
        return answer.toString().isNotEmpty;

      default:
        return false;
    }
  }

  bool _isUserMatchReleased() {
    if (_matchData == null || !_matchData!.exists) return false;

    final matchDocData = _matchData!.data() as Map<String, dynamic>?;
    if (matchDocData == null) return false;

    return matchDocData['released'] as bool? ?? true;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  void _scheduleFeedback() {
    if (_userGroup == null || _timerStarted) return;

    final groupCreated = _userGroup!.createdAt;
    _feedbackTime ??= groupCreated.add(Duration(minutes: 1));
    final now = DateTime.now();

    if (now.isAfter(_feedbackTime!)) {
      setState(() => _showFeedback = true);
      _loadFeedbackUsers();
    } else {
      _startCountdownTimer();
      _timerStarted = true;
    }
  }

  void _startCountdownTimer() {
    if (_userGroup == null || _feedbackTime == null) return;

    // Cancel existing timer if any
    _countdownTimer?.cancel();

    // Calculate initial remaining time
    _timeRemaining = _feedbackTime!.difference(DateTime.now());

    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (now.isAfter(_feedbackTime!)) {
        timer.cancel();
        setState(() {
          _showFeedback = true;
          _loadFeedbackUsers();
        });
        return;
      }

      setState(() {
        _timeRemaining = _feedbackTime!.difference(now);
      });
    });
  }

  void _setupListeners() {
    final eventId = widget.event.id;
    final userId = FirebaseAuth.instance.currentUser!.uid;

    _eventSubscription = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .snapshots()
        .listen((eventDoc) {
          if (eventDoc.exists) {
            final data = eventDoc.data() ?? {};
            final matchesReleased = data['matchesReleased'] ?? false;

            if (mounted) {
              setState(() {
                _matchReleased = matchesReleased;
              });
            }
          }
        });

    _matchSubscription = FirebaseFirestore.instance
        .collection('event_matches')
        .doc(eventId)
        .collection('matches')
        .doc(userId)
        .snapshots()
        .listen((matchDoc) {
          if (matchDoc.exists) {
            if (mounted) {
              setState(() {
                _matchData = matchDoc;
                final matchUser = matchDoc['matchedWith'] as String?;
                if (matchUser != null && matchUser.isNotEmpty) {
                  _fetchMatchedUserName(
                    matchUser,
                  ); // Fetches name, useful if needed elsewhere
                }
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _matchData =
                    null; // Ensure _matchData is null if doc doesn't exist
              });
            }
          }
        });
  }

  Future<void> _fetchUserGroup() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;

    try {
      final query =
          await FirebaseFirestore.instance
              .collection('groups')
              .where('eventId', isEqualTo: eventId)
              .where('members', arrayContains: userId)
              .limit(1)
              .get();

      if (query.docs.isNotEmpty) {
        final groupDoc = query.docs.first;
        final group = Group(
          id: groupDoc.id,
          name: groupDoc['name'] ?? 'Unnamed Group',
          eventId: eventId,
          round: 1,
          members: List<String>.from(groupDoc['members'] ?? []),
          createdAt:
              (groupDoc['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );

        // Pre-fetch all member data at once
        final membersData = await Future.wait(
          group.members.map((memberId) async {
            final userDoc =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(memberId)
                    .get();

            return {
              'id': memberId,
              'name': userDoc['name'] ?? 'Unknown Member',
              'photoURL': userDoc['photoURL'] as String?,
            };
          }),
        );

        if (mounted) {
          setState(() {
            _userGroup = group;
            _groupMembers = membersData;
          });
        }
        if (!_timerStarted) {
          _scheduleFeedback();
        }
      }
    } catch (e) {
      debugPrint('Error fetching user group: $e');
    }
  }

  Future<void> _submitFeedback() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;
    final batch = FirebaseFirestore.instance.batch();

    for (final user in _feedbackUsers) {
      final feedbackRef =
          FirebaseFirestore.instance.collection('feedback').doc();
      batch.set(feedbackRef, {
        'eventId': eventId,
        'fromUser': userId,
        'toUser': user['id'],
        'rating': user['rating'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
      if (mounted) {
        setState(() {
          _feedbackSubmitted = true;
          _hasSubmittedFeedback = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to submit feedback: $e")));
    }
  }

  Future<void> _fetchMatchedUserName(String userId) async {
    try {
      final actualUserId =
          userId.contains('-') ? userId.split('-').last : userId;
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(actualUserId)
              .get();
      if (mounted && userDoc.exists) {
        setState(() {
          _matchedUserName = userDoc['name'] as String?;
        });
      }
    } catch (e, stack) {
      debugPrint('Error fetching matched user: $e\n$stack');
    }
  }

  @override
  void dispose() {
    // _matchTimer?.cancel(); // _matchTimer was unused
    _eventSubscription?.cancel();
    _matchSubscription?.cancel();
    _feedbackTimer?.cancel();
    _countdownTimer?.cancel();

    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
  }

  void _checkEventStatus() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _eventHasStarted = now.isAfter(widget.event.startTime);
      });
    }
  }

  Future<void> _loadFeedbackUsers() async {
    if (_userGroup == null || FirebaseAuth.instance.currentUser == null) return;

    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final currentUserDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();

    final currentUserGender = currentUserDoc['gender'] as String? ?? 'unknown';

    // Filter users of opposite gender in the same group
    final oppositeGender =
        currentUserGender.toLowerCase() == 'male' ? 'female' : 'male';

    final users = await Future.wait(
      _userGroup!.members.map((userId) async {
        if (userId == currentUserId) return null;

        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();

        final userData = userDoc.data();
        final gender = userData?['gender'] as String? ?? 'unknown';

        return gender.toLowerCase() == oppositeGender
            ? {
              'id': userId,
              'name': userData?['name'] ?? 'Unknown User',
              'photoURL': userData?['photoURL'] as String?,
              'rating': 0, // Initial rating
            }
            : null;
      }),
    );

    setState(() {
      _feedbackUsers = users.whereType<Map<String, dynamic>>().toList();
    });
  }

  Future<Map<String, dynamic>> _fetchCheckInStatus() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('checkins')
          .doc('$eventId-$userId');
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

  Future<void> _fetchData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;
    try {
      await _fetchUserGroup();
      final results = await Future.wait([
        _fetchCheckInStatus(),
        FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .collection('applicants')
            .doc(userId)
            .get(),
        FirebaseFirestore.instance
            .collection('event_matches')
            .doc(eventId)
            .collection('matches')
            .doc(userId)
            .get(),
        FirebaseFirestore.instance.collection('events').doc(eventId).get(),
        FirebaseFirestore.instance
            .collection('feedback')
            .where('eventId', isEqualTo: eventId)
            .where('fromUser', isEqualTo: userId)
            .limit(1)
            .get(),
      ]);

      final checkinData = results[0] as Map<String, dynamic>;
      final applicantDoc = results[1] as DocumentSnapshot;
      final matchDoc = results[2] as DocumentSnapshot;
      final eventDoc = results[3] as DocumentSnapshot;

      final eventData = eventDoc.data() as Map<String, dynamic>? ?? {};
      final matchesReleasedOnEvent = eventData['matchesReleased'] ?? false;

      // Improved questionnaire ID extraction
      List<String> questionnaireIds = [];
      if (eventData.containsKey('questionnaire')) {
        final dynamic q = eventData['questionnaire'];
        if (q is List) {
          // Handle both string IDs and DocumentReference objects
          questionnaireIds =
              q.map((e) {
                if (e is DocumentReference) {
                  return e.id; // Extract ID from reference
                } else {
                  return e.toString(); // Convert to string
                }
              }).toList();
        }
      } else {
        // Use widget's questionnaire as fallback
        questionnaireIds = widget.event.questionnaire;
      }

      // Log questionnaire info for debugging
      debugPrint('Questionnaire IDs: $questionnaireIds');
      debugPrint('Questionnaire count: ${questionnaireIds.length}');

      QuerySnapshot? questionsSnapshot;
      if (questionnaireIds.isNotEmpty) {
        try {
          // Fetch questions using document IDs
          questionsSnapshot =
              await FirebaseFirestore.instance
                  .collection('questionmodels')
                  .where(FieldPath.documentId, whereIn: questionnaireIds)
                  .get();

          debugPrint('Fetched ${questionsSnapshot.docs.length} questions');
        } catch (e) {
          debugPrint('Error fetching questions: $e');
          // Try fetching without "whereIn" if too many IDs
          if (e.toString().contains('too many')) {
            questionsSnapshot =
                await FirebaseFirestore.instance
                    .collection('questionmodels')
                    .get();
            _cachedQuestions =
                questionsSnapshot.docs
                    .where((doc) => questionnaireIds.contains(doc.id))
                    .map((q) => QuestionModel.fromFirestore(q))
                    .toList();
          }
        }
      }

      if (questionsSnapshot != null) {
        _cachedQuestions =
            questionsSnapshot.docs
                .map((q) => QuestionModel.fromFirestore(q))
                .toList();
      } else {
        _cachedQuestions = [];
      }
      final feedbackQuery = results[4] as QuerySnapshot;
      if (mounted) {
        setState(() {
          _isCheckedIn = checkinData['isCheckedIn'] ?? false;
          _checkInTime = checkinData['checkInTime'] as DateTime?;
          _hasSubmittedFeedback = feedbackQuery.docs.isNotEmpty;

          if (applicantDoc.exists) {
            final data = applicantDoc.data() as Map<String, dynamic>?;
            if (data != null && data['answers'] != null) {
              _existingAnswers = data['answers'] as Map<String, dynamic>;
              _hasSubmittedAnswers = true;
            }
          }

          if (matchDoc.exists) {
            _matchData = matchDoc;
          } else {
            _matchData = null;
          }

          _matchReleased = matchesReleasedOnEvent;
          _checkEventStatus();
          _isLoading = false;
        });

        if (_userGroup != null) {
          _scheduleFeedback();
        }
      }

      // Fetch matched user name if needed
      if (matchDoc.exists) {
        final matchUser = matchDoc['matchedWith'] as String?;
        if (matchUser != null && matchUser.isNotEmpty) {
          await _fetchMatchedUserName(matchUser);
        }
      }
    } catch (e, stack) {
      debugPrint('Error in _fetchData: $e\n$stack');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading data: ${e.toString()}',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    if (mounted) setState(() => _isLoading = true);
    await _fetchData();
  }

  Widget _buildAnswerDisplay(QuestionModel q) {
    final answer = _existingAnswers?[q.id]?.toString() ?? 'Not answered';
    String displayText;
    IconData icon = Icons.help_outline;
    Color color = Colors.pinkAccent;

    switch (q.type) {
      case QuestionType.scale:
        displayText = '$answer (${q.scaleMin}-${q.scaleMax})';
        icon = Icons.slideshow_rounded;
        break;
      case QuestionType.multipleChoice:
        displayText = answer;
        icon = Icons.radio_button_checked;
        break;
      case QuestionType.multiSelect:
        final answers =
            _existingAnswers?[q.id] is List
                ? List<String>.from(_existingAnswers?[q.id] ?? [])
                : [];
        displayText = answers.join(', ');
        icon = Icons.check_box;
        break;
      case QuestionType.openText:
      default:
        displayText = answer;
        icon = Icons.text_fields_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  q.text,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    // color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            width: double.infinity,
            child: Text(
              displayText,
              style: GoogleFonts.raleway(color: Colors.grey[300], fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // Improved Form Fields
  Widget _buildAnswerField(QuestionModel q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("*", style: TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  q.text,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildQuestionInputField(q),
        ],
      ),
    );
  }

  Widget _buildGroupSection() {
    if (_userGroup == null) {
      return const SizedBox.shrink();
    }

    if (_userGroup!.members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          "No members found in this group",
          style: GoogleFonts.raleway(
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group, size: 26, color: Colors.blue),
                const SizedBox(width: 12),
                Text(
                  "Your Group",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_timeRemaining != null && _timeRemaining! > Duration.zero)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      "Interaction ends in: ${_formatDuration(_timeRemaining!)}",
                      style: GoogleFonts.raleway(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            if (_showFeedback && _feedbackUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child:
                    _hasSubmittedFeedback
                        ? ElevatedButton.icon(
                          icon: const Icon(Icons.check, size: 20),
                          label: const Text("Feedback Submitted"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: null, // Disabled button
                        )
                        : ElevatedButton(
                          onPressed: () {
                            // Scroll to feedback section
                            Scrollable.ensureVisible(
                              context,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pinkAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Rate Group Members"),
                        ),
              ),
            const SizedBox(height: 16),

            Text(
              _userGroup!.name,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Group Members:",
              style: GoogleFonts.raleway(
                fontWeight: FontWeight.w500,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            ..._groupMembers.map(
              (member) => ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      member['photoURL'] != null
                          ? NetworkImage(member['photoURL']!)
                          : null,
                  child:
                      member['photoURL'] == null
                          ? Text(member['name'][0])
                          : null,
                ),
                title: Text(member['name']),
              ),
            ),
            // ..._userGroup!.members
            //     .map(
            //       (memberId) => FutureBuilder<DocumentSnapshot>(
            //         future:
            //             FirebaseFirestore.instance
            //                 .collection('users')
            //                 .doc(memberId)
            //                 .get(),
            //         builder: (context, snapshot) {
            //           if (snapshot.connectionState == ConnectionState.waiting) {
            //             return ListTile(
            //               leading: const CircleAvatar(
            //                 child: CircularProgressIndicator(),
            //               ),
            //               title: Text('Loading...'),
            //             );
            //           }

            //           if (!snapshot.hasData || !snapshot.data!.exists) {
            //             return ListTile(
            //               leading: const CircleAvatar(
            //                 child: Icon(Icons.person),
            //               ),
            //               title: const Text('Unknown Member'),
            //               subtitle: Text('ID: $memberId'),
            //             );
            //           }

            //           final userData =
            //               snapshot.data!.data() as Map<String, dynamic>?;
            //           return ListTile(
            //             leading: CircleAvatar(
            //               backgroundImage:
            //                   userData?['photoURL'] != null
            //                       ? NetworkImage(userData!['photoURL'])
            //                       : null,
            //               child:
            //                   userData?['photoURL'] == null
            //                       ? Text(userData?['name']?[0] ?? '?')
            //                       : null,
            //             ),
            //             title: Text(userData?['name'] ?? 'Unknown Member'),
            //           );
            //         },
            //       ),
            //     )
            //     .toList(),
            const SizedBox(height: 12),
            Text(
              "Group created: ${DateFormat('MMM d, h:mm a').format(_userGroup!.createdAt)}",
              style: GoogleFonts.raleway(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionInputField(QuestionModel q) {
    switch (q.type) {
      case QuestionType.scale:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate((q.scaleMax! - q.scaleMin! + 1), (index) {
                final value = q.scaleMin! + index;
                bool isSelected = _answers[q.id] == value;
                return ChoiceChip(
                  label: Text('$value'),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _answers[q.id] = value);
                  },
                  selectedColor: Colors.purple,
                  labelStyle: GoogleFonts.raleway(
                    color: isSelected ? Colors.white : Colors.grey[300],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${q.scaleMin}',
                  style: GoogleFonts.raleway(color: Colors.grey[400]),
                ),
                Text(
                  '${q.scaleMax}',
                  style: GoogleFonts.raleway(color: Colors.grey[400]),
                ),
              ],
            ),
          ],
        );

      case QuestionType.multipleChoice:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              q.options!.map((option) {
                bool isSelected = _answers[q.id] == option;
                return ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _answers[q.id] = option);
                  },
                  selectedColor: Colors.purple,
                  labelStyle: GoogleFonts.raleway(
                    color: isSelected ? Colors.white : Colors.grey[300],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }).toList(),
        );

      case QuestionType.multiSelect:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              q.options!.map((option) {
                List<dynamic> currentAnswers =
                    _answers[q.id] is List ? List.from(_answers[q.id]!) : [];
                bool isSelected = currentAnswers.contains(option);
                return FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        currentAnswers.add(option);
                      } else {
                        currentAnswers.remove(option);
                      }
                      _answers[q.id] = currentAnswers;
                    });
                  },
                  selectedColor: Colors.purple,
                  labelStyle: GoogleFonts.raleway(
                    color: isSelected ? Colors.white : Colors.grey[300],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }).toList(),
        );

      case QuestionType.openText:
      default:
        return TextFormField(
          decoration: InputDecoration(
            hintText: "Type your answer...",
            hintStyle: GoogleFonts.raleway(color: Colors.grey[500]),
            filled: true,
            fillColor: Colors.grey[900],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          style: GoogleFonts.raleway(color: Colors.white, fontSize: 15),
          maxLines: 3,
          minLines: 1,
          onChanged: (val) => _answers[q.id] = val,
        );
    }
  }

  // Improved Questions Section
  Widget _buildQuestionsSection() {
    if (_cachedQuestions == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );
    }

    final questions = _cachedQuestions!;
    if (questions.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 24, color: Colors.blue.shade400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "No specific questions for this event.",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz_outlined, size: 26, color: Colors.purple),
                const SizedBox(width: 12),
                Text(
                  "Event Questions",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    // color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey[700]),
            const SizedBox(height: 20),

            if (_isCheckedIn && _checkInTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade500,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Checked in at ${DateFormat('h:mm a').format(_checkInTime!)}",
                      style: GoogleFonts.raleway(
                        color: Colors.green.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            if (_hasSubmittedAnswers)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade500,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "You've submitted your answers",
                            style: GoogleFonts.poppins(
                              color: Colors.green.shade500,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...questions.map((q) => _buildAnswerDisplay(q)),
                ],
              )
            else if (_isCheckedIn)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text(
                      "Please answer these questions to help with matchmaking:",
                      style: GoogleFonts.raleway(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...questions.map((q) => _buildAnswerField(q)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        // Validate answers
                        bool allValid = true;
                        for (final q in _cachedQuestions!) {
                          if (!_isAnswerValid(q, _answers[q.id])) {
                            allValid = false;
                            break;
                          }
                        }

                        if (!allValid) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Please answer all questions",
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              backgroundColor: Colors.orangeAccent,
                            ),
                          );
                          return;
                        }

                        setState(() => _isLoading = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('events')
                              .doc(widget.event.id)
                              .collection('applicants')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .update({'answers': _answers});

                          setState(() {
                            _hasSubmittedAnswers = true;
                            _existingAnswers = Map<String, dynamic>.from(
                              _answers,
                            );
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Answers submitted successfully!",
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Failed to submit answers: $e",
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 56),
                        textStyle: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 3,
                      ),
                      child: const Text("Submit Answers"),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade400,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Please check in to answer event questions.",
                        style: GoogleFonts.raleway(
                          color: Colors.blue.shade400,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackSection() {
    if (!_showFeedback || _feedbackUsers.isEmpty || _hasSubmittedFeedback) {
      return SizedBox();
    }

    return Card(
      elevation: 3,
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 26,
                  color: Colors.blueAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  // Wrap with Expanded
                  child: Text(
                    "Group Interaction Feedback",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Rate participants you connected with during the group activity:",
              style: GoogleFonts.raleway(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),

            if (_feedbackSubmitted)
              Column(
                children: [
                  const SizedBox(height: 20),
                  Icon(Icons.favorite, size: 64, color: Colors.pinkAccent),
                  const SizedBox(height: 16),
                  Text(
                    "Hearts Sent!",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your appreciation has been shared",
                    style: GoogleFonts.raleway(
                      fontSize: 16,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              )
            else
              Column(
                children: [
                  ..._feedbackUsers.map((user) => _buildFeedbackItem(user)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.pinkAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Submit Feedback"),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackItem(Map<String, dynamic> user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
        child: user['photoURL'] == null ? Text(user['name'][0]) : null,
      ),
      title: Text(user['name']),
      trailing: RatingBar.builder(
        initialRating: user['rating'].toDouble(),
        minRating: 1,
        maxRating: 5,
        direction: Axis.horizontal,
        allowHalfRating: false,
        itemCount: 5,
        itemSize: 30,
        itemBuilder:
            (context, _) => Icon(
              Icons.favorite,
              color: Colors.pinkAccent, // Filled heart color
            ),
        unratedColor: Colors.grey[600], // Unfilled heart color
        onRatingUpdate: (rating) {
          setState(() {
            user['rating'] = rating.toInt();
          });
        },
      ),
    );
  }

  Widget _buildMatchRevealSection() {
    if (!_eventHasStarted) {
      // Don't show match section if event hasn't started
      return const SizedBox.shrink();
    }

    // Get released status from event document first (_matchReleased)
    // Then check individual match document's released status if available
    final isUserMatchReleased =
        _matchData?.exists == true
            ? (_matchData!.data() as Map<String, dynamic>?)?.containsKey(
                      'released',
                    ) ==
                    true
                ? _matchData!.get('released') ?? false
                : false
            : false;

    // Case 1: Matches not released yet by admin OR user's specific match not released
    if (!_matchReleased || !isUserMatchReleased) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                Icons.hourglass_empty_rounded,
                size: 24,
                color: Colors.orange.shade400,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Match results will be available soon!",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Case 2: User has no match document at all (could happen if listener fires late or error)
    if (_matchData == null || !_matchData!.exists) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                "No match information available",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find match data for your account for this event.",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final matchDocData = _matchData!.data() as Map<String, dynamic>;
    final matchedWithId = matchDocData['matchedWith'] as String? ?? '';

    if (matchedWithId.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.people_alt_outlined, size: 48, color: Colors.blueGrey),
              const SizedBox(height: 16),
              Text(
                "No match this time",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find a match for you this event. Enjoy meeting new people!",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final matchedWithIdRaw = matchDocData['matchedWith'] as String? ?? '';
    final actualMatchedUserId =
        matchedWithIdRaw.contains('-')
            ? matchedWithIdRaw.split('-').last
            : matchedWithIdRaw;
    final isMatched = actualMatchedUserId.isNotEmpty;
    final matchReason =
        matchDocData['reason'] as String? ??
        'Shared interests and preferences!';

    // Case 3: User is unmatched (matchedWithId is empty)
    if (!isMatched) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.sentiment_dissatisfied_outlined,
                size: 48,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                "No match found this time",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find a suitable match for you at this event. Enjoy meeting everyone!",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (matchedWithId.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.people_alt_outlined, size: 48, color: Colors.blueGrey),
              const SizedBox(height: 16),
              Text(
                "No match this time",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find a match for you this event. Enjoy meeting new people!",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Case 4: User has a valid match
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Your Match!",
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.pinkAccent,
              ),
            ),
            const SizedBox(height: 20),
            FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(actualMatchedUserId)
                      .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircleAvatar(
                    radius: 52,
                    backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                    child: const CircularProgressIndicator(
                      color: Colors.pinkAccent,
                    ),
                  );
                }

                final userDoc = snapshot.data;
                String? photoURL;
                String displayName = 'Your Match';

                if (userDoc != null && userDoc.exists) {
                  final data = userDoc.data() as Map<String, dynamic>? ?? {};
                  photoURL =
                      data['photoURL']
                          as String?; // Ensure correct field name 'photoURL' not 'photoUrl'
                  displayName = data['name'] as String? ?? 'Your Match';
                }

                return Column(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                      backgroundImage:
                          (photoURL != null && photoURL.isNotEmpty)
                              ? NetworkImage(photoURL)
                              : null,
                      child:
                          (photoURL == null || photoURL.isEmpty)
                              ? Icon(
                                Icons.person_rounded,
                                size: 52,
                                color: Colors.pinkAccent.shade100,
                              )
                              : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.message_rounded, size: 20),
                      label: const Text("Send Message"),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ChatPage(
                                  matchedUserId: actualMatchedUserId,
                                  matchedUserName: displayName,
                                ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.pinkAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.pinkAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "Why you were matched:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.pinkAccent.shade100,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    matchReason,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.raleway(
                      color: Colors.grey[300],
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? backgroundColor, // Changed from color to backgroundColor for clarity
    Color? textColor,
    Color? iconColor,
  }) {
    bool isEnabled = onTap != null;
    Color currentBgColor =
        isEnabled ? (backgroundColor ?? Colors.purple) : Colors.grey[700]!;
    Color currentTextColor = textColor ?? Colors.white;
    Color currentIconColor = iconColor ?? Colors.white;

    return ElevatedButton.icon(
      icon: Icon(
        icon,
        color: currentIconColor.withValues(alpha: isEnabled ? 1.0 : 0.7),
      ),
      label: Text(
        label,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: currentBgColor,
        foregroundColor: currentTextColor,
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        disabledBackgroundColor:
            Colors.grey[800], // More distinct disabled state
        disabledForegroundColor: Colors.grey[500],
      ),
    );
  }

  Widget _buildMatchAnalysisSection() {
    if (_matchData != null &&
        _matchData!.exists &&
        (_matchData!.data() as Map<String, dynamic>)['matchedWith']?.isEmpty ==
            true) {
      return SizedBox.shrink();
    }

    final isReleased = _matchReleased && _isUserMatchReleased();

    if (!isReleased || _matchData == null || !_matchData!.exists) {
      return SizedBox.shrink();
    }

    return Card(
      elevation: 3,
      margin: EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Your Match Analysis",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            FutureBuilder<Map<String, dynamic>>(
              future: _fetchMatchAnalysisData(),
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!;
                final categoryScores =
                    data['categoryScores'] as Map<String, dynamic>? ?? {};
                final commonInterests = data['commonInterests'] ?? 0;
                final compatibilityScore = data['compatibilityScore'] ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Compatibility Score Card
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Overall Compatibility",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: compatibilityScore / 100,
                            minHeight: 20,
                            borderRadius: BorderRadius.circular(10),
                            backgroundColor: Colors.grey[700],
                            color:
                                compatibilityScore > 75
                                    ? Colors.green
                                    : compatibilityScore > 50
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "${compatibilityScore.toStringAsFixed(0)}% Match",
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color:
                                  compatibilityScore > 75
                                      ? Colors.green
                                      : compatibilityScore > 50
                                      ? Colors.orange
                                      : Colors.red,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "$commonInterests shared interests",
                            style: GoogleFonts.raleway(
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Compatibility Insights
                    Text(
                      "Compatibility Insights:",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Text(
                        data['insights'] ?? "No insights available",
                        style: GoogleFonts.raleway(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Category Breakdown Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Compatibility Breakdown",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          "Score",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Category Scores
                    if (categoryScores.isNotEmpty)
                      ..._buildCategoryScoreRows(categoryScores)
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            "No category data available",
                            style: GoogleFonts.raleway(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Shared Interests
                    if (commonInterests > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Shared Interests:",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[700]!),
                            ),
                            child: Text(
                              data['sharedInterestDetails'] ??
                                  "No specific shared interests identified",
                              style: GoogleFonts.raleway(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Update to return more detailed information
  // Update to return more detailed information
  Future<Map<String, dynamic>> _generateMatchAnalysis(
    String userId,
    String eventId,
  ) async {
    final random = Random();
    final db = FirebaseFirestore.instance;

    // Get user answers
    final userAnswersDoc =
        await db
            .collection('events')
            .doc(eventId)
            .collection('applicants')
            .doc(userId)
            .get();

    if (!userAnswersDoc.exists) {
      return _generateRandomMatchAnalysis(random);
    }

    final userAnswers =
        userAnswersDoc.data()?['answers'] as Map<String, dynamic>? ?? {};

    // Get match ID
    final matchDoc =
        await db
            .collection('event_matches')
            .doc(eventId)
            .collection('matches')
            .doc(userId)
            .get();

    if (!matchDoc.exists) {
      return _generateRandomMatchAnalysis(random);
    }

    final matchUserId = matchDoc['matchedWith'] as String?;
    if (matchUserId == null || matchUserId.isEmpty) {
      return _generateRandomMatchAnalysis(random);
    }

    // Get match answers
    final matchAnswersDoc =
        await db
            .collection('events')
            .doc(eventId)
            .collection('applicants')
            .doc(matchUserId)
            .get();

    final matchAnswers =
        matchAnswersDoc.data()?['answers'] as Map<String, dynamic>? ?? {};

    // Get questions
    final questions = _cachedQuestions ?? [];

    // Analyze by category
    Map<String, double> categoryScores = {};
    List<String> allCommonInterests = []; // Changed to List<String>

    for (final question in questions) {
      final userAnswer = userAnswers[question.id];
      final matchAnswer = matchAnswers[question.id];

      if (userAnswer == null || matchAnswer == null) continue;

      // final category = (question.category ?? 'general').toString();
      final category = question.category.toString();

      // Initialize category data
      categoryScores.putIfAbsent(category, () => 0.0);

      // Calculate similarity based on question type
      double similarity = 0;

      switch (question.type) {
        case QuestionType.scale:
          if (userAnswer is num && matchAnswer is num) {
            final maxDiff = question.scaleMax! - question.scaleMin!;
            final diff = (userAnswer - matchAnswer).abs();
            similarity = (1 - (diff / maxDiff)) * 100;
          }
          break;

        case QuestionType.multipleChoice:
          if (userAnswer == matchAnswer) {
            similarity = 100;
            allCommonInterests.add(userAnswer.toString());
          }
          break;

        case QuestionType.multiSelect:
          if (userAnswer is List && matchAnswer is List) {
            final userList = (userAnswer).map((e) => e.toString()).toList();
            final matchList = (matchAnswer).map((e) => e.toString()).toList();

            final userSet = Set<String>.from(userList);
            final matchSet = Set<String>.from(matchList);
            final common = userSet.intersection(matchSet);
            similarity =
                (common.length / max(userSet.length, matchSet.length)) * 100;
            allCommonInterests.addAll(common);
          }
          break;

        case QuestionType.openText:
        default:
          // Skip text similarity for now
          similarity = 0;
      }

      // Update category score
      categoryScores[category] = categoryScores[category]! + similarity;
    }

    // Calculate average category scores
    for (final category in categoryScores.keys) {
      final questionsInCategory =
          questions
              // .where((q) => (q.category ?? 'general').toString() == category)
              .where((q) => q.category.toString() == category)
              .length;
      if (questionsInCategory > 0) {
        categoryScores[category] =
            categoryScores[category]! / questionsInCategory;
      }
    }

    // Calculate overall compatibility score
    final compatibilityScore =
        categoryScores.values.isEmpty
            ? random.nextInt(40) + 60
            : categoryScores.values.reduce((a, b) => a + b) /
                categoryScores.length;

    // Generate insights - CORRECTED CALL
    final insights = _generateInsightsFromCategories(
      categoryScores,
      allCommonInterests,
    );

    return {
      'commonInterests': allCommonInterests.length,
      'sharedInterestDetails': allCommonInterests.take(5).join(', '),
      'compatibilityScore': compatibilityScore.clamp(0, 100),
      'insights': insights,
      'categoryScores': categoryScores,
    };
  }

  List<Widget> _buildCategoryScoreRows(Map<String, dynamic> categoryScores) {
    final List<MapEntry<String, dynamic>> sortedCategories =
        categoryScores.entries.toList()
          ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return sortedCategories.map((entry) {
      final category = entry.key;
      final rawScore = entry.value as double;
      final score = rawScore.clamp(0, 100);

      String displayName;
      IconData icon;
      Color color;

      // Normalize category name by converting to lowercase and removing spaces
      final normalizedCategory = category.toLowerCase().replaceAll(' ', '');

      switch (normalizedCategory) {
        case 'corevalues':
        case 'questioncategory.corevalues': // Handle full enum name
          displayName = "Core Values";
          icon = Icons.psychology_outlined;
          color = Colors.orange;
          break;
        case 'goals':
        case 'questioncategory.goals':
          displayName = "Life Goals";
          icon = Icons.flag_outlined;
          color = Colors.green;
          break;
        case 'interests':
        case 'questioncategory.interests':
          displayName = "Interests";
          icon = Icons.interests_outlined;
          color = Colors.purple;
          break;
        case 'personality':
        case 'questioncategory.personality':
          displayName = "Personality";
          icon = Icons.person_outline;
          color = Colors.pink;
          break;
        case 'dealbreakers':
        case 'questioncategory.dealbreakers':
          displayName = "Dealbreakers";
          icon = Icons.gpp_good_outlined;
          color = Colors.blue;
          break;
        default:
          // Handle other cases with formatting
          displayName =
              category
                  .replaceAll('QuestionCategory.', '')
                  .replaceAllMapped(
                    RegExp(r'[A-Z]'),
                    (match) => ' ${match.group(0)}',
                  )
                  .trim();
          icon = Icons.category_outlined;
          color = Colors.grey;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                displayName,
                style: GoogleFonts.raleway(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                backgroundColor: Colors.grey[700],
                color:
                    score > 75
                        ? Colors.green
                        : score > 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "${score.toStringAsFixed(0)}%",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color:
                    score > 75
                        ? Colors.green
                        : score > 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _fetchMatchAnalysisData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;

    try {
      // Fetch compatibility data from Firestore
      final doc =
          await FirebaseFirestore.instance
              .collection('match_analysis')
              .doc(eventId)
              .collection('reports')
              .doc(userId)
              .get();

      if (doc.exists) {
        return doc.data() ?? {};
      }

      // Generate report if doesn't exist
      return await _generateMatchAnalysis(userId, eventId);
    } catch (e) {
      debugPrint('Error fetching analysis: $e');
      return {};
    }
  }

  // Update the _generateInsightsFromCategories method
  String _generateInsightsFromCategories(
    Map<String, double> categoryScores,
    List<String> commonInterests, // Changed parameter name
  ) {
    if (categoryScores.isEmpty) {
      return "You share similar values in relationships and enjoy common activities.";
    }

    // Find strongest and weakest categories
    String strongestCategory = '';
    double strongestScore = 0;
    String weakestCategory = '';
    double weakestScore = 100;

    categoryScores.forEach((category, score) {
      if (score > strongestScore) {
        strongestScore = score;
        strongestCategory = category;
      }
      if (score < weakestScore) {
        weakestScore = score;
        weakestCategory = category;
      }
    });

    // Generate insights based on categories
    final insights = StringBuffer();

    // Strongest category insights
    switch (strongestCategory) {
      case 'dealbreakers':
        insights.writeln(
          "You align perfectly on fundamental values and dealbreakers.",
        );
        break;
      case 'interests':
        insights.writeln("You share many common interests and hobbies.");
        break;
      case 'goals':
        insights.writeln(
          "Your life goals and relationship expectations are well-matched.",
        );
        break;
      case 'coreValues':
        insights.writeln("Your core values and beliefs are highly compatible.");
        break;
      case 'personality':
        insights.writeln(
          "Your personalities complement each other extremely well.",
        );
        break;
      default:
        insights.writeln("You have strong compatibility in key areas.");
    }

    // Add specific common interests if available
    if (commonInterests.isNotEmpty) {
      // Use commonInterests directly
      insights.write("You both like: ");
      insights.write(commonInterests.take(3).join(', '));
      insights.writeln(".");
    }

    // Weakest category insights
    if (weakestScore < 50 && weakestCategory.isNotEmpty) {
      insights.write("\nYou might have differences in ");

      switch (weakestCategory) {
        case 'dealbreakers':
          insights.write("fundamental values");
          break;
        case 'interests':
          insights.write("hobbies and interests");
          break;
        case 'goals':
          insights.write("long-term goals");
          break;
        case 'coreValues':
          insights.write("core beliefs");
          break;
        case 'personality':
          insights.write("personality traits");
          break;
        default:
          insights.write("some areas");
      }

      insights.write(", which could lead to interesting conversations!");
    }

    return insights.toString();
  }

  Map<String, dynamic> _generateRandomMatchAnalysis(Random random) {
    return {
      'userScore': random.nextInt(70) + 30,
      'matchScore': random.nextInt(70) + 30,
      'eventAvg': random.nextInt(40) + 40,
      'commonInterests': random.nextInt(5) + 1,
      'compatibilityScore': random.nextInt(40) + 60,
      'insights':
          "You share similar values in relationships and enjoy outdoor activities. "
          "Your communication styles complement each other well.",
      'categoryScores': {
        'dealbreakers': random.nextInt(40) + 60,
        'interests': random.nextInt(40) + 60,
        'goals': random.nextInt(40) + 60,
        'coreValues': random.nextInt(40) + 60,
        'personality': random.nextInt(40) + 60,
      },
    };
  }

  Widget _buildEventHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // color: Colors.grey[850], // Dark card color
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.title,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.pinkAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat(
                    'EEEE, MMM d • h:mm a',
                  ).format(widget.event.startTime),
                  style: GoogleFonts.raleway(
                    // color: Colors.white12,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: Colors.pinkAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget
                      .event
                      .locationType, // Assuming locationType is a simple string
                  style: GoogleFonts.raleway(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitleStyle = GoogleFonts.poppins(fontWeight: FontWeight.bold);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
          "Event Actions",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
          elevation: 0,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ui.Color.fromARGB(100, 255, 249, 136),
                ui.Color.fromARGB(100, 158, 126, 249),
                ui.Color.fromARGB(100, 104, 222, 245),
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.pinkAccent),
          ),
        ),
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        title: Text(
          "Event Actions",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
         flexibleSpace: ValueListenableBuilder<bool>(
          valueListenable: _scrolledNotifier,
          builder: (context, isScrolled, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient:
                    isScrolled
                        ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.pinkAccent.shade100,
                            Colors.purple,
                            Colors.deepPurple,
                          ],
                        )
                        : null,
              ),
            );
          },
        ),
        actions: [
          // Add chat icon button here
          if (_eventHasStarted && _isCheckedIn)
            IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            EventChatPage(event: widget.event, isHost: false),
                  ),
                );
              },
              tooltip: 'Event Chat',
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ui.Color.fromARGB(100, 255, 249, 136),
              ui.Color.fromARGB(100, 158, 126, 249),
              ui.Color.fromARGB(100, 104, 222, 245),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: Colors.pinkAccent,
            // backgroundColor: Colors.grey[850],
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch, // Ensure cards take full width
                children: [
                  _buildEventHeader(),
                  const SizedBox(height: 20),
                  _buildActionButton(
                    _isCheckedIn
                        ? Icons.check_circle_rounded
                        : Icons.qr_code_scanner_rounded,
                    _isCheckedIn
                        ? "Checked In at ${_checkInTime != null ? DateFormat('h:mm a').format(_checkInTime!) : 'Successfully'}"
                        : _eventHasStarted
                        ? "Scan QR to Check In"
                        : "Check-in starts: ${DateFormat('h:mm a').format(widget.event.startTime)}",
                    _eventHasStarted && !_isCheckedIn
                        ? () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      ScanQRPage(eventId: widget.event.id),
                            ),
                          );
                          if (result == true && mounted) {
                            await _refreshData();
                          }
                        }
                        : null,
                    backgroundColor:
                        _isCheckedIn
                            ? Colors.green.shade600
                            : (_eventHasStarted
                                ? Colors.purple
                                : Colors.grey[700]),
                  ),
                  const SizedBox(height: 20),

                  _buildGroupSection(),

                  _buildFeedbackSection(),
                  const SizedBox(height: 20),

                  _buildMatchRevealSection(), // Will be SizedBox.shrink if event not started
                  _buildMatchAnalysisSection(),
                  const SizedBox(height: 24),

                  if (_eventHasStarted)
                    _buildQuestionsSection()
                  else
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.grey[850],
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.hourglass_top_rounded,
                              size: 48,
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Event actions & questions available once the event starts.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Starts at ${DateFormat('EEE, MMM d • h:mm a').format(widget.event.startTime)}",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.raleway(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20), // Bottom padding
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
