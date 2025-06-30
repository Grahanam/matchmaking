import 'package:app/bloc/event/event_bloc.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './event_detail_page.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

class NearbyEventsPage extends StatefulWidget {
  const NearbyEventsPage({super.key});

  @override
  State<NearbyEventsPage> createState() => _NearbyEventsPageState();
}

class _NearbyEventsPageState extends State<NearbyEventsPage> {
  double _searchRadius = 20;
  Position? _currentPosition;
  bool _locationServiceEnabled = false;
  bool _isCheckingLocation = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    setState(() => _isCheckingLocation = true);
    try {
      _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      
      if (!_locationServiceEnabled) {
        _showLocationServiceDialog();
        return;
      }
      
      await _ensurePermission();
      
      if (await Geolocator.isLocationServiceEnabled()) {
        _currentPosition = await Geolocator.getCurrentPosition();
        _loadEvents();
      }
    } catch (e) {
      setState(() => _locationError = 'Location error: $e');
    } finally {
      setState(() => _isCheckingLocation = false);
    }
  }

  Future<void> _ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.denied) {
        setState(() => _locationError = 'Location permissions denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationError = 'Location permissions permanently denied');
      await Geolocator.openAppSettings();
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Location Services Disabled", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A063A),
        content: const Text("Please enable location services to find nearby events", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.pinkAccent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
              await _initializeLocation();
            },
            child: const Text("Enable", style: TextStyle(color: Colors.pinkAccent)),
          ),
        ],
      ),
    );
  }

  void _loadEvents() async {
    if (_currentPosition != null) {
      context.read<EventBloc>().add(
        FetchNearbyEvents(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          radiusInKm: _searchRadius,
        ),
      );
    }
  }

  Widget _buildLocationError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off, size: 64, color: Colors.pinkAccent),
          const SizedBox(height: 20),
          Text(
            _locationError ?? 'Location services required',
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.location_on),
            label: const Text("Enable Location"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _initializeLocation,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Nearby Events",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
      ),
      body: BlocConsumer<EventBloc, EventState>(
        listener: (context, state) {
          if (state is EventFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: Colors.pinkAccent,
              ),
            );
          }
        },
        builder: (context, state) {
          if (_isCheckingLocation) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            );
          }
          
          if (!_locationServiceEnabled || _locationError != null) {
            return _buildLocationError();
          }
          
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0F0B21),
                  Colors.black,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search Radius Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1A063A),
                          Color(0xFF2D0B5A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Search radius:",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              "${_searchRadius.toInt()} km",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.pinkAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          min: 1,
                          max: 50,
                          divisions: 10,
                          value: _searchRadius,
                          activeColor: Colors.pinkAccent,
                          inactiveColor: Colors.purple.shade800,
                          thumbColor: Colors.white,
                          onChanged: (val) => setState(() => _searchRadius = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Refresh Button
                  ElevatedButton(
                    onPressed: _loadEvents,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(double.infinity, 50),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      "Refresh Events",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Map Section
                  if (_currentPosition != null && state is NearbyEventLoaded)
                    _buildMap(context, _currentPosition!, state),
                  const SizedBox(height: 16),
                  
                  // Events Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Date",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            "Event Name",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Host",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const Expanded(flex: 1, child: SizedBox()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Events List
                  Expanded(child: _buildEventsList(context, state)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMap(BuildContext context, Position position, NearbyEventLoaded state) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(position.latitude, position.longitude),
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.example.app',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(position.latitude, position.longitude),
                  radius: _searchRadius * 1000,
                  useRadiusInMeter: true,
                  color: Colors.pinkAccent.withOpacity(0.2),
                  borderColor: Colors.pinkAccent,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(position.latitude, position.longitude),
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.person_pin_circle, color: Colors.white),
                  ),
                ),
                ...state.events.map(
                  (event) => Marker(
                    point: LatLng(
                      event.location.latitude,
                      event.location.longitude,
                    ),
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.event, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildEventsList(BuildContext context, EventState state) {
  if (state is NearbyEventLoading) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.pinkAccent),
    );
  } else if (state is NearbyEventLoaded) {
    if (state.events.isEmpty) {
      return Center(
        child: Text(
          "No nearby events found",
          style: GoogleFonts.poppins(
            color: Colors.white70,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: state.events.length,
      itemBuilder: (context, index) {
        final event = state.events[index];
        return _EventListItem(event: event);
      },
    );
  } else if (state is EventFailure) {
    return Center(
      child: Text(
        "Error: ${state.error}",
        style: GoogleFonts.poppins(
          color: Colors.pinkAccent,
        ),
      ),
    );
  }
  return Center(
    child: Text(
      "Search for events",
      style: GoogleFonts.poppins(
        color: Colors.white70,
      ),
    ),
  );
}

class _EventListItem extends StatelessWidget {
  final Event event;

  const _EventListItem({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1A063A),
            Color(0xFF2D0B5A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM').format(event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.pinkAccent,
                      ),
                    ),
                    Text(
                      DateFormat('dd').format(event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      DateFormat('EEE, h:mm a').format(event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.description,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(event.createdBy)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator(
                        color: Colors.pinkAccent,
                        strokeWidth: 2,
                      );
                    }
                    
                    final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                    final name = userData?['name'] ?? 'Unknown';
                    final photoUrl = userData?['photoUrl'];
                    
                    return Row(
                      children: [
                        if (photoUrl != null)
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: NetworkImage(photoUrl),
                          )
                        else
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.purple,
                            child: Text(
                              name.isNotEmpty ? name[0] : '?',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Expanded(
                flex: 1,
                child: Icon(Icons.chevron_right, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}