import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/database_service.dart';
import '../services/supabase_config.dart';

class SyncSummary {
  final int pendingFarms;
  final int pendingPoints;
  final int pendingPolygons;
  final int pendingAnimals;
  final int pendingAlerts;
  final int totalPending;

  const SyncSummary({
    required this.pendingFarms,
    required this.pendingPoints,
    required this.pendingPolygons,
    required this.pendingAnimals,
    required this.pendingAlerts,
    required this.totalPending,
  });
}

class SyncProgress {
  final double progress; // 0.0 to 1.0
  final String message;
  final bool isCompleted;
  final bool hasError;

  const SyncProgress({
    required this.progress,
    required this.message,
    this.isCompleted = false,
    this.hasError = false,
  });
}

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  /// Gets count of unsynced points, polygons, farms, animals and alerts in SQLite.
  Future<SyncSummary> getPendingCount() async {
    try {
      final db = DatabaseService.instance;
      final farms = await db.query('farms', where: "sync_status = 'pendiente'");
      final points = await db.query('map_points', where: "sync_status = 'pendiente'");
      final polygons = await db.query('map_polygons', where: "sync_status = 'pendiente'");
      final animals = await db.query('animals', where: "sync_status = 'pendiente'");
      final alerts = await db.query('animal_alerts', where: "sync_status = 'pendiente'");

      final total = farms.length + points.length + polygons.length + animals.length + alerts.length;

      return SyncSummary(
        pendingFarms: farms.length,
        pendingPoints: points.length,
        pendingPolygons: polygons.length,
        pendingAnimals: animals.length,
        pendingAlerts: alerts.length,
        totalPending: total,
      );
    } catch (e) {
      print('Error getting pending sync counts: $e');
      return const SyncSummary(
        pendingFarms: 0,
        pendingPoints: 0,
        pendingPolygons: 0,
        pendingAnimals: 0,
        pendingAlerts: 0,
        totalPending: 0,
      );
    }
  }

  /// Runs the sync loop, backing up to Supabase when connected, emitting progress.
  Stream<SyncProgress> syncNow() async* {
    yield const SyncProgress(progress: 0.05, message: 'Verificando conectividad de red...');
    await Future.delayed(const Duration(milliseconds: 600));

    // 1. Check network connectivity
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasInternet = connectivityResults.any((result) => result != ConnectivityResult.none);

    if (!hasInternet) {
      yield const SyncProgress(
        progress: 0.0,
        message: 'Sin conexión a internet. La sincronización se pausará hasta tener señal.',
        hasError: true,
      );
      return;
    }

    if (!SupabaseConfig.isConfigured) {
      yield const SyncProgress(
        progress: 0.0,
        message: 'Supabase no configurado. Inserta tus credenciales en supabase_config.dart.',
        hasError: true,
      );
      return;
    }

    yield const SyncProgress(progress: 0.15, message: 'Obteniendo registros pendientes de base de datos local...');
    await Future.delayed(const Duration(milliseconds: 500));

    final db = DatabaseService.instance;
    final farms = await db.query('farms', where: "sync_status = 'pendiente'");
    final points = await db.query('map_points', where: "sync_status = 'pendiente'");
    final polygons = await db.query('map_polygons', where: "sync_status = 'pendiente'");
    final animals = await db.query('animals', where: "sync_status = 'pendiente'");
    final alerts = await db.query('animal_alerts', where: "sync_status = 'pendiente'");

    final totalCount = farms.length + points.length + polygons.length + animals.length + alerts.length;

    if (totalCount == 0) {
      yield const SyncProgress(
        progress: 1.0,
        message: 'Todos los datos de CampoMap ya están sincronizados en Supabase.',
        isCompleted: true,
      );
      return;
    }

    yield SyncProgress(
      progress: 0.20,
      message: 'Conectando con Supabase... ($totalCount registros por subir)',
    );
    await Future.delayed(const Duration(milliseconds: 600));

    final client = Supabase.instance.client;
    double currentProgress = 0.20;
    double stepSize = 0.70 / totalCount;

    try {
      // 1. Upload Farms
      for (final farm in farms) {
        yield SyncProgress(
          progress: currentProgress,
          message: 'Subiendo finca: "${farm['name']}"...',
        );
        await client.from('farms').upsert(farm);
        await db.update(
          'farms',
          {'sync_status': 'sincronizado', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [farm['id']],
        );
        currentProgress += stepSize;
      }

      // 2. Upload Polygons
      for (final poly in polygons) {
        yield SyncProgress(
          progress: currentProgress,
          message: 'Subiendo parcela: "${poly['name']}"...',
        );
        await client.from('map_polygons').upsert(poly);
        await db.update(
          'map_polygons',
          {'sync_status': 'sincronizado', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [poly['id']],
        );
        currentProgress += stepSize;
      }

      // 3. Upload Points
      for (final pt in points) {
        yield SyncProgress(
          progress: currentProgress,
          message: 'Subiendo punto de interés: "${pt['name']}"...',
        );
        await client.from('map_points').upsert(pt);
        await db.update(
          'map_points',
          {'sync_status': 'sincronizado', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [pt['id']],
        );
        currentProgress += stepSize;
      }

      // 4. Upload Animals
      for (final animal in animals) {
        yield SyncProgress(
          progress: currentProgress,
          message: 'Subiendo animal: "${animal['name']}"...',
        );
        await client.from('animals').upsert(animal);
        await db.update(
          'animals',
          {'sync_status': 'sincronizado'},
          where: 'id = ?',
          whereArgs: [animal['id']],
        );
        currentProgress += stepSize;
      }

      // 5. Upload Alerts
      for (final alert in alerts) {
        yield SyncProgress(
          progress: currentProgress,
          message: 'Subiendo alerta de geocerca: "${alert['animal_name']}"...',
        );
        await client.from('animal_alerts').upsert(alert);
        await db.update(
          'animal_alerts',
          {'sync_status': 'sincronizado'},
          where: 'id = ?',
          whereArgs: [alert['id']],
        );
        currentProgress += stepSize;
      }

      yield const SyncProgress(
        progress: 1.0,
        message: '¡Respaldo en la nube completado con éxito! Todos los datos locales están guardados en Supabase.',
        isCompleted: true,
      );
    } catch (e) {
      print('Supabase sync error: $e');
      yield SyncProgress(
        progress: currentProgress,
        message: 'Error al sincronizar con Supabase: $e. Reintentando más tarde.',
        hasError: true,
      );
    }
  }
}
