import 'dart:ui' as ui;

import 'package:app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app/models/question_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

String get geminiApiKey => dotenv.env['GEMINI_API_TOKEN'] ?? '';

class CreateQuestionPage extends StatefulWidget {
  final QuestionModel? existingQuestion;

  const CreateQuestionPage({super.key, this.existingQuestion});

  @override
  _CreateQuestionPageState createState() => _CreateQuestionPageState();
}

class _CreateQuestionPageState extends State<CreateQuestionPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _textController = TextEditingController();
  QuestionType _questionType = QuestionType.multipleChoice;
  QuestionCategory _category = QuestionCategory.interests;
  final List<TextEditingController> _optionControllers = [];
  int? _scaleMin;
  int? _scaleMax;
  int _weight = 3; // Default weight
  bool _isSubmitting = false;
  bool _isAILoading = false;
  final TextEditingController _aiPromptController = TextEditingController();
  QuestionModel? _aiSuggestion;

  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    if (widget.existingQuestion != null) {
      _initializeWithExistingQuestion();
    } else {
      _addOptionField();
    }
  }
  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  void _initializeWithExistingQuestion() {
    final question = widget.existingQuestion!;
    _textController.text = question.text;
    _questionType = question.type;
    _category = question.category;
    _weight = question.weight;
    _scaleMin = question.scaleMin;
    _scaleMax = question.scaleMax;

    if (question.options != null) {
      for (var option in question.options!) {
        final controller = TextEditingController(text: option);
        _optionControllers.add(controller);
      }
    }
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
                      "AI Question Assistant",
                      style: GoogleFonts.raleway(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_aiSuggestion == null)
                      TextFormField(
                        controller: _aiPromptController,
                        maxLines: 3,
                        autofocus: true, // Auto-focus keyboard
                        decoration: InputDecoration(
                          labelText: 'Describe the question you need',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed:
                                () => _generateAISuggestion(setModalState),
                          ),
                        ),
                      ),

                    if (_isAILoading)
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),

                    if (_aiSuggestion != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Suggested Question",
                            style: GoogleFonts.raleway(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 16),

                          _buildSuggestionItem(
                            "Question Text",
                            _aiSuggestion!.text,
                            () {
                              _textController.text = _aiSuggestion!.text;
                              Navigator.pop(context);
                            },
                          ),

                          if (_aiSuggestion!.options != null &&
                              _aiSuggestion!.options!.isNotEmpty)
                            _buildSuggestionItem(
                              "Options",
                              _aiSuggestion!.options!.join(', '),
                              () {
                                // Clear existing options
                                for (var controller in _optionControllers) {
                                  controller.dispose();
                                }
                                _optionControllers.clear();

                                // Add new options
                                for (var option in _aiSuggestion!.options!) {
                                  _optionControllers.add(
                                    TextEditingController(text: option),
                                  );
                                }
                                setState(() {});
                                Navigator.pop(context);
                              },
                            ),

                          if (_aiSuggestion!.type == QuestionType.scale)
                            _buildSuggestionItem(
                              "Scale Range",
                              "${_aiSuggestion!.scaleMin} to ${_aiSuggestion!.scaleMax}",
                              () {
                                setState(() {
                                  _scaleMin = _aiSuggestion!.scaleMin;
                                  _scaleMax = _aiSuggestion!.scaleMax;
                                });
                                Navigator.pop(context);
                              },
                            ),

                          _buildSuggestionItem(
                            "Type",
                            _getQuestionTypeLabel(_aiSuggestion!.type),
                            () {
                              setState(() {
                                _questionType = _aiSuggestion!.type;
                              });
                              Navigator.pop(context);
                            },
                          ),

                          _buildSuggestionItem(
                            "Category",
                            _getCategoryLabel(_aiSuggestion!.category),
                            () {
                              setState(() {
                                _category = _aiSuggestion!.category;
                              });
                              Navigator.pop(context);
                            },
                          ),

                          _buildSuggestionItem(
                            "Weight",
                            _aiSuggestion!.weight.toString(),
                            () {
                              setState(() {
                                _weight = _aiSuggestion!.weight;
                              });
                              Navigator.pop(context);
                            },
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
                            _aiSuggestion = null;
                            Navigator.pop(context);
                          },
                          child: const Text("Cancel"),
                        ),
                        if (_aiSuggestion != null)
                          ElevatedButton(
                            onPressed: () {
                              // Apply all suggestions
                              _textController.text = _aiSuggestion!.text;
                              setState(() {
                                _questionType = _aiSuggestion!.type;
                                _category = _aiSuggestion!.category;
                                _weight = _aiSuggestion!.weight;

                                if (_aiSuggestion!.options != null) {
                                  // Clear existing options
                                  for (var controller in _optionControllers) {
                                    controller.dispose();
                                  }
                                  _optionControllers.clear();

                                  // Add new options
                                  for (var option in _aiSuggestion!.options!) {
                                    _optionControllers.add(
                                      TextEditingController(text: option),
                                    );
                                  }
                                }

                                if (_aiSuggestion!.type == QuestionType.scale) {
                                  _scaleMin = _aiSuggestion!.scaleMin;
                                  _scaleMax = _aiSuggestion!.scaleMax;
                                }
                              });
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

  // Add this helper method
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

  // Add this AI generation method
  Future<void> _generateAISuggestion(
    void Function(void Function()) setModalState,
  ) async {
    setModalState(() => _isAILoading = true);

    try {
      final prompt = """
You are an expert in creating matchmaking questions. Based on the user's description:
"${_aiPromptController.text}"

Generate a question in JSON format with these fields:
- text: string (the question text)
- type: string (one of: scale, multipleChoice, openText, rank, multiSelect)
- category: string (one of: coreValues, personality, interests, goals, dealbreakers)
- options: list of strings (only required for multipleChoice, multiSelect, rank)
- scaleMin: integer (only required for scale type)
- scaleMax: integer (only required for scale type)
- weight: integer between 1-5 (importance level)

Example response:
{
  "text": "Which musical genre do you enjoy most?",
  "type": "multipleChoice",
  "category": "interests",
  "options": ["Rock", "Pop", "Hip Hop", "Classical", "Jazz"],
  "weight": 4
}

Another example:
{
  "text": "How important is shared taste in music?",
  "type": "scale",
  "category": "interests",
  "scaleMin": 1,
  "scaleMax": 5,
  "weight": 3
}

Now create a question based on the user's request:
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
        final jsonResponse = jsonDecode(content) as Map<String, dynamic>;

        // Map JSON to QuestionModel
        final question = QuestionModel(
          id: '',
          text: jsonResponse['text'] ?? '',
          type: QuestionType.values.firstWhere(
            (e) => e.name == jsonResponse['type'],
            orElse: () => QuestionType.multipleChoice,
          ),
          category: QuestionCategory.values.firstWhere(
            (e) => e.name == jsonResponse['category'],
            orElse: () => QuestionCategory.interests,
          ),
          options:
              jsonResponse['options'] != null
                  ? List<String>.from(jsonResponse['options'])
                  : null,
          scaleMin: jsonResponse['scaleMin'],
          scaleMax: jsonResponse['scaleMax'],
          weight: jsonResponse['weight'] ?? 3,
          createdAt: Timestamp.now(),
        );

        setModalState(() {
          _aiSuggestion = question;
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

  @override
  void dispose() {

     if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    _textController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOptionField() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOptionField(int index) {
    setState(() {
      _optionControllers.removeAt(index);
    });
  }

  Future<void> _submitQuestion() async {
    if (!_formKey.currentState!.validate()) {
      debugPrint('[WARNING] Form validation failed');
      return;
    }

    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not authenticated')));
      return;
    }

    try {
      final question = QuestionModel(
        id: widget.existingQuestion?.id ?? '',
        text: _textController.text,
        type: _questionType,
        category: _category,
        options:
            _questionType == QuestionType.multipleChoice ||
                    _questionType == QuestionType.multiSelect ||
                    _questionType == QuestionType.rank
                ? _optionControllers
                    .map((c) => c.text.trim())
                    .where((text) => text.isNotEmpty)
                    .toList()
                : null,
        scaleMin: _questionType == QuestionType.scale ? _scaleMin : null,
        scaleMax: _questionType == QuestionType.scale ? _scaleMax : null,
        weight: _weight,
        createdAt: widget.existingQuestion?.createdAt ?? Timestamp.now(),
        userId: user.uid, // Add user ID for custom questions
      );

     debugPrint('[DEBUG] Question object: $question');

      if (widget.existingQuestion != null) {
        await FirebaseFirestore.instance
            .collection('user_questions')
            .doc(widget.existingQuestion!.id)
            .update(question.toFirestore());
      } else {
        await FirebaseFirestore.instance
            .collection('user_questions')
            .add(question.toFirestore());
      }

      // Use FirestoreService to save
      await FirestoreService().saveQuestion(question);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingQuestion != null
                  ? 'Question updated!'
                  : 'Question created!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildSectionCard(Widget child) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.existingQuestion != null
              ? 'Edit Question'
              : 'Create Question',
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
          if (widget.existingQuestion == null) // Only show for new questions
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome, color: Colors.pinkAccent),
              label: const Text(
              'AI Suggestions',
              style: TextStyle(
                color: Colors.pinkAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
              onPressed: _showAISuggestionModal,
            ),
          // IconButton(
          //   icon: const Icon(Icons.auto_awesome),
          //   tooltip: 'AI Suggestions',
          //   onPressed: _showAISuggestionModal,
          // ),
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
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionCard(
                  TextFormField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      labelText: 'Question Text',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter question text';
                      }
                      return null;
                    },
                  ),
                ),
          
                _buildSectionCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Question Type'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<QuestionType>(
                        value: _questionType,
                        items:
                            QuestionType.values.map((type) {
                              return DropdownMenuItem<QuestionType>(
                                value: type,
                                child: Text(_getQuestionTypeLabel(type)),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _questionType = value);
                          }
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
          
                _buildSectionCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Category'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<QuestionCategory>(
                        value: _category,
                        items:
                            QuestionCategory.values.map((category) {
                              return DropdownMenuItem<QuestionCategory>(
                                value: category,
                                child: Text(_getCategoryLabel(category)),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _category = value);
                          }
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
          
                _buildSectionCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Question Weight (1-5)'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _weight,
                        items:
                            List.generate(5, (index) => index + 1).map((weight) {
                              return DropdownMenuItem<int>(
                                value: weight,
                                child: Text(
                                  '$weight - ${_getWeightDescription(weight)}',
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _weight = value);
                          }
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
          
                // Scale values (only for scale type)
                if (_questionType == QuestionType.scale)
                  _buildSectionCard(
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _scaleMin?.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min Value',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              _scaleMin = int.tryParse(value);
                            },
                            validator: (value) {
                              if (_scaleMin == null) {
                                return 'Enter a number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: _scaleMax?.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max Value',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              _scaleMax = int.tryParse(value);
                            },
                            validator: (value) {
                              if (_scaleMax == null) {
                                return 'Enter a number';
                              }
                              if (_scaleMin != null && _scaleMax! <= _scaleMin!) {
                                return 'Max must be greater than min';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          
                // Options for MCQ, MultiSelect, and Rank types
                if (_questionType == QuestionType.multipleChoice ||
                    _questionType == QuestionType.multiSelect ||
                    _questionType == QuestionType.rank)
                  _buildSectionCard(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getOptionsLabel()),
                        const SizedBox(height: 8),
                        ..._optionControllers.asMap().entries.map((entry) {
                          final index = entry.key;
                          final controller = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: controller,
                                    decoration: InputDecoration(
                                      labelText: 'Option ${index + 1}',
                                      border: const OutlineInputBorder(),
                                      suffixIcon:
                                          _optionControllers.length > 1
                                              ? IconButton(
                                                icon: const Icon(Icons.remove),
                                                onPressed:
                                                    () => _removeOptionField(index),
                                              )
                                              : null,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Option cannot be empty';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addOptionField,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Option'),
                        ),
                      ],
                    ),
                  ),
          
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitQuestion,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child:
                      _isSubmitting
                          ? const CircularProgressIndicator()
                          : Text(
                            widget.existingQuestion != null
                                ? 'Update Question'
                                : 'Create Question',
                            style: const TextStyle(fontSize: 16),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.scale:
        return 'Scale (1-5)';
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

  String _getWeightDescription(int weight) {
    switch (weight) {
      case 1:
        return 'Low importance';
      case 2:
        return 'Medium-low';
      case 3:
        return 'Medium';
      case 4:
        return 'Important';
      case 5:
        return 'Critical';
      default:
        return '';
    }
  }

  String _getOptionsLabel() {
    switch (_questionType) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice Options';
      case QuestionType.multiSelect:
        return 'Multi-Select Options';
      case QuestionType.rank:
        return 'Items to Rank';
      default:
        return 'Options';
    }
  }
}
