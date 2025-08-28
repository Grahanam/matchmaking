import 'dart:ui' as ui;
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

class _EventListItem extends StatefulWidget {
  final Event event;

  const _EventListItem({required this.event});

  @override
  State<_EventListItem> createState() => __EventListItemState();
}

class __EventListItemState extends State<_EventListItem> {
  // Step 2: Create a future instance in the state
  late Future<DocumentSnapshot> _userFuture;

  @override
  void initState() {
    super.initState();
    // Step 3: Initialize the future in initState
    _userFuture = _fetchUserData();
  }

  // Helper function to fetch user data
  Future<DocumentSnapshot> _fetchUserData() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.event.createdBy)
        .get();
  }

  @override
  void didUpdateWidget(covariant _EventListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Step 4: Only reload if the user ID changes
    if (oldWidget.event.createdBy != widget.event.createdBy) {
      _userFuture = _fetchUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A063A), Color(0xFF2D0B5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventDetailPage(event: widget.event),
              ),
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
                      DateFormat('MMM').format(widget.event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.pinkAccent,
                      ),
                    ),
                    Text(
                      DateFormat('dd').format(widget.event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      DateFormat('EEE, h:mm a').format(widget.event.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              // Step 5: Keep the event details section as is (no changes needed)
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.event.description,
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
              // Step 6: Update the FutureBuilder to use our state's future
              Expanded(
                flex: 2,
                child: FutureBuilder<DocumentSnapshot>(
                  future: _userFuture, // Use the state-managed future
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return CircularProgressIndicator(
                        color: Colors.pinkAccent,
                        strokeWidth: 2,
                      );
                    }

                    final userData =
                        userSnapshot.data?.data() as Map<String, dynamic>?;
                    final name = userData?['name'] ?? 'Unknown';
                    final photoUrl = userData?['photoURL'];

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
                              style: GoogleFonts.poppins(color: Colors.white),
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

class NearbyEventsPage extends StatefulWidget {
  const NearbyEventsPage({super.key});

  @override
  State<NearbyEventsPage> createState() => _NearbyEventsPageState();
}

class _NearbyEventsPageState extends State<NearbyEventsPage> {
  double _searchRadius = 10;
  Position? _currentPosition;
  bool _locationServiceEnabled = false;
  bool _isCheckingLocation = false;
  String? _locationError;
  String? selectedCountry;
  String? selectedState;
  String? selectedCity;
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  final TextEditingController _cityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    _initializeLocation();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients)
      return; // Check if controller is still attached

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
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
      setState(
        () => _locationError = 'Location permissions permanently denied',
      );
      await Geolocator.openAppSettings();
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "Location Services Disabled",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF1A063A),
            content: const Text(
              "Please enable location services to find nearby events",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.pinkAccent),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Geolocator.openLocationSettings();
                  await _initializeLocation();
                },
                child: const Text(
                  "Enable",
                  style: TextStyle(color: Colors.pinkAccent),
                ),
              ),
            ],
          ),
    );
  }

  void _clearFilters() {
    setState(() {
      selectedCity = null;
      _cityController.clear();
    });
    _loadEvents();
  }

  void _loadEvents() {
    if (selectedCity != null || _currentPosition != null) {
      final lat = selectedCity == null ? _currentPosition?.latitude : null;
      final lon = selectedCity == null ? _currentPosition?.longitude : null;

      // Only load if we have either a city or location
      if (selectedCity != null || (lat != null && lon != null)) {
        context.read<EventBloc>().add(
          FetchNearbyEvents(
            latitude: lat ?? 0.0,
            longitude: lon ?? 0.0,
            radiusInKm: _searchRadius,
            city: selectedCity,
          ),
        );
      }
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
            style: GoogleFonts.poppins(fontSize: 18, color: Colors.white70),
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Explore Events",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        flexibleSpace: ValueListenableBuilder<bool>(
          valueListenable: _scrolledNotifier,
          builder: (context, isScrolled, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient:
                    isScrolled
                        ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.pinkAccent,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SafeArea(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSearchFilters(),
                            const SizedBox(height: 16),
                            // Map Section
                            if (_currentPosition != null &&
                                state is NearbyEventLoaded)
                              _buildMap(context, _currentPosition!, state),
                            const SizedBox(height: 10),
                            // Events List
                            _buildEventsList(context, state),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A063A), Color(0xFF2D0B5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Search Events Around You",
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
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //   children: [
          // Text(
          //   "Search Filters",
          //   style: GoogleFonts.poppins(
          //     fontSize: 16,
          //     fontWeight: FontWeight.w600,
          //     color: Colors.white70,
          //   ),
          // ),
          // if (selectedCity != null)
          //   TextButton(
          //     onPressed: _clearFilters,
          //     child: Text(
          //       "Clear filter",
          //       style: GoogleFonts.poppins(
          //         color: Colors.pinkAccent,
          //         fontSize: 14,
          //       ),
          //     ),
          //   ),
          //   ],
          // ),
          // const SizedBox(height: 12),
          const SizedBox(height: 8),
          Row(
            children: [
              // Expanded so text field takes available space
              Expanded(
                child: TextFormField(
                  controller: _cityController,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by City',
                    hintStyle: GoogleFonts.poppins(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon:
                        _cityController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                _cityController.clear();
                                setState(() {
                                  selectedCity = null;
                                });
                              },
                            )
                            : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      selectedCity = value.isNotEmpty ? value : null;
                    });
                  },
                ),
              ),

              const SizedBox(width: 8),

              // Search button with icon
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    // if (_cityController.text.isNotEmpty) {
                    _loadEvents();
                    // }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(0), // remove extra padding
                  ),
                  child: const Icon(Icons.search, size: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMap(
    BuildContext context,
    Position position,
    NearbyEventLoaded state,
  ) {
    // --- Robust Bounds Calculation ---
    LatLngBounds? safeBounds;
    LatLng effectiveCenter = LatLng(
      position.latitude,
      position.longitude,
    ); // Default center
    double effectiveZoom = 10.5; // Default zoom

    // Only attempt bounds calculation if there are events
    if (state.events.isNotEmpty) {
      List<LatLng> allPoints = [
        LatLng(position.latitude, position.longitude), // User location
        ...state.events.map(
          (e) => LatLng(e.location.latitude, e.location.longitude),
        ),
      ];

      // Check for edge case: all points are identical
      bool allPointsIdentical = allPoints.every(
        (point) =>
            point.latitude == allPoints[0].latitude &&
            point.longitude == allPoints[0].longitude,
      );

      if (!allPointsIdentical) {
        try {
          safeBounds = LatLngBounds.fromPoints(allPoints);

          // Validate the bounds (check for NaN/Infinity in center or span)
          if (!safeBounds.center.latitude.isNaN &&
              !safeBounds.center.longitude.isNaN &&
              !safeBounds.center.latitude.isInfinite &&
              !safeBounds.center.longitude.isInfinite) {
            effectiveCenter = safeBounds.center;
            effectiveZoom = 13.0;
          } else {
            // If bounds calculation resulted in invalid numbers, log and fallback
            debugPrint(
              "Warning: LatLngBounds calculation resulted in NaN/Infinity. Falling back to user location.",
            );
            safeBounds = null; // Ensure bounds aren't used
          }
        } catch (e) {
          // If LatLngBounds.fromPoints throws (e.g., due to identical points causing division by zero)
          debugPrint(
            "LatLngBounds calculation error: $e. Falling back to user location.",
          );
          safeBounds = null; // Ensure bounds aren't used
        }
      } else {
        // All points are the same, cannot calculate meaningful bounds
        debugPrint(
          "All marker points are identical. Cannot fit bounds. Showing default view.",
        );
        safeBounds = null; // Ensure bounds aren't used
      }
    } else {
      // No events, just show user location
      safeBounds = null;
    }

    // --- Map Widget ---
    return Container(
      constraints: const BoxConstraints(maxHeight: 350, minHeight: 350),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(128, 0, 128, 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          options: MapOptions(
            // Provide a valid initial center and zoom to prevent TileLayer errors
            initialCenter: effectiveCenter, // Guaranteed to be valid
            initialZoom: effectiveZoom, // Guaranteed to be valid
            // Only use initialCameraFit if we have valid bounds
            // This will override initialCenter/Zoom once calculated
            initialCameraFit:
                safeBounds != null
                    ? CameraFit.bounds(
                      bounds: safeBounds,
                      padding: const EdgeInsets.all(50.0),
                    )
                    : null,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.de/{z}/{x}/{y}.png",
              // Add error handling for tiles - important!
              // Make sure NetworkTileProvider is imported from flutter_map
              tileProvider: NetworkTileProvider(),
              // Optional: Add errorBuilder for better tile loading UX
              // errorBuilder: (context, error, stackTrace) {
              //   return Container(color: Colors.grey.shade300); // Placeholder for failed tiles
              // },
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(position.latitude, position.longitude),
                  radius: _searchRadius * 1000,
                  useRadiusInMeter: true,
                  color: const Color.fromRGBO(255, 64, 129, 0.2),
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
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: Colors.white,
                    ),
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
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.event,
                        size: 16,
                        color: Colors.white,
                      ),
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

  Widget _buildEventsList(BuildContext context, EventState state) {
    if (state is NearbyEventLoading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    } else if (state is NearbyEventLoaded) {
      if (state.events.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              "No nearby events found",
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.pinkAccent,
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
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    "Event Name",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "Host",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Expanded(flex: 1, child: SizedBox()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.events.length,
            itemBuilder: (context, index) {
              final event = state.events[index];
              return _EventListItem(event: event);
            },
          ),
        ],
      );
    } else if (state is EventFailure) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            "Error: ${state.error}",
            style: GoogleFonts.poppins(color: Colors.pinkAccent),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          "Search for events",
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
      ),
    );
  }
}
