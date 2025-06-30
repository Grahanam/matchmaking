part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class SignInRequested extends AuthEvent{
  final String email;
  final String password;

  const SignInRequested(this.email,this.password);
}

class SignUpRequested extends AuthEvent{
  final String email;
  final String password;

  const SignUpRequested(this.email,this.password);
  @override
  List<Object> get props => [email, password];
}

class GoogleSignInRequested extends AuthEvent{}

class CheckProfileStatus extends AuthEvent {}

class SignOutRequested extends AuthEvent{}

// Add this new event class
class NavigateToProfile extends AuthEvent {
  final String userId;
  
  const NavigateToProfile(this.userId);
  
  @override
  List<Object> get props => [userId];
}