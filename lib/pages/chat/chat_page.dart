// In chat_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app/services/firestore_service.dart';
import 'package:app/models/chat.dart';
import 'package:google_fonts/google_fonts.dart'; // Add this import

class ChatPage extends StatefulWidget {
  final String matchedUserId;
  final String matchedUserName;
  final String? matchedUserPhotoUrl; // Add this parameter

  const ChatPage({
    super.key,
    required this.matchedUserId,
    required this.matchedUserName,
    this.matchedUserPhotoUrl, // Add this parameter
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Stream<List<Message>> _messagesStream;
  String? _chatId;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _chatId = await FirestoreService().getOrCreateChat(
      user.uid,
      widget.matchedUserId,
    );

    _messagesStream = FirestoreService().streamMessages(_chatId!);
    setState(() {});
  }

  void _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _chatId == null || _controller.text.trim().isEmpty)
      return;

    await FirestoreService().sendMessage(
      chatId: _chatId!,
      senderId: user.uid,
      text: _controller.text.trim(),
    );

    _controller.clear();

    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            // User profile picture
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: widget.matchedUserPhotoUrl != null && widget.matchedUserPhotoUrl!.isNotEmpty
                    ? NetworkImage(widget.matchedUserPhotoUrl!)
                    : null,
                child: widget.matchedUserPhotoUrl == null || widget.matchedUserPhotoUrl!.isEmpty
                    ? Icon(Icons.person, 
                          color: colorScheme.onSurfaceVariant,
                          size: 20)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.matchedUserName,
              style: GoogleFonts.raleway(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      // Rest of the body remains the same...
      body: _chatId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (_isFirstLoad && snapshot.hasData) {
                      _isFirstLoad = false;
                      _scrollToBottom();
                    }

                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final messages = snapshot.data ?? [];
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: false,
                      padding: const EdgeInsets.all(8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == user?.uid;
                        return Align(
                          alignment:
                              isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isMe
                                      ? Colors.deepPurple[500]
                                      : Colors.grey[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg.text,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 9.0,
                  right: 9.0,
                  bottom: 30.0,
                  top: 9.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _sendMessage,
                      color: Colors.deepPurple,
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}