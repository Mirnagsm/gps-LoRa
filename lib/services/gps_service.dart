import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GpsService {
  static final GpsService instance = GpsService._init();

  // Mock coordinates for testing: A rural area in Colombia/Venezuela
  static const double mockLatitude = 4.7110;
  static const double mockLongitude = -74.0721;

  GpsService._init();

  Future<bool> checkAndRequestPermissions() async {
    if (kIsWeb) {
      // Browsers handle this natively when calling geolocation API
      return true;
    }

    // Check location permission using permission_handler
    var status = await Permission.location.status;
    if (status.isDenied) {
      status = await Permission.location.request();
    }

    if (status.isPermanentlyDenied) {
      // Open settings if permanently denied
      await openAppSettings();
      return false;
    }

    return status.isGranted;
  }

  Future<Position> getCurrentPosition() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        return _getMockPosition();
      }

      // Check if location services are enabled
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        return _getMockPosition();
      }

      // Fetch actual position
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      print('GPS Error, falling back to mock: $e');
      return _getMockPosition();
    }
  }

  Stream<Position> getPositionStream() {
    if (kIsWeb) {
      // Return a periodic stream with mock positions for simplicity in web testing
      return Stream.periodic(
        const Duration(seconds: 5),
        (_) => _getMockPosition(),
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // notify every 2 meters
      ),
    );
  }

  /// High-frequency stream for walk-trace / lindero mode.
  /// Captures every 3 seconds with a minimum distance of 2 meters.
  Stream<Position> getHighFrequencyStream() {
    if (kIsWeb) {
      // Simulate walking by shifting the mock position slightly each tick
      int tick = 0;
      return Stream.periodic(
        const Duration(seconds: 3),
        (_) {
          tick++;
          return Position(
            latitude: mockLatitude + (tick * 0.00003),
            longitude: mockLongitude + (tick * 0.00002),
            timestamp: DateTime.now(),
            accuracy: 4.0 + (tick % 3),
            altitude: 2600.0,
            heading: (tick * 15.0) % 360,
            speed: 1.2,
            speedAccuracy: 0.5,
            altitudeAccuracy: 1.0,
            headingAccuracy: 5.0,
          );
        },
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2, // minimum 2 meters between updates
      ),
    );
  }

  Position _getMockPosition() {
    return Position(
      latitude: mockLatitude,
      longitude: mockLongitude,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 2600.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 1.0,
      headingAccuracy: 1.0,
    );
  }
}
