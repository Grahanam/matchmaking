import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/models/question_model.dart';
import 'package:app/pages/questions/create_question_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

String get geminiApiKey => dotenv.env['GEMINI_API_TOKEN'] ?? '';

class LocationSuggestion {
  final String displayName;
  final double lat;
  final double lon;

  LocationSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

extension StringCasingExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _searchController = TextEditingController();
  final MapController _mapController = MapController();
  List<LocationSuggestion> _locationSuggestions = [];
  bool _isMapControllerReady = false;

  bool _isRefreshingQuestions = false;

  int? guestCount;

  final _formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final List<int> guestOptions = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  LatLng? _selectedLocation;
  bool _isMapVisible = true;
  final bool _hostParticipates = false;
  Position? _currentPosition;
  String? _city;
  String? _state;

  String matchingType = 'platonic';

  DateTime? selectedDateTime;
  Duration selectedDuration = const Duration(hours: 2);

  bool _isAILoading = false;
  final TextEditingController _aiPromptController = TextEditingController();
  Map<String, dynamic>? _aiSuggestions;

  List<String> selectedQuestionIds = [];
  List<QuestionModel> availableQuestions = [];
  Map<QuestionCategory, List<QuestionModel>> groupedQuestions = {};

  File? _pickedCoverImage;
  bool _uploadingCoverImage = false;
  String? _currentCoverImageUrl;
  final ImagePicker _imagePicker = ImagePicker();

  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  Future<void> _pickCoverImage() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _pickedCoverImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadCoverImage() async {
    if (_pickedCoverImage == null) return null;

    setState(() => _uploadingCoverImage = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // Create a reference to the location in Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('event_covers')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Upload the file to Firebase Storage
      await storageRef.putFile(_pickedCoverImage!);

      // Get the download URL
      final downloadURL = await storageRef.getDownloadURL();

      if (!mounted) return null; // Check if widget is still mounted

      setState(() => _uploadingCoverImage = false);
      return downloadURL;
    } catch (e) {
      debugPrint('Error uploading cover image: $e');

      if (!mounted) return null; // Check if widget is still mounted

      setState(() => _uploadingCoverImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload cover image')),
      );
      return null;
    }
  }

  Future<void> _fetchQuestions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Single query to get both common and user's custom questions
      final snapshot =
          await FirebaseFirestore.instance
              .collection('questionmodels')
              .where(
                Filter.or(
                  // Get common questions (no user ID)
                  Filter('userId', isNull: true),
                  // Get custom questions for current user
                  Filter('userId', isEqualTo: user.uid),
                ),
              )
              .get();

      if (!mounted) return;

      final allQuestions =
          snapshot.docs.map((doc) => QuestionModel.fromFirestore(doc)).toList();

      // Group questions by category
      final grouped = <QuestionCategory, List<QuestionModel>>{};
      for (var question in allQuestions) {
        grouped.putIfAbsent(question.category, () => []).add(question);
      }

