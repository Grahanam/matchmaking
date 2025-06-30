part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  
  @override
  List<Object> get props => [];
}

final class Loading extends AuthState {}

final class Authenticated extends AuthState {}

final class UnAuthenticated extends AuthState {}


final class AuthError extends AuthState {
  final String error;

  const AuthError(this.error);

  @override
  List<Object> get props => [error];
}

class ProfileIncomplete extends AuthState {
  final String userId;
  
  const ProfileIncomplete(this.userId);
  
  @override
  List<Object> get props => [userId];
}