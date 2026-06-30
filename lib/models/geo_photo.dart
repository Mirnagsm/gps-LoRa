class GeoPhoto {
  final String id;
  final String farmId;
  final String elementId; // The ID of the point or polygon this photo is attached to
  final String elementType; // 'point' or 'polygon'
  final String localPath;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String syncStatus; // 'pendiente', 'sincronizado', 'error', 'actualizado', 'eliminado'

  GeoPhoto({
    required this.id,
    required this.farmId,
    required this.elementId,
    required this.elementType,
    required this.localPath,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farm_id': farmId,
      'element_id': elementId,
      'element_type': elementType,
      'local_path': localPath,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory GeoPhoto.fromMap(Map<String, dynamic> map) {
    return GeoPhoto(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      elementId: map['element_id'] as String,
      elementType: map['element_type'] as String,
      localPath: map['local_path'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      syncStatus: map['sync_status'] as String,
    );
  }

  GeoPhoto copyWith({
    String? id,
    String? farmId,
    String? elementId,
    String? elementType,
    String? localPath,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    String? syncStatus,
  }) {
    return GeoPhoto(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      elementId: elementId ?? this.elementId,
      elementType: elementType ?? this.elementType,
      localPath: localPath ?? this.localPath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
