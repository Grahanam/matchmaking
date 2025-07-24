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

  @override
  void initState() {
    super.initState();
    _fetchPopularEvents();
  }

  Future<void> _fetchPopularEvents() async {
    try {
      final eventsSnapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('startTime', isGreaterThanOrEqualTo: DateTime.now())
          .get();

      // Get all host IDs
      final hostIds = eventsSnapshot.docs
          .map((doc) => Event.fromDocumentSnapshot(doc).createdBy)
          .toSet()
          .toList();

      // Fetch host experience and names in batch
      if (hostIds.isNotEmpty) {
        final hostsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: hostIds)
            .get();

        for (final doc in hostsSnapshot.docs) {
          _hostExperienceMap[doc.id] = (doc['hostedCount'] as int?) ?? 0;
          _hostNameMap[doc.id] = doc['name'] as String? ?? 'Unknown host';
        }
      }

      // Parse events and sort by host experience
      final events = eventsSnapshot.docs
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
        color: Colors.orange.withOpacity(0.2),
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
      color: Colors.grey[850],
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
            // ClipRRect(
            //   borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            //   child: event.imageUrl.isNotEmpty
            //       ? Image.network(
            //           event.imageUrl,
            //           height: 180,
            //           width: double.infinity,
            //           fit: BoxFit.cover,
            //           errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
            //         )
            //       : _buildImagePlaceholder(),
            // ),
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
                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEE, MMM d').format(event.startTime),
                        style: GoogleFonts.poppins(),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('h:mm a').format(event.startTime),
                        style: GoogleFonts.poppins(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (event.city.isNotEmpty || event.state.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          [event.city, event.state].where((s) => s.isNotEmpty).join(', '),
                          style: GoogleFonts.poppins(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    event.description,
                    style: GoogleFonts.poppins(color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Hosted by $hostName',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
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

  Widget _buildImagePlaceholder() {
    return Container(
      height: 180,
      color: Colors.grey[200],
      child: const Center(child: Icon(Icons.event, size: 60, color: Colors.grey)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Popular Events',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        // backgroundColor: Colors.white,
        elevation: 0,
      ),
      // backgroundColor: Colors.white,
      body: _isLoading
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
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          return _buildEventCard(_events[index]);
                        },
                      ),
                    ),
    );
  }
}