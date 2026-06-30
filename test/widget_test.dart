import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:campomap_offline/models/farm.dart';
import 'package:campomap_offline/models/map_point.dart';
import 'package:campomap_offline/models/map_polygon.dart';
import 'package:campomap_offline/services/export_service.dart';
import 'package:campomap_offline/services/gis_helper.dart';
import 'dart:convert';

void main() {
  group('CampoMap Offline Unit Tests', () {
    test('Farm model toMap and fromMap serialization matches', () {
      final now = DateTime.now();
      final farm = Farm(
        id: 'farm-123',
        name: 'El Potrero',
        ownerName: 'Carlos Gómez',
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final map = farm.toMap();
      expect(map['id'], 'farm-123');
      expect(map['name'], 'El Potrero');
      expect(map['owner_name'], 'Carlos Gómez');
      expect(map['sync_status'], 'pendiente');

      final deserialized = Farm.fromMap(map);
      expect(deserialized.id, farm.id);
      expect(deserialized.name, farm.name);
      expect(deserialized.ownerName, farm.ownerName);
      expect(deserialized.createdAt.toIso8601String(), farm.createdAt.toIso8601String());
      expect(deserialized.syncStatus, farm.syncStatus);
    });

    test('MapPoint model serialization matches', () {
      final now = DateTime.now();
      final point = MapPoint(
        id: 'PTO-001',
        farmId: 'farm-123',
        type: 'pozo',
        name: 'Pozo Principal',
        description: 'Pozo de agua dulce',
        latitude: 4.7110,
        longitude: -74.0721,
        photoPath: '/path/to/photo.jpg',
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final map = point.toMap();
      expect(map['id'], 'PTO-001');
      expect(map['latitude'], 4.7110);
      expect(map['longitude'], -74.0721);
      expect(map['photo_path'], '/path/to/photo.jpg');

      final deserialized = MapPoint.fromMap(map);
      expect(deserialized.id, point.id);
      expect(deserialized.latitude, point.latitude);
      expect(deserialized.longitude, point.longitude);
      expect(deserialized.photoPath, point.photoPath);
    });

    test('ExportService correctly formats features into GeoJSON [lng, lat] format', () {
      final now = DateTime.now();
      final point = MapPoint(
        id: 'PTO-001',
        farmId: 'farm-123',
        type: 'pozo',
        name: 'Pozo Principal',
        description: 'Pozo de agua dulce',
        latitude: 4.7110,  // Lat
        longitude: -74.0721, // Lng
        photoPath: '/path/to/photo.jpg',
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final polygon = MapPolygon(
        id: 'PAR-001',
        farmId: 'farm-123',
        type: 'parcela',
        name: 'Parcela Norte',
        description: 'Maíz',
        areaHectares: 1.5,
        coordinates: [
          LatLng(4.7110, -74.0721),
          LatLng(4.7120, -74.0721),
          LatLng(4.7120, -74.0710),
          LatLng(4.7110, -74.0721), // closed ring
        ],
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final geoJsonStr = ExportService.instance.exportToGeoJson([point], [polygon]);
      final geoJson = jsonDecode(geoJsonStr) as Map<String, dynamic>;

      expect(geoJson['type'], 'FeatureCollection');
      final features = geoJson['features'] as List<dynamic>;
      expect(features.length, 2);

      // Verify Point GeoJSON Geometry (ordered as [longitude, latitude])
      final pointFeature = features.firstWhere((f) => f['properties']['id'] == 'PTO-001');
      expect(pointFeature['geometry']['type'], 'Point');
      final pointCoords = pointFeature['geometry']['coordinates'] as List<dynamic>;
      expect(pointCoords[0], -74.0721); // Lng
      expect(pointCoords[1], 4.7110);  // Lat

      // Verify Polygon GeoJSON Geometry
      final polyFeature = features.firstWhere((f) => f['properties']['id'] == 'PAR-001');
      expect(polyFeature['geometry']['type'], 'Polygon');
      final polyRings = polyFeature['geometry']['coordinates'] as List<dynamic>;
      expect(polyRings.length, 1); // outer ring
      final polyCoords = polyRings[0] as List<dynamic>;
      expect(polyCoords.length, 4); // 4 points
      expect(polyCoords[0][0], -74.0721); // Lng
      expect(polyCoords[0][1], 4.7110);  // Lat
    });

    test('GisHelper area calculation works accurately', () {
      // 0.001 degrees at Equator (lat = 0) is approx 111.3199 meters.
      // Square of 0.001 x 0.001 degrees should be approx 12,392 m² = 1.2392 Hectares.
      final points = [
        LatLng(0.0, 0.0),
        LatLng(0.001, 0.0),
        LatLng(0.001, 0.001),
        LatLng(0.0, 0.001),
      ];

      final area = GisHelper.calculateAreaInHectares(points);
      // Expect approx 1.2392 hectares, within 1% tolerance
      expect(area, closeTo(1.2392, 0.01));
    });

    test('ExportService formats features into KML correctly', () {
      final now = DateTime.now();
      final point = MapPoint(
        id: 'PTO-001',
        farmId: 'farm-123',
        type: 'pozo',
        name: 'Pozo Principal',
        description: 'Pozo de agua dulce',
        latitude: 4.7110,
        longitude: -74.0721,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final polygon = MapPolygon(
        id: 'PAR-001',
        farmId: 'farm-123',
        type: 'parcela',
        name: 'Parcela Norte',
        description: 'Maíz',
        areaHectares: 1.5,
        coordinates: [
          LatLng(4.7110, -74.0721),
          LatLng(4.7120, -74.0721),
          LatLng(4.7120, -74.0710),
        ],
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendiente',
      );

      final kmlStr = ExportService.instance.exportToKml('Finca Ejemplo', [point], [polygon]);
      
      // Basic XML structure checks
      expect(kmlStr, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(kmlStr, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
      expect(kmlStr, contains('<Placemark>'));
      expect(kmlStr, contains('<Point>'));
      expect(kmlStr, contains('<Polygon>'));
      expect(kmlStr, contains('<coordinates>'));
      expect(kmlStr, contains('-74.0721,4.711,0')); // Coordinate print formats
    });
  });
}
