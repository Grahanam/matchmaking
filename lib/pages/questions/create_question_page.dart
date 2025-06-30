import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app/models/question.dart'; // Adjust path as needed

class CreateQuestionPage extends StatefulWidget {
  final Question? existingQuestion;

  const CreateQuestionPage({Key? key, this.existingQuestion}) : super(key: key);

  @override
  _CreateQuestionPageState createState() => _CreateQuestionPageState();
}

class _CreateQuestionPageState extends State<CreateQuestionPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  String _questionType = 'text';
  String _eventType = 'both';
  String? _musicType;
  List<TextEditingController> _optionControllers = [];
  int? _minValue;
  int? _maxValue;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingQuestion != null) {
      _initializeWithExistingQuestion();
    } else {
      _addOptionField(); // Start with one option field for new questions
    }
  }

  void _initializeWithExistingQuestion() {
    final question = widget.existingQuestion!;
    _titleController.text = question.title;
    _questionType = question.type;
    _eventType = question.eventType;
    _musicType = question.musicType;
    _minValue = question.min;
    _maxValue = question.max;
    
    // Initialize options
    if (question.options != null) {
      for (var option in question.options!) {
        final controller = TextEditingController(text: option);
        _optionControllers.add(controller);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final questionData = {
        'title': _titleController.text,
        'type': _questionType,
        'eventType': _eventType,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add conditional fields
      if (_questionType == 'mcq' && _optionControllers.isNotEmpty) {
        questionData['options'] = _optionControllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
      }

      if (_questionType == 'range') {
        questionData['min'] = _minValue;
        questionData['max'] = _maxValue;
      }

      if (_questionType == 'spotify_track' && _musicType != null) {
        questionData['musicType'] = _musicType;
      }

      if (widget.existingQuestion != null) {
        // Update existing question
        await FirebaseFirestore.instance
            .collection('questions')
            .doc(widget.existingQuestion!.id)
            .update(questionData);
      } else {
        // Create new question
        await FirebaseFirestore.instance
            .collection('questions')
            .add(questionData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            widget.existingQuestion != null 
              ? 'Question updated!' 
              : 'Question created!'
          )),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
      appBar: AppBar(
        title: Text(
          widget.existingQuestion != null 
            ? 'Edit Question' 
            : 'Create New Question',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionCard(
              TextFormField(
                controller: _titleController,
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
                  DropdownButtonFormField<String>(
                    value: _questionType,
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Text Answer')),
                      DropdownMenuItem(value: 'range', child: Text('Range Slider')),
                      DropdownMenuItem(value: 'mcq', child: Text('Multiple Choice')),
                      DropdownMenuItem(value: 'spotify_track', child: Text('Spotify Music')),
                    ],
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
                  const Text('Applicable Event Types'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _eventType,
                    items: const [
                      DropdownMenuItem(value: 'dating', child: Text('Dating Events')),
                      DropdownMenuItem(value: 'friendship', child: Text('Friendship Events')),
                      DropdownMenuItem(value: 'both', child: Text('Both Event Types')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _eventType = value);
                      }
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // Music type selector (only for spotify_track)
            if (_questionType == 'spotify_track')
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Music Selection Type'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _musicType,
                      items: const [
                        DropdownMenuItem(value: 'track', child: Text('Specific Track')),
                        DropdownMenuItem(value: 'artist', child: Text('Artist/Composer')),
                        DropdownMenuItem(value: 'genre', child: Text('Music Genre')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _musicType = value);
                        }
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (_questionType == 'spotify_track' && value == null) {
                          return 'Please select a music type';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

            // Range values (only for range type)
            if (_questionType == 'range')
              _buildSectionCard(
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _minValue?.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Value',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _minValue = int.tryParse(value);
                        },
                        validator: (value) {
                          if (_minValue == null) {
                            return 'Enter a number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: _maxValue?.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Value',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _maxValue = int.tryParse(value);
                        },
                        validator: (value) {
                          if (_maxValue == null) {
                            return 'Enter a number';
                          }
                          if (_minValue != null && _maxValue! <= _minValue!) {
                            return 'Max must be greater than min';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // Options for MCQ
            if (_questionType == 'mcq')
              _buildSectionCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Multiple Choice Options'),
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
                                  suffixIcon: _optionControllers.length > 1
                                      ? IconButton(
                                          icon: const Icon(Icons.remove),
                                          onPressed: () => _removeOptionField(index),
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
                    }).toList(),
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
              child: _isSubmitting
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
    );
  }
}