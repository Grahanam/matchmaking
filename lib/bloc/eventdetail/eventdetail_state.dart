part of 'eventdetail_bloc.dart';

sealed class EventdetailState extends Equatable {
  const EventdetailState();

}

final class EventdetailInitial extends EventdetailState {
  @override
  List<Object> get props => [];
}


class EventdetailLoaded extends EventdetailState{
  final Event event;
  final bool isCheckedIn;
  final DateTime? checkInTime;
  final bool hasSubmittedAnswers;
  final Map<String, dynamic>? existingAnswers;
  final DocumentSnapshot? matchData;
  final List<Question> questions;
  final bool eventHasStarted;
  final bool matchReleased;

  const EventdetailLoaded({
    required this.event,
    required this.isCheckedIn,
    this.checkInTime,
    required this.hasSubmittedAnswers,
    this.existingAnswers,
    this.matchData,
    required this.questions,
    required this.eventHasStarted,
    this.matchReleased = false,
  });

  EventdetailLoaded copyWith({
    bool? isCheckedIn,
    DateTime? checkInTime,
    bool? hasSubmittedAnswers,
    Map<String, dynamic>? existingAnswers,
    DocumentSnapshot? matchData,
    List<Question>? questions,
    bool? eventHasStarted,
    bool? matchReleased,
  }) {
    return EventdetailLoaded(
      event: event,
      isCheckedIn: isCheckedIn ?? this.isCheckedIn,
      checkInTime: checkInTime ?? this.checkInTime,
      hasSubmittedAnswers: hasSubmittedAnswers ?? this.hasSubmittedAnswers,
      existingAnswers: existingAnswers ?? this.existingAnswers,
      matchData: matchData ?? this.matchData,
      questions: questions ?? this.questions,
      eventHasStarted: eventHasStarted ?? this.eventHasStarted,
      matchReleased: matchReleased ?? this.matchReleased,
    );
  }

   @override
  List<Object?> get props => [
        event,
        isCheckedIn,
        checkInTime,
        hasSubmittedAnswers,
        existingAnswers,
        matchData,
        questions,
        eventHasStarted,
        matchReleased,
      ];
}

class EventdetailError extends EventdetailState {
  final String message;
  const EventdetailError(this.message);

  @override
  List<Object> get props => [message];
}
