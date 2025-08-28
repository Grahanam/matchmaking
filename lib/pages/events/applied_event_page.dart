import 'dart:async';
import 'dart:ui' as ui;

import 'package:app/pages/events/accepted_event_page.dart';
import 'package:app/pages/events/manage_event_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';

class AppliedEventsPage extends StatefulWidget {
  const AppliedEventsPage({super.key});

  @override
  State<AppliedEventsPage> createState() => _AppliedEventsPageState();
}

class _AppliedEventsPageState extends State<AppliedEventsPage> {
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;
  List<Event> _allEvents = [];
  List<Event> _liveEvents = [];
  List<Event> _upcomingEvents = [];
  List<Event> _endedEvents = [];
  bool _isLoading = true;
  Map<String, String> _statusMap = {};
  Map<String, bool> _isHostedMap = {};
  Map<String, String> _hostNames = {};
  String _currentUserId = '';

  bool _isDisposed = false;
  Future<void>? _fetchAllEventsOperation;

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    _currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _fetchAllEvents();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  Future<void> _fetchAllEvents() async {
    // Cancel any previous operation
    _fetchAllEventsOperation?.ignore();

    // Create a new operation
    final completer = Completer<void>();
    _fetchAllEventsOperation = completer.future;

    try {
      if (_isDisposed) {
        completer.complete();
        return;
      }

      setState(() {
        _isLoading = true;
      });

      // Get events user has applied to
      final applicationsSnapshot =
          await FirebaseFirestore.instance
              .collection('event_applications')
              .where('userId', isEqualTo: _currentUserId)
              .get();

      if (_isDisposed) {
        completer.complete();
        return;
      }

      final applicationEventIds =
          applicationsSnapshot.docs
              .map((doc) => doc['eventId'] as String)
              .toList();

      // Store application statuses
      for (var doc in applicationsSnapshot.docs) {
        _statusMap[doc['eventId']] = doc['status'] ?? 'pending';
      }

      // Get events user has hosted
      final hostedEventsSnapshot =
          await FirebaseFirestore.instance
              .collection('events')
              .where('createdBy', isEqualTo: _currentUserId)
              .get();

      if (_isDisposed) {
        completer.complete();
        return;
      }

      final hostedEventIds =
          hostedEventsSnapshot.docs
              .map((doc) => Event.fromDocumentSnapshot(doc).id)
              .toList();

      // Mark hosted events
      for (var id in hostedEventIds) {
        _isHostedMap[id] = true;
      }

      // Combine all event IDs
      final allEventIds = {...applicationEventIds, ...hostedEventIds}.toList();

      if (allEventIds.isEmpty || _isDisposed) {
        setState(() {
          _isLoading = false;
        });
        completer.complete();
        return;
      }

      // Get all events data
      final eventsSnapshot =
          await FirebaseFirestore.instance
              .collection('events')
              .where(FieldPath.documentId, whereIn: allEventIds)
              .get();

      if (_isDisposed) {
        completer.complete();
        return;
      }

      final events =
          eventsSnapshot.docs
              .map((doc) => Event.fromDocumentSnapshot(doc))
              .toList();

      // Get all host IDs to fetch their names
      final hostIds = events.map((e) => e.createdBy).toSet().toList();
      await _fetchHostNames(hostIds);

      if (_isDisposed) {
        completer.complete();
        return;
      }

      // Categorize events
      final now = DateTime.now();
      _liveEvents =
          events.where((event) {
            return now.isAfter(event.startTime) && now.isBefore(event.endTime);
          }).toList();

      _upcomingEvents =
          events.where((event) {
            return now.isBefore(event.startTime);
          }).toList();

      _endedEvents =
          events.where((event) {
            return now.isAfter(event.endTime);
          }).toList();

      // Sort events
      _liveEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
      _upcomingEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
      _endedEvents.sort((a, b) => b.endTime.compareTo(a.endTime));

      if (_isDisposed) {
        completer.complete();
        return;
      }

      setState(() {
        _allEvents = events;
        _isLoading = false;
      });

      completer.complete();
    } catch (e) {
      if (_isDisposed) {
        completer.complete();
        return;
      }

      debugPrint('Error fetching events: $e');
      setState(() {
        _isLoading = false;
      });

      completer.complete();
    }
  }

