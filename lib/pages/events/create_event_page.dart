import 'package:app/bloc/event/event_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  int? guestCount;
  final _formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final List<int> guestOptions = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  LatLng? _selectedLocation;
  bool _isMapVisible = false;
  bool _hostParticipates = false;
  Position? _currentPosition;

  DateTime? selectedDateTime;
  Duration selectedDuration = const Duration(hours: 2);
  String matchingType = 'platonic';
  String guestType = 'friends';
  String locationType = 'home';

  List<String> selectedQuestionIds = [];
  List<Map<String, dynamic>> availableQuestions = [];

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    latController.dispose();
    lngController.dispose();
    super.dispose();
  }

  // Add this new method to get current location
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        if (_selectedLocation == null) {
          _selectedLocation = LatLng(position.latitude, position.longitude);
        }
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: ${e.toString()}')),
      );
    }
  }

  // Add this new method to toggle map visibility
  void _toggleMapVisibility() {
    setState(() {
      _isMapVisible = !_isMapVisible;
      if (_isMapVisible && _selectedLocation == null) {
        _getCurrentLocation();
      }
    });
  }

  Future<void> _fetchQuestions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('questions')
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        debugPrint('No questions found in the database');
        return;
      }

      setState(() {
        availableQuestions =
            snapshot.docs.map((doc) {
              return {
                'id': doc.id,
                'title': doc['title'],
                'type': doc['type'] ?? 'answer',
              };
            }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching questions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load questions: ${e.toString()}')),
      );
    }
  }

  Future<void> pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              // FIXED: DialogTheme -> DialogThemeData
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              // FIXED: DialogTheme -> DialogThemeData
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time == null || !mounted) return;

    setState(() {
      selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Widget _buildSectionCard(Widget child) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildChoiceField(
    String title,
    String value,
    void Function(String) onChange,
    List<Map<String, String>> options, // Add explicit type annotation here
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.raleway(
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children:
              options
                  .map(
                    (opt) => FilterChip(
                      label: Text(opt['label']!),
                      selected: value == opt['value'],
                      onSelected: (isSelected) {
                        if (isSelected) {
                          final val = opt['value'];
                          if (val != null) {
                            onChange(val);
                          }
                        }
                      },
                      selectedColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        color:
                            value == opt['value']
                                ? Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Create Match Event",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildSectionCard(
                _buildChoiceField(
                  "1. What kind of connection?",
                  matchingType,
                  (val) => setState(() => matchingType = val),
                  [
                    {"label": "😊 Just friends", "value": "platonic"},
                    {"label": "💘 Romance", "value": "romantic"},
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                _buildChoiceField(
                  "2. Who's coming?",
                  guestType,
                  (val) => setState(() => guestType = val),
                  [
                    {"label": "👯 Only my friends", "value": "friends"},
                    {"label": "🔁 Friends bring guests", "value": "plus_one"},
                    {"label": "🌐 From my group", "value": "community"},
                    {"label": "🎟️ Selling tickets", "value": "public"},
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                _buildChoiceField(
                  "3. Where is it happening?",
                  locationType,
                  (val) => setState(() => locationType = val),
                  [
                    {"label": "🏠 At my place", "value": "home"},
                    {"label": "🏞️ Public park", "value": "park"},
                    {"label": "🍕 Restaurant/cafe", "value": "restaurant"},
                    {"label": "🏛️ Event venue", "value": "venue"},
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Event Details",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: titleController,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Event Title',
                        labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      ),
                      validator:
                          (value) => value?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: descController,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      ),
                      validator:
                          (value) => value?.isEmpty ?? true ? 'Required' : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Date & Time",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.calendar_today, size: 20),
                      ),
                      title: Text(
                        selectedDateTime == null
                            ? 'Select date & time'
                            : DateFormat(
                              'MMM d, yyyy - h:mm a',
                            ).format(selectedDateTime!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: pickDateTime,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Event Duration",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Duration>(
                      value: selectedDuration,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => selectedDuration = value);
                        }
                      },
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: Duration(hours: 1),
                          child: Text("1 hour"),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 2),
                          child: Text("2 hours"),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 3),
                          child: Text("3 hours"),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 4),
                          child: Text("4 hours"),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 5),
                          child: Text("5 hours"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Location",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Add map toggle button
                    ElevatedButton.icon(
                      onPressed: _toggleMapVisibility,
                      icon: Icon(_isMapVisible ? Icons.close : Icons.map),
                      label: Text(_isMapVisible ? "Hide Map" : "Select on Map"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Add map view when visible
                    if (_isMapVisible && _selectedLocation != null)
                      Container(
                        height: 250,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: _selectedLocation!,
                              initialZoom: 15.0,
                              onTap: (tapPosition, point) {
                                setState(() {
                                  _selectedLocation = point;
                                  latController.text =
                                      point.latitude.toString();
                                  lngController.text =
                                      point.longitude.toString();
                                });
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _selectedLocation!,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_pin,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (_isMapVisible) const SizedBox(height: 16),

                    // Existing latitude field
                    TextFormField(
                      controller: latController,
                      // ... existing properties
                    ),
                    const SizedBox(height: 16),

                    // Existing longitude field
                    TextFormField(
                      controller: lngController,
                      // ... existing properties
                    ),

                    // Add current location button
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_currentPosition != null) {
                          setState(() {
                            _selectedLocation = LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            );
                            latController.text =
                                _currentPosition!.latitude.toString();
                            lngController.text =
                                _currentPosition!.longitude.toString();
                          });
                        } else {
                          _getCurrentLocation();
                        }
                      },
                      icon: const Icon(Icons.my_location),
                      label: const Text("Use Current Location"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

              // _buildSectionCard(
              //   Column(
              //     crossAxisAlignment: CrossAxisAlignment.start,
              //     children: [
              //       Text(
              //         "Location",
              //         style: GoogleFonts.raleway(
              //           textStyle: const TextStyle(
              //             fontSize: 16,
              //             fontWeight: FontWeight.bold
              //           ),
              //         ),
              //       ),
              //       const SizedBox(height: 16),
              //       TextFormField(
              //         controller: latController,
              //         style: TextStyle(
              //           color: Theme.of(context).colorScheme.onSurface
              //         ),
              //         decoration: InputDecoration(
              //           labelText: 'Latitude',
              //           labelStyle: TextStyle(
              //             color: Theme.of(context).colorScheme.onSurfaceVariant
              //           ),
              //           prefixIcon: const Icon(Icons.location_on),
              //           border: const OutlineInputBorder(
              //             borderRadius: BorderRadius.all(Radius.circular(12)),
              //           ),
              //           filled: true,
              //           fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              //         ),
              //         keyboardType: TextInputType.number,
              //         validator: (value) {
              //           if (value?.isEmpty ?? true) return 'Required';
              //           // if (double.tryParse(value) == null) return 'Invalid number';
              //           return null;
              //         },
              //       ),
              //       const SizedBox(height: 16),
              //       TextFormField(
              //         controller: lngController,
              //         style: TextStyle(
              //           color: Theme.of(context).colorScheme.onSurface
              //         ),
              //         decoration: InputDecoration(
              //           labelText: 'Longitude',
              //           labelStyle: TextStyle(
              //             color: Theme.of(context).colorScheme.onSurfaceVariant
              //           ),
              //           prefixIcon: const Icon(Icons.location_on),
              //           border: const OutlineInputBorder(
              //             borderRadius: BorderRadius.all(Radius.circular(12)),
              //           ),
              //           filled: true,
              //           fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              //         ),
              //         keyboardType: TextInputType.number,
              //         validator: (value) {
              //           if (value?.isEmpty ?? true) return 'Required';
              //           // if (double.tryParse(value) == null) return 'Invalid number';
              //           return null;
              //         },
              //       ),
              //     ],
              //   ),
              // ),
              const SizedBox(height: 16),
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Questions for Guests',
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (availableQuestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No questions available',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      )
                    else
                      ...availableQuestions.map(
                        (q) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            q['title'],
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          value: selectedQuestionIds.contains(q['id']),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                selectedQuestionIds.add(q['id']);
                              } else {
                                selectedQuestionIds.removeWhere(
                                  (id) => id == q['id'],
                                );
                              }
                            });
                          },
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Guest Capacity",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "How many guests are expected?",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children:
                          guestOptions.map((number) {
                            return FilterChip(
                              label: Text('$number'),
                              selected: guestCount == number,
                              onSelected:
                                  (_) => setState(
                                    () => guestCount = number,
                                  ), // FIXED: No string conversion needed
                              selectedColor:
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                              backgroundColor:
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                color:
                                    guestCount == number
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                              ),
                            );
                          }).toList(),
                    ),
                  
                  ],
                ),
              ),

              const SizedBox(height: 24),

                Row(
                children: [
                  Checkbox(
                    value: _hostParticipates,
                    onChanged:
                        (value) =>
                            setState(() => _hostParticipates = value ?? true),
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "I will participate in this event",
                      style: GoogleFonts.raleway(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),  Padding(
        padding: const EdgeInsets.only(left: 32),
        child: Text(
          _hostParticipates 
            ? "You'll be included in matchmaking" 
            : "You'll only manage the event",
          style: GoogleFonts.raleway(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      const SizedBox(height: 24),
              
              BlocConsumer<EventBloc, EventState>(
                listener: (context, state) {
                  if (state is EventSuccess) {
                    Navigator.pop(context);
                  } else if (state is EventFailure) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(state.error)));
                  }
                },
                builder: (context, state) {
                  final isLoading = state is EventSubmitting;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed:
                        isLoading
                            ? null
                            : () {
                              if (!_formKey.currentState!.validate()) return;

                              final eventData = {
                                'title': titleController.text,
                                'description': descController.text,
                                'location': GeoPoint(
                                  double.tryParse(latController.text) ?? 0.0,
                                  double.tryParse(lngController.text) ?? 0.0,
                                ),
                                'matchingType': matchingType,
                                'guestType': guestType,
                                'guestCount': guestCount ?? 0,
                                'locationType': locationType,
                                'startTime': selectedDateTime ?? DateTime.now(),
                                'endTime': (selectedDateTime ?? DateTime.now())
                                    .add(selectedDuration),
                                'questionnaire': selectedQuestionIds,
                                'createdBy':
                                    FirebaseAuth.instance.currentUser!.uid,
                                'hostParticipates':_hostParticipates,
                                'createdAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              };

                              context.read<EventBloc>().add(
                                SubmitEvent(eventData: eventData),
                              );
                            },
                    child: Text(
                      isLoading ? "Creating Event..." : "Create Event",
                      style: GoogleFonts.raleway(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
