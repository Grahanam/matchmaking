import 'package:app/pages/home/home.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// import 'package:image/image.dart' as img;

class ProfileCompletionPage extends StatefulWidget {
  final bool
  coreDetailsSet; // True if name, gender, dob, preference are already set

  const ProfileCompletionPage({super.key, this.coreDetailsSet = false});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _introController = TextEditingController();
  final _hobbiesController = TextEditingController();
  final _photoUrlController = TextEditingController();
  bool _isValidImageUrl = true;
  bool _isCheckingImage = false;
  Uint8List? _imageBytes;
  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedPreference;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _introController.text = data['introduction'] ?? '';
          _photoUrlController.text = data['photoURL'] ?? '';

          // Handle hobbies as List or String
          final hobbies = data['hobbies'];
          if (hobbies is List) {
            _hobbiesController.text = hobbies.join(', ');
          } else if (hobbies is String) {
            _hobbiesController.text = hobbies;
          } else {
            _hobbiesController.text = '';
          }

          if (data['dob'] != null) {
            _selectedDob = (data['dob'] as Timestamp).toDate();
          }

          _selectedGender = data['gender'];
          _selectedPreference = data['preference'];
          _loading = false;
        });
      } else {
        setState(() => _loading = false); // Add this
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _introController.dispose();
    _hobbiesController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

   Future<bool> _validateImageUrl(String url) async {
    if (url.isEmpty) return true;
    
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return false;
    
    // Check if URL looks like an image
    if (uri.pathSegments.isNotEmpty) {
      final lastSegment = uri.pathSegments.last.toLowerCase();
      if (lastSegment.contains('.')) {
        final ext = lastSegment.split('.').last;
        const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
        if (imageExtensions.contains(ext)) return true;
      }
    }
    
    // Check by downloading image headers
    try {
      setState(() => _isCheckingImage = true);
      final response = await http.head(uri);
      
      if (response.statusCode != 200) return false;
      
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      return contentType.startsWith('image/');
    } catch (e) {
      return false;
    } finally {
      setState(() => _isCheckingImage = false);
    }
  }

  Future<void> _loadPreview() async {
    if (_photoUrlController.text.isEmpty) {
      setState(() {
        _imageBytes = null;
        _isValidImageUrl = true;
      });
      return;
    }
    
    final isValid = await _validateImageUrl(_photoUrlController.text);
    setState(() => _isValidImageUrl = isValid);
    
    if (isValid) {
      try {
        final response = await http.get(Uri.parse(_photoUrlController.text));
        if (response.statusCode == 200) {
          setState(() => _imageBytes = response.bodyBytes);
        }
      } catch (e) {
        setState(() => _imageBytes = null);
      }
    }
  }

  Future<void> _pickDob() async {
    if (widget.coreDetailsSet) {
      return; // Prevent changing if core details are set
    }

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
    );

    if (date != null) {
      setState(() => _selectedDob = date);
    }
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

     if (_photoUrlController.text.isNotEmpty) {
    final isValid = await _validateImageUrl(_photoUrlController.text);
    setState(() => _isValidImageUrl = isValid);
    
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid image URL')),
      );
      return;
    }
  }

    final profileData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'introduction': _introController.text,
      'photoURL': _photoUrlController.text,
    };

    // Process hobbies
    if (_hobbiesController.text.isNotEmpty) {
      profileData['hobbies'] =
          _hobbiesController.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    }

    // Only set core details if they haven't been set before
    if (!widget.coreDetailsSet) {
      // Validate core fields
      if (_selectedDob == null ||
          _selectedGender == null ||
          _selectedPreference == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All core fields are required')),
        );
        return;
      }

      profileData.addAll({
        'name': _nameController.text,
        'dob': Timestamp.fromDate(_selectedDob!),
        'gender': _selectedGender!,
        'preference': _selectedPreference!,
        'profileComplete': true,
      });
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(profileData);

      if (!mounted) return;
      // For new users, navigate back to home which will now show the home UI
      if (!widget.coreDetailsSet) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Home()),
        );
      } else {
        // For existing users editing profile, just pop
        Navigator.pop(context,true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent back navigation if core details aren't set
        return widget.coreDetailsSet;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.coreDetailsSet ? "Edit Profile" : "Complete Your Profile",
          ),
          automaticallyImplyLeading: widget.coreDetailsSet,
          actions: [
            if (!widget.coreDetailsSet)
              TextButton(
                onPressed: _submitProfile,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        // Name field (locked if core details set)
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name*',
                            prefixIcon: const Icon(Icons.person),
                            suffixIcon:
                                widget.coreDetailsSet
                                    ? const Icon(
                                      Icons.lock,
                                      size: 18,
                                      color: Colors.grey,
                                    )
                                    : null,
                          ),
                          enabled: !widget.coreDetailsSet,
                          validator:
                              (value) =>
                                  value?.isEmpty ?? true
                                      ? 'Name is required'
                                      : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
  controller: _photoUrlController,
  decoration: InputDecoration(
    labelText: 'Profile Photo URL',
    prefixIcon: const Icon(Icons.link),
    helperText: 'Enter a direct image URL',
    errorText: _isValidImageUrl ? null : 'Invalid image URL',
    suffixIcon: _isCheckingImage
        ? const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null,
  ),
  keyboardType: TextInputType.url,
  onChanged: (value) => _loadPreview(),
),
const SizedBox(height: 16),

// Image preview
if (_imageBytes != null)
  Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        _imageBytes!,
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    ),
  ),
                        const SizedBox(height: 16),

                        // Introduction field (always editable)
                        TextFormField(
                          controller: _introController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Introduction',
                            prefixIcon: Icon(Icons.info),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Hobbies field (always editable)
                        TextFormField(
                          controller: _hobbiesController,
                          decoration: const InputDecoration(
                            labelText: 'Hobbies (comma separated)',
                            prefixIcon: Icon(Icons.sports_soccer),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Date of Birth (locked if core details set)
                        ListTile(
                          leading: const Icon(Icons.cake),
                          title: Text(
                            _selectedDob == null
                                ? 'Select Date of Birth*'
                                : 'DOB: ${DateFormat.yMd().format(_selectedDob!)}',
                          ),
                          trailing:
                              widget.coreDetailsSet
                                  ? const Icon(
                                    Icons.lock,
                                    size: 18,
                                    color: Colors.grey,
                                  )
                                  : const Icon(Icons.arrow_drop_down),
                          onTap: _pickDob,
                        ),
                        if (_selectedDob == null && !widget.coreDetailsSet)
                          const Padding(
                            padding: EdgeInsets.only(left: 16, top: 4),
                            child: Text(
                              'Date of birth is required',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // Gender (locked if core details set)
                        DropdownButtonFormField<String>(
                          value: _selectedGender,
                          decoration: InputDecoration(
                            labelText: 'Gender*',
                            prefixIcon: const Icon(Icons.person_outline),
                            suffixIcon:
                                widget.coreDetailsSet
                                    ? const Icon(
                                      Icons.lock,
                                      size: 18,
                                      color: Colors.grey,
                                    )
                                    : null,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'male',
                              child: Text('Male'),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Female'),
                            ),
                            // DropdownMenuItem(
                            //   value: 'other',
                            //   child: Text('Other'),
                            // ),
                          ],
                          onChanged:
                              widget.coreDetailsSet
                                  ? null
                                  : (value) =>
                                      setState(() => _selectedGender = value),
                          validator:
                              widget.coreDetailsSet
                                  ? null
                                  : (value) =>
                                      value == null
                                          ? 'Please select your gender'
                                          : null,
                        ),
                        const SizedBox(height: 16),

                        // Opposite Sex Preference (locked if core details set)
                        DropdownButtonFormField<String>(
                          value: _selectedPreference,
                          decoration: InputDecoration(
                            labelText: 'Interested In*',
                            prefixIcon: const Icon(Icons.favorite),
                            helperText: 'Who are you interested in meeting?',
                            suffixIcon:
                                widget.coreDetailsSet
                                    ? const Icon(
                                      Icons.lock,
                                      size: 18,
                                      color: Colors.grey,
                                    )
                                    : null,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'men', child: Text('Men')),
                            DropdownMenuItem(
                              value: 'women',
                              child: Text('Women'),
                            ),
                            // DropdownMenuItem(value: 'both', child: Text('Both')),
                            // DropdownMenuItem(
                            //   value: 'none',
                            //   child: Text('Prefer not to say'),
                            // ),
                          ],
                          onChanged:
                              widget.coreDetailsSet
                                  ? null
                                  : (value) => setState(
                                    () => _selectedPreference = value,
                                  ),
                          validator:
                              widget.coreDetailsSet
                                  ? null
                                  : (value) =>
                                      value == null
                                          ? 'Please select your preference'
                                          : null,
                        ),
                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: _submitProfile,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: Text(
                            widget.coreDetailsSet
                                ? "Save Changes"
                                : "Complete Profile",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
