part of 'applicant_bloc.dart';

sealed class ApplicantState extends Equatable {
  const ApplicantState();
  
  @override
  List<Object> get props => [];
}

final class ApplicantInitial extends ApplicantState {}
