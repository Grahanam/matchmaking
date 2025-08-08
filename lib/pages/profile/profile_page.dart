import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app/pages/profile/profile_completion_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
    
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StreamBuilder<DocumentSnapshot>(
          stream: _getUserStream(),
          builder: (context, snapshot) {
            // Handle loading state
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            // Handle error or no data
            if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
              return const Center(child: Text('User data not found'));
            }
            
            final userData = snapshot.data!.data() as Map<String, dynamic>;
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
                        _buildEditProfileButton(context),
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
                          color: Colors.white.withValues(alpha: 0.7),
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

  Widget _buildEditProfileButton(BuildContext context) {
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
      child: ElevatedButton(
        onPressed: () async {
          await Navigator.push(
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