import 'dart:math' show cos, pi;
import 'package:latlong2/latlong.dart';

class GisHelper {
  /// Calculates the area of a polygon in Hectares using a local Cartesian projection.
  /// This sinusoildal tangent plane projection is highly accurate for typical farm-sized areas.
  static double calculateAreaInHectares(List<LatLng> points) {
    if (points.length < 3) return 0.0;

    // 1. Calculate centroid to use as local origin (projection reference)
    double sumLat = 0.0;
    double sumLng = 0.0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    final double lat0 = sumLat / points.length;
    final double lon0 = sumLng / points.length;

    // 2. Project points to local meter offset (x, y) relative to origin
    // 111,319.9 meters is the approximate distance of one degree of latitude.
    const double metersPerDegree = 111319.9;
    final double radLat = lat0 * pi / 180.0;
    final double cosLat = cos(radLat);

    final List<_LocalPoint> projected = points.map((p) {
      final double y = (p.latitude - lat0) * metersPerDegree;
      final double x = (p.longitude - lon0) * metersPerDegree * cosLat;
      return _LocalPoint(x, y);
    }).toList();

    // 3. Apply the Shoelace Formula
    double area = 0.0;
    int j = projected.length - 1;
    for (int i = 0; i < projected.length; i++) {
      area += (projected[j].x + projected[i].x) * (projected[j].y - projected[i].y);
      j = i;
    }

    // Convert absolute area in square meters to hectares (1 Ha = 10,000 sq m)
    final double areaSquareMeters = area.abs() / 2.0;
    return areaSquareMeters / 10000.0;
  }

  /// Calculates the geometric center (centroid) of a polygon.
  static LatLng getCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0.0, 0.0);
    double sumLat = 0.0;
    double sumLng = 0.0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  /// Checks if a point is inside a polygon using the Ray-Casting algorithm.
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    double x = point.longitude;
    double y = point.latitude;
    
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      double xi = polygon[i].longitude;
      double yi = polygon[i].latitude;
      double xj = polygon[j].longitude;
      double yj = polygon[j].latitude;
      
      bool intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi + 0.0000000001) + xi);
      if (intersect) inside = !inside;
      j = i;
    }
    return inside;
  }
}

class _LocalPoint {
  final double x;
  final double y;
  const _LocalPoint(this.x, this.y);
}
