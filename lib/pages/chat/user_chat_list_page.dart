import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app/services/firestore_service.dart';
import 'package:app/pages/chat/chat_page.dart';
import 'package:google_fonts/google_fonts.dart';

class UserChatListPage extends StatefulWidget {
  const UserChatListPage({Key? key}) : super(key: key);

  @override
  State<UserChatListPage> createState() => _UserChatListPageState();
}

class _UserChatListPageState extends State<UserChatListPage> {
  final Map<String, Map<String, dynamic>> _matchedUsers = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final firestore = FirebaseFirestore.instance;
      
      // Query all matches where the user is involved and released=true
      final matchesSnapshot = await firestore
          .collectionGroup('matches')
          .where('userId', isEqualTo: user.uid)
          .where('released', isEqualTo: true)
          .where('matchedWith', isNotEqualTo: '')
          .orderBy('matchedWith')
          .get();

      // Process matches and get unique matched users
      final matchedUserIds = matchesSnapshot.docs
          .map((doc) => doc.data()['matchedWith'] as String)
          .toSet();

      // Get user details for each matched user
      for (final userId in matchedUserIds) {
        final userDoc = await firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>? ?? {};
          
          _matchedUsers[userId] = {
            'name': userData['name'] ?? 'User',
            'photoUrl': userData['photoURL'] as String? ?? '', // Safe access
            'reason': matchesSnapshot.docs
                .firstWhere((doc) => doc['matchedWith'] == userId)['reason'] ?? ''
          };
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load matches: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        title: Text(
          'Chats',
          style: GoogleFonts.raleway(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: colorScheme.onBackground,
          ),
        ),
        centerTitle: false,
      ),
      backgroundColor: colorScheme.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: _buildChatListContent(context, colorScheme),
      ),
    );
  }

  Widget _buildChatListContent(BuildContext context, ColorScheme colorScheme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            style: GoogleFonts.raleway(color: colorScheme.error, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_matchedUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, color: colorScheme.onSurfaceVariant, size: 64),
              const SizedBox(height: 20),
              Text(
                'No matches yet',
                style: GoogleFonts.raleway(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Start attending events and matching to see your chats here!',
                style: GoogleFonts.raleway(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _matchedUsers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final userId = _matchedUsers.keys.elementAt(index);
        final userData = _matchedUsers[userId]!;
        final photoUrl = userData['photoUrl'] as String?;
        return Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: colorScheme.surfaceContainer,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatPage(
                    matchedUserId: userId,
                    matchedUserName: userData['name'],
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colorScheme.primary.withOpacity(0.08),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Icon(Icons.person, color: colorScheme.primary, size: 32)
                        : null,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userData['name'],
                          style: GoogleFonts.raleway(
                            color: colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          userData['reason'],
                          style: GoogleFonts.raleway(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: colorScheme.onSurfaceVariant, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}