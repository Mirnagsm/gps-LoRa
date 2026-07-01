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

  /// Runs the sync loop: uploads local changes first (Push), then downloads all from cloud (Pull).
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

    yield const SyncProgress(progress: 0.10, message: 'Obteniendo registros pendientes de base de datos local...');
    await Future.delayed(const Duration(milliseconds: 300));

    final db = DatabaseService.instance;
    final farms = await db.query('farms', where: "sync_status = 'pendiente'");
    final points = await db.query('map_points', where: "sync_status = 'pendiente'");
    final polygons = await db.query('map_polygons', where: "sync_status = 'pendiente'");
    final animals = await db.query('animals', where: "sync_status = 'pendiente'");
    final alerts = await db.query('animal_alerts', where: "sync_status = 'pendiente'");

    final totalCount = farms.length + points.length + polygons.length + animals.length + alerts.length;
    final client = Supabase.instance.client;

    try {
      // ==========================================
      // FASE 1: SUBIDA (PUSH)
      // ==========================================
      if (totalCount > 0) {
        yield SyncProgress(
          progress: 0.15,
          message: 'Conectando con Supabase... ($totalCount registros por subir)',
        );
        await Future.delayed(const Duration(milliseconds: 500));

        double currentProgress = 0.15;
        double stepSize = 0.40 / totalCount; // allocate up to 55% for uploading

        // 1. Upload Farms
        for (final farm in farms) {
          yield SyncProgress(
            progress: currentProgress,
            message: 'Subiendo finca: "${farm['name']}"...',
          );
          await client.from('farms').upsert(Map<String, dynamic>.from(farm));
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
          await client.from('map_polygons').upsert(Map<String, dynamic>.from(poly));
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
          await client.from('map_points').upsert(Map<String, dynamic>.from(pt));
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
          await client.from('animals').upsert(Map<String, dynamic>.from(animal));
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
          await client.from('animal_alerts').upsert(Map<String, dynamic>.from(alert));
          await db.update(
            'animal_alerts',
            {'sync_status': 'sincronizado'},
            where: 'id = ?',
            whereArgs: [alert['id']],
          );
          currentProgress += stepSize;
        }
      } else {
        yield const SyncProgress(
          progress: 0.30,
          message: 'Sin registros locales pendientes por subir. Iniciando descarga...',
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // ==========================================
      // FASE 2: DESCARGA (PULL)
      // ==========================================
      yield const SyncProgress(
        progress: 0.55,
        message: 'Descargando datos actualizados de Supabase...',
      );
      await Future.delayed(const Duration(milliseconds: 600));

      // 1. Download Farms
      yield const SyncProgress(progress: 0.60, message: 'Descargando fincas de la nube...');
      final serverFarms = await client.from('farms').select();
      for (final farm in serverFarms) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(farm);
        row['sync_status'] = 'sincronizado';
        await db.insert('farms', row);
      }

      // 2. Download Polygons
      yield const SyncProgress(progress: 0.70, message: 'Descargando parcelas/lotes de la nube...');
      final serverPolygons = await client.from('map_polygons').select();
      for (final poly in serverPolygons) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(poly);
        row['sync_status'] = 'sincronizado';
        await db.insert('map_polygons', row);
      }

      // 3. Download Points
      yield const SyncProgress(progress: 0.80, message: 'Descargando puntos de interés de la nube...');
      final serverPoints = await client.from('map_points').select();
      for (final pt in serverPoints) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(pt);
        row['sync_status'] = 'sincronizado';
        await db.insert('map_points', row);
      }

      // 4. Download Animals
      yield const SyncProgress(progress: 0.85, message: 'Descargando animales de la nube...');
      final serverAnimals = await client.from('animals').select();
      for (final animal in serverAnimals) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(animal);
        row['sync_status'] = 'sincronizado';
        await db.insert('animals', row);
      }

      // 5. Download Alerts
      yield const SyncProgress(progress: 0.90, message: 'Descargando historial de alertas de la nube...');
      final serverAlerts = await client.from('animal_alerts').select();
      for (final alert in serverAlerts) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(alert);
        row['sync_status'] = 'sincronizado';
        await db.insert('animal_alerts', row);
      }

      yield const SyncProgress(
        progress: 1.0,
        message: '¡Sincronización bidireccional completada con éxito!',
        isCompleted: true,
      );
    } catch (e) {
      print('Supabase sync error: $e');
      yield SyncProgress(
        progress: 0.50,
        message: 'Error al sincronizar con Supabase: $e. Reintentando más tarde.',
        hasError: true,
      );
    }
  }
}
