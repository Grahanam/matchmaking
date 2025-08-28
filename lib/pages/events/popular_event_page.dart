import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import 'event_detail_page.dart';

class PopularEventsPage extends StatefulWidget {
  const PopularEventsPage({super.key});

  @override
  State<PopularEventsPage> createState() => _PopularEventsPageState();
}

class _PopularEventsPageState extends State<PopularEventsPage> {
  List<Event> _events = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, int> _hostExperienceMap = {};
  final Map<String, String> _hostNameMap = {};
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    _fetchPopularEvents();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  Future<void> _fetchPopularEvents() async {
    try {
      final eventsSnapshot =
          await FirebaseFirestore.instance
              .collection('events')
              // .where('startTime', isGreaterThanOrEqualTo: DateTime.now())
              .where(
                'endTime',
                isGreaterThan: DateTime.now(),
              ) // Only events that haven't ended
              .orderBy('endTime') // Optional: sort by end time
              .get();

      // Get all host IDs
      final hostIds =
          eventsSnapshot.docs
              .map((doc) => Event.fromDocumentSnapshot(doc).createdBy)
              .toSet()
              .toList();

      // Fetch host experience and names in batch
      if (hostIds.isNotEmpty) {
        final hostsSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .where(FieldPath.documentId, whereIn: hostIds)
                .get();

        for (final doc in hostsSnapshot.docs) {
          _hostExperienceMap[doc.id] = (doc['hostedCount'] as int?) ?? 0;
          _hostNameMap[doc.id] = doc['name'] as String? ?? 'Unknown host';
        }
      }

      // Parse events and sort by host experience
      final events =
          eventsSnapshot.docs
              .map((doc) => Event.fromDocumentSnapshot(doc))
              .toList();

      events.sort((a, b) {
        final aExp = _hostExperienceMap[a.createdBy] ?? 0;
        final bExp = _hostExperienceMap[b.createdBy] ?? 0;

        if (bExp != aExp) {
          return bExp.compareTo(aExp);
        }
        return a.startTime.compareTo(b.startTime);
      });

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load popular events: $e';
      });
    }
  }

  Widget _buildExperienceBadge(int experience) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: Colors.orange),
          const SizedBox(width: 4),
          Text(
            '$experience events',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Event event) {
    final hostName = _hostNameMap[event.createdBy] ?? 'Unknown host';
    final hostExperience = _hostExperienceMap[event.createdBy] ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      color: Color(0xFF2D0B5A),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventDetailPage(event: event),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
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
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildExperienceBadge(hostExperience),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.pinkAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEE, MMM d').format(event.startTime),
                        style: GoogleFonts.poppins(color: Colors.white60),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.pinkAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('h:mm a').format(event.startTime),
                        style: GoogleFonts.poppins(color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (event.city.isNotEmpty || event.state.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.pinkAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          [
                            event.city,
                            event.state,
                          ].where((s) => s.isNotEmpty).join(', '),
                          style: GoogleFonts.poppins(color: Colors.white60),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    event.description,
                    style: GoogleFonts.poppins(color: Colors.white60),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 16,
                        color: Colors.pinkAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hosted by $hostName',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Popular Events',
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
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _events.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event, size: 60, color: Colors.grey[400]),
                        const SizedBox(height: 20),
                        Text(
                          'No popular events found',
                          style: GoogleFonts.poppins(fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Check back later for trending events',
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                  : RefreshIndicator(
                    onRefresh: _fetchPopularEvents,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        return _buildEventCard(_events[index]);
                      },
                    ),
                  ),
        ),
      ),
    );
  }
}
