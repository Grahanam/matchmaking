import 'package:app/services/auth_repo.dart';
import 'package:app/services/firestore_service.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepo;
  final FirestoreService firestoreService;

  AuthBloc(this.authRepo, this.firestoreService) : super(UnAuthenticated()) {
    on<SignUpRequested>(_signUpRequested);
    on<SignInRequested>(_signInRequested);
    on<GoogleSignInRequested>(_googleSignInRequested);
    on<SignOutRequested>(_signOutRequested);
    on<CheckProfileStatus>(_checkProfileStatus);
    on<NavigateToProfile>(_navigateToProfile);
  }


Future<void> _navigateToProfile(
    NavigateToProfile event,
    Emitter<AuthState> emit,
  ) async {
    emit(ProfileIncomplete(event.userId));
  }

  // Future<void> _signUpRequested(
  //   SignUpRequested event,
  //   Emitter<AuthState> emit,
  // ) async {
  //   emit(Loading());
  //   try {
  //     await authRepo.signUp(
  //       email: event.email,
  //       password: event.password
  //     );
  //     final user = FirebaseAuth.instance.currentUser;
  //     if (user != null) {
  //       // Immediately navigate to profile completion
  //       add(NavigateToProfile(user.uid));
  //     }
  //   } catch (e) {
  //     emit(AuthError(e.toString()));
  //     emit(UnAuthenticated());
  //   }
  // }

  // Update other methods similarly
//   Future<void> _googleSignInRequested(
//     GoogleSignInRequested event,
//     Emitter<AuthState> emit,
//   ) async {
//     emit(Loading());
//     try {
//       await authRepo.signInWithGoogle();
//       final user = FirebaseAuth.instance.currentUser;
//       if (user != null) {
//         // Immediately navigate to profile completion
//         add(NavigateToProfile(user.uid));
//       }
//     } catch (e) {
//       emit(AuthError(e.toString()));
//       emit(UnAuthenticated());
//     }
//   }
// }
  Future<void> _checkProfileStatus(
    CheckProfileStatus event,
    Emitter<AuthState> emit,
  ) async {
    emit(Loading());
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return emit(UnAuthenticated());

      final profileComplete = await firestoreService.isProfileComplete(
        user.uid,
      );

      if (profileComplete) {
        emit(Authenticated());
      } else {
        emit(ProfileIncomplete(user.uid));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
      emit(UnAuthenticated());
    }
  }

  Future<void> _signUpRequested(
    SignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(Loading());
    try {
      await authRepo.signUp(email: event.email, password: event.password);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Immediately navigate to profile completion
        emit(Authenticated());
      }
      // if (user != null) {
      //   final profileComplete = await firestoreService.isProfileComplete(
      //     user.uid,
      //   );
      //   if (profileComplete) {
      //     emit(Authenticated());
      //   } else {
      //     emit(ProfileIncomplete(user.uid));
      //   }
      // }
      // emit(Authenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
      emit(UnAuthenticated());
    }
  }

  Future<void> _signInRequested(
    SignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(Loading());
    try {
      await authRepo.signIn(email: event.email, password: event.password);
      final user = FirebaseAuth.instance.currentUser;
      // if (user != null) {
      //   final profileComplete = await firestoreService.isProfileComplete(
      //     user.uid,
      //   );
      //   if (profileComplete) {
      //     emit(Authenticated());
      //   } else {
      //     emit(ProfileIncomplete(user.uid));
      //   }
      // }
      // add(CheckProfileStatus());
      // emit(Authenticated());
       if (user != null) {
      emit(Authenticated());
    } else {
      emit(AuthError('Wrong credentials'));
      emit(UnAuthenticated());
    }
    } catch (e) {
      emit(AuthError(e.toString()));
      emit(UnAuthenticated());
    }
  }

  Future<void> _googleSignInRequested(
    GoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(Loading());
    try {
      await authRepo.signInWithGoogle();
      final user = FirebaseAuth.instance.currentUser;
      // if (user != null) {
      //   final profileComplete = await firestoreService.isProfileComplete(
      //     user.uid,
      //   );
      //   if (profileComplete) {
      //     emit(Authenticated());
      //   } else {
      //     emit(ProfileIncomplete(user.uid));
      //   }
      // }

      // add(CheckProfileStatus());
      emit(Authenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
      emit(UnAuthenticated());
    }
  }

  Future<void> _signOutRequested(
    SignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(Loading());
    await authRepo.signOut();
    emit(UnAuthenticated());
  }
}
