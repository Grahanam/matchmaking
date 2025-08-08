import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app/pages/chat/chat_page.dart';
import 'package:google_fonts/google_fonts.dart';

class UserChatListPage extends StatefulWidget {
  const UserChatListPage({super.key});

  @override
  State<UserChatListPage> createState() => _UserChatListPageState();
}

class _UserChatListPageState extends State<UserChatListPage> {
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, Map<String, dynamic>> _matchedUsers = {};
  final Map<String, Map<String, dynamic>> _filteredUsers = {};
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadMatches();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterUsers();
    });
  }

  void _filterUsers() {
    if (_searchQuery.isEmpty) {
      _filteredUsers.clear();
      _filteredUsers.addAll(_matchedUsers);
    } else {
      _filteredUsers.clear();
      for (var entry in _matchedUsers.entries) {
        final name = entry.value['name']?.toString().toLowerCase() ?? '';
        if (name.contains(_searchQuery)) {
          _filteredUsers[entry.key] = entry.value;
        }
      }
    }
  }

  Future<void> _loadMatches() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
        _matchedUsers.clear();
        _filteredUsers.clear();
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final firestore = FirebaseFirestore.instance;
      
      final matchesSnapshot = await firestore
          .collectionGroup('matches')
          .where('userId', isEqualTo: user.uid)
          .where('released', isEqualTo: true)
          .where('matchedWith', isNotEqualTo: '')
          .get();

      final matchedUserIds = matchesSnapshot.docs
          .map((doc) => doc.data()['matchedWith'] as String)
          .toSet();

      await Future.wait(
        matchedUserIds.map((userId) => _fetchUserDetails(userId)),
      );

      _filterUsers(); // Initialize filtered list
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load chats. Please try again.';
      });
    }
  }

  Future<void> _fetchUserDetails(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? {};
      
      setState(() {
        _matchedUsers[userId] = {
          'name': userData['name'] ?? 'User',
          'photoUrl': userData['photoURL'] as String? ?? '',
        };
      });
    } catch (e) {
      setState(() {
        _matchedUsers[userId] = {
          'name': 'Unknown User',
          'photoUrl': '',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'Chats',
          style: GoogleFonts.raleway(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          if (_matchedUsers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // Focus on search field
                FocusScope.of(context).requestFocus(_searchFocusNode);
                Future.delayed(const Duration(milliseconds: 50), () {
                  FocusScope.of(context).requestFocus();
                });
              },
            ),
        ],
      ),
      body: _buildChatListContent(context, colorScheme),
    );
  }

  Widget _buildChatListContent(BuildContext context, ColorScheme colorScheme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, 
                  size: 48, 
                  color: colorScheme.error),
              const SizedBox(height: 20),
              Text(
                _error!,
                style: GoogleFonts.raleway(
                  color: colorScheme.onSurface, 
                  fontSize: 16
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadMatches,
                child: Text('Retry', style: GoogleFonts.raleway()),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: colorScheme.primary,
              strokeWidth: 2,
            ),
            const SizedBox(height: 20),
            Text(
              'Loading your chats...',
              style: GoogleFonts.raleway(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_matchedUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, 
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7), 
                  size: 80),
              const SizedBox(height: 24),
              Text(
                'No chats yet',
                style: GoogleFonts.raleway(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Match with people at events to start chatting',
                style: GoogleFonts.raleway(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              focusNode: _searchFocusNode,
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: GoogleFonts.raleway(color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: GoogleFonts.raleway(color: colorScheme.onSurface),
            ),
          ),
        ),
        
        // Chat list
        Expanded(
          child: _filteredUsers.isEmpty && _searchQuery.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, 
                            size: 48, 
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          'No matches found',
                          style: GoogleFonts.raleway(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: GoogleFonts.raleway(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredUsers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final userId = _filteredUsers.keys.elementAt(index);
                    final userData = _filteredUsers[userId]!;
                    final photoUrl = userData['photoUrl'] as String?;
                    return _ChatListItem(
                      userId: userId,
                      name: userData['name'] as String,
                      photoUrl: photoUrl,
                      colorScheme: colorScheme,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              matchedUserId: userId,
                              matchedUserName: userData['name'] as String,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final String userId;
  final String name;
  final String? photoUrl;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ChatListItem({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: colorScheme.surfaceContainer,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.surfaceVariant,
                  backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                      ? NetworkImage(photoUrl!)
                      : null,
                  child: (photoUrl == null || photoUrl!.isEmpty)
                      ? Icon(Icons.person, 
                          color: colorScheme.onSurfaceVariant,
                          size: 24)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.raleway(
                    color: colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: colorScheme.onSurfaceVariant,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}