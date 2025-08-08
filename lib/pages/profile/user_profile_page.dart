import 'package:app/pages/chat/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfilePage extends StatelessWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
            return const Center(child: Text('User not found', style: TextStyle(color: Colors.white)));
          }
          
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          return _buildProfile(context, userData);
        },
      ),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic> userData) {
    final photoUrl = userData['photoURL'] as String?;
    final name = userData['name'] ?? 'User';
    final introduction = userData['introduction'] ?? '';
    final gender = userData['gender'] ?? '';
    final dob = userData['dob'] is Timestamp ? (userData['dob'] as Timestamp).toDate() : null;
    final preference = userData['preference'] ?? '';
    final hobbies = (userData['hobbies'] as List?)?.cast<String>() ?? [];

    // Calculate age from DOB
    String age = '';
    if (dob != null) {
      final now = DateTime.now();
      int years = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        years--;
      }
      age = '$years years';
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300.0,
          floating: false,
          pinned: true,
          backgroundColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Profile background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.purple, Colors.deepPurple],
                    ),
                  ),
                ),
                
                // Profile image
                if (photoUrl != null && photoUrl.isNotEmpty)
                  Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                
                // Dark overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7)
                      ],
                    ),
                  ),
                ),
                
                // User name and basic info
                Positioned(
                  bottom: 16,
                  left: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (gender.isNotEmpty || age.isNotEmpty)
                        Row(
                          children: [
                            if (gender.isNotEmpty)
                              Text(
                                gender,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  color: Colors.white70,
                                ),
                              ),
                            if (gender.isNotEmpty && age.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '•',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            if (age.isNotEmpty)
                              Text(
                                age,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      if (preference.isNotEmpty)
                        Text(
                          'Interested in $preference',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Introduction
                  if (introduction.isNotEmpty) ...[
                    Text(
                      'About Me',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
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
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Hobbies
                  if (hobbies.isNotEmpty) ...[
                    Text(
                      'Favorite Activities',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildHobbiesGrid(hobbies),
                    const SizedBox(height: 24),
                  ],
                  
                  // Action buttons
                  Row(
  children: [
    Expanded(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.message),
        label: const Text('Send Message'),
        onPressed: () {
          Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                ChatPage(matchedUserId: userId, matchedUserName: name),
      ),
    );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    const SizedBox(width: 16), // This goes between the two buttons
    // IconButton(
    //   icon: const Icon(Icons.favorite_border, size: 32),
    //   color: Colors.pink,
    //   onPressed: () {
    //     // Implement like functionality
    //   },
    // ),
  ],
)
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildHobbiesGrid(List<String> hobbies) {
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
}