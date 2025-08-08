import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/home/home.dart';
import '../pages/login/login.dart';

class AuthService {

  Future<void> signup({
    required String email,
    required String password,
    required BuildContext context
  }) async {
    
    try {

      final credential=await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password
      );

      debugPrint('$credential');

      await Future.delayed(const Duration(seconds: 1));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) => const Home()
        )
      );
      
    } on FirebaseAuthException catch(e) {
      String message = '';
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists with that email.';
      }
       Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.SNACKBAR,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
        fontSize: 14.0,
      );
    }
    catch(e,stack){
 debugPrint('Sign-in error: $e\n$stack');
    }

  }

  Future<void> signin({
  required String email,
  required String password,
  required BuildContext context
}) async {
  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password
    );
    // Only navigate on successful login
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const Home())
    );
  } on FirebaseAuthException catch(e) {
    String message = '';
    if (e.code == 'user-not-found') {
      message = 'No user found for that email.';
    } else if (e.code == 'wrong-password') {
      message = 'Wrong password provided.';
    } else {
      message = 'Login failed: ${e.message}';
    }
    
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.SNACKBAR,
      backgroundColor: Colors.black54,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
  catch(e,stack){
    debugPrint('Sign-in error: $e\n$stack');
    Fluttertoast.showToast(
      msg: 'An unexpected error occurred',
      toastLength: Toast.LENGTH_LONG,
    );
  }
}

  Future<void> signout({
    required BuildContext context
  }) async {
    
    await FirebaseAuth.instance.signOut();
    await Future.delayed(const Duration(seconds: 1));
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) =>Login()
        )
      );
  }

Future<void> googleauth({
  required BuildContext context,
}) async {
  try {
    // Initialize GoogleSignIn with forced account selection
    final GoogleSignIn googleSignIn = GoogleSignIn(
      signInOption: SignInOption.standard, // Always show account selection
      scopes: ['email', 'profile'],
    );

    // Sign out first to ensure account selection
    await googleSignIn.signOut();

    // Proceed with sign in
    final GoogleSignInAccount? user = await googleSignIn.signIn();
    if (user == null) return; // user cancelled
  
    final displayName = user.displayName;        // Full name
    final email = user.email;                    // Email
    final photoUrl = user.photoUrl;              // Profile picture URL

    debugPrint('$user');


    final GoogleSignInAuthentication userAuth = await user.authentication;
  
    final credential = GoogleAuthProvider.credential(
      idToken: userAuth.idToken,
      accessToken: userAuth.accessToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);

    final currentUser=FirebaseAuth.instance.currentUser;

    final uid=currentUser?.uid;

     final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
      
      // Save only if user doc does not exist
    if (!userDoc.exists) {
    // Prepare minimal user data for initial signup
      final userData = {
        'uid': uid,
        'email': email,
        'name': displayName ?? '',
        'photoURL': photoUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': false, // Mark profile as incomplete
        // Optional fields initialized as null
        'age': null,
        'dob': null,
        'introduction': null,
        'hostedCount': 0,
        'attendedCount': 0,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData);
    }
   
    if (FirebaseAuth.instance.currentUser != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Home()),
      );
    }
  } catch (e, stack) {
    debugPrint('Google sign-in failed: $e\n$stack');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Google sign-in failed: ${e.toString()}')),
    );
  }
}

 
}