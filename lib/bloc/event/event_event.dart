part of 'event_bloc.dart';

sealed class EventEvent extends Equatable {
  const EventEvent();

  @override
  List<Object?> get props => [];
}

class SubmitEvent extends EventEvent {
  final Map<String, dynamic> eventData;

  const SubmitEvent({required this.eventData});

  @override
  List<Object?> get props => [eventData];
}

class FetchNearbyEvents extends EventEvent {
  final double latitude;
  final double longitude;
  final double radiusInKm;
  final String? city;   
  const FetchNearbyEvents({required this.latitude,
    required this.longitude,required this.radiusInKm,this.city});
  @override
  List<Object?> get props => [latitude,longitude,radiusInKm,city];
}

class FetchYourEvents extends EventEvent{

}

// Add these to your EventState
class NearbyEventLoading extends EventState {}
class NearbyEventLoaded extends EventState {
  final List<Event> events;
  // final Position position;
  
  // const NearbyEventLoaded({required this.events, required this.position});
  const NearbyEventLoaded({required this.events});
  
  @override
  // List<Object> get props => [events, position];
  List<Object> get props => [events];
}

class YourEventsLoaded extends EventState{
  final List<Event> events;

  const YourEventsLoaded({required this.events});
}

class UpdateEvent extends EventEvent {
  final String eventId;
  final Map<String, dynamic> updatedData;
  const UpdateEvent({required this.eventId, required this.updatedData});
  @override
  List<Object?> get props => [eventId, updatedData];
}


class DeleteEvent extends EventEvent {
  final String eventId;
  const DeleteEvent({required this.eventId});
  @override
  List<Object?> get props => [eventId];
}

class FetchEventWithApplicants extends EventEvent {
  final String eventId;
  const FetchEventWithApplicants(this.eventId);

  @override
  List<Object> get props => [eventId];
}

class FetchEventDetail extends EventEvent {
  final String eventId;
  const FetchEventDetail(this.eventId);
}

class UpdateApplicantStatus extends EventEvent {
  final String eventId;
  final String userId;
  final String newStatus;

  const UpdateApplicantStatus({
    required this.eventId,
    required this.userId,
    required this.newStatus,
  });

  @override
  List<Object> get props => [eventId, userId, newStatus];
}

class ToggleQRCodeVisibility extends EventEvent {
  final bool show;
  const ToggleQRCodeVisibility({required this.show});
}

class ResetEventState extends EventEvent {}