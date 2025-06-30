import 'package:app/pages/events/accepted_event_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';

class AppliedEventsPage extends StatelessWidget {
  const AppliedEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.black, // Match home.dart background
      appBar: AppBar(
        title: Text(
          "Applied Events",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white, // White title for dark AppBar
          ),
        ),
        backgroundColor: Colors.grey[900], // Dark AppBar background
        elevation: 0, // Flat design
        iconTheme: const IconThemeData(color: Colors.white), // White back arrow
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('event_applications')
            .where('userId', isEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.pinkAccent));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy_outlined, // Changed icon
                    size: 64,
                    color: Colors.grey[700], // Softer color for dark theme
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No applied events yet",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500, // Adjusted weight
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Apply to events to see them here.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.raleway(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          final applications = snapshot.data!.docs;
          final eventIds =
              applications.map((doc) => doc['eventId'] as String).toList();
          final statusMap = {
            for (var doc in applications)
              doc['eventId']: doc['status'] ?? 'pending',
          };

          // Prevent query error for empty list
          if (eventIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(
                    Icons.event_busy_outlined,
                    size: 64,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No events found for your applications.",
                     style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .where(FieldPath.documentId, whereIn: eventIds)
                .snapshots(),
            builder: (context, eventSnapshot) {
              if (eventSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.pinkAccent));
              }

              if (!eventSnapshot.hasData ||
                  eventSnapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    "No event data available",
                    style: GoogleFonts.raleway(
                      color: Colors.grey[500],
                    ),
                  ),
                );
              }

              final events = eventSnapshot.data!.docs
                  .map((doc) => Event.fromDocumentSnapshot(doc))
                  .toList();

              // Sort events: live first, then upcoming, then completed
              events.sort((a, b) {
                final now = DateTime.now();

                final aIsLive =
                    now.isAfter(a.startTime) && now.isBefore(a.endTime);
                final bIsLive =
                    now.isAfter(b.startTime) && now.isBefore(b.endTime);

                if (aIsLive != bIsLive) {
                  return aIsLive ? -1 : 1;
                }

                final aIsUpcoming = now.isBefore(a.startTime);
                final bIsUpcoming = now.isBefore(b.startTime);

                if (aIsUpcoming != bIsUpcoming) {
                  return aIsUpcoming ? -1 : 1;
                }
                
                final aStatus = statusMap[a.id] ?? 'pending';
                final bStatus = statusMap[b.id] ?? 'pending';

                // Custom sort for status: accepted -> pending -> rejected
                const statusOrder = {'accepted': 0, 'pending': 1, 'rejected': 2};
                final aStatusOrder = statusOrder[aStatus] ?? 99;
                final bStatusOrder = statusOrder[bStatus] ?? 99;

                if (aStatusOrder != bStatusOrder) {
                    return aStatusOrder.compareTo(bStatusOrder);
                }
                
                return a.startTime.compareTo(b.startTime);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final status = statusMap[event.id] ?? 'pending';
                  final isAccepted = status == 'accepted';

                  final now = DateTime.now();
                  final isLive =
                      now.isAfter(event.startTime) && now.isBefore(event.endTime);
                  final isUpcoming = now.isBefore(event.startTime);
                  final isCompleted = now.isAfter(event.endTime);

                  return Card(
                    elevation: 3, // Subtle elevation
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.grey[850], // Dark card color
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: isAccepted && !isCompleted // Allow tap only if accepted and not completed
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AcceptedEventDetailPage(event: event),
                                ),
                              );
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.title,
                                        style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('EEE, MMM d • HH:mm') // 24hr format
                                            .format(event.startTime),
                                        style: GoogleFonts.raleway(
                                          fontSize: 14,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildStatusBadge(status, isLive, isUpcoming, isCompleted),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              event.description,
                              style: GoogleFonts.raleway(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                             if (isLive)
                              Row(
                                children: [
                                  Icon(Icons.sensors, color: Colors.pinkAccent, size: 16), // Matching live badge icon
                                  const SizedBox(width: 6),
                                  Text(
                                    "Live now",
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.pinkAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else if (isCompleted)
                              Text(
                                "This event has ended.",
                                style: GoogleFonts.raleway(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else if (isUpcoming && isAccepted)
                               Row(
                                children: [
                                  Icon(Icons.event_available, color: Colors.green.shade400, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    "You're accepted!",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.green.shade400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isLive, bool isUpcoming, bool isCompleted) {
    IconData icon;
    Color backgroundColor;
    String label;

    if (isLive) {
      icon = Icons.sensors; // Consistent with "Live now" text
      backgroundColor = Colors.pinkAccent;
      label = 'Live';
    } else if (isCompleted) {
      icon = Icons.check_circle_outline;
      backgroundColor = Colors.grey.shade800; // Darker grey
      label = 'Completed';
    } else {
      // Event hasn't started yet - show application status
      switch (status) {
        case 'accepted':
          icon = Icons.check_circle;
          backgroundColor = Colors.green.shade600; // Vibrant green
          label = 'Accepted';
          break;
        case 'rejected':
          icon = Icons.cancel;
          backgroundColor = Colors.red.shade700; // Strong red
          label = 'Rejected';
          break;
        default: // pending
          icon = Icons.hourglass_empty_rounded; // Different pending icon
          backgroundColor = Colors.orange.shade700; // Rich orange
          label = 'Pending';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), // Adjusted padding
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16), // Pill shape
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white), // Slightly smaller icon
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.poppins( // Changed to Poppins
              fontSize: 12,
              fontWeight: FontWeight.w500, // Medium weight
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}