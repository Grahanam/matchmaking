import 'package:app/models/event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import './manage_event_page.dart';
// Import your_event_page.dart with a prefix
import 'package:app/pages/events/your_event_page.dart' as yourEventPageStringExt;
// You might also have manage_event_page.dart imported, potentially with a prefix too if needed elsewhere
import 'package:app/pages/events/manage_event_page.dart' as manageEventPageStringExt;

class YourEventsPage extends StatefulWidget {
  const YourEventsPage({Key? key}) : super(key: key);

  @override
  State<YourEventsPage> createState() => _YourEventPageState();
}

class _YourEventPageState extends State<YourEventsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? currentUser;

   @override
  void initState() {
    super.initState();
    currentUser = FirebaseAuth.instance.currentUser;
  }


  @override
  Widget build(BuildContext context) {

      if (currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          "Your Events",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .where('createdBy', isEqualTo: currentUser!.uid)
            .orderBy('startTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.purpleAccent),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 64,
                    color: Colors.purpleAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No events created yet",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Create your first event to get started",
                    style: GoogleFonts.poppins(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to create event page
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: Text(
                      "Create Event",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final events = snapshot.data!.docs
              .map((doc) => Event.fromDocumentSnapshot(doc))
              .toList();

          final now = DateTime.now();
          final upcoming = events
              .where((e) => e.endTime.isAfter(now))
              .toList();
          final past = events
              .where((e) => e.endTime.isBefore(now))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (upcoming.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Text(
                    "UPCOMING EVENTS",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.pinkAccent,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                ...upcoming.map((event) => _buildEventCard(context, event))
                    .toList(),
              ],
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                  child: Text(
                    "PAST EVENTS",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.pinkAccent,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                ...past.map((event) => _buildEventCard(context, event,
                    isPast: true)).toList(),
              ],
            ],
          );
        },
      ),
    );
  }

Widget _buildEventCard(BuildContext context, Event event, {bool isPast = false}) {
  final dateFormat = DateFormat('MMM d');
  final timeFormat = DateFormat('h:mm a');
  final guestCount = event.guestCount;
  final isOngoing = event.startTime.isBefore(DateTime.now()) &&
      event.endTime.isAfter(DateTime.now());

  return GestureDetector(
     onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => manageEventPageStringExt.ManageEventPage(eventId: event.id)

        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1C1C1E), // Dark background
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              event.title,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[300]),
                const SizedBox(width: 6),
                Text(
                  dateFormat.format(event.startTime),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[300],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time, size: 16, color: Colors.grey[300]),
                const SizedBox(width: 6),
                Text(
                  timeFormat.format(event.startTime),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
  spacing: 12,
  runSpacing: 8,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    _buildStatChip(
      icon: Icons.group,
      value: guestCount.toString(),
      label: "Guests",
      color: Colors.pinkAccent,
    ),
    _buildStatChip(
      icon: Icons.location_on,
      value: yourEventPageStringExt.StringExtension(event.locationType).capitalize(),
      label: "Location",
      color: Colors.green,
    ),
    if (isOngoing)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange),
        ),
        child: Text(
          "Live Now",
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
      ),
    if (isPast)
      Text(
        "Completed",
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
      ),
  ],
),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}