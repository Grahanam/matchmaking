import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../models/group.dart';

class GroupChatPage extends StatefulWidget {
  final Event event;
  final Group group;
  final bool isHost;
  
  const GroupChatPage({
    super.key,
    required this.event,
    required this.group,
    required this.isHost,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.group.name} Chat"),
      ),
      body: Column(
        children: [
          if (widget.isHost) _buildAnnouncementSection(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('group_chats')
                  .doc(widget.group.id)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                });
                
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildMessageBubble(data);
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildAnnouncementSection() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.announcement),
        label: const Text("Send Announcement to All Groups"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
        ),
        onPressed: () {
          _showAnnouncementDialog();
        },
      ),
    );
  }

  void _showAnnouncementDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final announcementController = TextEditingController();
        return AlertDialog(
          title: const Text("Send Announcement"),
          content: TextField(
            controller: announcementController,
            decoration: const InputDecoration(
              hintText: "Enter announcement message",
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                _sendAnnouncement(announcementController.text);
                Navigator.pop(context);
              },
              child: const Text("Send"),
            ),
          ],
        );
      },
    );
  }

  void _sendAnnouncement(String message) async {
    if (message.isEmpty) return;
    
    // Send to all groups in the event
    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('eventId', isEqualTo: widget.event.id)
        .get();
    
    for (final groupDoc in groupsSnapshot.docs) {
      await FirebaseFirestore.instance
          .collection('group_chats')
          .doc(groupDoc.id)
          .collection('messages')
          .add({
            'text': message,
            'senderId': currentUser.uid,
            'senderName': "Event Host",
            'timestamp': Timestamp.now(),
            'isAnnouncement': true,
          });
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['senderId'] == currentUser.uid;
    final isAnnouncement = message['isAnnouncement'] == true;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAnnouncement
                ? Colors.amber[100]
                : isMe
                    ? Colors.blue[100]
                    : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isAnnouncement)
                Row(
                  children: [
                    Icon(Icons.announcement, size: 16, color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    Text(
                      "ANNOUNCEMENT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[700],
                      ),
                    ),
                  ],
                ),
              if (!isMe && !isAnnouncement)
                Text(
                  message['senderName'] ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              Text(message['text']),
              const SizedBox(height: 4),
              Text(
                DateFormat('h:mm a').format(
                  (message['timestamp'] as Timestamp).toDate(),
                ),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    await FirebaseFirestore.instance
        .collection('group_chats')
        .doc(widget.group.id)
        .collection('messages')
        .add({
          'text': text,
          'senderId': currentUser.uid,
          'senderName': userDoc['name'] ?? 'Unknown',
          'timestamp': Timestamp.now(),
          'isAnnouncement': false,
        });

    _messageController.clear();
  }
}