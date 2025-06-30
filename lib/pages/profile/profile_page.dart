import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app/services/firestore_service.dart';
import 'package:app/models/event.dart';
import 'package:app/pages/profile/profile_completion_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<Map<String, dynamic>?> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.data();
  }

  Future<List<Event>> _fetchHostedEvents(String userId) async {
    return await FirestoreService().getEventsByCreator(userId);
  }

  Future<List<Event>> _fetchAttendedEvents(String userId) async {
    // Get all event_applications where userId == current user and status == 'accepted'
    final apps = await FirebaseFirestore.instance
        .collection('event_applications')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();
    final eventIds = apps.docs.map((doc) => doc['eventId'] as String).toList();
    if (eventIds.isEmpty) return [];
    final eventsSnap = await FirebaseFirestore.instance
        .collection('events')
        .where(FieldPath.documentId, whereIn: eventIds)
        .get();
    return eventsSnap.docs.map((doc) => Event.fromDocumentSnapshot(doc)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _fetchUserData(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final userData = snapshot.data!;
            final photoUrl = userData['photoURL'] as String?;
            final name = userData['name'] ?? '';
            final introduction = userData['introduction'] ?? '';
            final gender = userData['gender'] ?? '';
            final dob = userData['dob'] is Timestamp ? (userData['dob'] as Timestamp).toDate() : null;
            final preference = userData['preference'] ?? '';
            final hobbies = (userData['hobbies'] as List?)?.cast<String>() ?? [];
            final attendedCount = userData['attendedCount'] ?? 0;
            final hostedCount = userData['hostedCount'] ?? 0;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover Image (no padding)
                  _buildProfileHeader(context, photoUrl, name, introduction),
                  // Content below image (with padding)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _buildEditProfileButton(),
                        const SizedBox(height: 32),
                        _buildSectionTitle('BASIC INFO'),
                        const SizedBox(height: 16),
                        _buildInfoItem('Gender', gender),
                        _buildInfoItem('Birthdate', dob != null ? '${dob.day}/${dob.month}/${dob.year}' : 'Not set'),
                        _buildInfoItem('Interested In', preference),
                        _buildInfoItem('Attended Events', attendedCount.toString()),
                        _buildInfoItem('Hosted Events', hostedCount.toString()),
                        const SizedBox(height: 32),
                        _buildSectionTitle('FAVOURITE ACTIVITIES'),
                        const SizedBox(height: 16),
                        _buildHobbiesGrid(hobbies),
                        const SizedBox(height: 40),
                        _buildSignOutButton(context),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, String? photoUrl, String name, String introduction) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Photo
            SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.35,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
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
            const SizedBox(height: 20),
            // Name and Bio with padding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    introduction,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Transparent top bar with back button
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 8),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Back',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditProfileButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Colors.purple, Colors.pink],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileCompletionPage(coreDetailsSet: true),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'EDIT PROFILE',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
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

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHobbiesGrid(List<String> hobbies) {
    if (hobbies.isEmpty) {
      return const Text('No hobbies listed', style: TextStyle(color: Colors.white70));
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: hobbies.map((hobby) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.purple),
          ),
          child: Text(
            hobby,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEventTile(Event event) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(event.title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${event.description}\n${event.startTime != null ? 'Start: ' + event.startTime.toString().substring(0, 16) : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () {
          context.read<AuthBloc>().add(SignOutRequested());
        },
        child: Text(
          'SIGN OUT',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.red,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}