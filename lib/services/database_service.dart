import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// HTML local storage import for Web platform fallback
// We use a conditional compile or dynamic import helper if needed, but since we compile for both,
// we can safely access browser APIs using a universal web check or dart:html.
// To avoid compilation errors on mobile when using dart:html, we can use window.localStorage via JavaScript integration,
// or we can use a library, or we can use standard web local storage dynamically.
// To make it compile on all platforms without issue, let's implement a clean memory-based list that integrates
// with a simple conditional fallback or web-only storage helper.
// A safe way on Flutter to do Web local storage without imports that crash mobile is using Shared Preferences,
// but since we want to keep it simple, we can write a simple MemoryDatabase that does not import dart:html,
// or use window/localStorage dynamically through dart:js or similar, or just a memory database which is super safe.
// Wait, a memory database is 100% safe to compile on all platforms and works perfectly for our testing!
// Let's implement a MemoryDatabase fallback that compiles everywhere, and if we want persistence on web, we can use a simple map.

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  sqflite.Database? _db;

  // Web in-memory database mock
  final Map<String, List<Map<String, dynamic>>> _webDb = {
    'farms': [],
    'map_points': [],
    'map_polygons': [],
    'geo_photos': [],
    'animals': [],
    'animal_alerts': [],
  };

  DatabaseService._init();

  Future<void> initDatabase() async {
    if (kIsWeb) {
      // Initialize web mock database
      return;
    }

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dbPath = path.join(documentsDirectory.path, 'campomap.db');

      _db = await sqflite.openDatabase(
        dbPath,
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      print('Error opening SQLite database: $e');
    }
  }

  Future<void> _onUpgrade(sqflite.Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAnimalsAndAlertsTables(db);
    }
  }

  Future<void> _createAnimalsAndAlertsTables(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS animals (
        id TEXT PRIMARY KEY,
        farm_id TEXT,
        name TEXT,
        details TEXT,
        caretaker TEXT,
        allowed_polygon_id TEXT,
        last_latitude REAL,
        last_longitude REAL,
        status TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS animal_alerts (
        id TEXT PRIMARY KEY,
        animal_id TEXT,
        animal_name TEXT,
        animal_details TEXT,
        caretaker TEXT,
        violation_latitude REAL,
        violation_longitude REAL,
        timestamp TEXT,
        sync_status TEXT
      )
    ''');
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute('''
      CREATE TABLE farms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        owner_name TEXT,
        created_at TEXT,
        updated_at TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE map_points (
        id TEXT PRIMARY KEY,
        farm_id TEXT,
        type TEXT,
        name TEXT,
        description TEXT,
        latitude REAL,
        longitude REAL,
        photo_path TEXT,
        created_at TEXT,
        updated_at TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE map_polygons (
        id TEXT PRIMARY KEY,
        farm_id TEXT,
        type TEXT,
        name TEXT,
        description TEXT,
        area_hectares REAL,
        coordinates_json TEXT,
        created_at TEXT,
        updated_at TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE geo_photos (
        id TEXT PRIMARY KEY,
        farm_id TEXT,
        element_id TEXT,
        element_type TEXT,
        local_path TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT,
        sync_status TEXT
      )
    ''');

    await _createAnimalsAndAlertsTables(db);
  }

  // Generic Query Method
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    if (kIsWeb) {
      var results = List<Map<String, dynamic>>.from(_webDb[table] ?? []);
      
      // Simple mock filtering for basic SQL queries (e.g. "farm_id = ?")
      if (where != null && whereArgs != null) {
        if (where.contains('farm_id = ?')) {
          final farmId = whereArgs[0] as String;
          results = results.where((row) => row['farm_id'] == farmId).toList();
        } else if (where.contains('id = ?')) {
          final id = whereArgs[0] as String;
          results = results.where((row) => row['id'] == id).toList();
        } else if (where.contains('animal_id = ?')) {
          final animalId = whereArgs[0] as String;
          results = results.where((row) => row['animal_id'] == animalId).toList();
        } else if (where.contains('sync_status = ?')) {
          final syncStatus = whereArgs[0] as String;
          results = results.where((row) => row['sync_status'] == syncStatus).toList();
        }
      }

      if (orderBy != null) {
        if (orderBy.contains('created_at DESC')) {
          results.sort((a, b) {
            final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
            final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
            return bTime.compareTo(aTime);
          });
        }
      }

      return results;
    }


    if (_db == null) await initDatabase();
    return await _db!.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  // Generic Insert Method
  Future<int> insert(String table, Map<String, dynamic> values) async {
    if (kIsWeb) {
      final list = _webDb[table] ??= [];
      // Remove any existing with the same ID to behave like REPLACE/conflict resolver
      list.removeWhere((item) => item['id'] == values['id']);
      list.add(Map<String, dynamic>.from(values));
      return 1;
    }

    if (_db == null) await initDatabase();
    return await _db!.insert(
      table,
      values,
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  // Generic Update Method
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    if (kIsWeb) {
      final list = _webDb[table] ?? [];
      int updatedCount = 0;

      for (int i = 0; i < list.length; i++) {
        bool matches = false;
        if (where.contains('id = ?')) {
          matches = list[i]['id'] == whereArgs[0];
        } else if (where.contains('farm_id = ?')) {
          matches = list[i]['farm_id'] == whereArgs[0];
        }

        if (matches) {
          final updatedRow = Map<String, dynamic>.from(list[i]);
          values.forEach((key, val) {
            updatedRow[key] = val;
          });
          list[i] = updatedRow;
          updatedCount++;
        }
      }
      return updatedCount;
    }

    if (_db == null) await initDatabase();
    return await _db!.update(table, values, where: where, whereArgs: whereArgs);
  }

  // Generic Delete Method
  Future<int> delete(
    String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    if (kIsWeb) {
      final list = _webDb[table] ?? [];
      int beforeLength = list.length;

      if (where.contains('id = ?')) {
        list.removeWhere((item) => item['id'] == whereArgs[0]);
      } else if (where.contains('farm_id = ?')) {
        list.removeWhere((item) => item['farm_id'] == whereArgs[0]);
      }

      return beforeLength - list.length;
    }

    if (_db == null) await initDatabase();
    return await _db!.delete(table, where: where, whereArgs: whereArgs);
  }
}
