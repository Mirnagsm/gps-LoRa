class Animal {
  final String id;
  final String farmId;
  final String name;
  final String details;
  final String caretaker;
  final String? allowedPolygonId; // Can contain comma-separated list of polygon IDs
  final double? lastLatitude;
  final double? lastLongitude;
  final String status; // 'dentro', 'fuera'
  final String syncStatus; // 'pendiente', 'sincronizado'
  final String species; // 'caballo', 'perro', 'gato', 'vaca/toro', 'ovejo'

  Animal({
    required this.id,
    required this.farmId,
    required this.name,
    required this.details,
    required this.caretaker,
    this.allowedPolygonId,
    this.lastLatitude,
    this.lastLongitude,
    required this.status,
    required this.syncStatus,
    required this.species,
  });

  /// Helper getter to retrieve list of all allowed geofence polygon IDs
  List<String> get allowedPolygonIds {
    if (allowedPolygonId == null || allowedPolygonId!.trim().isEmpty) return [];
    return allowedPolygonId!.split(',').where((id) => id.isNotEmpty).toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farm_id': farmId,
      'name': name,
      'details': details,
      'caretaker': caretaker,
      'allowed_polygon_id': allowedPolygonId,
      'last_latitude': lastLatitude,
      'last_longitude': lastLongitude,
      'status': status,
      'sync_status': syncStatus,
      'species': species,
    };
  }

  factory Animal.fromMap(Map<String, dynamic> map) {
    return Animal(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      name: map['name'] as String,
      details: map['details'] as String,
      caretaker: map['caretaker'] as String,
      allowedPolygonId: map['allowed_polygon_id'] as String?,
      lastLatitude: map['last_latitude'] != null ? (map['last_latitude'] as num).toDouble() : null,
      lastLongitude: map['last_longitude'] != null ? (map['last_longitude'] as num).toDouble() : null,
      status: map['status'] as String? ?? 'dentro',
      syncStatus: map['sync_status'] as String? ?? 'pendiente',
      species: map['species'] as String? ?? 'vaca/toro',
    );
  }

  Animal copyWith({
    String? id,
    String? farmId,
    String? name,
    String? details,
    String? caretaker,
    String? allowedPolygonId,
    double? lastLatitude,
    double? lastLongitude,
    String? status,
    String? syncStatus,
    String? species,
  }) {
    return Animal(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      name: name ?? this.name,
      details: details ?? this.details,
      caretaker: caretaker ?? this.caretaker,
      allowedPolygonId: allowedPolygonId ?? this.allowedPolygonId,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      species: species ?? this.species,
    );
  }
}
