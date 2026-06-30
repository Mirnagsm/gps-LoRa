class AnimalAlert {
  final String id;
  final String animalId;
  final String animalName;
  final String animalDetails;
  final String caretaker;
  final double violationLatitude;
  final double violationLongitude;
  final DateTime timestamp;
  final String syncStatus;

  AnimalAlert({
    required this.id,
    required this.animalId,
    required this.animalName,
    required this.animalDetails,
    required this.caretaker,
    required this.violationLatitude,
    required this.violationLongitude,
    required this.timestamp,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'animal_id': animalId,
      'animal_name': animalName,
      'animal_details': animalDetails,
      'caretaker': caretaker,
      'violation_latitude': violationLatitude,
      'violation_longitude': violationLongitude,
      'timestamp': timestamp.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory AnimalAlert.fromMap(Map<String, dynamic> map) {
    return AnimalAlert(
      id: map['id'] as String,
      animalId: map['animal_id'] as String,
      animalName: map['animal_name'] as String,
      animalDetails: map['animal_details'] as String,
      caretaker: map['caretaker'] as String,
      violationLatitude: (map['violation_latitude'] as num).toDouble(),
      violationLongitude: (map['violation_longitude'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      syncStatus: map['sync_status'] as String? ?? 'pendiente',
    );
  }

  AnimalAlert copyWith({
    String? id,
    String? animalId,
    String? animalName,
    String? animalDetails,
    String? caretaker,
    double? violationLatitude,
    double? violationLongitude,
    DateTime? timestamp,
    String? syncStatus,
  }) {
    return AnimalAlert(
      id: id ?? this.id,
      animalId: animalId ?? this.animalId,
      animalName: animalName ?? this.animalName,
      animalDetails: animalDetails ?? this.animalDetails,
      caretaker: caretaker ?? this.caretaker,
      violationLatitude: violationLatitude ?? this.violationLatitude,
      violationLongitude: violationLongitude ?? this.violationLongitude,
      timestamp: timestamp ?? this.timestamp,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
