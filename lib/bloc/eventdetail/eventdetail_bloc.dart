import 'package:app/models/event.dart';
import 'package:app/models/question.dart';
import 'package:app/services/firestore_service.dart';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'dart:async';

part 'eventdetail_event.dart';
part 'eventdetail_state.dart';

class EventdetailBloc extends Bloc<EventdetailEvent, EventdetailState> {
  final FirestoreService firestoreService;
  final Event event;
  final String userId;

  StreamSubscription? _eventSubscription;
  StreamSubscription? _matchSubscription;


  EventdetailBloc({required this.firestoreService, required this.event, required this.userId}) : super(EventdetailInitial()) {
    on<LoadEventDetail>(_onLoadEventDetail);
    on<CheckInRequested>(_onCheckInRequested);
    on<SubmitAnswers>(_onSubmitAnswers);
    on<UpdateMatchStatus>(_onUpdateMatchStatus);
    on<EventDetailRefresh>(_onRefresh);

    _setupListeners();
  }

  void _setupListeners() {
    _eventSubscription = FirebaseFirestore.instance
        .collection('events')
        .doc(event.id)
        .snapshots()
        .listen((eventDoc) {
      if (eventDoc.exists) {
        final data = eventDoc.data()!;
        add(UpdateMatchStatus(matchesReleased: data['matchesReleased'] ?? false));
      }

       _matchSubscription = FirebaseFirestore.instance
        .collection('event_matches')
        .doc(event.id)
        .collection('matches')
        .doc(userId)
        .snapshots()
        .listen((matchDoc) {
      if (matchDoc.exists) {
        add(UpdateMatchStatus(matchDoc: matchDoc));
      }
    });
    }

  );
  }



    Future<void> _onLoadEventDetail(
    LoadEventDetail event,
    Emitter<EventdetailState> emit,
  ) async {
    emit(EventdetailInitial());
    try {
      final results = await Future.wait([
        firestoreService.getCheckInStatus(eventId: event.event.id, userId: userId),
        firestoreService.getApplicantDocument(event.event.id, userId),
        firestoreService.getMatchDocument(event.event.id, userId),
        firestoreService.getQuestions(event.event.questionnaire),
      ]);

      final checkinData = results[0] as Map<String, dynamic>;
      final applicantDoc = results[1] as DocumentSnapshot;
      final matchDoc = results[2] as DocumentSnapshot;
      final questions = results[3] as List<Question>;

      Map<String, dynamic>? existingAnswers;
      bool hasSubmittedAnswers = false;

      if (applicantDoc.exists) {
        final data = applicantDoc.data() as Map<String, dynamic>?;
        if (data != null && data['answers'] != null) {
          existingAnswers = data['answers'] as Map<String, dynamic>;
          hasSubmittedAnswers = true;
        }
      }

      emit(EventdetailLoaded(
        event: event.event,
        isCheckedIn: checkinData['isCheckedIn'] ?? false,
        checkInTime: checkinData['checkInTime'],
        hasSubmittedAnswers: hasSubmittedAnswers,
        existingAnswers: existingAnswers,
        matchData: matchDoc,
        questions: questions,
        eventHasStarted: DateTime.now().isAfter(event.event.startTime),
      ));
    } catch (e) {
      emit(EventdetailError('Error loading event details: $e'));
    }
  }
     


      Future<void> _onCheckInRequested(
    CheckInRequested event,
    Emitter<EventdetailState> emit,
  ) async {
    try {
      await firestoreService.checkInUser(
        userId: userId,
        eventId: event.event.id,
      );
      add(EventDetailRefresh(event: event.event));
    } catch (e) {
      emit(EventdetailError('Check-in failed: $e'));
    }
  }
     Future<void> _onSubmitAnswers(
    SubmitAnswers event,
    Emitter<EventdetailState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EventdetailLoaded) return;

    try {
      await firestoreService.updateApplicantAnswers(
        currentState.event.id,
        userId,
        event.answers,
      );
      
      emit(currentState.copyWith(
        hasSubmittedAnswers: true,
        existingAnswers: event.answers,
      ));
    } catch (e) {
      emit(EventdetailError('Failed to submit answers: $e'));
    }
  }

  Future<void> _onUpdateMatchStatus(
    UpdateMatchStatus event,
    Emitter<EventdetailState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EventdetailLoaded) return;

    emit(currentState.copyWith(
      matchReleased: event.matchesReleased,
      matchData: event.matchDoc ?? currentState.matchData,
    ));
  }

  Future<void> _onRefresh(
    EventDetailRefresh event,
    Emitter<EventdetailState> emit,
  ) async {
    add(LoadEventDetail(event: event.event));
  }

  @override
  Future<void> close() {
    _eventSubscription?.cancel();
    _matchSubscription?.cancel();
    return super.close();
  }

}
