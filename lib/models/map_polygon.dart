import 'dart:convert';
import 'package:latlong2/latlong.dart';

class MapPolygon {
  final String id;
  final String farmId;
  final String type; // 'parcela', 'lindero', 'zona_inundable', 'potrero', 'corral', etc.
  final String name;
  final String description;
  final double areaHectares;
  final List<LatLng> coordinates;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // 'pendiente', 'sincronizado', 'error', 'actualizado', 'eliminado'

  MapPolygon({
    required this.id,
    required this.farmId,
    required this.type,
    required this.name,
    required this.description,
    required this.areaHectares,
    required this.coordinates,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    final coordinatesList = coordinates.map((latLng) => [latLng.latitude, latLng.longitude]).toList();
    return {
      'id': id,
      'farm_id': farmId,
      'type': type,
      'name': name,
      'description': description,
      'area_hectares': areaHectares,
      'coordinates_json': jsonEncode(coordinatesList),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory MapPolygon.fromMap(Map<String, dynamic> map) {
    final coordinatesJson = map['coordinates_json'] as String;
    final List<dynamic> decodedList = jsonDecode(coordinatesJson) as List<dynamic>;
    final coordinates = decodedList.map((item) {
      final List<dynamic> point = item as List<dynamic>;
      return LatLng(
        (point[0] as num).toDouble(),
        (point[1] as num).toDouble(),
      );
    }).toList();

    return MapPolygon(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      type: map['type'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      areaHectares: (map['area_hectares'] as num).toDouble(),
      coordinates: coordinates,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncStatus: map['sync_status'] as String,
    );
  }

  MapPolygon copyWith({
    String? id,
    String? farmId,
    String? type,
    String? name,
    String? description,
    double? areaHectares,
    List<LatLng>? coordinates,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return MapPolygon(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      areaHectares: areaHectares ?? this.areaHectares,
      coordinates: coordinates ?? this.coordinates,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
