// bottom_navbar_widget.dart
import 'package:app/pages/chat/user_chat_list_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BottomNavbarWidget extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavbarWidget({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BottomNavbarWidget> createState() => _BottomNavbarWidgetState();
}

class _BottomNavbarWidgetState extends State<BottomNavbarWidget> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      color: Color(0xFF2D0B5A),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        widget.currentIndex == 0
                            ? Colors.purple.withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.home,
                    color:
                        widget.currentIndex == 0
                            ? Colors.pinkAccent
                            : Colors.white70,
                  ),
                ),
                Text(
                  "Home",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70
                  ),
                ),
              ],
            ),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        widget.currentIndex == 1
                            ? Colors.purple.withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.event,
                    color:
                        widget.currentIndex == 1
                            ? Colors.pinkAccent
                            : Colors.white70,
                  ),
                ),
                Text(
                  "Events",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70
                  ),
                ),
              ],
            ),
            label: "Events",
          ),
          BottomNavigationBarItem(
            icon: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        widget.currentIndex == 2
                            ? Colors.purple.withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.people,
                    color:
                        widget.currentIndex == 2
                            ? Colors.pinkAccent
                            : Colors.white70,
                  ),
                ),
                // Add some spacing between icon and text
                Text(
                  "Match",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70
                  ),
                ),
              ],
            ),
            label: "Match",
          ),
          BottomNavigationBarItem(
            icon: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        widget.currentIndex == 3
                            ? Colors.purple.withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.chat,
                    color:
                        widget.currentIndex == 3
                            ? Colors.pinkAccent
                            : Colors.white70,
                  ),
                ),// Add some spacing between icon and text
                Text(
                  "Message",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70
                  ),
                ),
              ],
            ),
            label: "Message",
          ),
          BottomNavigationBarItem(
            icon: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FutureBuilder<DocumentSnapshot>(
                  future:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(user?.uid)
                          .get(),
                  builder: (context, snapshot) {
                    String? photoUrl;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      photoUrl = data?['photoURL'] as String?;
                    }
                    return CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          (photoUrl != null && photoUrl.isNotEmpty)
                              ? NetworkImage(photoUrl)
                              : null,
                      child:
                          (photoUrl == null || photoUrl.isEmpty)
                              ? const Icon(
                                Icons.person,
                                color: Colors.grey,
                                size: 20,
                              )
                              : null,
                    );
                  },
                ),
                const SizedBox(
                  height: 4,
                ), // Add some spacing between icon and text
                Text(
                  "You",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70
                  ),
                ),
              ],
            ),
            label: "", // Keep this empty since we're adding the label manually
          ),
        ],
        currentIndex: widget.currentIndex,
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        onTap: widget.onTap,
      ),
    );
  }
}
