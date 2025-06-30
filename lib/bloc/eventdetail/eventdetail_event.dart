part of 'eventdetail_bloc.dart';

sealed class EventdetailEvent extends Equatable {
  const EventdetailEvent();

  @override
  List<Object> get props => [];
}


class LoadEventDetail extends EventdetailEvent{
  final Event event;
  const LoadEventDetail({required this.event});

  @override
  List<Object> get props => [];
}

class CheckInRequested extends EventdetailEvent {
  final Event event;
  const CheckInRequested({required this.event});

  @override
  List<Object> get props => [event];
}

class SubmitAnswers extends EventdetailEvent {
  final Map<String, dynamic> answers;
  const SubmitAnswers({required this.answers});

  @override
  List<Object> get props => [answers];
}

class UpdateMatchStatus extends EventdetailEvent {
  final bool matchesReleased;
  final DocumentSnapshot? matchDoc;
  const UpdateMatchStatus({this.matchesReleased = false, this.matchDoc});

  @override
  List<Object> get props => [matchesReleased, matchDoc ?? 'null'];
}

class EventDetailRefresh extends EventdetailEvent {
  final Event event;
  const EventDetailRefresh({required this.event});

  @override
  List<Object> get props => [event];
}


