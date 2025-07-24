import 'dart:async';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/models/question_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:app/services/firestore_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

  String get geminiApiKey => dotenv.env['GEMINI_API_TOKEN'] ?? '';
  String get _aiApiToken => dotenv.env['AI_API_TOKEN'] ?? '';
const String _aiApiEndpoint =
    'https://models.github.ai/inference/chat/completions';

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
  final bool _isSearching = false;

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
  String? _city;
  String? _state;

  DateTime? selectedDateTime;
  Duration selectedDuration = const Duration(hours: 2);
  String matchingType = 'platonic';
  String guestType = 'friends';
  String locationType = 'home';

  bool _isAILoading = false;
  final TextEditingController _aiPromptController = TextEditingController();
  Map<String, dynamic>? _aiSuggestions;

  List<String> selectedQuestionIds = [];
  // List<Map<String, dynamic>> availableQuestions = [];
  List<QuestionModel> availableQuestions = []; // Changed to QuestionModel list
  Map<QuestionCategory, List<QuestionModel>> groupedQuestions = {};

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

    // Move map to the selected location
    _mapController.move(_selectedLocation!, 15.0);
    _reverseGeocode(point);
  }

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
    _mapController.dispose();
    _searchController.dispose();
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
        print(address);
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

  // Add this new method to get current location
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        // if (_selectedLocation == null) {
        _selectedLocation ??= LatLng(position.latitude, position.longitude);
        // }
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

  // Future<void> _fetchQuestions() async {
  //   try {
  //     final snapshot =
  //         await FirebaseFirestore.instance.collection('questionmodels').get();

  //     if (!mounted) {
  //       return;
  //     }

  //     final questions =
  //         snapshot.docs.map((doc) {
  //           return QuestionModel.fromFirestore(doc);
  //         }).toList();

  //     // Group questions by category
  //     final grouped = <QuestionCategory, List<QuestionModel>>{};
  //     for (var question in questions) {
  //       grouped.putIfAbsent(question.category, () => []).add(question);
  //     }

  //     setState(() {
  //       availableQuestions = questions;
  //       groupedQuestions = grouped;
  //     });
  //   } catch (e) {
  //     if (!mounted) {
  //       return;
  //     }
  //     debugPrint('Error fetching questions: $e');
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Failed to load questions: ${e.toString()}')),
  //     );
  //   }
  // }

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

  //   Future<void> _generateAISuggestions(void Function(void Function()) setModalState) async {
  //     setModalState(() => _isAILoading = true);

  //     try {
  //       final prompt = """
  // You are an expert event planner specializing in matchmaking events. Based on the user's description:
  // "${_aiPromptController.text}"

  // Generate compelling event title and description suggestions. Also suggest suitable guest count.

  // Return response in JSON format with these keys:
  // {
  //   "title": "Event title suggestion",
  //   "description": "Event description suggestion",
  //   "guest_count": suggested guest count number,
  //   "reason": "Brief explanation of suggestions"
  // }
  // """;

  //       final response = await http.post(
  //         Uri.parse('https://models.github.ai/inference/chat/completions'),
  //        headers: {
  //           'Authorization': 'Bearer $_aiApiToken',
  //           'Content-Type': 'application/json',
  //           'Accept': 'application/json',
  //         },
  //         body: jsonEncode({
  //           "model": "openai/gpt-4.1",
  //           "messages": [
  //             {
  //               "role": "system",
  //               "content": "You are a helpful event planning assistant. Return ONLY valid JSON objects.",
  //             },
  //             {"role": "user", "content": prompt},
  //           ],
  //           "max_tokens": 500,
  //           "temperature": 0.7,
  //           "response_format": {"type": "json_object"},
  //         }),
  //       );

  //       print(response.statusCode);

  //       if (response.statusCode == 200) {
  //         print('hi');
  //         final data = jsonDecode(response.body);

  //         final content = data['choices'][0]['message']['content'];
  //         final suggestions = jsonDecode(content) as Map<String, dynamic>;
  //         print('$content');
  //         setModalState(() {
  //           _aiSuggestions = suggestions;
  //           _isAILoading = false;
  //         });
  //       } else {
  //         throw Exception('AI service error: ${response.statusCode}');
  //       }
  //     } catch (e) {
  //       setModalState(() {
  //         _isAILoading = false;
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(content: Text('AI error: ${e.toString()}')),
  //         );
  //       });
  //     }
  //   }

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

      final geminiApiEndpoint ='https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$geminiApiKey';

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
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AI Suggestions'),
            onPressed: () {
              _aiPromptController.clear();
              _aiSuggestions = null;
              _showAISuggestionModal();
            },
          ),
        ],
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
                                  initialZoom: 15.0,
                                  onTap: (tapPosition, point) async {
                                    setState(() {
                                      _selectedLocation = point;
                                      latController.text =
                                          point.latitude.toString();
                                      lngController.text =
                                          point.longitude.toString();
                                      _searchController.clear();
                                    });

                                    await _reverseGeocode(point); // Add this
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
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
                        ],
                      ),
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

                    // if (_isMapVisible && _selectedLocation != null)
                    //   Container(
                    //     height: 250,
                    //     decoration: BoxDecoration(
                    //       borderRadius: BorderRadius.circular(12),
                    //       border: Border.all(
                    //         color: Theme.of(context).colorScheme.outline,
                    //       ),
                    //     ),
                    //     child: ClipRRect(
                    //       borderRadius: BorderRadius.circular(12),
                    //       child: FlutterMap(
                    //         options: MapOptions(
                    //           initialCenter: _selectedLocation!,
                    //           initialZoom: 15.0,
                    //           onTap: (tapPosition, point) {
                    //             setState(() {
                    //               _selectedLocation = point;
                    //               latController.text =
                    //                   point.latitude.toString();
                    //               lngController.text =
                    //                   point.longitude.toString();
                    //             });
                    //           },
                    //         ),
                    //         children: [
                    //           TileLayer(
                    //             urlTemplate:
                    //                 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                    //             userAgentPackageName: 'com.example.app',
                    //           ),
                    //           MarkerLayer(
                    //             markers: [
                    //               Marker(
                    //                 point: _selectedLocation!,
                    //                 width: 40,
                    //                 height: 40,
                    //                 child: const Icon(
                    //                   Icons.location_pin,
                    //                   color: Colors.red,
                    //                   size: 40,
                    //                 ),
                    //               ),
                    //             ],
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
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
                            Theme.of(context).colorScheme.onSecondaryContainer,
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
                    const SizedBox(height: 12),

                    if (groupedQuestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No questions available',
                          style: TextStyle(color: Colors.grey.shade400),
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
                                  color: Theme.of(context).colorScheme.primary,
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
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(4),
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

              const SizedBox(height: 16),

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
              //       if (availableQuestions.isEmpty)
              //         Padding(
              //           padding: const EdgeInsets.symmetric(vertical: 8),
              //           child: Text(
              //             'No questions available',
              //             style: TextStyle(color: Colors.grey.shade400),
              //           ),
              //         )
              //       else
              //         ...availableQuestions.map(
              //           (q) => CheckboxListTile(
              //             contentPadding: EdgeInsets.zero,
              //             title: Text(
              //               q['title'],
              //               style: TextStyle(
              //                 color: Theme.of(context).colorScheme.onSurface,
              //               ),
              //             ),
              //             value: selectedQuestionIds.contains(q['id']),
              //             onChanged: (bool? value) {
              //               setState(() {
              //                 if (value == true) {
              //                   selectedQuestionIds.add(q['id']);
              //                 } else {
              //                   selectedQuestionIds.removeWhere(
              //                     (id) => id == q['id'],
              //                   );
              //                 }
              //               });
              //             },
              //             activeColor: Theme.of(context).colorScheme.primary,
              //           ),
              //         ),
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

              // Row(
              //   children: [
              //     Checkbox(
              //       value: _hostParticipates,
              //       onChanged:
              //           (value) =>
              //               setState(() => _hostParticipates = value ?? true),
              //       activeColor: Theme.of(context).colorScheme.primary,
              //     ),
              //     const SizedBox(width: 8),
              //     Flexible(
              //       child: Text(
              //         "I will participate in this event",
              //         style: GoogleFonts.raleway(
              //           fontSize: 15,
              //           color: Theme.of(context).colorScheme.onSurface,
              //         ),
              //       ),
              //     ),
              //   ],
              // ),
              // Padding(
              //   padding: const EdgeInsets.only(left: 32),
              //   child: Text(
              //     _hostParticipates
              //         ? "You'll be included in matchmaking"
              //         : "You'll only manage the event",
              //     style: GoogleFonts.raleway(
              //       fontSize: 13,
              //       color: Theme.of(context).colorScheme.onSurfaceVariant,
              //       fontStyle: FontStyle.italic,
              //     ),
              //   ),
              // ),
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
                              final city = _city ?? '';
                              final state = _state ?? '';

                              // Split into lowercase keyword list
                              // final cityKeywords =
                              //     {
                              //       ...city.toLowerCase().split(' '),
                              //       ...state.toLowerCase().split(' '),
                              //       city.toLowerCase(),
                              //       state.toLowerCase(),
                              //     }.toList();

                              final cityKeywords =
                                  {
                                        _city?.toLowerCase().trim(),
                                        _state?.toLowerCase().trim(),
                                        _city?.trim(),
                                        _state?.trim(),
                                        '${_city ?? ''}, ${_state ?? ''}'
                                            .toLowerCase()
                                            .trim(),
                                      }
                                      .where((e) => e != null && e.isNotEmpty)
                                      .cast<String>()
                                      .toList();
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
                                'guestType': guestType,
                                'guestCount': guestCount ?? 0,
                                'locationType': locationType,
                                'startTime': selectedDateTime ?? DateTime.now(),
                                'endTime': (selectedDateTime ?? DateTime.now())
                                    .add(selectedDuration),
                                'questionnaire': selectedQuestionIds,
                                'createdBy':
                                    FirebaseAuth.instance.currentUser!.uid,
                                'hostParticipates': _hostParticipates,
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
