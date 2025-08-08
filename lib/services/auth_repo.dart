import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthRepository {
  final _firebaseAuth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _saveInitialUserData(
    User user, {
    String? name,
    String? photoUrl,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);

    // Check if user document already exists
    final doc = await userRef.get();

    if (doc.exists) {
      // For existing users: merge updates without overwriting existing data
      await userRef.set({
        'name': name ?? user.displayName ?? doc.data()?['name'] ?? '',
        'photoURL': photoUrl ?? user.photoURL ?? doc.data()?['photoURL'] ?? '',
        'email': user.email ?? doc.data()?['email'] ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // For new users: set initial data
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'name': name ?? user.displayName ?? '',
        'photoURL': photoUrl ?? user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': false,
        'attendedCount': 0,
        'hostedCount': 0,
        // Initialize other fields to null
        'dob': null,
        'gender': null,
        'preference': null,
        'introduction': null,
        'hobbies': null,
      }, SetOptions(merge: true));
    }
  }

  Future<void> signUp({required String email, required String password}) async {
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        await _saveInitialUserData(userCredential.user!);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        throw Exception('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        throw Exception('The account already exists for that email.');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw Exception('No user found for that email.');
      } else if (e.code == 'wrong-password') {
        throw Exception('Wrong password provided for that user.');
      }
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );

      if (userCredential.user != null) {
        await _saveInitialUserData(
          userCredential.user!,
          name: googleUser.displayName,
          photoUrl: googleUser.photoUrl,
        );
      }
    } catch (e) {
      throw Exception("Google Sign-In failed: ${e.toString()}");
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
    } catch (e) {
      throw Exception(e);
    }
  }
}
