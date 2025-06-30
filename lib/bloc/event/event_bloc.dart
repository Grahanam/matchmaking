import 'package:app/models/event.dart';
import 'package:app/services/firestore_service.dart';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

part 'event_event.dart';
part 'event_state.dart';

class EventBloc extends Bloc<EventEvent, EventState> {
  EventBloc() : super(EventInitial()) {
    on<SubmitEvent>(_onSubmit);
    on<FetchNearbyEvents>(_onFetchNearbyEvents);
    on<FetchYourEvents>(_onFetchYourEvents);
    on<UpdateEvent>(_onUpdateEvent);
    on<DeleteEvent>(_onDeleteEvent);
    on<FetchEventDetail>(_onFetchEventDetail);
    on<UpdateApplicantStatus>(_onUpdateApplicantStatus);
    on<FetchEventWithApplicants>(_onFetchEventWithApplicants);
    on<ToggleQRCodeVisibility>(_onToggleQRCodeVisibility);
    on<ResetEventState>(_onResetEventState);
  }


   Future<void> _onSubmit(SubmitEvent event, Emitter<EventState> emit) async {
    emit(EventSubmitting());
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("User not logged in");

      final eventData = {
        ...event.eventData,
        'createdBy': currentUser.uid,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      await FirebaseFirestore.instance.collection('events').add(eventData);

      emit(EventSuccess());
    } catch (e) {
      emit(EventFailure(e.toString()));
    }
  }

  // Add this new handler method
  void _onResetEventState(ResetEventState event, Emitter<EventState> emit) {
    emit(EventInitial());
  }

  void _onToggleQRCodeVisibility(
  ToggleQRCodeVisibility event, Emitter<EventState> emit
) {
  if (state is EventWithApplicantsLoaded) {
    final current = state as EventWithApplicantsLoaded;
    emit(EventWithApplicantsLoaded(
      event: current.event,
      applicants: current.applicants,
      showQRCode: event.show,
    ));
  }
}

  Future<void> _onFetchNearbyEvents(FetchNearbyEvents event, Emitter<EventState> emit) async {
    emit(EventLoading());
    try {
      final position = await Geolocator.getCurrentPosition();
      final events = await FirestoreService().getNearbyEvents(
        position.latitude,
        position.longitude,
        radiusInKm: event.radiusInKm,
      );
     
      emit(NearbyEventLoaded(events: events, position: position));
    } catch (e) {
      emit(EventFailure(e.toString()));
    }
  }

  Future<void> _onFetchYourEvents(FetchYourEvents event, Emitter<EventState> emit) async {
    emit(EventLoading());
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
    final events = await FirestoreService().getEventsByCreator(userId);
    
    emit(YourEventsLoaded(events:events));
    } catch (e) {
      emit(EventFailure(e.toString()));
    }
  }

  

  Future<void> _onUpdateEvent(UpdateEvent event, Emitter<EventState> emit) async {
    emit(EventUpdating());
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.eventId)
          .update(event.updatedData);
      emit(EventSuccess());
    } catch (e) {
      emit(EventFailure(e.toString()));
    }
  }

  Future<void> _onDeleteEvent(DeleteEvent event, Emitter<EventState> emit) async {
    emit(EventDeleting());
    try {
      await FirebaseFirestore.instance.collection('events').doc(event.eventId).delete();
      emit(EventSuccess());
    } catch (e) {
      emit(EventFailure(e.toString()));
    }
  }

  Future<void> _onFetchEventDetail(FetchEventDetail event, Emitter<EventState> emit) async {
  emit(EventDetailLoading());
  try {
    final detail = await FirestoreService().getEventWithApplicants(event.eventId);
    emit(EventDetailLoaded(eventData: detail['event'], applicants: detail['applicants']));
  } catch (e) {
    emit(EventDetailError(e.toString()));
  }
}

Future<void> _onUpdateApplicantStatus(
  UpdateApplicantStatus event,
  Emitter<EventState> emit,
) async {
  try {
    await FirestoreService().updateApplicantStatus(
      event.eventId,
      event.userId,
      event.newStatus,
    );

    // After status update, re-fetch the event with applicants
    add(FetchEventWithApplicants(event.eventId));
  } catch (e) {
    emit(EventFailure("Failed to update status: $e"));
  }
}

Future<void> _onFetchEventWithApplicants(
  FetchEventWithApplicants event,
  Emitter<EventState> emit,
) async {
  emit(EventLoading());
  try {
    final docSnap = await FirebaseFirestore.instance.collection('events').doc(event.eventId).get();
    final applicantsSnap = await FirebaseFirestore.instance.collection('events').doc(event.eventId).collection('applicants').get();

    final eventData = Event.fromDocumentSnapshot(docSnap);
    final applicants = applicantsSnap.docs.map((e) {
      final data = e.data();
      data['id'] = e.id;
      return data;
    }).toList();

    emit(EventWithApplicantsLoaded(event: eventData, applicants: applicants));
  } catch (e) {
    emit(EventFailure(e.toString()));
  }
}



}

