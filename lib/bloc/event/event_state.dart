part of 'event_bloc.dart';

sealed class EventState extends Equatable {
  const EventState();
  
  @override
  List<Object?> get props => [];
}

//create Event
class EventInitial extends EventState {}

class EventSubmitting extends EventState {}

class EventSuccess extends EventState {}

class EventFailure extends EventState {
  final String error;

  const EventFailure(this.error);

  @override
  List<Object?> get props => [error];
}

// Get Nearby Event
class EventLoading extends EventState {}



// Update Event 
class EventUpdating extends EventState {}

// Delete Event
class EventDeleting extends EventState {}

class EventDetailLoading extends EventState {}
class EventDetailLoaded extends EventState {
  final Event eventData;
  final List<Map<String, dynamic>> applicants;
  const EventDetailLoaded({required this.eventData, required this.applicants});
}
class EventDetailError extends EventState {
  final String error;
  const EventDetailError(this.error);
}

class EventWithApplicantsLoaded extends EventState {
  final Event event;
  final List<Map<String, dynamic>> applicants;
  final bool showQRCode;


  const EventWithApplicantsLoaded({
    required this.event,
    required this.applicants,
    this.showQRCode = false,
  });

  @override
  List<Object> get props => [event, applicants,showQRCode];
}


