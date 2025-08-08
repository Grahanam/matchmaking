import 'dart:ui';

import 'package:app/pages/chat/chat_page.dart';
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/profile/user_profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  int _selectedIndex = 0;
  final Map<String, Map<String, dynamic>> _matchedUsers = {};
  bool _loading = true;
  String? _error;
  List<MapEntry<String, Map<String, dynamic>>> userList = [];

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
        _matchedUsers.clear();
        userList.clear();
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final matchesSnapshot =
          await firestore
              .collectionGroup('matches')
              .where('userId', isEqualTo: user.uid)
              .where('released', isEqualTo: true)
              .where('matchedWith', isNotEqualTo: '')
              .get();

      final matchedUserIds =
          matchesSnapshot.docs
              .map((doc) => doc.data()['matchedWith'] as String)
              .toSet();

      // Get user details
      await Future.wait(
        matchedUserIds.map(
          (userId) => _fetchUserDetails(userId, matchesSnapshot),
        ),
      );

      setState(() {
        _loading = false;
        userList = _matchedUsers.entries.toList();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load matches. Please try again.';
      });
    }
  }

  Future<void> _fetchUserDetails(
    String userId,
    QuerySnapshot matchesSnapshot,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? {};

      // Find matching document safely
      final matchDocs =
          matchesSnapshot.docs
              .where((doc) => doc['matchedWith'] == userId)
              .toList();

      if (matchDocs.isEmpty) return;

      final matchReason =
          matchDocs.first['reason'] as String? ?? 'You matched!';

      setState(() {
        _matchedUsers[userId] = {
          'name': userData['name'] ?? 'Unknown User',
          'photoUrl': userData['photoURL'] as String? ?? '',
          'reason': matchReason,
        };
      });
    } catch (e) {
      setState(() {
        _matchedUsers[userId] = {
          'name': 'Unknown User',
          'photoUrl': '',
          'reason': 'Match found, but details unavailable',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Your Matches',
          style: GoogleFonts.raleway(
            fontWeight: FontWeight.w800,
            fontSize: 26,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withOpacity(0.8),
            ],
          ),
        ),
        child: _buildContent(context, colorScheme),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    if (_error != null) {
      return _buildErrorState(colorScheme);
    }

    if (_loading) {
      return _buildLoadingState(colorScheme);
    }

    if (userList.isEmpty) {
      return _buildEmptyState(colorScheme);
    }

    final selectedUser = userList[_selectedIndex].value;
    final selectedUserId = userList[_selectedIndex].key;

    return Column(
      children: [
        // Top user avatars
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemCount: userList.length,
            itemBuilder: (context, index) {
              final user = userList[index].value;
              final isSelected = index == _selectedIndex;
              return _UserAvatar(
                name: user['name'] ?? 'Unknown',
                photoUrl: user['photoUrl'] ?? '',
                isSelected: isSelected,
                onTap: () => setState(() => _selectedIndex = index),
                colorScheme: colorScheme,
              );
            },
          ),
        ),

        const Divider(height: 0, thickness: 1),

        // Main content area
        Expanded(
          child: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: _UserBackgroundImage(
                  photoUrl: selectedUser['photoUrl'] ?? '',
                  colorScheme: colorScheme,
                ),
              ),

              // Gradient overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        colorScheme.surface.withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
              ),

              // User info
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child:ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: BackdropFilter(
                   filter: ImageFilter.blur(sigmaX: 10.0,sigmaY: 10.0),
                   child: Container(
                    padding: const EdgeInsets.all(1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color:Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'You Matched with ..',
                          style: GoogleFonts.raleway(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.red,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 👤 Name with Strong Hierarchy
                    Text(
                      selectedUser['name'] ?? 'Unknown User',
                      style: GoogleFonts.raleway(
                        fontSize: 40, // Larger for impact
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.15,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ], // Soft shadow for depth
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 🏷️ "Match Result" → More natural: "You have a match"
                    Text(
                      selectedUser['reason'] ??
                          'You both enjoy coding and coffee!',
                      style: GoogleFonts.raleway(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant.withValues(alpha:0.95),
                        height: 1.5,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.left,
                    ),

                    const SizedBox(height: 16),

                    // 🏆 Optional: Match Strength Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha:0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha:0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: colorScheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'High Compatibility',
                            style: GoogleFonts.raleway(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                    ),
                   ),
                  ),
                ),
                // child: Column(
                //   crossAxisAlignment: CrossAxisAlignment.start,
                //   children: [
                //     Row(
                //       children: [
                //         Icon(
                //           Icons.favorite,
                //           color:Colors.red,
                //           size: 20,
                //         ),
                //         const SizedBox(width: 2),
                //         Text(
                //           'You Matched with ..',
                //           style: GoogleFonts.raleway(
                //             fontSize: 18,
                //             fontWeight: FontWeight.w800,
                //             color: Colors.red,
                //             letterSpacing: 0.5,
                //           ),
                //         ),
                //       ],
                //     ),
                //     const SizedBox(height: 4),

                //     // 👤 Name with Strong Hierarchy
                //     Text(
                //       selectedUser['name'] ?? 'Unknown User',
                //       style: GoogleFonts.raleway(
                //         fontSize: 40, // Larger for impact
                //         fontWeight: FontWeight.bold,
                //         color: colorScheme.onSurface,
                //         height: 1.15,
                //         shadows: [
                //           Shadow(
                //             color: Colors.black.withOpacity(0.2),
                //             blurRadius: 4,
                //             offset: Offset(0, 2),
                //           ),
                //         ], // Soft shadow for depth
                //       ),
                //     ),

                //     const SizedBox(height: 8),

                //     // 🏷️ "Match Result" → More natural: "You have a match"
                //     Text(
                //       selectedUser['reason'] ??
                //           'You both enjoy coding and coffee!',
                //       style: GoogleFonts.raleway(
                //         fontSize: 18,
                //         fontWeight: FontWeight.w500,
                //         color: colorScheme.onSurfaceVariant.withOpacity(0.95),
                //         height: 1.5,
                //         letterSpacing: 0.2,
                //       ),
                //       textAlign: TextAlign.left,
                //     ),

                //     const SizedBox(height: 16),

                //     // 🏆 Optional: Match Strength Badge
                //     Container(
                //       padding: const EdgeInsets.symmetric(
                //         horizontal: 12,
                //         vertical: 6,
                //       ),
                //       decoration: BoxDecoration(
                //         color: colorScheme.primary.withOpacity(0.15),
                //         borderRadius: BorderRadius.circular(20),
                //         border: Border.all(
                //           color: colorScheme.primary.withOpacity(0.3),
                //           width: 1,
                //         ),
                //       ),
                //       child: Row(
                //         mainAxisSize: MainAxisSize.min,
                //         children: [
                //           Icon(
                //             Icons.star,
                //             color: colorScheme.primary,
                //             size: 16,
                //           ),
                //           const SizedBox(width: 6),
                //           Text(
                //             'High Compatibility',
                //             style: GoogleFonts.raleway(
                //               fontSize: 14,
                //               fontWeight: FontWeight.w600,
                //               color: colorScheme.primary,
                //             ),
                //           ),
                //         ],
                //       ),
                //     ),
                //   ],
                // ),
              ),

              // Circular action buttons in top-right corner
              Positioned(
                top: 24,
                right: 16,
                child: Column(
                  children: [
                    // Message button
                    _CircularActionButton(
                      icon: Icons.chat_bubble_outline,
                      onPressed:
                          () => _openChat(
                            context,
                            selectedUserId,
                            selectedUser['name'],
                          ),
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 16),
                    // Profile button
                    _CircularActionButton(
                      icon: Icons.person_outline,
                      onPressed: () => _openProfile(context, selectedUserId),
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 24),
            Text(
              _error!,
              style: GoogleFonts.raleway(
                color: colorScheme.onSurface,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadMatches,
              child: Text(
                'Try Again',
                style: GoogleFonts.raleway(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
          const SizedBox(height: 20),
          Text(
            'Finding your matches...',
            style: GoogleFonts.raleway(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_add,
              size: 80,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No matches yet',
              style: GoogleFonts.raleway(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Attend events and interact with others to discover new connections',
              style: GoogleFonts.raleway(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NearbyEventsPage()),
                );
              },
              child: Text(
                'Explore Events',
                style: GoogleFonts.raleway(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserProfilePage(userId: userId)),
    );
  }

  void _openChat(BuildContext context, String userId, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                ChatPage(matchedUserId: userId, matchedUserName: userName),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _UserAvatar({
    required this.name,
    required this.photoUrl,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                width: 3,
              ),
              boxShadow:
                  isSelected
                      ? [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                      : null,
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: colorScheme.surfaceVariant,
              foregroundImage:
                  photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child:
                  photoUrl.isEmpty
                      ? Icon(
                        Icons.person,
                        size: 28,
                        color: colorScheme.onSurfaceVariant,
                      )
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBackgroundImage extends StatelessWidget {
  final String photoUrl;
  final ColorScheme colorScheme;

  const _UserBackgroundImage({
    required this.photoUrl,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isEmpty) {
      return Container(
        color: colorScheme.surfaceVariant,
        child: Center(
          child: Icon(
            Icons.person,
            size: 120,
            color: colorScheme.onSurfaceVariant.withOpacity(0.3),
          ),
        ),
      );
    }

    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: colorScheme.surfaceVariant,
          child: Center(
            child: CircularProgressIndicator(
              color: colorScheme.primary,
              value:
                  loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
            ),
          ),
        );
      },
      errorBuilder:
          (_, __, ___) => Container(
            color: colorScheme.surfaceVariant,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Couldn\'t load image',
                    style: GoogleFonts.raleway(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _CircularActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;

  const _CircularActionButton({
    required this.icon,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surface.withOpacity(0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: colorScheme.primary),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}
