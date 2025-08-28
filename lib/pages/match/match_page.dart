import 'dart:async';
import 'dart:ui' as ui;
import 'package:app/pages/chat/chat_page.dart';
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/profile/user_profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// String _capitalizeName(String name) {
//   if (name == 'Unknown User') return name;

//   // Capitalize each word
//   return name
//       .split(' ')
//       .map((word) {
//         if (word.isEmpty) return word;
//         return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
//       })
//       .join(' ');
// }

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
  // bool _showFullReason = false;
  List<MapEntry<String, Map<String, dynamic>>> userList = [];
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;
  bool _isDisposed = false;
  Future<void>? _loadMatchesOperation;

  @override
  void initState() {
    super.initState();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    _loadMatches();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _loadMatchesOperation?.ignore();
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  Future<void> _loadMatches() async {
    _loadMatchesOperation?.ignore();

    final completer = Completer<void>();
    _loadMatchesOperation = completer.future;

    try {
      if (_isDisposed) {
        completer.complete();
        return;
      }
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

      if (_isDisposed) {
        completer.complete();
        return;
      }

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

      if (_isDisposed) {
        completer.complete();
        return;
      }
      setState(() {
        _loading = false;
        userList = _matchedUsers.entries.toList();
      });
    } catch (e) {
      if (_isDisposed) {
        completer.complete();
        return;
      }
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
      if (_isDisposed) return;
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? {};
      final matchDocs =
          matchesSnapshot.docs
              .where((doc) => doc['matchedWith'] == userId)
              .toList();

      if (matchDocs.isEmpty) return;

      final matchReason =
          matchDocs.first['reason'] as String? ?? 'You matched!';

      if (_isDisposed) return;

      setState(() {
        _matchedUsers[userId] = {
          'name': userData['name'] ?? 'Unknown User',
          'photoUrl': userData['photoURL'] as String? ?? '',
          'reason': matchReason,
          'gender': userData['gender'],
          'age': userData['age'],
          'preference': userData['preference'],
          'introduction': userData['introduction'],
          'hobbies':
              userData['hobbies'] is List
                  ? List<String>.from(userData['hobbies'])
                  : [],
          'eventName': userData['eventName'], // If you have this field
          // Add any other fields you need
        };
      });
    } catch (e) {
      if (_isDisposed) return;
      setState(() {
        _matchedUsers[userId] = {
          'name': 'Unknown User',
          'photoUrl': '',
          'reason': 'Match found, but details unavailable',
          'gender': null,
          'age': null,
          'preference': null,
          'introduction': null,
          'hobbies': [],
          'eventName': null,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Your Matches",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
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
        child: SafeArea(child: _buildContent(context, colorScheme)),
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

        // const Divider(height: 0, thickness: 1),

        // Main content area
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            // child: Expanded(
            child: Column(
              children: [
                Stack(
                  // fit: StackFit.expand,
                  children: [
                    // Profile image
                    if (selectedUser['photoUrl'] != null &&
                        selectedUser['photoUrl'].isNotEmpty)
                      Image.network(
                        selectedUser['photoUrl'],
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        // width: double.infinity,
                        // height: double.infinity,
                      ),

                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(
                                alpha: 0.7,
                              ), // Use withOpacity instead of withValues
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Dark overlay
                    // Container(
                    //   width: double.infinity,
                    //   decoration: BoxDecoration(
                    //     gradient: LinearGradient(
                    //       begin: Alignment.topCenter,
                    //       end: Alignment.bottomCenter,
                    //       colors: [
                    //         Colors.transparent,
                    //         Colors.black.withValues(alpha: 0.7),
                    //       ],
                    //     ),
                    //   ),
                    // ),

                    // User name and basic info
                    Positioned(
                      bottom: 16,
                      left: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedUser['name'],
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (selectedUser['gender'] != null ||
                              selectedUser['age'] != null)
                            Row(
                              children: [
                                if (selectedUser['gender'] != null)
                                  Text(
                                    selectedUser['gender'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      color: Colors.white70,
                                    ),
                                  ),
                                if (selectedUser['gender'] != null &&
                                    selectedUser['age'] != null)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      '•',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                if (selectedUser['age'] != null)
                                  Text(
                                    selectedUser['age'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          // if (selectedUser['preference'] != null)
                          //   Text(
                          //     selectedUser['preference'],
                          //     style: GoogleFonts.poppins(
                          //       fontSize: 16,
                          //       color: Colors.white70,
                          //     ),
                          //   ),
                        ],
                      ),
                    ),
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
                                  selectedUser['photoUrl'],
                                ),
                            colorScheme: colorScheme,
                          ),
                          // const SizedBox(height: 16),

                          // _CircularActionButton(
                          //   icon: Icons.person_outline,
                          //   onPressed:
                          //       () => _openProfile(context, selectedUserId),
                          //   colorScheme: colorScheme,
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Introduction
                      if (selectedUser['introduction'] != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About Me',
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                selectedUser['introduction'],
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],

                      // Hobbies
                      if (selectedUser['hobbies'] != null) ...[
                        // Text(
                        //   'Favorite Activities',
                        //   style: GoogleFonts.poppins(
                        //     fontSize: 20,
                        //     fontWeight: FontWeight.bold,
                        //   ),
                        // ),
                        // const SizedBox(height: 16),
                        // _buildHobbiesGrid(hobbies),
                        // const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            margin: const EdgeInsets.all(5),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.black26
                                      : Colors.white70,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('FAVOURITE ACTIVITIES'),
                                const SizedBox(height: 16),
                                _buildHobbiesGrid(selectedUser['hobbies']),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Action buttons
                      // Row(
                      //   children: [
                      //     Expanded(
                      //       child: ElevatedButton.icon(
                      //         icon: const Icon(Icons.message),
                      //         label: const Text('Send Message'),
                      //         onPressed: () {
                      //           Navigator.push(
                      //             context,
                      //             MaterialPageRoute(
                      //               builder:
                      //                   (context) => ChatPage(
                      //                     matchedUserId: userId,
                      //                     matchedUserName: name,
                      //                   ),
                      //             ),
                      //           );
                      //         },
                      //         style: ElevatedButton.styleFrom(
                      //           backgroundColor: Colors.purple,
                      //           foregroundColor: Colors.white,
                      //           padding: const EdgeInsets.symmetric(vertical: 16),
                      //           shape: RoundedRectangleBorder(
                      //             borderRadius: BorderRadius.circular(12),
                      //           ),
                      //         ),
                      //       ),
                      //     ),
                      //     const SizedBox(
                      //       width: 16,
                      //     ), // This goes between the two buttons
                      //     IconButton(
                      //       icon: const Icon(Icons.favorite_border, size: 32),
                      //       color: Colors.pink,
                      //       onPressed: () {
                      // Implement like functionality
                      //       },
                      //     ),
                      //   ],
                      // ),
                    ],
                  ),
                ),
              ],
            ),
            // ),
          ),
        ),
        // Expanded(
        //   child: Stack(
        //     children: [
        //       // Background image
        //       Positioned.fill(
        //         child: _UserBackgroundImage(
        //           photoUrl: selectedUser['photoUrl'] ?? '',
        //           colorScheme: colorScheme,
        //         ),
        //       ),

        //       // Gradient overlay
        //       Positioned(
        //         bottom: 0,
        //         left: 0,
        //         right: 0,
        //         child: Container(
        //           height: 200,
        //           decoration: BoxDecoration(
        //             gradient: LinearGradient(
        //               begin: Alignment.topCenter,
        //               end: Alignment.bottomCenter,
        //               colors: [
        //                 Colors.transparent,
        //                 Colors.black.withValues(alpha: 0.85),
        //               ],
        //             ),
        //           ),
        //         ),
        //       ),

        //       // User info
        //       Positioned(
        //         bottom: 24,
        //         left: 18,
        //         right: 18,
        //         child: ClipRRect(
        //           borderRadius: BorderRadius.circular(10),
        //           child: BackdropFilter(
        //             filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
        //             child: Container(
        //               padding: const EdgeInsets.all(10),
        //               child: Column(
        //                 crossAxisAlignment: CrossAxisAlignment.start,
        //                 children: [
        //                   Row(
        //                     children: [
        //                       Icon(Icons.favorite, color: Colors.red, size: 20),
        //                       const SizedBox(width: 2),
        //                       Text(
        //                         'You Matched with ..',
        //                         style: GoogleFonts.raleway(
        //                           fontSize: 18,
        //                           fontWeight: FontWeight.w800,
        //                           color: Colors.red,
        //                           letterSpacing: 0.5,
        //                         ),
        //                       ),
        //                     ],
        //                   ),
        //                   const SizedBox(height: 4),
        //                   Text(
        //                     _capitalizeName(
        //                       selectedUser['name'] ?? 'Unknown User',
        //                     ),
        //                     style: GoogleFonts.raleway(
        //                       fontSize: 40, // Larger for impact
        //                       fontWeight: FontWeight.bold,
        //                       // color: colorScheme.onSurface,
        //                       color: Colors.white70,
        //                       height: 1.15,
        //                       shadows: [
        //                         Shadow(
        //                           color: Colors.black.withValues(alpha: 0.2),
        //                           blurRadius: 4,
        //                           offset: Offset(0, 2),
        //                         ),
        //                       ], // Soft shadow for depth
        //                     ),
        //                   ),

        //                   const SizedBox(height: 8),

        // 🏷️ "Match Result" → More natural: "You have a match"
        // Text(
        //   selectedUser['reason'] ??
        //       'You both enjoy coding and coffee!',
        //   style: GoogleFonts.raleway(
        //     fontSize: 18,
        //     fontWeight: FontWeight.w500,
        //     color: colorScheme.onSurfaceVariant.withValues(
        //       alpha: 0.95,
        //     ),
        //     height: 1.5,
        //     letterSpacing: 0.2,
        //   ),
        //   textAlign: TextAlign.left,
        // ),
        // Replace the Text widget for reason with this:
        //                   LayoutBuilder(
        //                     builder: (context, constraints) {
        //                       final reason =
        //                           selectedUser['reason'] ??
        //                           'You both enjoy coding and coffee!';
        //                       final textPainter = TextPainter(
        //                         text: TextSpan(
        //                           text: reason,
        //                           style: GoogleFonts.raleway(
        //                             fontSize: 10,
        //                             fontWeight: FontWeight.w500,
        //                             // color: colorScheme.onSurfaceVariant
        //                             //     .withValues(alpha: 0.95),
        //                             color: Colors.white60,
        //                           ),
        //                         ),
        //                         maxLines: 1,
        //                         textDirection: TextDirection.ltr,
        //                       )..layout(maxWidth: constraints.maxWidth);

        //                       return Column(
        //                         crossAxisAlignment: CrossAxisAlignment.start,
        //                         children: [
        //                           Row(
        //                             children: [
        //                               Icon(
        //                                 Icons.event,
        //                                 size: 18,
        //                                 color: colorScheme.primary,
        //                               ),
        //                               const SizedBox(width: 4),
        //                               Text(
        //                                 'Matched at: Event',
        //                                 style: GoogleFonts.raleway(
        //                                   fontSize: 14,
        //                                   color: colorScheme.primary,
        //                                 ),
        //                               ),
        //                             ],
        //                           ),
        //                           const SizedBox(height: 8),
        //                           Column(
        //                             crossAxisAlignment:
        //                                 CrossAxisAlignment.start,
        //                             children: [
        //                               // Event info
        //                               if (selectedUser['eventName'] !=
        //                                   null) ...[
        //                                 Row(
        //                                   children: [
        //                                     Icon(
        //                                       Icons.event,
        //                                       size: 18,
        //                                       // color: colorScheme.primary,
        //                                       color: Colors.white,
        //                                     ),
        //                                     const SizedBox(width: 4),
        //                                     Text(
        //                                       'Matched at: ${selectedUser['eventName']}',
        //                                       style: GoogleFonts.raleway(
        //                                         fontSize: 14,
        //                                         color: colorScheme.primary,
        //                                       ),
        //                                     ),
        //                                   ],
        //                                 ),
        //                                 const SizedBox(height: 8),
        //                               ],

        //                               // Reason text with expand/collapse
        //                               LayoutBuilder(
        //                                 builder: (context, constraints) {
        //                                   final reason =
        //                                       selectedUser['reason'] ??
        //                                       'You both enjoy coding and coffee!';
        //                                   final textPainter = TextPainter(
        //                                     text: TextSpan(
        //                                       text: reason,
        //                                       style: GoogleFonts.raleway(
        //                                         fontSize: 14,
        //                                         fontWeight: FontWeight.w500,
        //                                         color: Colors.white,
        //                                       ),
        //                                     ),
        //                                     maxLines: 1,
        //                                     textDirection: TextDirection.ltr,
        //                                   )..layout(
        //                                     maxWidth: constraints.maxWidth,
        //                                   );

        //                                   final isOverflowing =
        //                                       textPainter.didExceedMaxLines;

        //                                   return Column(
        //                                     crossAxisAlignment:
        //                                         CrossAxisAlignment.start,
        //                                     children: [
        //                                       if (isOverflowing &&
        //                                           !_showFullReason)
        //                                         Text(
        //                                           '${reason.substring(0, 30)}...',
        //                                           style: GoogleFonts.raleway(
        //                                             fontSize: 14,
        //                                             fontWeight: FontWeight.w500,
        //                                             // color: colorScheme
        //                                             //     .onSurfaceVariant
        //                                             //     .withValues(alpha:0.95),
        //                                             color: Colors.white70,
        //                                           ),
        //                                         ),

        //                                       if (!isOverflowing ||
        //                                           _showFullReason)
        //                                         Text(
        //                                           reason,
        //                                           style: GoogleFonts.raleway(
        //                                             fontSize: 14,
        //                                             fontWeight: FontWeight.w500,
        //                                             color: Colors.white70,
        //                                           ),
        //                                         ),

        //                                       if (isOverflowing)
        //                                         GestureDetector(
        //                                           onTap:
        //                                               () => setState(
        //                                                 () =>
        //                                                     _showFullReason =
        //                                                         !_showFullReason,
        //                                               ),
        //                                           child: Text(
        //                                             _showFullReason
        //                                                 ? 'Show less'
        //                                                 : 'Show more',
        //                                             style: GoogleFonts.raleway(
        //                                               fontSize: 16,
        //                                               color:
        //                                                   colorScheme.primary,
        //                                               decoration:
        //                                                   TextDecoration
        //                                                       .underline,
        //                                             ),
        //                                           ),
        //                                         ),
        //                                     ],
        //                                   );
        //                                 },
        //                               ),
        //                             ],
        //                           ),
        //                         ],
        //                       );
        //                     },
        //                   ),

        //                   // Add this method to your _MatchesPageState class:
        //                   const SizedBox(height: 16),

        //                   // 🏆 Optional: Match Strength Badge
        //                   Container(
        //                     padding: const EdgeInsets.symmetric(
        //                       horizontal: 12,
        //                       vertical: 6,
        //                     ),
        //                     decoration: BoxDecoration(
        //                       color: colorScheme.primary.withValues(
        //                         alpha: 0.15,
        //                       ),
        //                       borderRadius: BorderRadius.circular(20),
        //                       border: Border.all(
        //                         color: colorScheme.primary.withValues(
        //                           alpha: 0.3,
        //                         ),
        //                         width: 1,
        //                       ),
        //                     ),
        //                     child: Row(
        //                       mainAxisSize: MainAxisSize.min,
        //                       children: [
        //                         Icon(
        //                           Icons.star,
        //                           color: colorScheme.primary,
        //                           size: 16,
        //                         ),
        //                         const SizedBox(width: 6),
        //                         Text(
        //                           'High Compatibility',
        //                           style: GoogleFonts.raleway(
        //                             fontSize: 14,
        //                             fontWeight: FontWeight.w600,
        //                             color: colorScheme.primary,
        //                           ),
        //                         ),
        //                       ],
        //                     ),
        //                   ),
        //                 ],
        //               ),
        //             ),
        //           ),
        //         ),
        //       ),

        //       // Circular action buttons in top-right corner

        //     ],
        //   ),
        // ),
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

  Widget _buildHobbiesGrid(List<String> hobbies) {
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

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
    // return Center(
    //   child: Column(
    //     mainAxisSize: MainAxisSize.min,
    //     children: [
    //       CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
    //       const SizedBox(height: 20),
    //       Text(
    //         'Finding your matches...',
    //         style: GoogleFonts.raleway(
    //           color: colorScheme.onSurfaceVariant,
    //           fontSize: 16,
    //         ),
    //       ),
    //     ],
    //   ),
    // );
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
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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

  void _openChat(
    BuildContext context,
    String userId,
    String userName,
    String photoUrl,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatPage(
              matchedUserId: userId,
              matchedUserName: userName,
              matchedUserPhotoUrl: photoUrl,
            ),
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
                color:
                    isSelected
                        ? Colors.pinkAccent.shade100
                        : Colors.transparent,
                width: 3,
              ),
              boxShadow:
                  isSelected
                      ? [
                        BoxShadow(
                          // color: colorScheme.primary.withValues(alpha:0.3),
                          color: Colors.purple,
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                      : null,
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: colorScheme.surfaceContainerHighest,
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
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.person,
            size: 120,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
          color: colorScheme.surfaceContainerHighest,
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
            color: colorScheme.surfaceContainerHighest,
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
        color: colorScheme.surface.withValues(alpha: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
