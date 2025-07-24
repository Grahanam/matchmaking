import 'package:app/bloc/auth/auth_bloc.dart';
import 'package:app/bloc/event/event_bloc.dart';
import 'package:app/firebase_options.dart';
import 'package:app/pages/profile/profile_completion_page.dart';
import 'package:app/pages/auth/entry_page.dart'; 
import 'package:app/pages/events/nearby_event_page.dart';
import 'package:app/pages/home/home.dart';
import 'package:app/services/auth_repo.dart';
import 'package:app/services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final AuthRepository _authRepository = AuthRepository();
  final firestoreService = FirestoreService();

  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => AuthRepository(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => EventBloc(),
            child: NearbyEventsPage(),
          ),
          BlocProvider(
            create: (context) => AuthBloc(_authRepository, firestoreService),
          ),
        ],
        child: MaterialApp(
          title: 'MatchBox',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          
          debugShowCheckedModeBanner: false,
          // Updated home with AuthWrapper
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

// New AuthWrapper widget to handle authentication and profile state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
     return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is ProfileIncomplete) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileCompletionPage(),
            ),
          );
        }
      },
    child:StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authSnapshot.hasData) {
          return FutureBuilder<bool>(
            future: FirestoreService().isProfileComplete(authSnapshot.data!.uid),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              if (profileSnapshot.hasData && profileSnapshot.data!) {
                return const Home();
              } else {
                return const ProfileCompletionPage();
              }
            },
          );
        }
        
        return const EntryPage();
      },
    ));
  }
}