// main_layout.dart
import 'package:app/pages/events/applied_event_page.dart';
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/home/home.dart';
import 'package:app/pages/match/match_page.dart';
import 'package:flutter/material.dart';
import 'package:app/pages/chat/user_chat_list_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:app/widgets/bottom_navbar_widget.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const Home(),
    const AppliedEventsPage(),
    const MatchesPage(),
    const UserChatListPage(),
    const ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavbarWidget(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}