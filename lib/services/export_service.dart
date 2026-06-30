import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/map_point.dart';
import '../models/map_polygon.dart';

class ExportService {
  static final ExportService instance = ExportService._init();

  ExportService._init();

  /// Converts lists of MapPoints and MapPolygons to a GeoJSON string.
  String exportToGeoJson(List<MapPoint> points, List<MapPolygon> polygons) {
    final List<Map<String, dynamic>> features = [];

    // 1. Export Points
    for (final point in points) {
      features.add({
        'type': 'Feature',
        'properties': {
          'id': point.id,
          'farm_id': point.farmId,
          'type': point.type,
          'name': point.name,
          'description': point.description,
          'photo_path': point.photoPath,
          'created_at': point.createdAt.toIso8601String(),
          'sync_status': point.syncStatus,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude], // GeoJSON is [lng, lat]
        },
      });
    }

    // 2. Export Polygons
    for (final polygon in polygons) {
      if (polygon.coordinates.isEmpty) continue;

      // Close the polygon ring if it is not already closed
      final coords = List<List<double>>.from(
        polygon.coordinates.map((latLng) => [latLng.longitude, latLng.latitude])
      );
      
      if (coords.first[0] != coords.last[0] || coords.first[1] != coords.last[1]) {
        coords.add(coords.first);
      }

      features.add({
        'type': 'Feature',
        'properties': {
          'id': polygon.id,
          'farm_id': polygon.farmId,
          'type': polygon.type,
          'name': polygon.name,
          'description': polygon.description,
          'area_hectares': polygon.areaHectares,
          'created_at': polygon.createdAt.toIso8601String(),
          'sync_status': polygon.syncStatus,
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coords], // List of rings
        },
      });
    }

    final geoJsonMap = {
      'type': 'FeatureCollection',
      'features': features,
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(geoJsonMap);
  }

  /// Converts lists of MapPoints and MapPolygons to a KML XML string.
  String exportToKml(String farmName, List<MapPoint> points, List<MapPolygon> polygons) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('  <Document>');
    buffer.writeln('    <name>$farmName</name>');
    buffer.writeln('    <description>Exportación de CampoMap Offline para finca $farmName</description>');
    
    // 1. Export Points
    for (final point in points) {
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>${point.name}</name>');
      buffer.writeln('      <description><![CDATA[Tipo: ${point.type}<br>Detalles: ${point.description}]]></description>');
      buffer.writeln('      <Point>');
      buffer.writeln('        <coordinates>${point.longitude},${point.latitude},0</coordinates>');
      buffer.writeln('      </Point>');
      buffer.writeln('    </Placemark>');
    }
    
    // 2. Export Polygons (Parcels)
    for (final polygon in polygons) {
      if (polygon.coordinates.isEmpty) continue;
      
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>${polygon.name}</name>');
      buffer.writeln('      <description><![CDATA[Uso: ${polygon.type}<br>Área: ${polygon.areaHectares.toStringAsFixed(4)} Ha<br>Detalles: ${polygon.description}]]></description>');
      buffer.writeln('      <Polygon>');
      buffer.writeln('        <outerBoundaryIs>');
      buffer.writeln('          <LinearRing>');
      buffer.writeln('            <coordinates>');
      
      for (final coord in polygon.coordinates) {
        buffer.writeln('              ${coord.longitude},${coord.latitude},0');
      }
      
      // Close the KML ring if it is not already closed
      final first = polygon.coordinates.first;
      final last = polygon.coordinates.last;
      if (first.latitude != last.latitude || first.longitude != last.longitude) {
        buffer.writeln('              ${first.longitude},${first.latitude},0');
      }
      
      buffer.writeln('            </coordinates>');
      buffer.writeln('          </LinearRing>');
      buffer.writeln('        </outerBoundaryIs>');
      buffer.writeln('      </Polygon>');
      buffer.writeln('    </Placemark>');
    }
    
    buffer.writeln('  </Document>');
    buffer.writeln('</kml>');
    
    return buffer.toString();
  }

  /// Saves the GeoJSON locally and launches the native share sheet.
  /// On web, it returns the content directly or triggers a download.
  Future<void> shareGeoJson(
    String farmName,
    List<MapPoint> points,
    List<MapPolygon> polygons,
  ) async {
    final geoJsonString = exportToGeoJson(points, polygons);
    final fileName = '${farmName.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_')}_geojson.json';

    if (kIsWeb) {
      print('=== GEOJSON EXPORT ===\n$geoJsonString\n======================');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(geoJsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Exportación de datos de la finca $farmName',
        subject: 'GeoJSON de $farmName',
      );
    } catch (e) {
      print('Error exporting and sharing GeoJSON: $e');
    }
  }

  /// Saves the KML locally and launches the native share sheet.
  Future<void> shareKml(
    String farmName,
    List<MapPoint> points,
    List<MapPolygon> polygons,
  ) async {
    final kmlString = exportToKml(farmName, points, polygons);
    final fileName = '${farmName.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_')}_kml.kml';

    if (kIsWeb) {
      print('=== KML EXPORT ===\n$kmlString\n==================');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(kmlString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Exportación de datos KML de la finca $farmName',
        subject: 'KML de $farmName',
      );
    } catch (e) {
      print('Error exporting and sharing KML: $e');
    }
  }
}
