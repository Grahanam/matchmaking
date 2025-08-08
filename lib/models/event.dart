import 'package:cloud_firestore/cloud_firestore.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final GeoPoint location;
  final DateTime startTime;
  final DateTime endTime;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String matchingType;
  final String guestType;
  final String locationType;
  final int guestCount;
  final String city;  
  final String state;
  final List<String> cityKeywords; 

  final List<String> questionnaire;
  final int applicationCount;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.matchingType,
    required this.guestType,
    required this.locationType,
    required this.city,
    required this.state,
    required this.cityKeywords,
    required this.guestCount,
    required this.questionnaire,
    required this.applicationCount,
  });

  factory Event.fromDocumentSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? GeoPoint(0, 0),
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      matchingType: data['matchingType'] ?? 'platonic',
      guestType: data['guestType'] ?? 'friends',
      locationType: data['locationType'] ?? 'home',
      city: data['city'] ?? '',
      state: data['state'] ?? '',
      cityKeywords: List<String>.from(data['cityKeywords'] ?? []),
      guestCount: data['guestCount'] ?? 0,
      questionnaire: List<String>.from(data['questionnaire'] ?? []),
      applicationCount: data['applicationCount'] ?? 0,
    );
  }

  Event copyWith({int? applicationCount}) {
    return Event(
      id: id,
      title: title,
      description: description,
      location: location,
      startTime: startTime,
      endTime: endTime,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      matchingType: matchingType,
      guestType: guestType,
      locationType: locationType,
      guestCount: guestCount,
      city:city,
      state:state,
      cityKeywords: cityKeywords,
      questionnaire: questionnaire,
      applicationCount: applicationCount ?? this.applicationCount,
    );
  }

  factory Event.fromMap(Map<String, dynamic> data) {
  return Event(
    id: data['id'] ?? '',
    title: data['title'] ?? '',
    description: data['description'] ?? '',
    location: data['location'] ?? GeoPoint(0, 0),
    startTime: (data['startTime'] as Timestamp).toDate(),
    endTime: (data['endTime'] as Timestamp).toDate(),
    createdBy: data['createdBy'] ?? '',
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    matchingType: data['matchingType'] ?? 'platonic',
    guestType: data['guestType'] ?? 'friends',
    city: data['city'] ?? '',
    state: data['state'] ?? '',
    cityKeywords: List<String>.from(data['cityKeywords'] ?? []),
    locationType: data['locationType'] ?? 'home',
    guestCount: data['guestCount'] ?? 0,
    questionnaire: List<String>.from(data['questionnaire'] ?? []),
    applicationCount: data['applicationCount'] ?? 0,
  );
}

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'matchingType': matchingType,
      'guestType': guestType,
      'locationType': locationType,
      'guestCount': guestCount,
      'questionnaire': questionnaire,
      'applicationCount': applicationCount,
      'city':city,
      'state':state,
      'cityKeywords': cityKeywords,
    };
  }
}