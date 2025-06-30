import 'dart:async';
import 'package:app/pages/qr/scan_qr_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../models/question.dart';
// import 'package:app/models/chat.dart'; // Chat model seems unused here, consider removing if not needed
// import 'package:app/services/firestore_service.dart'; // Firestore service seems unused, direct calls are made
import 'package:app/pages/chat/chat_page.dart';

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
  bool _isLoading = true;
  bool _hasSubmittedAnswers = false;
  bool _isCheckedIn = false;
  Map<String, dynamic>? _existingAnswers;
  DocumentSnapshot? _matchData;
  String? _matchedUserName; // This is fetched but seems not directly used for display in match card, name is fetched again there.
  bool _eventHasStarted = false;
  DateTime? _checkInTime;

  // Timer? _matchTimer; // _matchTimer seems unused
  // bool _showMatch = false; // _showMatch seems unused in logic flow for match reveal
  bool _matchReleased = false;

  StreamSubscription<DocumentSnapshot>? _eventSubscription;
  StreamSubscription<DocumentSnapshot>? _matchSubscription;
  List<Question>? _cachedQuestions;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupListeners();
    _checkEventStatus();
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
              _fetchMatchedUserName(matchUser); // Fetches name, useful if needed elsewhere
            }
          });
        }
      } else {
         if (mounted) {
          setState(() {
            _matchData = null; // Ensure _matchData is null if doc doesn't exist
          });
        }
      }
    });
  }

  Future<void> _fetchMatchedUserName(String userId) async {
    try {
      final actualUserId =
          userId.contains('-') ? userId.split('-').last : userId;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(actualUserId).get();
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

  Future<Map<String, dynamic>> _fetchCheckInStatus() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final eventId = widget.event.id;
    try {
      final docRef = FirebaseFirestore.instance.collection('checkins').doc('$eventId-$userId');
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
      final results = await Future.wait([
        _fetchCheckInStatus(),
        FirebaseFirestore.instance.collection('events').doc(eventId).collection('applicants').doc(userId).get(),
        FirebaseFirestore.instance.collection('event_matches').doc(eventId).collection('matches').doc(userId).get(),
        FirebaseFirestore.instance.collection('events').doc(eventId).get(),
        if (widget.event.questionnaire.isNotEmpty)
           FirebaseFirestore.instance.collection('questions').where(FieldPath.documentId, whereIn: widget.event.questionnaire).get()
        else
          Future.value(null), // Handle empty questionnaire
      ]);

      final checkinData = results[0] as Map<String, dynamic>;
      final applicantDoc = results[1] as DocumentSnapshot;
      final matchDoc = results[2] as DocumentSnapshot;
      final eventDoc = results[3] as DocumentSnapshot;
      final questionsSnapshot = results[4] as QuerySnapshot?;


      final eventData = eventDoc.data() as Map<String, dynamic>? ?? {};
      final matchesReleasedOnEvent = eventData['matchesReleased'] ?? false;

      if (questionsSnapshot != null) {
        _cachedQuestions = questionsSnapshot.docs.map((q) => Question.fromDocument(q)).toList();
      } else {
        _cachedQuestions = [];
      }


      if (mounted) {
        setState(() {
          _isCheckedIn = checkinData['isCheckedIn'] ?? false;
          _checkInTime = checkinData['checkInTime'] as DateTime?;

          if (applicantDoc.exists) {
            final data = applicantDoc.data() as Map<String, dynamic>?;
            if (data != null && data['answers'] != null) {
              _existingAnswers = data['answers'] as Map<String, dynamic>;
              _hasSubmittedAnswers = true;
            }
          }

          if (matchDoc.exists) {
            _matchData = matchDoc;
            // _matchedUserName is fetched via listener or here if needed immediately
          } else {
             _matchData = null; // Explicitly set to null if no match doc
          }
          
          _matchReleased = matchesReleasedOnEvent;

          _checkEventStatus();
          _isLoading = false;
        });
      }
      // Redundant fetch if listener is active, but good for initial load
      if (matchDoc.exists) {
        final matchUser = matchDoc['matchedWith'] as String?;
        if (matchUser != null && matchUser.isNotEmpty) {
          await _fetchMatchedUserName(matchUser);
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e', style: GoogleFonts.poppins(color: Colors.white)),
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

  Widget _buildAnswerDisplay(Question q) {
    final answer = _existingAnswers?[q.id]?.toString() ?? 'Not answered';
    String displayText;
    IconData icon = Icons.help_outline;
    Color color = Colors.grey[500]!;
    switch (q.type) {
      case 'selection':
        if (answer == 'agree') {
          displayText = 'Agree';
          icon = Icons.thumb_up_alt_outlined;
          color = Colors.green.shade400;
        } else if (answer == 'disagree') {
          displayText = 'Disagree';
          icon = Icons.thumb_down_alt_outlined;
          color = Colors.red.shade400;
        } else {
          displayText = 'Neutral';
          icon = Icons.thumbs_up_down_outlined;
          color = Colors.orange.shade400;
        }
        break;
      case 'boolean':
        final boolAnswer = answer == 'true';
        displayText = boolAnswer ? 'Yes' : 'No';
        icon = boolAnswer ? Icons.check_circle_outline : Icons.highlight_off_outlined;
        color = boolAnswer ? Colors.green.shade400 : Colors.red.shade400;
        break;
      case 'text':
      default:
        displayText = answer;
        icon = Icons.text_fields_outlined;
        color = Colors.blue.shade400;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        q.title,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.85), fontSize: 15),
      ),
      subtitle: Text(
        displayText,
        style: GoogleFonts.raleway(color: Colors.grey[400], fontSize: 14),
      ),
    );
  }

  Widget _buildAnswerField(Question q) {
     final inputDecoration = InputDecoration(
        labelText: q.title,
        labelStyle: GoogleFonts.raleway(color: Colors.grey[400]),
        border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.grey[700]!)),
        enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.grey[700]!)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.purple)),
        filled: true,
        fillColor: Colors.grey[800],
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      );


    switch (q.type) {
      case 'selection':
        return DropdownButtonFormField<String>(
          decoration: inputDecoration,
          dropdownColor: Colors.grey[800],
          style: GoogleFonts.raleway(color: Colors.white, fontSize: 15),
          items: const [
            DropdownMenuItem<String>(value: 'agree', child: Text('Agree')),
            DropdownMenuItem<String>(value: 'neutral', child: Text('Neutral')),
            DropdownMenuItem<String>(value: 'disagree', child: Text('Disagree')),
          ],
          onChanged: (val) {
            if (val != null) _answers[q.id] = val;
          },
          onSaved: (val) {
            if (val != null) _answers[q.id] = val;
          },
        );
      case 'boolean':
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[700]!)
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(q.title, style: GoogleFonts.raleway(fontSize: 15, color: Colors.white.withOpacity(0.85))),
              ),
              StatefulBuilder(
                builder: (context, setStateSB) {
                  final value = _answers[q.id] as bool? ?? false; // Ensure type
                  return Switch(
                    value: value,
                    onChanged: (val) {
                      setStateSB(() => _answers[q.id] = val);
                    },
                    activeColor: Colors.purple,
                    inactiveTrackColor: Colors.grey[700],
                    inactiveThumbColor: Colors.grey[400],
                  );
                },
              ),
            ],
          ),
        );
      case 'text':
      default:
        return TextFormField(
          decoration: inputDecoration,
          style: GoogleFonts.raleway(color: Colors.white, fontSize: 15),
          onSaved: (val) {
            if (val != null) _answers[q.id] = val;
          },
        );
    }
  }

  Widget _buildQuestionsSection() {
    if (_cachedQuestions == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
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
                    color: Colors.white.withOpacity(0.8),
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
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey[700]),
            const SizedBox(height: 16),

            if (_isCheckedIn && _checkInTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade500, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Checked in at ${DateFormat('h:mm a').format(_checkInTime!)}",
                      style: GoogleFonts.raleway(color: Colors.green.shade500, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            if (_hasSubmittedAnswers)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                     padding: const EdgeInsets.only(bottom:16.0),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade500, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "You've submitted your answers",
                          style: GoogleFonts.raleway(color: Colors.green.shade500, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  ...questions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildAnswerDisplay(q),
                    ),
                  ),
                ],
              )
            else if (_isCheckedIn)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text(
                      "Please answer these questions to help with matchmaking:",
                      style: GoogleFonts.raleway(color: Colors.grey[400], fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    ...questions.map(
                      (q) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildAnswerField(q),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        _formKey.currentState?.save();
                        if (_answers.entries.where((e) => e.value.toString().isNotEmpty).isEmpty) { // Check if any answer is actually provided
                          ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                              content: Text("Please answer at least one question", style: GoogleFonts.poppins(color: Colors.white)),
                              backgroundColor: Colors.orangeAccent,
                            ),
                          );
                          return;
                        }
                        setState(() => _isLoading = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('events').doc(widget.event.id)
                              .collection('applicants').doc(FirebaseAuth.instance.currentUser!.uid)
                              .update({'answers': _answers});
                          setState(() {
                            _hasSubmittedAnswers = true;
                            _existingAnswers = Map<String, dynamic>.from(_answers);
                          });
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                              content: Text("Answers submitted successfully!", style: GoogleFonts.poppins(color: Colors.white)),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Failed to submit answers: $e", style: GoogleFonts.poppins(color: Colors.white)), backgroundColor: Colors.redAccent),
                          );
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Submit Answers"),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade400, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Please check in to answer event questions.",
                        style: GoogleFonts.raleway(color: Colors.blue.shade400, fontWeight: FontWeight.w500, fontSize: 15),
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

  Widget _buildMatchRevealSection() {
     if (!_eventHasStarted) { // Don't show match section if event hasn't started
       return const SizedBox.shrink();
     }

    // Get released status from event document first (_matchReleased)
    // Then check individual match document's released status if available
    final isUserMatchReleased = _matchData?.exists == true ? (_matchData!.data() as Map<String, dynamic>?)?.containsKey('released') == true ? _matchData!.get('released') ?? false : false : false;


    // Case 1: Matches not released yet by admin OR user's specific match not released
    if (!_matchReleased || !isUserMatchReleased) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 24, color: Colors.orange.shade400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Match results will be available soon!",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.8),
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
              Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                "No match information available",
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find match data for your account for this event.",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }


    final matchDocData = _matchData!.data() as Map<String, dynamic>;
    final matchedWithIdRaw = matchDocData['matchedWith'] as String? ?? '';
    final actualMatchedUserId = matchedWithIdRaw.contains('-') ? matchedWithIdRaw.split('-').last : matchedWithIdRaw;
    final isMatched = actualMatchedUserId.isNotEmpty;
    final matchReason = matchDocData['reason'] as String? ?? 'Shared interests and preferences!';


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
              Icon(Icons.sentiment_dissatisfied_outlined, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                "No match found this time",
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find a suitable match for you at this event. Enjoy meeting everyone!",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(color: Colors.grey[500], fontSize: 14),
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
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
            ),
            const SizedBox(height: 20),
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(actualMatchedUserId).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircleAvatar(radius: 52, backgroundColor: Colors.pinkAccent.withOpacity(0.2), child: const CircularProgressIndicator(color: Colors.pinkAccent));
                }

                final userDoc = snapshot.data;
                String? photoUrl;
                String displayName = 'Your Match';

                if (userDoc != null && userDoc.exists) {
                  final data = userDoc.data() as Map<String, dynamic>? ?? {};
                  photoUrl = data['photoURL'] as String?; // Ensure correct field name 'photoURL' not 'photoUrl'
                  displayName = data['name'] as String? ?? 'Your Match';
                }

                return Column(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.pinkAccent.withOpacity(0.2),
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? Icon(Icons.person_rounded, size: 52, color: Colors.pinkAccent.shade100)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
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
                            builder: (context) => ChatPage(
                              matchedUserId: actualMatchedUserId,
                              matchedUserName: displayName,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                color: Colors.pinkAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.pinkAccent.withOpacity(0.3))
              ),
              child: Column(
                children: [
                  Text(
                    "Why you were matched:",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.pinkAccent.shade100, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    matchReason,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.raleway(color: Colors.grey[300], fontSize: 14, height: 1.4),
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
    Color currentBgColor = isEnabled ? (backgroundColor ?? Colors.purple) : Colors.grey[700]!;
    Color currentTextColor = textColor ?? Colors.white;
    Color currentIconColor = iconColor ?? Colors.white;


    return ElevatedButton.icon(
      icon: Icon(icon, color: currentIconColor.withOpacity(isEnabled ? 1.0 : 0.7)),
      label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 15)),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: currentBgColor,
        foregroundColor: currentTextColor,
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        disabledBackgroundColor: Colors.grey[800], // More distinct disabled state
        disabledForegroundColor: Colors.grey[500],
      ),
    );
  }

  Widget _buildEventHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.grey[850], // Dark card color
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.title,
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: Colors.grey[400], size: 16),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM d • h:mm a').format(widget.event.startTime),
                  style: GoogleFonts.raleway(color: Colors.grey[400], fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
             Row(
              children: [
                Icon(Icons.location_on_outlined, color: Colors.grey[400], size: 16),
                const SizedBox(width: 8),
                Text(
                  widget.event.locationType, // Assuming locationType is a simple string
                  style: GoogleFonts.raleway(color: Colors.grey[400], fontSize: 14),
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
     final appBarTitleStyle = GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text("Event Actions", style: appBarTitleStyle),
          backgroundColor: Colors.grey[900],
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("Event Actions", style: appBarTitleStyle),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: Colors.pinkAccent,
        backgroundColor: Colors.grey[850],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Ensure cards take full width
            children: [
              _buildEventHeader(),
              const SizedBox(height: 20),
              _buildActionButton(
                _isCheckedIn ? Icons.check_circle_rounded : Icons.qr_code_scanner_rounded,
                _isCheckedIn
                    ? "Checked In at ${_checkInTime != null ? DateFormat('h:mm a').format(_checkInTime!) : 'Successfully'}"
                    : _eventHasStarted
                        ? "Scan QR to Check In"
                        : "Check-in starts: ${DateFormat('h:mm a').format(widget.event.startTime)}",
                _eventHasStarted && !_isCheckedIn
                    ? () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ScanQRPage(eventId: widget.event.id)),
                        );
                        if (result == true && mounted) {
                          await _refreshData();
                        }
                      }
                    : null,
                backgroundColor: _isCheckedIn ? Colors.green.shade600 : (_eventHasStarted ? Colors.purple : Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              
              _buildMatchRevealSection(), // Will be SizedBox.shrink if event not started
              
              const SizedBox(height: 24),

              if (_eventHasStarted)
                _buildQuestionsSection()
              else
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  color: Colors.grey[850],
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 48, color: Colors.orange.shade600),
                        const SizedBox(height: 16),
                        Text(
                          "Event actions & questions available once the event starts.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Starts at ${DateFormat('EEE, MMM d • h:mm a').format(widget.event.startTime)}",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.raleway(color: Colors.grey[500], fontSize: 14),
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
    );
  }
}