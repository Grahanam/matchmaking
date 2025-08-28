import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/pages/auth/signin_page.dart';
import 'package:app/pages/events/accepted_event_page.dart';
import 'package:app/pages/events/event_detail_page.dart';
import 'package:app/pages/events/manage_event_page.dart';
import 'package:app/pages/events/popular_event_page.dart';
import 'package:app/pages/events/your_event_page.dart';
import 'package:app/pages/match/match_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:app/pages/questions/create_question_page.dart';
import 'package:app/widgets/bottom_navbar_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:app/pages/events/create_event_page.dart';
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/events/applied_event_page.dart';
import 'package:app/pages/profile/profile_completion_page.dart';
import 'package:app/pages/chat/user_chat_list_page.dart';
import 'dart:ui' as ui;
import '../../models/event.dart';
import 'package:intl/intl.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Map<String, dynamic>? _userProfile;
  bool _loadingHeader = true;
  // ignore: unused_field
  bool _profileComplete = false;
  // ignore: unused_field
  bool _loadingProfile = false;
  // ignore: unused_field
  bool _profileChecked = false;
  List<Event> _puneEvents = [];
  bool _loadingPuneEvents = true;

  List<Event> _liveEvents = [];
  bool _loadingLiveEvents = true;
  Map<String, Map<String, dynamic>> _hostProfiles = {};

  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<bool> _scrolledNotifier;
  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isScrolled = _scrollController.offset > 50;
    if (_scrolledNotifier.hasListeners &&
        isScrolled != _scrolledNotifier.value) {
      _scrolledNotifier.value = isScrolled;
    }
  }

  Future<void> _fetchPuneEvents() async {
    try {
      final eventsSnapshot =
          await FirebaseFirestore.instance
              .collection('events')
              .where('endTime', isGreaterThan: DateTime.now())
              .orderBy('endTime')
              .limit(10)
              .get();
      setState(() {
        _puneEvents =
            eventsSnapshot.docs
                .map((doc) => Event.fromDocumentSnapshot(doc))
                .toList();
        _loadingPuneEvents = false;
      });
    } catch (e) {
      debugPrint('Error fetching Popular Events: $e');
      setState(() {
        _loadingPuneEvents = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _fetchPuneEvents();
    _fetchLiveEvents();
    _scrolledNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    if (_scrollController.hasListeners) {
      _scrollController.removeListener(_scrollListener);
    }
    _scrollController.dispose();
    _scrolledNotifier.dispose();
    super.dispose();
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
      debugPrint('Error fetching user profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _loadingHeader = false;
        });
      }
    }
  }

  Future<void> _fetchLiveEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _loadingLiveEvents = true;
    });

    try {
      final now = DateTime.now();

      // Get all events where user is host (without time filtering)
      final hostedEventsSnapshot =
          await FirebaseFirestore.instance
              .collection('events')
              .where('createdBy', isEqualTo: user.uid)
              .get();

      // Get events where user has accepted application
      final applicationsSnapshot =
          await FirebaseFirestore.instance
              .collection('event_applications')
              .where('userId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'accepted')
              .get();

      final applicationEventIds =
          applicationsSnapshot.docs
              .map((doc) => doc['eventId'] as String)
              .toList();

      List<Event> appliedEvents = [];
      if (applicationEventIds.isNotEmpty) {
        final appliedEventsSnapshot =
            await FirebaseFirestore.instance
                .collection('events')
                .where(FieldPath.documentId, whereIn: applicationEventIds)
                .get();

        appliedEvents =
            appliedEventsSnapshot.docs
                .map((doc) => Event.fromDocumentSnapshot(doc))
                .toList();
      }

      // Combine all events
      final allEvents = [
        ...hostedEventsSnapshot.docs.map(
          (doc) => Event.fromDocumentSnapshot(doc),
        ),
        ...appliedEvents,
      ];

      // Filter for live events on the client side
      final allLiveEvents =
          allEvents
              .where((event) {
                return event.startTime.isBefore(now) &&
                    event.endTime.isAfter(now);
              })
              .toSet()
              .toList();

      // Fetch host profiles
      final hostIds = allLiveEvents.map((e) => e.createdBy).toSet().toList();
      final hostsSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: hostIds)
              .get();

      final Map<String, Map<String, dynamic>> hostProfiles = {};
      for (var doc in hostsSnapshot.docs) {
        hostProfiles[doc.id] = doc.data() as Map<String, dynamic>;
      }

      setState(() {
        _liveEvents = allLiveEvents;
        _hostProfiles = hostProfiles;
        _loadingLiveEvents = false;
      });
    } catch (e) {
      debugPrint('Error fetching live events: $e');
      setState(() {
        _loadingLiveEvents = false;
      });
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
            (route) => false,
          );
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            'Match.Box',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              // color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          // title: Text(
          //   "Match.Box",
          //   style: GoogleFonts.raleway(fontWeight: FontWeight.bold),
          // ),
          backgroundColor: Colors.transparent,
          elevation: 0,
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
          //   GestureDetector(
          //     onTap: () async {
          //       await Navigator.push(
          //         context,
          //         MaterialPageRoute(
          //           builder:
          //               (context) =>
          //                   const ProfileCompletionPage(coreDetailsSet: true),
          //         ),
          //       );
          //     },
          //     child: Container(
          //       margin: const EdgeInsets.only(right: 24),
          //       padding: const EdgeInsets.all(9),
          //       decoration: BoxDecoration(
          //         shape: BoxShape.circle,
          //         color: Colors.pinkAccent,
          //       ),
          //       child: const Icon(Icons.edit, size: 20, color: Colors.white),
          //     ),
          //   ),
          // ],
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
          child: SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        //greeting section
                        Row(
                          children: [
                            Text(
                              'Hey, ',
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase() +
                                        userName.substring(1)
                                    : '',
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.pinkAccent,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              ' !',
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        Text(
                          'Discover fun events and meet amazing people near you.',
                          style: GoogleFonts.poppins(
                            // color: Colors.purple,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildLiveEvents(),
                  const SizedBox(height: 10),
                  //add card with hello message and username
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Card(
                      elevation: 2,
                      color: Color(0xFF2D0B5A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NearbyEventsPage(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.explore, color: Colors.pinkAccent),
                              SizedBox(width: 12),
                              Text(
                                'Explore Nearby Events',
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                              Spacer(),
                              Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // _buildQuickActions(),

                  // Venue Slider Section
                  _buildCreateEventSection(context),
                  const SizedBox(height: 10),
                  _buildPopularEvents(),
                  // const SizedBox(height: 10),

                  // _buildSectionTitle(
                  //   "Discover Events",
                  //   onPressed: () {
                  // Navigator.push(
                  //   context,
                  //   MaterialPageRoute(builder: (context) => const AllEventsPage()),
                  // );
                  //   },
                  // ),
                  // const SizedBox(height: 10),
                  // GridView.count(
                  //   padding: EdgeInsets.only(right: 7, left: 7),
                  //   shrinkWrap: true,
                  //   physics: const NeverScrollableScrollPhysics(),
                  //   crossAxisCount: 2,
                  //   childAspectRatio: 0.85,
                  //   crossAxisSpacing: 16,
                  //   mainAxisSpacing: 16,
                  //   children: [
                  // _buildEventCard(
                  //   context,
                  //   title: "Nearby Events",
                  //   icon: Icons.location_on,
                  //   gradientColors: [
                  //     Colors.blue.shade600,
                  //     Colors.blue.shade400,
                  //   ],
                  //   onTap:
                  //       () => Navigator.push(
                  //         context,
                  //         MaterialPageRoute(
                  //           builder: (context) => const NearbyEventsPage(),
                  //         ),
                  //       ),
                  //   imageUrl:
                  //       "https://images.unsplash.com/photo-1645730826845-cd2ddec9984f?q=80&w=2044&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                  // ),
                  // _buildEventCard(
                  //   context,
                  //   title: "Your Events",
                  //   icon: Icons.calendar_today,
                  //   gradientColors: [
                  //     Colors.purple.shade600,
                  //     Colors.purple.shade400,
                  //   ],
                  //   onTap:
                  //       () => Navigator.push(
                  //         context,
                  //         MaterialPageRoute(
                  //           builder: (context) => const YourEventsPage(),
                  //         ),
                  //       ),
                  //   imageUrl:
                  //       "https://images.unsplash.com/photo-1675852102347-fb3f8a2f48b5?q=80&w=1974&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                  // ),
                  // _buildEventCard(
                  //   context,
                  //   title: "Applied",
                  //   icon: Icons.check_circle,
                  //   gradientColors: [
                  //     Colors.green.shade600,
                  //     Colors.green.shade400,
                  //   ],
                  //   onTap:
                  //       () => Navigator.push(
                  //         context,
                  //         MaterialPageRoute(
                  //           builder: (context) => const AppliedEventsPage(),
                  //         ),
                  //       ),
                  //   imageUrl:
                  //       "https://images.unsplash.com/photo-1579457870499-e781952098c6?q=80&w=2073&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                  // ),
                  // _buildEventCard(
                  //   context,
                  //   title: "Popular",
                  //   icon: Icons.trending_up,
                  //   gradientColors: [
                  //     Colors.orange.shade600,
                  //     Colors.orange.shade400,
                  //   ],
                  //   onTap: () {
                  //     Navigator.push(
                  //       context,
                  //       MaterialPageRoute(
                  //         builder: (context) => const PopularEventsPage(),
                  //       ),
                  //     );
                  //   },
                  //   imageUrl:
                  //       "https://images.unsplash.com/photo-1702144949391-e905ba8d36dc?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBhcnR5JTIwaG9zdHxlbnwwfHwwfHx8MA%3D%3D",
                  // ),
                  //   ],
                  // ),
                  const SizedBox(height: 30),

                  // Create Event Section
                  // Center(
                  //   child: Text(
                  //     "Host Your Event At...",
                  //     style: GoogleFonts.poppins(
                  //       fontSize: 18,
                  //       fontWeight: FontWeight.bold,
                  //       color: Colors.pinkAccent,
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(height: 16),
                  // _buildVenueSlider(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // CustomScrollView(
          //   slivers: [
          //     SliverAppBar(
          //       automaticallyImplyLeading: false,
          //       // expandedHeight: MediaQuery.of(context).size.height * 0.11,
          //       pinned: false,
          //       floating: false,
          //       backgroundColor: Colors.transparent,
          //       flexibleSpace: FlexibleSpaceBar(
          //         background: _buildModernHeader(context, userName),
          //       ),
          //     ),
          //     SliverToBoxAdapter(

          //     ),
          //     // ),
          //   ],
          // ),
        ),
      ),
    );
  }

  // Venue Slider (Where events can be hosted)
  // Widget _buildVenueSlider() {
  //   final List<Map<String, String>> venues = [
  //     {
  //       'title': 'Trendy Rooftop',
  //       'image':
  //           'https://plus.unsplash.com/premium_photo-1661715804059-cc71a28f2c34?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
  //     },
  //     {
  //       'title': 'Cozy Coffee House',
  //       'image':
  //           'https://texascoffeeschool.com/wp-content/uploads/2024/08/1418-e1723733846245.jpg',
  //     },
  //     {
  //       'title': 'Art Gallery',
  //       'image':
  //           'https://srv-2.eden-gallery.com/wp-content/uploads/sites/15/2019/12/crowd-in-gallery.jpg',
  //     },
  //     {
  //       'title': 'Chic Bar & Lounge',
  //       'image':
  //           'https://thumbs.dreamstime.com/b/young-people-cocktails-nightclub-group-best-friends-partying-pub-toasting-drinks-85710542.jpg',
  //     },
  //     {
  //       'title': 'Outdoor Park',
  //       'image':
  //           'https://media-api.xogrp.com/images/e5abd221-4871-4172-af96-564f1cdb7218~cr_50.5.1974.1294?quality=50',
  //     },
  //   ];
  //   return _AutoVenueSlider(venues: venues);
  // }

  // Widget _buildQuickActions() {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
  //     child: Row(
  //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //       children: [
  //         Expanded(
  //           child: _buildQuickActionButton(
  //             icon: Icons.people,
  //             label: "Matches",
  //             onTap: () {
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(builder: (context) => MatchesPage()),
  //               );
  //             },
  //             color: Colors.pink,
  //           ),
  //         ),
  //         Expanded(
  //           child: _buildQuickActionButton(
  //             icon: Icons.chat,
  //             label: "Messages",
  //             onTap: () {
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (context) => const UserChatListPage(),
  //                 ),
  //               );
  //             },
  //             color: Colors.blue,
  //           ),
  //         ),
  //         Expanded(
  //           // Added Expanded
  //           child: _buildQuickActionButton(
  //             icon: Icons.add_circle,
  //             label: "Questions",
  //             onTap: () {
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(builder: (context) => CreateQuestionPage()),
  //               );
  //             },
  //             color: Colors.green,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildLiveEvents() {
    if (_loadingLiveEvents) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );
    }

    if (_liveEvents.isEmpty) {
      return Container(); // Don't show anything if no live events
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _buildSectionTitle(
          "Your Ongoing Events",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const YourEventsPage()),
            );
          },
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _liveEvents.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final event = _liveEvents[index];
              return _buildLiveEventCard(event);
            },
          ),
        ),
      ],
    );
  }

  // Add this widget to build individual live event cards
  Widget _buildLiveEventCard(Event event) {
    final hostProfile = _hostProfiles[event.createdBy];
    final hostName = hostProfile?['name'] ?? 'Unknown';
    final hostPhoto = hostProfile?['photoUrl'];
    final isHost = event.createdBy == FirebaseAuth.instance.currentUser?.uid;

    return InkWell(
       onTap: () {
      if (isHost) {
        // Navigate to ManageEventPage for events hosted by the user
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ManageEventPage(eventId: event.id),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AcceptedEventDetailPage(event: event),
          ),
        );
      }
    },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    image: DecorationImage(
                      image: NetworkImage(
                        event.cover.isNotEmpty
                            ? event.cover
                            : "https://images.unsplash.com/photo-1540575467063-178a50c2df87?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1350&q=80",
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "LIVE",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Event Details
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage:
                            hostProfile?['photoURL'] != null
                                ? NetworkImage(hostProfile!['photoURL'])
                                : null,
                        child:
                            hostProfile?['photoURL'] == null
                                ? Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.white,
                                )
                                : null,
                        backgroundColor:
                            hostProfile?['photoURL'] == null
                                ? Colors.grey
                                : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isHost ? "Hosted by You" : "Hosted by $hostName",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.pinkAccent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.city.isNotEmpty ? event.city : "City",
                          style: GoogleFonts.poppins(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
            color: color.withValues(alpha: 0.1),
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
  Widget _buildSectionTitle(String title, {required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
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
            onPressed: onPressed,
            child: Text(
              "See all",
              style: GoogleFonts.poppins(
                color: Colors.pinkAccent,
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
              color: gradientColors.first.withValues(alpha: 0.18),
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
                        Colors.black.withValues(alpha: 0.5),
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
                      color: Colors.white.withValues(alpha: 0.2),
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
                      color: Colors.white.withValues(alpha: 0.9),
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

  Widget _buildPopularEvents() {
    if (_loadingPuneEvents) {
      return const Center(
        child: Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    }

    if (_puneEvents.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _buildSectionTitle(
          "Popular Events",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PopularEventsPage(),
              ),
            );
          },
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _puneEvents.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final event = _puneEvents[index];
              return _buildPopularEventCard(event);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPopularEventCard(Event event) {
    print(event);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventDetailPage(event: event),
          ),
        );
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    image: DecorationImage(
                      image: NetworkImage(
                        event.cover.isNotEmpty
                            ? event.cover
                            : "https://images.unsplash.com/photo-1540575467063-178a50c2df87?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1350&q=80",
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat.MMM().format(event.startTime),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          DateFormat.d().format(event.startTime),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Event Details
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      // color: Colors.purple
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.pinkAccent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.city.isNotEmpty ? event.city : "City",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            // color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // const SizedBox(height: 4),
                ],
              ),
            ),
          ],
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
                    color: Color(0xFF2D0B5A),
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
                          // foregroundColor: Colors.white,
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
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.pinkAccent,
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

  // void _onItemTapped(int index) {
  //   setState(() {
  //     _selectedIndex = index;
  //   });
  // }

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
                color: Colors.purple.withValues(alpha: 0.18),
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
                  color: Colors.white.withValues(alpha: 0.15),
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
                        color: Colors.white.withValues(alpha: 0.9),
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
                  color: Colors.purple.withValues(alpha: 0.18),
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
                          Colors.black.withValues(alpha: 0.7),
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
