import 'dart:ui' as ui;

import 'package:app/models/event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:app/pages/events/manage_event_page.dart';
import 'package:app/pages/events/accepted_event_page.dart';

class YourEventsPage extends StatefulWidget {
  const YourEventsPage({super.key});

  @override
  State<YourEventsPage> createState() => _YourEventPageState();
}

class _YourEventPageState extends State<YourEventsPage> {
  User? currentUser;
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;
  List<Event> _liveEvents = [];
  bool _isLoading = true;
  Map<String, Map<String, dynamic>> _hostProfiles = {};

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    currentUser = FirebaseAuth.instance.currentUser;
    _fetchLiveEvents();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  Future<void> _fetchLiveEvents() async {
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      
      // Get all events where user is host (without time filtering)
      final hostedEventsSnapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('createdBy', isEqualTo: currentUser!.uid)
          .get();

      // Get events where user has accepted application
      final applicationsSnapshot = await FirebaseFirestore.instance
          .collection('event_applications')
          .where('userId', isEqualTo: currentUser!.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final applicationEventIds = applicationsSnapshot.docs
          .map((doc) => doc['eventId'] as String)
          .toList();

      List<Event> appliedEvents = [];
      if (applicationEventIds.isNotEmpty) {
        final appliedEventsSnapshot = await FirebaseFirestore.instance
            .collection('events')
            .where(FieldPath.documentId, whereIn: applicationEventIds)
            .get();

        appliedEvents = appliedEventsSnapshot.docs
            .map((doc) => Event.fromDocumentSnapshot(doc))
            .toList();
      }

      // Combine all events
      final allEvents = [
        ...hostedEventsSnapshot.docs.map((doc) => Event.fromDocumentSnapshot(doc)),
        ...appliedEvents,
      ];

      // Filter for live events on the client side
      final allLiveEvents = allEvents.where((event) {
        return event.startTime.isBefore(now) && event.endTime.isAfter(now);
      }).toSet().toList();

      // Fetch host profiles
      final hostIds = allLiveEvents.map((e) => e.createdBy).toSet().toList();
      final hostsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: hostIds)
          .get();

      final Map<String, Map<String, dynamic>> hostProfiles = {};
      for (var doc in hostsSnapshot.docs) {
        hostProfiles[doc.id] = doc.data() as Map<String, dynamic>;
      }

      setState(() {
        _liveEvents = allLiveEvents;
        _hostProfiles = hostProfiles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching live events: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isHosted(String eventId) {
    return _liveEvents.any((event) => event.id == eventId && event.createdBy == currentUser!.uid);
  }

  String _getHostName(String hostId) {
    if (hostId == currentUser!.uid) {
      return 'You';
    }
    return _hostProfiles[hostId]?['name'] ?? 'Unknown';
  }

  @override
  void dispose() {
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          "Your Ongoing Events",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        flexibleSpace: ValueListenableBuilder<bool>(
          valueListenable: _scrolledNotifier,
          builder: (context, isScrolled, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: isScrolled
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.pinkAccent),
                )
              : _liveEvents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_available,
                              size: 64, color: Colors.purpleAccent),
                          const SizedBox(height: 20),
                          Text(
                            "No ongoing events",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "You don't have any live events right now.",
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchLiveEvents,
                      child: ListView(
                        controller: _scrollController,
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          ..._liveEvents.map((event) => _buildEventCard(context, event)),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Event event) {
    final isHosted = _isHosted(event.id);
    final hostName = _getHostName(event.createdBy);
    final hostPhoto = _hostProfiles[event.createdBy]?['photoURL'];
    final dateFormat = DateFormat('MMM d');
    final timeFormat = DateFormat('h:mm a');

    return GestureDetector(
      onTap: () {
        if (isHosted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ManageEventPage(eventId: event.id),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AcceptedEventDetailPage(event: event),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Color(0xFF2D0B5A),
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
            children: [
              // Event image
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(event.cover.isNotEmpty
                        ? event.cover
                        : "https://images.unsplash.com/photo-1540575467063-178a50c2df87?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1350&q=80"),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "LIVE",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Colors.pinkAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateFormat.format(event.startTime),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[300],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 16, color: Colors.pinkAccent),
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
              // Host information
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.pinkAccent),
                  const SizedBox(width: 6),
                  Text(
                    isHosted ? "Hosted by You" : "Hosted by $hostName",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                event.description,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.sensors, color: Colors.pinkAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "Live now",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.pinkAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (isHosted)
                    Text(
                      "You're hosting!",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.green.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Text(
                      "You're participating!",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.blue.shade400,
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
  }
}