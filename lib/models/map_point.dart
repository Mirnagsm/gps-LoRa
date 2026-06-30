class MapPoint {
  final String id;
  final String farmId;
  final String type; // 'pozo', 'cerca', 'corral', 'portón', 'árbol', etc.
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // 'pendiente', 'sincronizado', 'error', 'actualizado', 'eliminado'

  MapPoint({
    required this.id,
    required this.farmId,
    required this.type,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farm_id': farmId,
      'type': type,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory MapPoint.fromMap(Map<String, dynamic> map) {
    return MapPoint(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      type: map['type'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      photoPath: map['photo_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncStatus: map['sync_status'] as String,
    );
  }

  MapPoint copyWith({
    String? id,
    String? farmId,
    String? type,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    String? photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return MapPoint(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
