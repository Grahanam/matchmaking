import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/pages/home/home.dart';
import 'package:app/pages/layout/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProfileCompletionPage extends StatefulWidget {
  final bool coreDetailsSet;

  const ProfileCompletionPage({super.key, this.coreDetailsSet = false});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _introController = TextEditingController();
  final _hobbiesController = TextEditingController();
  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedPreference;
  bool _loading = true;
  File? _pickedImage;
  bool _uploadingImage = false;
  String? _currentImageUrl;

  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;


  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    _loadProfileData();
  }

   void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
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
          _currentImageUrl = data['photoURL'];

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
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    _nameController.dispose();
    _introController.dispose();
    _hobbiesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _pickedImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return null;

    setState(() => _uploadingImage = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // Create a reference to the location in Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_profile_images')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Upload the file to Firebase Storage
      await storageRef.putFile(_pickedImage!);

      // Get the download URL
      final downloadURL = await storageRef.getDownloadURL();

      setState(() => _uploadingImage = false);
      return downloadURL;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload image')));
      return null;
    }
  }

  Future<void> _pickDob() async {
    if (widget.coreDetailsSet) {
      return; // Prevent changing if core details are set
    }

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(
        const Duration(days: 365 * 18),
      ), // 18+ only
    );

    if (date != null) {
      setState(() => _selectedDob = date);
    }
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user is at least 18 years old
    if (_selectedDob != null) {
      final now = DateTime.now();
      final age = now.year - _selectedDob!.year;
      final isBirthdayPassed =
          now.month > _selectedDob!.month ||
          (now.month == _selectedDob!.month && now.day >= _selectedDob!.day);

      if (age < 18 || (age == 18 && !isBirthdayPassed)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be at least 18 years old')),
        );
        return;
      }
    }

    String? imageUrl;
    if (_pickedImage != null) {
      imageUrl = await _uploadImage();
      if (imageUrl == null) return; // Stop if image upload failed
    }

    final profileData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'introduction': _introController.text,
      'photoURL': imageUrl ?? _currentImageUrl,
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
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      } else {
        // For existing users editing profile, just pop
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: ${e.toString()}')),
      );
    }
  }

  // Calculate age from date of birth
  int? _calculateAge() {
    if (_selectedDob == null) return null;
    final now = DateTime.now();
    int age = now.year - _selectedDob!.year;
    if (now.month < _selectedDob!.month ||
        (now.month == _selectedDob!.month && now.day < _selectedDob!.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return WillPopScope(
      onWillPop: () async {
        // Prevent back navigation if core details aren't set
        return widget.coreDetailsSet;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          title: Text(
            widget.coreDetailsSet ? "Edit Profile" : "Complete Your Profile",
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
          automaticallyImplyLeading: widget.coreDetailsSet,
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
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                      padding: const EdgeInsets.only(left:16,right:16),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          controller: _scrollController,
                          children: [
                            const SizedBox(height: 10,),
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Profile Photo',
                                      style: GoogleFonts.raleway(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Center(
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                                width: 2,
                                              ),
                                            ),
                                            child: ClipOval(
                                              child:
                                                  _pickedImage != null
                                                      ? Image.file(
                                                        _pickedImage!,
                                                        fit: BoxFit.cover,
                                                      )
                                                      : _currentImageUrl !=
                                                              null &&
                                                          _currentImageUrl!
                                                              .isNotEmpty
                                                      ? Image.network(
                                                        _currentImageUrl!,
                                                        fit: BoxFit.cover,
                                                        loadingBuilder: (
                                                          context,
                                                          child,
                                                          loadingProgress,
                                                        ) {
                                                          if (loadingProgress ==
                                                              null)
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
                                                          return Icon(
                                                            Icons.person,
                                                            size: 60,
                                                            color:
                                                                Colors
                                                                    .grey
                                                                    .shade400,
                                                          );
                                                        },
                                                      )
                                                      : Icon(
                                                        Icons.person,
                                                        size: 60,
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade400,
                                                      ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              height: 40,
                                              width: 40,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: colorScheme.primary,
                                              ),
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.camera_alt,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                                onPressed: _pickImage,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_uploadingImage)
                                      const Center(
                                        child: Column(
                                          children: [
                                            SizedBox(height: 8),
                                            CircularProgressIndicator(),
                                            SizedBox(height: 8),
                                            Text(
                                              'Uploading image...',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Core details section
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Basic Information',
                                      style: GoogleFonts.raleway(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
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
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      enabled: !widget.coreDetailsSet,
                                      validator:
                                          (value) =>
                                              value?.isEmpty ?? true
                                                  ? 'Name is required'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    // Date of Birth
                                    InkWell(
                                      onTap: _pickDob,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade400,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.cake,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Date of Birth*',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _selectedDob == null
                                                        ? 'Select your date of birth (18+ only)'
                                                        : '${DateFormat.yMMMd().format(_selectedDob!)} (${_calculateAge()} years old)',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color:
                                                          _selectedDob == null
                                                              ? Colors.grey
                                                              : Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (widget.coreDetailsSet)
                                              const Icon(
                                                Icons.lock,
                                                size: 18,
                                                color: Colors.grey,
                                              )
                                            else
                                              const Icon(
                                                Icons.arrow_drop_down,
                                                color: Colors.grey,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_selectedDob == null &&
                                        !widget.coreDetailsSet)
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          left: 8,
                                          top: 4,
                                        ),
                                        child: Text(
                                          'You must be at least 18 years old',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    // Gender
                                    DropdownButtonFormField<String>(
                                      value: _selectedGender,
                                      decoration: InputDecoration(
                                        labelText: 'Gender*',
                                        prefixIcon: const Icon(
                                          Icons.person_outline,
                                        ),
                                        suffixIcon:
                                            widget.coreDetailsSet
                                                ? const Icon(
                                                  Icons.lock,
                                                  size: 18,
                                                  color: Colors.grey,
                                                )
                                                : null,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
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
                                      ],
                                      onChanged:
                                          widget.coreDetailsSet
                                              ? null
                                              : (value) => setState(
                                                () => _selectedGender = value,
                                              ),
                                      validator:
                                          widget.coreDetailsSet
                                              ? null
                                              : (value) =>
                                                  value == null
                                                      ? 'Please select your gender'
                                                      : null,
                                    ),
                                    const SizedBox(height: 16),
                                    // Preference
                                    DropdownButtonFormField<String>(
                                      value: _selectedPreference,
                                      decoration: InputDecoration(
                                        labelText: 'Interested In*',
                                        prefixIcon: const Icon(Icons.favorite),
                                        helperText:
                                            'Who are you interested in meeting?',
                                        suffixIcon:
                                            widget.coreDetailsSet
                                                ? const Icon(
                                                  Icons.lock,
                                                  size: 18,
                                                  color: Colors.grey,
                                                )
                                                : null,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'men',
                                          child: Text('Men'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'women',
                                          child: Text('Women'),
                                        ),
                                      ],
                                      onChanged:
                                          widget.coreDetailsSet
                                              ? null
                                              : (value) => setState(
                                                () =>
                                                    _selectedPreference = value,
                                              ),
                                      validator:
                                          widget.coreDetailsSet
                                              ? null
                                              : (value) =>
                                                  value == null
                                                      ? 'Please select your preference'
                                                      : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // About section
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'About You',
                                      style: GoogleFonts.raleway(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _introController,
                                      maxLines: 4,
                                      decoration: InputDecoration(
                                        labelText: 'Introduction',
                                        hintText:
                                            'Tell others about yourself...',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _hobbiesController,
                                      decoration: InputDecoration(
                                        labelText: 'Hobbies & Interests',
                                        hintText:
                                            'e.g., Reading, hiking, photography',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Submit button
                            ElevatedButton(
                              onPressed:
                                  _uploadingImage ? null : _submitProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child:
                                  _uploadingImage
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                      : Text(
                                        widget.coreDetailsSet
                                            ? "Save Changes"
                                            : "Complete Profile",
                                        style: GoogleFonts.raleway(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                            ),
                            const SizedBox(height: 10,),
                          ],
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