      setState(() {
        availableQuestions = allQuestions;
        groupedQuestions = grouped;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching questions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load questions: ${e.toString()}')),
      );
    }
  }

  FutureOr<List<LocationSuggestion>> _searchLocations(String query) async {
    if (query.isEmpty) {
      return <LocationSuggestion>[];
    }

    try {
      final encodedQuery = Uri.encodeQueryComponent(query);
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=$encodedQuery',
        ),
        headers: {'User-Agent': 'MatchmakingApp/1.0 (your@email.com)'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<LocationSuggestion>((item) {
          return LocationSuggestion(
            displayName: item['display_name'] ?? 'Unknown location',
            lat: double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
            lon: double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
          );
        }).toList();
      } else {
        debugPrint('API error: ${response.statusCode} ${response.body}');
        throw Exception('Failed to search locations');
      }
    } catch (e) {
      debugPrint('Search error: $e');
      return <LocationSuggestion>[];
    }
  }

  // Add this method to handle location selection
  void _onLocationSelected(LocationSuggestion suggestion) {
    final point = LatLng(suggestion.lat, suggestion.lon);
    setState(() {
      _selectedLocation = point;
      latController.text = suggestion.lat.toString();
      lngController.text = suggestion.lon.toString();
      _searchController.clear();
      _locationSuggestions = [];
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      // Move map to the selected location
      _mapController.move(_selectedLocation!, 13.0);
    });
    _reverseGeocode(point);
  }

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isMapControllerReady = true;
        });
      }
    });

    // Initialize map with current location or default view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    latController.dispose();
    lngController.dispose();
    _mapController.dispose();
    _searchController.dispose();
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}',
        ),
        headers: {'User-Agent': 'MatchmakingApp/1.0 (your@email.com)'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        // print(address);
        if (address != null) {
          setState(() {
            // Different regions use different keys for city/state
            _city =
                address['city'] ??
                address['state_district'] ??
                address['town'] ??
                address['county'] ??
                address['village'] ??
                'Unknown';

            _state =
                address['state'] ??
                address['region'] ??
                address['province'] ??
                'Unknown';
          });
        }
      } else {
        debugPrint('Reverse geocoding error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // 1. Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      // 2. Handle different permission states
      if (permission == LocationPermission.denied) {
        // Permission was denied previously, request it again
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permission denied again
          if (mounted) {
            // Check if the widget is still mounted
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Location permissions denied. Please enable location access in settings.',
                ),
                backgroundColor: Colors.orange, // Or your preferred color
              ),
            );
          }
          // Set a default location if permission is denied
          setState(() {
            _selectedLocation = LatLng(0, 0); // World map view
          });
          return; // Stop execution if permission is denied
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permission denied permanently, open app settings
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permissions permanently denied. Please enable location access in app settings.',
              ),
              backgroundColor: Colors.red, // Or your preferred color
            ),
          );
        }
        // Set a default location if permission is permanently denied
        setState(() {
          _selectedLocation = LatLng(0, 0); // World map view
        });
        return; // Stop execution if permission is denied forever
      }

      // 3. If permission is granted (either initially or after request)
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Check if location services are enabled
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Location services are disabled. Please enable location services.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          // Set a default location if services are disabled
          setState(() {
            _selectedLocation = LatLng(0, 0); // World map view
          });
          return;
        }

        // 4. Now, get the current position
        final position = await Geolocator.getCurrentPosition();

        // 5. Update the state with the new position
        if (mounted) {
          // Crucial check before calling setState
          setState(() {
            _currentPosition = position;
            _selectedLocation = LatLng(position.latitude, position.longitude);
            latController.text = position.latitude.toString();
            lngController.text = position.longitude.toString();
          });

          await Future.delayed(const Duration(milliseconds: 100));
          // if (_mapController.ready) {
          if (_isMapControllerReady) {
            _mapController.move(_selectedLocation!, 13.0);
          }
          // }
          // Perform reverse geocoding after setting the location
          await _reverseGeocode(_selectedLocation!);
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      // Provide user feedback on any other errors
      if (mounted) {
        String errorMessage = 'Default Location Selected.';
        // Check the type of exception
        if (e is LocationServiceDisabledException) {
          errorMessage = 'Location services are disabled.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
      // Set a default location on error
      setState(() {
        _selectedLocation = LatLng(0, 0);
      });
      // Future.delayed(const Duration(milliseconds: 100), () {
      //   if (_isMapControllerReady) {
      //     _mapController.move(
      //       _selectedLocation!,
      //       3.0,
      //     ); // Zoom level 3 for continent view
      //   }
      // });
    }
  }

  // Removed _toggleMapVisibility method

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.scale:
        return 'Scale';
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.openText:
        return 'Open Text';
      case QuestionType.rank:
        return 'Ranking';
      case QuestionType.multiSelect:
        return 'Multi-Select';
    }
  }

  String _getCategoryLabel(QuestionCategory category) {
    switch (category) {
      case QuestionCategory.coreValues:
        return 'Core Values';
      case QuestionCategory.personality:
        return 'Personality';
      case QuestionCategory.interests:
        return 'Interests (Music, etc.)';
      case QuestionCategory.goals:
        return 'Relationship Goals';
      case QuestionCategory.dealbreakers:
        return 'Dealbreakers';
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
            // colorScheme: ColorScheme.dark(
            //   primary: Theme.of(context).colorScheme.primary,
            //   onPrimary: Colors.white,
            //   surface: Theme.of(context).colorScheme.surface,
            //   onSurface: Colors.white,
            // ),
            dialogTheme: DialogThemeData(
              // FIXED: DialogTheme -> DialogThemeData
              // backgroundColor: Theme.of(context).colorScheme.surface,
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
            // colorScheme: ColorScheme.dark(
            //   primary: Theme.of(context).colorScheme.primary,
            //   onPrimary: Colors.white,
            //   surface: Theme.of(context).colorScheme.surface,
            //   onSurface: Colors.white,
            // ),
            dialogTheme: DialogThemeData(
              // FIXED: DialogTheme -> DialogThemeData
              // backgroundColor: Theme.of(context).colorScheme.surface,
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

  void _showAISuggestionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "AI Event Assistant",
                      style: GoogleFonts.raleway(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_aiSuggestions == null)
                      TextFormField(
                        controller: _aiPromptController,
                        maxLines: 3,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Describe your event in 1-2 sentences',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed:
                                () => _generateAISuggestions(setModalState),
                          ),
                        ),
                      ),

                    if (_isAILoading)
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),

                    if (_aiSuggestions != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Suggestions",
                            style: GoogleFonts.raleway(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 16),

                          _buildSuggestionItem(
                            "Title",
                            _aiSuggestions!['title'] ?? '',
                            () {
                              titleController.text =
                                  _aiSuggestions!['title'] ?? '';
                              Navigator.pop(context);
                            },
                          ),

                          _buildSuggestionItem(
                            "Description",
                            _aiSuggestions!['description'] ?? '',
                            () {
                              descController.text =
                                  _aiSuggestions!['description'] ?? '';
                              Navigator.pop(context);
                            },
                          ),

                          if (_aiSuggestions!['guest_count'] != null)
                            _buildSuggestionItem(
                              "Guest Count",
                              _aiSuggestions!['guest_count'].toString(),
                              () {
                                setState(() {
                                  guestCount = _aiSuggestions!['guest_count'];
                                });
                                Navigator.pop(context);
                              },
                            ),

                          if (_aiSuggestions!['reason'] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                "Reason: ${_aiSuggestions!['reason']}",
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            _aiPromptController.clear();
                            _aiSuggestions = null;
                            Navigator.pop(context);
                          },
                          child: const Text("Cancel"),
                        ),
                        if (_aiSuggestions != null)
                          ElevatedButton(
                            onPressed: () {
                              titleController.text =
                                  _aiSuggestions!['title'] ??
                                  titleController.text;
                              descController.text =
                                  _aiSuggestions!['description'] ??
                                  descController.text;

                              if (_aiSuggestions!['guest_count'] != null) {
                                setState(
                                  () =>
                                      guestCount =
                                          _aiSuggestions!['guest_count'],
                                );
                              }
                              Navigator.pop(context);
                            },
                            child: const Text("Apply All"),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSuggestionItem(
    String label,
    String value,
    VoidCallback onApply,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
        trailing: IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: onApply,
        ),
      ),
    );
  }

  Future<void> _generateAISuggestions(
    void Function(void Function()) setModalState,
  ) async {
    setModalState(() => _isAILoading = true);

    try {
      final prompt = """
You are an expert event planner specializing in matchmaking events. Based on the user's description:
"${_aiPromptController.text}"

Generate compelling event title and description suggestions. Also suggest suitable guest count.

Return response in JSON format with these keys:
{
  "title": "Event title suggestion",
  "description": "Event description suggestion",
  "guest_count": suggested guest count number,
  "reason": "Brief explanation of suggestions"
}
""";

      final geminiApiEndpoint =
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$geminiApiKey';

      final response = await http.post(
        Uri.parse(geminiApiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
          "generationConfig": {"responseMimeType": "application/json"},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['candidates'][0]['content']['parts'][0]['text'];
        final suggestions = jsonDecode(content) as Map<String, dynamic>;

        setModalState(() {
          _aiSuggestions = suggestions;
          _isAILoading = false;
        });
      } else {
        throw Exception(
          'Gemini API error: ${response.statusCode}\n${response.body}',
        );
      }
    } catch (e) {
      setModalState(() {
        _isAILoading = false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI error: ${e.toString()}')));
      });
    }
  }

  Widget _buildChoiceField(
    String title,
    String value,
    void Function(String) onChange,
    List<Map<String, String>> options,
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

  Widget _buildSectionCard(Widget child) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        title: Text(
          "Create Event",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
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
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.auto_awesome, color: Colors.pinkAccent),
            label: const Text(
              'AI Suggestions',
              style: TextStyle(
                color: Colors.pinkAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              _aiPromptController.clear();
              _aiSuggestions = null;
              _showAISuggestionModal();
            },
          ),
        ],
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
        child: Padding(
          padding: const EdgeInsets.only(right: 16, left: 16),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollController,
              children: [
                // Replace the entire event cover section with this code:
                _buildSectionCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Event Cover Photo",
                        style: GoogleFonts.raleway(
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child:
                                    _pickedCoverImage != null
                                        ? Image.file(
                                          _pickedCoverImage!,
                                          fit: BoxFit.cover,
                                        )
                                        : _currentCoverImageUrl != null &&
                                            _currentCoverImageUrl!.isNotEmpty
                                        ? Image.network(
                                          _currentCoverImageUrl!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (
                                            context,
                                            child,
                                            loadingProgress,
                                          ) {
                                            if (loadingProgress == null)
                                              return child;
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value:
                                                    loadingProgress
                                                                .expectedTotalBytes !=
                                                            null
                                                        ? loadingProgress
                                                                .cumulativeBytesLoaded /
                                                            loadingProgress
                                                                .expectedTotalBytes!
                                                        : null,
                                              ),
                                            );
                                          },
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return const Icon(
                                              Icons.image,
                                              size: 60,
                                              color: Colors.grey,
                                            );
                                          },
                                        )
                                        : Icon(
                                          Icons.image,
                                          size: 60,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                  onPressed: _pickCoverImage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_uploadingCoverImage)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
                _buildSectionCard(
                  _buildChoiceField(
                    "What kind of connection?",
                    matchingType,
                    (val) => setState(() => matchingType = val),
                    [
                      {"label": "😊 Just friends", "value": "platonic"},
                      {"label": "💘 Romance", "value": "romantic"},
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                            (value) =>
                                value?.isEmpty ?? true ? 'Required' : null,
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                            (value) =>
                                value?.isEmpty ?? true ? 'Required' : null,
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
                          child: Icon(
                            Icons.calendar_today,
                            size: 20,
                            color:
                                Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant, // Use theme color
                          ),
                        ),
                        title: Text(
                          selectedDateTime == null
                              ? 'Select date & time'
                              : DateFormat(
                                'MMM d, yyyy - h:mm a',
                              ).format(selectedDateTime!),
                          style: TextStyle(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onSurface, // Use theme color
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant, // Use theme color
                        ),
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

                      // Always show the map (removed toggle button)
                      if (_selectedLocation != null && _isMapControllerReady)
                        Column(
                          children: [
                            // Search field
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: TypeAheadField<LocationSuggestion>(
                                controller: _searchController,
                                suggestionsCallback: _searchLocations,
                                itemBuilder: (
                                  context,
                                  LocationSuggestion suggestion,
                                ) {
                                  return ListTile(
                                    leading: const Icon(Icons.location_on),
                                    title: Text(suggestion.displayName),
                                  );
                                },
                                onSelected: _onLocationSelected,
                                builder: (context, controller, focusNode) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      hintText: 'Search for a location...',
                                      prefixIcon: const Icon(Icons.search),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    ),
                                  );
                                },
                                loadingBuilder:
                                    (context) => const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                emptyBuilder:
                                    (context) => const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text('No locations found'),
                                    ),
                              ),
                            ),

                            // Map container
                            // Container(
                            //   height: 250,
                            //   decoration: BoxDecoration(
                            //     borderRadius: BorderRadius.circular(12),
                            //     border: Border.all(
                            //       color: Theme.of(context).colorScheme.outline,
                            //     ),
                            //   ),
                            //   child: ClipRRect(
                            //     borderRadius: BorderRadius.circular(12),
                            //     child: FlutterMap(
                            //       mapController: _mapController,
                            //       options: MapOptions(
                            //         initialCenter: _selectedLocation!,
                            //         initialZoom: 15.0,
                            //         onTap: (tapPosition, point) async {
                            //           setState(() {
                            //             _selectedLocation = point;
                            //             latController.text =
                            //                 point.latitude.toString();
                            //             lngController.text =
                            //                 point.longitude.toString();
                            //             _searchController.clear();
                            //           });

                            //           await _reverseGeocode(point); // Add this
                            //         },
                            //       ),
                            //       children: [
                            //         TileLayer(
                            //           urlTemplate:
                            //               'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                            //           userAgentPackageName: 'com.example.app',
                            //         ),
                            //         RichAttributionWidget(
                            //           attributions: [
                            //             TextSourceAttribution(
                            //               '© OpenStreetMap contributors',
                            //               // onTap: () async {
                            //               //   final url = Uri.parse('https://www.openstreetmap.org/copyright');
                            //               //   if (await canLaunchUrl(url)) {
                            //               //     await launchUrl(url);
                            //               //   }
                            //               // },
                            //             ),
                            //           ],
                            //         ),

                            //         MarkerLayer(
                            //           markers: [
                            //             Marker(
                            //               point: _selectedLocation!,
                            //               width: 40,
                            //               height: 40,
                            //               child: const Icon(
                            //                 Icons.location_pin,
                            //                 color: Colors.red,
                            //                 size: 40,
                            //               ),
                            //             ),
                            //           ],
                            //         ),
                            //       ],
                            //     ),
                            //   ),
                            // ),
                            // Simple approach without FutureBuilder
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
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: _selectedLocation!,
                                    initialZoom: 1.0,
                                    onTap: (tapPosition, point) async {
                                      setState(() {
                                        _selectedLocation = point;
                                        latController.text =
                                            point.latitude.toString();
                                        lngController.text =
                                            point.longitude.toString();
                                        _searchController.clear();
                                      });
                                      await _reverseGeocode(point);
                                    },
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.example.app',
                                    ),
                                    // RichAttributionWidget(
                                    //   attributions: [
                                    //     TextSourceAttribution(
                                    //       'OpenStreetMap contributors',
                                    //     ),
                                    //   ],
                                    // ),
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
                          ],
                        )
                      else
                        const Center(child: CircularProgressIndicator()),
                      if (_city != null || _state != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '${_city ?? ''}, ${_state ?? ''}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),

                      // Removed: latitude and longitude text fields

                      // Add current location button
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (_currentPosition != null) {
                            final point = LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            );
                            setState(() {
                              _selectedLocation = point;
                              latController.text = point.latitude.toString();
                              lngController.text = point.longitude.toString();
                            });
                            //  if (_mapController.ready) {
                            _mapController.move(point, 13.0);
                            // }
                            await _reverseGeocode(point); // Add this
                          } else {
                            await _getCurrentLocation();
                          }
                        },
                        icon: const Icon(Icons.my_location),
                        label: const Text("Use Current Location"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondaryContainer,
                          foregroundColor:
                              Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),

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

                      // Add the informational message
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "These questions will be asked to applicants and used for matchmaking",
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                      // More prominent "Add Custom Question" button
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            // Use await to wait for the CreateQuestionPage to return
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreateQuestionPage(),
                              ),
                            );

                            // Refresh the questions after returning from CreateQuestionPage
                            setState(() => _isRefreshingQuestions = true);
                            await _fetchQuestions();
                            setState(() => _isRefreshingQuestions = false);
                          },
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text("Create Custom Question"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      if (_isRefreshingQuestions)
                        const Center(child: CircularProgressIndicator())
                      else if (groupedQuestions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No questions available. Add some questions to help with matchmaking.',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...groupedQuestions.entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 8,
                                ),
                                child: Text(
                                  _getCategoryLabel(entry.key),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              ...entry.value.map(
                                (q) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    q.text,
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Question type badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          _getQuestionTypeLabel(q.type),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),

                                      // Display options for relevant question types
                                      if (q.options != null &&
                                          q.options!.isNotEmpty)
                                        Text(
                                          'Options: ${q.options!.join(', ')}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                      // Display scale range for scale questions
                                      if (q.type == QuestionType.scale &&
                                          q.scaleMin != null &&
                                          q.scaleMax != null)
                                        Text(
                                          'Scale: ${q.scaleMin} to ${q.scaleMax}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                  value: selectedQuestionIds.contains(q.id),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        selectedQuestionIds.add(q.id);
                                      } else {
                                        selectedQuestionIds.removeWhere(
                                          (id) => id == q.id,
                                        );
                                      }
                                    });
                                  },
                                  activeColor:
                                      Theme.of(context).colorScheme.primary,
                                  secondary: Text(
                                    'W: ${q.weight}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                    ],
                  ),
                ),

                // _buildSectionCard(
                //   Column(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Text(
                //         'Questions for Guests',
                //         style: GoogleFonts.raleway(
                //           textStyle: const TextStyle(
                //             fontSize: 16,
                //             fontWeight: FontWeight.bold,
                //           ),
                //         ),
                //       ),
                //       const SizedBox(height: 12),

                //       if (groupedQuestions.isEmpty)
                //         Padding(
                //           padding: const EdgeInsets.symmetric(vertical: 8),
                //           child: Text(
                //             'No questions available',
                //             style: TextStyle(color: Colors.grey.shade400),
                //           ),
                //         )
                //       else
                //         ...groupedQuestions.entries.map((entry) {
                //           return Column(
                //             crossAxisAlignment: CrossAxisAlignment.start,
                //             children: [
                //               Padding(
                //                 padding: const EdgeInsets.only(
                //                   top: 16,
                //                   bottom: 8,
                //                 ),
                //                 child: Text(
                //                   _getCategoryLabel(entry.key),
                //                   style: TextStyle(
                //                     fontWeight: FontWeight.bold,
                //                     fontSize: 16,
                //                     color:
                //                         Theme.of(context).colorScheme.primary,
                //                   ),
                //                 ),
                //               ),
                //               ...entry.value.map(
                //                 (q) => CheckboxListTile(
                //                   contentPadding: EdgeInsets.zero,
                //                   title: Text(
                //                     q.text,
                //                     style: TextStyle(
                //                       color:
                //                           Theme.of(
                //                             context,
                //                           ).colorScheme.onSurface,
                //                       fontWeight: FontWeight.w500,
                //                     ),
                //                   ),
                //                   subtitle: Column(
                //                     crossAxisAlignment:
                //                         CrossAxisAlignment.start,
                //                     children: [
                //                       // Question type badge
                //                       Container(
                //                         padding: const EdgeInsets.symmetric(
                //                           horizontal: 6,
                //                           vertical: 2,
                //                         ),
                //                         decoration: BoxDecoration(
                //                           color:
                //                               Theme.of(context)
                //                                   .colorScheme
                //                                   .surfaceContainerHighest,
                //                           borderRadius: BorderRadius.circular(
                //                             4,
                //                           ),
                //                         ),
                //                         child: Text(
                //                           _getQuestionTypeLabel(q.type),
                //                           style: TextStyle(
                //                             fontSize: 12,
                //                             color:
                //                                 Theme.of(
                //                                   context,
                //                                 ).colorScheme.onSurfaceVariant,
                //                           ),
                //                         ),
                //                       ),
                //                       const SizedBox(height: 4),

                //                       // Display options for relevant question types
                //                       if (q.options != null &&
                //                           q.options!.isNotEmpty)
                //                         Text(
                //                           'Options: ${q.options!.join(', ')}',
                //                           style: TextStyle(
                //                             fontSize: 12,
                //                             color:
                //                                 Theme.of(
                //                                   context,
                //                                 ).colorScheme.onSurfaceVariant,
                //                             fontStyle: FontStyle.italic,
                //                           ),
                //                           maxLines: 2,
                //                           overflow: TextOverflow.ellipsis,
                //                         ),

                //                       // Display scale range for scale questions
                //                       if (q.type == QuestionType.scale &&
                //                           q.scaleMin != null &&
                //                           q.scaleMax != null)
                //                         Text(
                //                           'Scale: ${q.scaleMin} to ${q.scaleMax}',
                //                           style: TextStyle(
                //                             fontSize: 12,
                //                             color:
                //                                 Theme.of(
                //                                   context,
                //                                 ).colorScheme.onSurfaceVariant,
                //                           ),
                //                         ),
                //                     ],
                //                   ),
                //                   value: selectedQuestionIds.contains(q.id),
                //                   onChanged: (bool? value) {
                //                     setState(() {
                //                       if (value == true) {
                //                         selectedQuestionIds.add(q.id);
                //                       } else {
                //                         selectedQuestionIds.removeWhere(
                //                           (id) => id == q.id,
                //                         );
                //                       }
                //                     });
                //                   },
                //                   activeColor:
                //                       Theme.of(context).colorScheme.primary,
                //                   secondary: Text(
                //                     'W: ${q.weight}',
                //                     style: TextStyle(
                //                       fontWeight: FontWeight.bold,
                //                       color:
                //                           Theme.of(context).colorScheme.primary,
                //                     ),
                //                   ),
                //                 ),
                //               ),
                //             ],
                //           );
                //         }),
                //     ],
                //   ),
                // ),
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
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed:
                          isLoading
                              ? null
                              : () async {
                                final eventBloc = context.read<EventBloc>();
                                if (!_formKey.currentState!.validate()) return;

                                String? coverImageUrl;
                                if (_pickedCoverImage != null) {
                                  coverImageUrl = await _uploadCoverImage();
                                  if (coverImageUrl == null)
                                    return; // Stop if upload failed
                                }

                                if (!mounted) return;

                                final city = _city ?? '';
                                final state = _state ?? '';
                                final cityKeywords =
                                    <String>{
                                      // --- Full Names ---
                                      if (_city != null &&
                                          _city!.isNotEmpty) ...[
                                        _city!.toLowerCase().trim(),
                                        _city!.trim(),
                                      ],
                                      if (_state != null &&
                                          _state!.isNotEmpty) ...[
                                        _state!.toLowerCase().trim(),
                                        _state!.trim(),
                                      ],
                                      if (_city != null &&
                                          _state != null &&
                                          _city!.isNotEmpty &&
                                          _state!.isNotEmpty) ...[
                                        '${_city!.toLowerCase().trim()}, ${_state!.toLowerCase().trim()}',
                                        '${_city!.trim()}, ${_state!.trim()}',
                                      ],
                                      // --- Individual Words ---
                                      if (_city != null && _city!.isNotEmpty)
                                        ..._city!
                                            .split(RegExp(r'[\s\-]+'))
                                            .where(
                                              (word) => word.trim().isNotEmpty,
                                            )
                                            .map(
                                              (word) =>
                                                  word.trim().toLowerCase(),
                                            ),
                                      if (_state != null && _state!.isNotEmpty)
                                        ..._state!
                                            .split(RegExp(r'[\s\-]+'))
                                            .where(
                                              (word) => word.trim().isNotEmpty,
                                            )
                                            .map(
                                              (word) =>
                                                  word.trim().toLowerCase(),
                                            ),
                                    }.where((e) => e.isNotEmpty).toSet().toList();

                                final eventData = {
                                  'title': titleController.text,
                                  'description': descController.text,
                                  'location': GeoPoint(
                                    double.tryParse(latController.text) ?? 0.0,
                                    double.tryParse(lngController.text) ?? 0.0,
                                  ),
                                  'city': city,
                                  'state': state,
                                  'cityKeywords': cityKeywords,
                                  'matchingType': matchingType,
                                  'guestCount': guestCount ?? 0,
                                  'startTime':
                                      selectedDateTime ?? DateTime.now(),
                                  'endTime': (selectedDateTime ??
                                          DateTime.now())
                                      .add(selectedDuration),
                                  'questionnaire': selectedQuestionIds,
                                  'createdBy':
                                      FirebaseAuth.instance.currentUser!.uid,
                                  'hostParticipates': _hostParticipates,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                  'cover':
                                      coverImageUrl ??
                                      _currentCoverImageUrl, // Add cover URL
                                };

                                eventBloc.add(
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
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
