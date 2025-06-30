import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'applicant_event.dart';
part 'applicant_state.dart';

class ApplicantBloc extends Bloc<ApplicantEvent, ApplicantState> {
  ApplicantBloc() : super(ApplicantInitial()) {
    on<ApplicantEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
