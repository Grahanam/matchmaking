import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app/pages/chat/chat_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rxdart/rxdart.dart';

class UserChatListPage extends StatefulWidget {
  const UserChatListPage({super.key});

  @override
  State<UserChatListPage> createState() => _UserChatListPageState();
}

class _UserChatListPageState extends State<UserChatListPage> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final BehaviorSubject<String> _searchQuery = BehaviorSubject.seeded('');
  final BehaviorSubject<bool> _loading = BehaviorSubject.seeded(true);
  final BehaviorSubject<String?> _error = BehaviorSubject.seeded(null);
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;

  // Stream for matched users
  final BehaviorSubject<Map<String, Map<String, dynamic>>> _matchedUsers =
      BehaviorSubject.seeded({});

  // Combined stream for filtered users
  late final Stream<Map<String, Map<String, dynamic>>> _filteredUsers;

  // Track if the page is disposed
  bool _isDisposed = false;

  // Track ongoing operations to cancel them on dispose
  Future<void>? _loadMatchesOperation;

  @override
  void initState() {
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
    super.initState();

    // Create filtered users stream by combining search query and matched users
    _filteredUsers = Rx.combineLatest2(_matchedUsers, _searchQuery, (
      Map<String, Map<String, dynamic>> users,
      String query,
    ) {
      if (query.isEmpty) return users;

      final filtered = <String, Map<String, dynamic>>{};
      for (var entry in users.entries) {
        final name = entry.value['name']?.toString().toLowerCase() ?? '';
        if (name.contains(query)) {
          filtered[entry.key] = entry.value;
        }
      }
      return filtered;
    });

    _searchController.addListener(_onSearchChanged);
    _loadMatches();
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
    _isDisposed = true;
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();

    // Cancel any ongoing operations
    _loadMatchesOperation?.ignore();

    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();

    // Only close streams if they haven't been closed already
    if (!_searchQuery.isClosed) _searchQuery.close();
    if (!_loading.isClosed) _loading.close();
    if (!_error.isClosed) _error.close();
    if (!_matchedUsers.isClosed) _matchedUsers.close();

    super.dispose();
  }

  void _onSearchChanged() {
    if (_isDisposed) return;
    _searchQuery.add(_searchController.text.toLowerCase());
  }

  Future<void> _loadMatches() async {
    // Cancel any previous operation
    _loadMatchesOperation?.ignore();

    // Create a new operation
    final completer = Completer<void>();
    _loadMatchesOperation = completer.future;

    try {
      if (_isDisposed) return;
      _loading.add(true);
      _error.add(null);
      _matchedUsers.add({});

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _isDisposed) {
        completer.complete();
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

      if (matchedUserIds.isEmpty) {
        if (_isDisposed) {
          completer.complete();
          return;
        }
        _loading.add(false);
        completer.complete();
        return;
      }

      // Batch fetch all user details at once
      final usersSnapshot =
          await firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: matchedUserIds.toList())
              .get();

      if (_isDisposed) {
        completer.complete();
        return;
      }

      final usersMap = <String, Map<String, dynamic>>{};
      for (var doc in usersSnapshot.docs) {
        final userData = doc.data();
        usersMap[doc.id] = {
          'name': userData['name'] ?? 'User',
          'photoUrl': userData['photoURL'] as String? ?? '',
        };
      }

      if (_isDisposed) {
        completer.complete();
        return;
      }

      _matchedUsers.add(usersMap);
      _loading.add(false);
      completer.complete();
    } catch (e) {
      if (_isDisposed) {
        completer.complete();
        return;
      }
      _loading.add(false);
      _error.add('Failed to load chats. Please try again.');
      completer.complete();
    }
  }

  // Helper method to safely add to streams
  void _safeAddToStream<T>(BehaviorSubject<T> stream, T value) {
    if (!_isDisposed && !stream.isClosed) {
      stream.add(value);
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
          'Chats',
          style: GoogleFonts.raleway(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: colorScheme.onSurface,
          ),
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
        // actions: [
        //   StreamBuilder<Map<String, Map<String, dynamic>>>(
        //     stream: _matchedUsers,
        //     builder: (context, snapshot) {
        //       final hasUsers = snapshot.hasData && snapshot.data!.isNotEmpty;
        //       return hasUsers
        //           ? IconButton(
        //               icon: const Icon(Icons.search),
        //               onPressed: () {
        //                 FocusScope.of(context).requestFocus(_searchFocusNode);
        //               },
        //             )
        //           : const SizedBox.shrink();
        //     },
        //   ),
        // ],
      ),
      body: StreamBuilder<Map<String, Map<String, dynamic>>>(
        stream: _matchedUsers,
        builder: (context, matchedUsersSnapshot) {
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
              child: StreamBuilder<bool>(
                stream: _loading,
                builder: (context, loadingSnapshot) {
                  return StreamBuilder<String?>(
                    stream: _error,
                    builder: (context, errorSnapshot) {
                      return _buildChatListContent(
                        context,
                        colorScheme,
                        matchedUsersSnapshot.data ?? {},
                        loadingSnapshot.data ?? true,
                        errorSnapshot.data,
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatListContent(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, Map<String, dynamic>> matchedUsers,
    bool loading,
    String? error,
  ) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 20),
              Text(
                error,
                style: GoogleFonts.raleway(
                  color: colorScheme.onSurface,
                  fontSize: 16,
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

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );
      // return Center(
      //   child: Column(
      //     mainAxisSize: MainAxisSize.min,
      //     children: [
      //       CircularProgressIndicator(
      //         color: colorScheme.primary,
      //         strokeWidth: 2,
      //       ),
      //       const SizedBox(height: 20),
      //       Text(
      //         'Loading your chats...',
      //         style: GoogleFonts.raleway(
      //           color: colorScheme.onSurfaceVariant,
      //           fontSize: 16,
      //         ),
      //       ),
      //     ],
      //   ),
      // );
    }

    if (matchedUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.forum_outlined,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                size: 80,
              ),
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
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              focusNode: _searchFocusNode,
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: GoogleFonts.raleway(
                  color: colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: GoogleFonts.raleway(color: colorScheme.onSurface),
            ),
          ),
        ),

        // Chat list with filtered users
        Expanded(
          child: StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: _filteredUsers,
            builder: (context, snapshot) {
              final filteredUsers = snapshot.data ?? {};
              final searchQuery = _searchController.text.toLowerCase();

              if (filteredUsers.isEmpty && searchQuery.isNotEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: GoogleFonts.raleway(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try searching with a different name',
                          style: GoogleFonts.raleway(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                controller: _scrollController,
                physics: AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: filteredUsers.length,
                separatorBuilder:
                    (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final userId = filteredUsers.keys.elementAt(index);
                  final userData = filteredUsers[userId]!;
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
                          builder:
                              (context) => ChatPage(
                                matchedUserId: userId,
                                matchedUserName: userData['name'] as String,
                                matchedUserPhotoUrl:
                                    userData['photoUrl'] as String?,
                              ),
                        ),
                      );
                    },
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
      // color: colorScheme.surfaceContainer,
      color:
          Theme.of(context).brightness == Brightness.dark
              ? Colors.black26
              : Colors.white70,
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
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (photoUrl != null && photoUrl!.isNotEmpty)
                          ? NetworkImage(photoUrl!)
                          : null,
                  child:
                      (photoUrl == null || photoUrl!.isEmpty)
                          ? Icon(
                            Icons.person,
                            color: colorScheme.onSurfaceVariant,
                            size: 24,
                          )
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
