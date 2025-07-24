import 'package:app/bloc/event/event_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../bloc/eventdetail/eventdetail_bloc.dart';
import '../../models/event.dart';
import '../../models/question.dart';
import '../../services/firestore_service.dart';
import '../qr/scan_qr_page.dart';

class AcceptedEventDetailPage extends StatelessWidget {
  final Event event;
  const AcceptedEventDetailPage({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    return BlocProvider(
      create: (context) => EventdetailBloc(
        firestoreService: FirestoreService(),
        event: event,
        userId: userId,
      )..add(LoadEventDetail(event: event)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Event Actions",
            style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
          ),
        ),
        body: BlocConsumer<EventdetailBloc, EventdetailState>(
          listener: (context, state) {
            if (state is EventdetailError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is EventDetailLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (state is EventdetailError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    state.message,
                    style: GoogleFonts.raleway(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            
            if (state is EventdetailLoaded) {
              return _buildBody(context, state);
            }
            
            return Container();
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EventdetailLoaded state) {
    final bloc = BlocProvider.of<EventdetailBloc>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEventHeader(state.event),
            const SizedBox(height: 20),
            _buildCheckInButton(context, bloc, state),
            const SizedBox(height: 12),
            _buildMatchRevealSection(context, state),
            const SizedBox(height: 24),
            _buildQuestionsSection(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildEventHeader(Event event) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: GoogleFonts.raleway(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('EEEE, MMM d • h:mm a').format(event.startTime),
              style: GoogleFonts.raleway(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              event.locationType,
              style: GoogleFonts.raleway(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  // Added context parameter here
  Widget _buildCheckInButton(BuildContext context, EventdetailBloc bloc, EventdetailLoaded state) {
    return ElevatedButton.icon(
      icon: Icon(
        Icons.qr_code_scanner,
        color: state.isCheckedIn ? Colors.white : Colors.white,
      ),
      label: Text(
        state.isCheckedIn
            ? "Checked In at ${state.checkInTime != null ? DateFormat('h:mm a').format(state.checkInTime!) : ''}"
            : state.eventHasStarted
                ? "Scan QR to Check In"
                : "Check-in available at ${DateFormat('h:mm a').format(state.event.startTime)}",
      ),
      onPressed: state.eventHasStarted && !state.isCheckedIn
          ? () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScanQRPage(eventId: state.event.id),
                ),
              );
              if (result == true) {
                bloc.add(EventDetailRefresh(event: state.event));
              }
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: state.isCheckedIn
            ? Colors.green
            : state.eventHasStarted
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }

  // Added context parameter here
  Widget _buildMatchRevealSection(BuildContext context, EventdetailLoaded state) {
    // Show loading indicator while initializing
    if (state.matchData == null) {
      return _buildActionButton(
        context, // Pass context here
        Icons.favorite,
        "Match result not available yet",
        null,
        color: Colors.grey,
      );
    }

    // Get released status from match document
    final isMatchReleased = state.matchData?.exists == true
        ? state.matchData!.get('released') ?? false
        : false;

    // Extract match data if document exists
    final hasDirectMatch = state.matchData!.exists;

    // Properly extract matchedWith ID
    final matchedWithId = hasDirectMatch
        ? state.matchData!.get('matchedWith') as String? ?? ''
        : '';

    // Extract only the user ID part after the prefix
    final actualMatchedUserId = matchedWithId.contains('-')
        ? matchedWithId.split('-').last
        : matchedWithId;

    final isMatched = actualMatchedUserId.isNotEmpty;

    // Handle match reason safely
    final matchReason = hasDirectMatch
        ? state.matchData!.get('reason') as String? ?? 'Compatible interests'
        : '';

    // Case 1: Matches not released yet
    if (!state.matchReleased || !isMatchReleased) {
      return _buildActionButton(
        context, // Pass context here
        Icons.favorite,
        "Match result not available yet",
        null,
        color: Colors.grey,
      );
    }

    // Case 2: User has no match document
    if (!hasDirectMatch) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                "No match information available",
                style: GoogleFonts.raleway(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find match data for your account",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Case 3: User is unmatched
    if (!isMatched) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                "No match found this time",
                style: GoogleFonts.raleway(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We couldn't find a suitable match for you at this event",
                textAlign: TextAlign.center,
                style: GoogleFonts.raleway(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Case 4: User has a valid match - show match details
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Your Match!",
              style: GoogleFonts.raleway(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.pink,
              ),
            ),
            const SizedBox(height: 16),

            // Show matched user's avatar
            FutureBuilder<DocumentSnapshot>(
              future: FirestoreService().getUserDocument(actualMatchedUserId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.blue.shade100,
                    child: const CircularProgressIndicator(),
                  );
                }

                final userDoc = snapshot.data;
                String? photoUrl;
                String? displayName = 'Your Match Partner';

                if (userDoc != null && userDoc.exists) {
                  final data = userDoc.data() as Map<String, dynamic>? ?? {};
                  photoUrl = data['photoUrl'] as String?;
                  displayName = data['name'] as String?;
                }

                return Column(
                  children: [
                    photoUrl != null && photoUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 48,
                            backgroundImage: NetworkImage(photoUrl),
                          )
                        : CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(
                              Icons.person,
                              size: 48,
                              color: Colors.blue,
                            ),
                          ),
                    const SizedBox(height: 16),
                    Text(
                      displayName ?? 'Your Match Partner',
                      style: GoogleFonts.raleway(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),
            Card(
              color: Colors.pink.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      "Why you were matched:",
                      style: GoogleFonts.raleway(
                        fontWeight: FontWeight.w600,
                        color: Colors.pink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      matchReason,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.raleway(color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.message),
              label: const Text("Send Message"),
              onPressed: () {
                // Implement messaging functionality
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Added context parameter
  Widget _buildActionButton(
    BuildContext context, // Context added here
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? color,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: color ?? Colors.white),
      label: Text(label),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }

  Widget _buildAnswerDisplay(Question q, Map<String, dynamic>? existingAnswers) {
    final answer = existingAnswers?[q.id]?.toString() ?? 'Not answered';
    String displayText;
    IconData icon = Icons.question_answer;
    Color color = Colors.grey;
    switch (q.type) {
      case 'selection':
        if (answer == 'agree') {
          displayText = 'Agree';
          icon = Icons.thumb_up;
          color = Colors.green;
        } else if (answer == 'disagree') {
          displayText = 'Disagree';
          icon = Icons.thumb_down;
          color = Colors.red;
        } else {
          displayText = 'Neutral';
          icon = Icons.thumbs_up_down;
          color = Colors.orange;
        }
        break;
      case 'boolean':
        final boolAnswer = answer == 'true';
        displayText = boolAnswer ? 'Yes' : 'No';
        icon = boolAnswer ? Icons.check_circle : Icons.cancel;
        color = boolAnswer ? Colors.green : Colors.red;
        break;
      case 'text':
      default:
        displayText = answer;
        icon = Icons.text_fields;
        color = Colors.blue;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        q.title,
        style: GoogleFonts.raleway(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        displayText,
        style: GoogleFonts.raleway(color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildAnswerField(Question q, Map<String, dynamic> answers) {
    switch (q.type) {
      case 'selection':
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: q.title,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            filled: true,
          ),
          items: const [
            DropdownMenuItem<String>(value: 'agree', child: Text('Agree')),
            DropdownMenuItem<String>(value: 'neutral', child: Text('Neutral')),
            DropdownMenuItem<String>(
              value: 'disagree',
              child: Text('Disagree'),
            ),
          ],
          onChanged: (val) {
            if (val != null) answers[q.id] = val;
          },
          onSaved: (val) {
            if (val != null) answers[q.id] = val;
          },
        );
      case 'boolean':
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(q.title, style: GoogleFonts.raleway(fontSize: 16)),
            ),
            StatefulBuilder(
              builder: (context, setStateSB) {
                final value = answers[q.id] ?? false;
                return Switch(
                  value: value,
                  onChanged: (val) {
                    setStateSB(() => answers[q.id] = val);
                  },
                );
              },
            ),
          ],
        );
      case 'text':
      default:
        return TextFormField(
          decoration: InputDecoration(
            labelText: q.title,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            filled: true,
          ),
          onSaved: (val) {
            if (val != null) answers[q.id] = val;
          },
        );
    }
  }

  Widget _buildQuestionsSection(BuildContext context, EventdetailLoaded state) {
    final colorScheme = Theme.of(context).colorScheme;
    final bloc = BlocProvider.of<EventdetailBloc>(context);
    Map<String, dynamic> answers = {};

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.quiz, size: 24, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  "Event Questions",
                  style: GoogleFonts.raleway(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Show check-in status message
            if (state.isCheckedIn && state.checkInTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Checked in at ${DateFormat('h:mm a').format(state.checkInTime!)}",
                      style: GoogleFonts.raleway(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            if (state.hasSubmittedAnswers)
              Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "You've submitted your answers",
                        style: GoogleFonts.raleway(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...state.questions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildAnswerDisplay(q, state.existingAnswers),
                    ),
                  ),
                ],
              )
            else if (state.isCheckedIn) // Only show questions if checked in
              Form(
                key: GlobalKey<FormState>(),
                child: Column(
                  children: [
                    Text(
                      "Please answer these questions to help with matchmaking:",
                      style: GoogleFonts.raleway(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...state.questions.map(
                      (q) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildAnswerField(q, answers),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (answers.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Please answer at least one question",
                              ),
                            ),
                          );
                          return;
                        }
                        bloc.add(SubmitAnswers(answers: answers));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: Text(
                        "Submit Answers",
                        style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Please check in first",
                      style: GoogleFonts.raleway(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
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
}