import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/pages/auth/signin_page.dart';
import 'package:app/pages/events/popular_event_page.dart';
import 'package:app/pages/events/your_event_page.dart';
import 'package:app/pages/match/match_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:app/pages/questions/create_question_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import 'dart:async';
import 'package:app/pages/events/create_event_page.dart';
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/events/applied_event_page.dart';
import 'package:app/pages/profile/profile_completion_page.dart';
import 'package:app/pages/chat/user_chat_list_page.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Map<String, dynamic>? _userProfile;
  bool _loadingHeader = true;
  bool _profileComplete = false;
  bool _loadingProfile = false;
  bool _profileChecked = false;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _loadingProfile = true;
      _loadingHeader = true;
    });

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        final profileComplete = data['profileComplete'] == true;

        setState(() {
          _userProfile = data;
          _profileChecked = profileComplete;
          _profileComplete = profileComplete;
        });

        if (!profileComplete) {
          // Navigate to profile completion after a short delay
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          const ProfileCompletionPage(coreDetailsSet: false),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _loadingHeader = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final String userEmail = user?.email ?? 'User';

    // Get name from Firestore profile if available
    String userName = 'User';
    if (_userProfile != null && _userProfile!['name'] != null) {
      userName = _userProfile!['name'];
    } else if (!_loadingHeader) {
      userName = userEmail.split('@').first;
    }

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is UnAuthenticated) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const SignIn()),
            (route) => false, // Remove all existing routes
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModernHeader(context, userName),
                const SizedBox(height: 16),
                // Quick Actions Row (moved to top)
                _buildQuickActions(),
                // Discover Events Section
                _buildSectionTitle("Discover Events"),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildEventCard(
                        context,
                        title: "Nearby Events",
                        icon: Icons.location_on,
                        gradientColors: [
                          Colors.blue.shade600,
                          Colors.blue.shade400,
                        ],
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NearbyEventsPage(),
                              ),
                            ),
                        imageUrl:
                            "https://images.unsplash.com/photo-1645730826845-cd2ddec9984f?q=80&w=2044&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                      ),
                      _buildEventCard(
                        context,
                        title: "Your Events",
                        icon: Icons.calendar_today,
                        gradientColors: [
                          Colors.purple.shade600,
                          Colors.purple.shade400,
                        ],
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const YourEventsPage(),
                              ),
                            ),
                        imageUrl:
                            "https://images.unsplash.com/photo-1675852102347-fb3f8a2f48b5?q=80&w=1974&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                      ),
                      _buildEventCard(
                        context,
                        title: "Applied",
                        icon: Icons.check_circle,
                        gradientColors: [
                          Colors.green.shade600,
                          Colors.green.shade400,
                        ],
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AppliedEventsPage(),
                              ),
                            ),
                        imageUrl:
                            "https://images.unsplash.com/photo-1579457870499-e781952098c6?q=80&w=2073&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                      ),
                      _buildEventCard(
                        context,
                        title: "Popular",
                        icon: Icons.trending_up,
                        gradientColors: [
                          Colors.orange.shade600,
                          Colors.orange.shade400,
                        ],
                         onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PopularEventsPage()),
    );
  },
                        imageUrl:
                            "https://images.unsplash.com/photo-1702144949391-e905ba8d36dc?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBhcnR5JTIwaG9zdHxlbnwwfHwwfHx8MA%3D%3D",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Create Event Section
                _buildCreateEventSection(context),
                const SizedBox(height: 16),
                // Venue Slider Section
                Center(
                  child: Text(
                    "Host Your Event At...",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildVenueSlider(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildModernBottomNavBar(),
      ),
    );
  }

  // NEW: Modern Header Design
  Widget _buildModernHeader(BuildContext context, String name) {
    final user = FirebaseAuth.instance.currentUser;
    return Stack(
      children: [
        // Vibrant gradient background
        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.pinkAccent.shade100,
                Colors.purple.shade800,
                Colors.deepPurple.shade900,
              ],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
        ),
        // Blurred overlay for effect
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withOpacity(0.15)),
          ),
        ),
        // Content
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App name left-aligned at the top
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        'Match.Box',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Find your perfect match, or your next adventure.',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Profile avatar removed from here
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Venue Slider (Where events can be hosted)
  Widget _buildVenueSlider() {
    final List<Map<String, String>> venues = [
      {
        'title': 'Trendy Rooftop',
        'image':
            'https://plus.unsplash.com/premium_photo-1661715804059-cc71a28f2c34?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
      },
      {
        'title': 'Cozy Coffee House',
        'image':
            'https://texascoffeeschool.com/wp-content/uploads/2024/08/1418-e1723733846245.jpg',
      },
      {
        'title': 'Art Gallery',
        'image':
            'https://srv-2.eden-gallery.com/wp-content/uploads/sites/15/2019/12/crowd-in-gallery.jpg',
      },
      {
        'title': 'Chic Bar & Lounge',
        'image':
            'https://thumbs.dreamstime.com/b/young-people-cocktails-nightclub-group-best-friends-partying-pub-toasting-drinks-85710542.jpg',
      },
      {
        'title': 'Outdoor Park',
        'image':
            'https://media-api.xogrp.com/images/e5abd221-4871-4172-af96-564f1cdb7218~cr_50.5.1974.1294?quality=50',
      },
    ];
    return _AutoVenueSlider(venues: venues);
  }

  // NEW: Quick Action Buttons
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickActionButton(
            icon: Icons.people,
            label: "Matches",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => MatchesPage()),
              );
            },
            color: Colors.pink,
          ),
          // _buildQuickActionButton(
          //   icon: Icons.favorite,
          //   label: "Likes",
          //   onTap: () {},
          //   color: Colors.red,
          // ),
          _buildQuickActionButton(
            icon: Icons.chat,
            label: "Messages",
            onTap:
                () => {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserChatListPage(),
                    ),
                  ),
                },
            color: Colors.blue,
          ),
          // Add this button for testing question creation
          _buildQuickActionButton(
            icon: Icons.add_circle,
            label: "Create Question",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateQuestionPage()),
              );
            },
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: IconButton(icon: Icon(icon, color: color), onPressed: onTap),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
        ),
      ],
    );
  }

  // NEW: Section Title
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {},
            child: Text(
              "See all",
              style: GoogleFonts.poppins(
                color: Colors.purple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Redesigned Event Card
  Widget _buildEventCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    String? imageUrl,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          image:
              imageUrl != null
                  ? DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  )
                  : null,
          gradient:
              imageUrl == null
                  ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradientColors,
                  )
                  : null,
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Gradient overlay for text readability
            if (imageUrl != null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.5),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            // Event info
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Find your perfect match",
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Action icons
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  Icon(Icons.favorite_border, color: Colors.white),
                  const SizedBox(width: 8),
                  Icon(Icons.bookmark_border, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Modern Bottom Navigation Bar
  Widget _buildModernBottomNavBar() {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      _selectedIndex == 0
                          ? Colors.purple.withOpacity(0.15)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.home,
                  color: _selectedIndex == 0 ? Colors.purple : Colors.grey,
                ),
              ),
              label: "",
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      _selectedIndex == 1
                          ? Colors.purple.withOpacity(0.15)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.chat,
                  color: _selectedIndex == 1 ? Colors.purple : Colors.grey,
                ),
              ),
              label: "",
            ),
            // Profile avatar as third item
            BottomNavigationBarItem(
              icon: FutureBuilder<DocumentSnapshot>(
                future:
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(user?.uid)
                        .get(),
                builder: (context, snapshot) {
                  String? photoUrl;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    photoUrl = data?['photoURL'] as String?;
                  }
                  return CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage:
                        (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                    child:
                        (photoUrl == null || photoUrl.isEmpty)
                            ? Icon(Icons.person, color: Colors.grey, size: 20)
                            : null,
                  );
                },
              ),
              label: "",
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.purple,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          onTap: (index) {
            if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserChatListPage(),
                ),
              );
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            } else {
              _onItemTapped(index);
            }
          },
        ),
      ),
    );
  }

  void _showCreateEventDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_available,
                    size: 64,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Create New Event",
                    style: GoogleFonts.raleway(
                      textStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "You're about to create a new event. Make sure you have all the details ready!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.raleway(
                      textStyle: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => BlocProvider(
                                    create: (context) => EventBloc(),
                                    child: const CreateEventPage(),
                                  ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text("Continue"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildCreateEventSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => _showCreateEventDialog(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.purple, Colors.pinkAccent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event, color: Colors.white, size: 36),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Host a New Event!",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Bring people together, make new friends, or find your perfect match. Start your own event now!",
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Place this at the bottom of the file, outside of any class
class _AutoVenueSlider extends StatefulWidget {
  final List<Map<String, String>> venues;
  const _AutoVenueSlider({required this.venues});

  @override
  State<_AutoVenueSlider> createState() => _AutoVenueSliderState();
}

class _AutoVenueSliderState extends State<_AutoVenueSlider> {
  late final ScrollController _scrollController;
  Timer? _timer;
  double _scrollPosition = 0.0;
  static const double _cardWidth = 260.0;
  static const double _cardMargin = 16.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController.hasClients) {
        _scrollPosition += 0.8; // Adjust for speed
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (_scrollPosition >= maxScroll) {
          _scrollPosition = 0.0;
        }
        _scrollController.jumpTo(_scrollPosition);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: widget.venues.length,
        itemBuilder: (context, i) {
          final venue = widget.venues[i];
          return Container(
            width: _cardWidth,
            margin: EdgeInsets.only(
              left: i == 0 ? _cardMargin : _cardMargin / 2,
              right:
                  i == widget.venues.length - 1 ? _cardMargin : _cardMargin / 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              image: DecorationImage(
                image: NetworkImage(venue['image']!),
                fit: BoxFit.cover,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      venue['title']!,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