  Future<void> _fetchHostNames(List<String> hostIds) async {
    if (hostIds.isEmpty || _isDisposed) return;

    try {
      final usersSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: hostIds)
              .get();

      if (_isDisposed) return;

      for (var doc in usersSnapshot.docs) {
        _hostNames[doc.id] = doc.get('name') ?? 'Unknown';
      }
    } catch (e) {
      if (_isDisposed) return;
      debugPrint('Error fetching host names: $e');
    }
  }

  String _getHostName(String hostId) {
    if (hostId == _currentUserId) {
      return 'Me';
    }
    return _hostNames[hostId] ?? 'Unknown';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fetchAllEventsOperation?.ignore();
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        title: Text(
          "Your Events",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
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
          child:
              _isLoading
                  ? const Center(
                    child: CircularProgressIndicator(color: Colors.pinkAccent),
                  )
                  : _allEvents.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            size: 80,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "No events yet",
                            style: GoogleFonts.raleway(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Apply to events or create your own to see them here.",
                            style: GoogleFonts.raleway(
                                      fontSize: 16,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                  : RefreshIndicator(
                    onRefresh: _fetchAllEvents,
                    child: ListView(
                      controller: _scrollController,
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_liveEvents.isNotEmpty) ...[
                          _buildSectionHeader("Live Events"),
                          ..._liveEvents.map((event) => _buildEventCard(event)),
                        ],
                        if (_upcomingEvents.isNotEmpty) ...[
                          _buildSectionHeader("Upcoming Events"),
                          ..._upcomingEvents.map(
                            (event) => _buildEventCard(event),
                          ),
                        ],
                        if (_endedEvents.isNotEmpty) ...[
                          _buildSectionHeader("Past Events"),
                          ..._endedEvents.map(
                            (event) => _buildEventCard(event),
                          ),
                        ],
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.pinkAccent,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildEventCard(Event event) {
    final now = DateTime.now();
    final isLive = now.isAfter(event.startTime) && now.isBefore(event.endTime);
    final isUpcoming = now.isBefore(event.startTime);
    final isCompleted = now.isAfter(event.endTime);
    final isHosted = _isHostedMap[event.id] ?? false;
    final status = isHosted ? 'host' : _statusMap[event.id] ?? 'pending';
    final hostName = _getHostName(event.createdBy);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Color(0xFF2D0B5A),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            (isHosted || status == 'accepted') && !isCompleted
                ? () {
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          DateFormat(
                            'EEE, MMM d • HH:mm',
                          ).format(event.startTime),
                          style: GoogleFonts.raleway(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusBadge(
                    status,
                    isLive,
                    isUpcoming,
                    isCompleted,
                    isHosted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Host information
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(
                    'Hosted by: $hostName',
                    style: GoogleFonts.raleway(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              else if (isUpcoming && (isHosted || status == 'accepted'))
                Row(
                  children: [
                    Icon(
                      Icons.event_available,
                      color: Colors.green.shade400,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isHosted ? "You're hosting!" : "You're accepted!",
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
  }

  Widget _buildStatusBadge(
    String status,
    bool isLive,
    bool isUpcoming,
    bool isCompleted,
    bool isHosted,
  ) {
    IconData icon;
    Color backgroundColor;
    String label;

    if (isLive) {
      icon = Icons.sensors;
      backgroundColor = Colors.pinkAccent;
      label = 'Live';
    } else if (isCompleted) {
      icon = Icons.check_circle_outline;
      backgroundColor = Colors.grey.shade800;
      label = 'Completed';
    } else if (isHosted) {
      icon = Icons.star;
      backgroundColor = Colors.purple;
      label = 'Host';
    } else {
      switch (status) {
        case 'accepted':
          icon = Icons.check_circle;
          backgroundColor = Colors.green.shade600;
          label = 'Accepted';
          break;
        case 'rejected':
          icon = Icons.cancel;
          backgroundColor = Colors.red.shade700;
          label = 'Rejected';
          break;
        default: // pending
          icon = Icons.hourglass_empty_rounded;
          backgroundColor = Colors.orange.shade700;
          label = 'Pending';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
