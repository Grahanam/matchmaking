import 'dart:ui' as ui;
import 'package:app/pages/auth/signin_page.dart';
import 'package:app/theme/theme_manager.dart';
import 'package:app/widgets/bottom_navbar_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app/pages/profile/profile_completion_page.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
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
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
  }

  Stream<DocumentSnapshot> _getUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return const Scaffold(body: Center(child: Text('Not logged in')));
  }

  return BlocListener<AuthBloc, AuthState>(
    listener: (context, state) {
      if (state is UnAuthenticated) {
        // Navigate to login page when signed out
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SignIn()),
          (route) => false,
        );
      }
    }, child:Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Profile",
          style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
          GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          const ProfileCompletionPage(coreDetailsSet: true),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 24),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.pinkAccent,
              ),
              child: const Icon(Icons.edit, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _getUserStream(),
        builder: (context, snapshot) {
          // Always return the container with gradient background
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
            child: SafeArea(
              child: _buildContentBasedOnSnapshot(snapshot, context),
            ),
          );
        },
      ),
    ),);
  }

  Widget _buildContentBasedOnSnapshot(
    AsyncSnapshot<DocumentSnapshot> snapshot,
    BuildContext context,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!snapshot.hasData || !snapshot.data!.exists) {
      return const Center(child: Text('User data not found'));
    }

    final userData = snapshot.data!.data() as Map<String, dynamic>;
    final photoUrl = userData['photoURL'] as String?;
    final name = userData['name'] ?? '';
    final introduction = userData['introduction'] ?? '';
    final gender = userData['gender'] ?? '';
    final dob =
        userData['dob'] is Timestamp
            ? (userData['dob'] as Timestamp).toDate()
            : null;
    final preference = userData['preference'] ?? '';
    final hobbies = (userData['hobbies'] as List?)?.cast<String>() ?? [];
    final attendedCount = userData['attendedCount'] ?? 0;
    final hostedCount = userData['hostedCount'] ?? 0;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(context, photoUrl, name, introduction),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.black26
                        : Colors.white70,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('BASIC INFO'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoItem(
                          'Gender',
                          gender,
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildInfoItem(
                          'Birthdate',
                          dob != null
                              ? '${dob.day}/${dob.month}/${dob.year}'
                              : 'Not set',
                          icon: Icons.cake,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoItem(
                          'Hosted',
                          hostedCount.toString(),
                          icon: Icons.flag,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildInfoItem(
                          'Attended',
                          attendedCount.toString(),
                          icon: Icons.event,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              margin: const EdgeInsets.all(5),
              width: double.infinity,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.black26
                        : Colors.white70,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('FAVOURITE ACTIVITIES'),
                  const SizedBox(height: 16),
                  _buildHobbiesGrid(hobbies),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildThemeToggle(context),
          const SizedBox(height: 16),
          _buildSignOutButton(context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    String? photoUrl,
    String name,
    String introduction,
  ) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.35,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child:
                  photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height * 0.35,
                      )
                      : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.purple, Colors.deepPurple],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 0),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            margin: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        
                          child: Text(
                            toBeginningOfSentenceCase(name) ?? name,
                            style: GoogleFonts.poppins(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Colors.green, Colors.greenAccent],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withValues(alpha:0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.verified_user_sharp, size: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    introduction,
                    style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0, left: 7),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.purple,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(
              themeManager.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: themeManager.isDarkMode ? Colors.yellow : Colors.blue,
            ),
            title: Text(
              themeManager.isDarkMode
                  ? 'Switch to Light Mode'
                  : 'Switch to Dark Mode',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Switch(
              value: themeManager.isDarkMode,
              activeColor: Colors.purple,
              inactiveThumbColor: Colors.grey,
              onChanged: (value) async {
                await themeManager.toggleTheme();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(String label, String value, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
          if (icon != null) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.purpleAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHobbiesGrid(List<String> hobbies) {
    if (hobbies.isEmpty) {
      return const Text(
        'No hobbies listed',
        style: TextStyle(color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          hobbies.map((hobby) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.purple),
              ),
              child: Text(hobby, style: GoogleFonts.poppins(fontSize: 16)),
            );
          }).toList(),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _showSignOutConfirmation(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            // elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                'SIGN OUT',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSignOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            // ignore: deprecated_member_use
            backgroundColor: Theme.of(context).dialogBackgroundColor,
            title: Text(
              'Sign Out',
              style: GoogleFonts.poppins(
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            content: Text(
              'Are you sure you want to sign out?',
              style: GoogleFonts.poppins(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: Colors.purple),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<AuthBloc>().add(SignOutRequested());
                },
                child: Text(
                  'Sign Out',
                  style: GoogleFonts.poppins(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }
}
