import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/farm.dart';
import '../models/map_point.dart';
import '../models/map_polygon.dart';
import '../models/animal.dart';
import '../models/animal_alert.dart';

import '../services/database_service.dart';
import '../services/gps_service.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../services/gis_helper.dart';
import '../services/supabase_config.dart';

import 'point_form_screen.dart';
import 'polygon_form_screen.dart';
import 'sync_screen.dart';

class MapScreen extends StatefulWidget {
  final Farm farm;

  const MapScreen({super.key, required this.farm});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late TabController _tabController;

  List<MapPoint> _points = [];
  List<MapPolygon> _polygons = [];
  List<Animal> _animals = [];
  List<AnimalAlert> _alerts = [];
  
  LatLng? _currentLocation;
  bool _isGpsLoading = false;
  String _connectionText = "Verificando...";
  Color _connectionColor = Colors.grey;
  bool _isOffline = false;

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  StreamSubscription<Position>? _gpsSubscription;
  bool _showSatellite = false;
  
  // Drawing Mode
  bool _isDrawingMode = false;
  List<LatLng> _drawingPoints = [];

  // GPS Walk Drawing Mode
  bool _isWalkDrawingMode = false;

  // Ruler Mode (Measurement tool)
  bool _isRulerMode = false;
  List<LatLng> _rulerPoints = [];

  // Test Animal Tracker Mode
  bool _isTrackerMode = false;
  Animal? _trackingAnimal;

  // Alarm state variables
  bool _isAlarmActive = false;
  bool _isAlarmPlaying = false;
  Timer? _alarmTimer;
  bool _alarmFlash = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMapData();
    _checkInitialConnection();
    _subscribeToConnectivity();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _gpsSubscription?.cancel();
    _alarmTimer?.cancel();
    _mapController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Load points, polygons, animals and alerts
  Future<void> _loadMapData() async {
    try {
      final pointMaps = await DatabaseService.instance.query(
        'map_points',
        where: 'farm_id = ?',
        whereArgs: [widget.farm.id],
      );
      final polygonMaps = await DatabaseService.instance.query(
        'map_polygons',
        where: 'farm_id = ?',
        whereArgs: [widget.farm.id],
      );
      final animalMaps = await DatabaseService.instance.query(
        'animals',
        where: 'farm_id = ?',
        whereArgs: [widget.farm.id],
      );

      final loadedPoints = pointMaps.map((m) => MapPoint.fromMap(m)).toList();
      final loadedPolygons = polygonMaps.map((m) => MapPolygon.fromMap(m)).toList();
      final loadedAnimals = animalMaps.map((m) => Animal.fromMap(m)).toList();

      // Load alerts for all these animals
      final List<AnimalAlert> loadedAlerts = [];
      for (final animal in loadedAnimals) {
        final alertMaps = await DatabaseService.instance.query(
          'animal_alerts',
          where: 'animal_id = ?',
          whereArgs: [animal.id],
        );
        loadedAlerts.addAll(alertMaps.map((m) => AnimalAlert.fromMap(m)));
      }
      loadedAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _points = loadedPoints;
        _polygons = loadedPolygons;
        _animals = loadedAnimals;
        _alerts = loadedAlerts;
      });
    } catch (e) {
      print('Error loading map data: $e');
    }
  }

  // Connection check functions
  Future<void> _checkInitialConnection() async {
    final connectivity = Connectivity();
    final results = await connectivity.checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _subscribeToConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isNone = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    setState(() {
      _isOffline = isNone;
      if (isNone) {
        _connectionText = "Modo Offline (Guardando localmente)";
        _connectionColor = Colors.orange[800]!;
      } else {
        _connectionText = "En Línea (Listo para sincronizar)";
        _connectionColor = Colors.green[800]!;
      }
    });
  }

  // GPS tracking functions
  Future<void> _startGpsTracking() async {
    setState(() => _isGpsLoading = true);
    final position = await GpsService.instance.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _isGpsLoading = false;
    });

    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }

    _gpsSubscription = GpsService.instance.getPositionStream().listen((pos) {
      if (mounted) {
        final newLatLng = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentLocation = newLatLng;
        });

        // Add GPS walking point if active
        if (_isWalkDrawingMode && _isDrawingMode) {
          if (_drawingPoints.isEmpty ||
              Geolocator.distanceBetween(
                    _drawingPoints.last.latitude,
                    _drawingPoints.last.longitude,
                    newLatLng.latitude,
                    newLatLng.longitude,
                  ) > 2.5) {
            setState(() {
              _drawingPoints.add(newLatLng);
            });
          }
        }
      }
    });
  }

  Future<void> _centerOnCurrentLocation() async {
    setState(() => _isGpsLoading = true);
    final pos = await GpsService.instance.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      _isGpsLoading = false;
    });
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    }
  }

  void _finishDrawingAndSave() {
    if (_drawingPoints.length < 3) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PolygonFormScreen(
          farmId: widget.farm.id,
          coordinates: List<LatLng>.from(_drawingPoints),
        ),
      ),
    ).then((result) {
      if (result == true) {
        setState(() {
          _isDrawingMode = false;
          _isWalkDrawingMode = false;
          _drawingPoints.clear();
        });
        _loadMapData();
      }
    });
  }

  void _showAddPointScreen() {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esperando señal GPS válida...')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PointFormScreen(
          farmId: widget.farm.id,
          initialLatitude: _currentLocation!.latitude,
          initialLongitude: _currentLocation!.longitude,
        ),
      ),
    ).then((_) => _loadMapData());
  }

  // Visual Polygons styling by category
  Color _getPolygonColor(String type) {
    switch (type.toLowerCase()) {
      case 'cultivo':
        return Colors.green.withOpacity(0.35);
      case 'potrero':
        return Colors.amber.withOpacity(0.35);
      case 'agua':
        return Colors.blue.withOpacity(0.35);
      case 'corral':
        return Colors.orange.withOpacity(0.35);
      case 'zona dañada':
      case 'zona talada':
        return Colors.red.withOpacity(0.35);
      case 'infraestructura':
        return Colors.blueGrey.withOpacity(0.35);
      default:
        return Colors.teal.withOpacity(0.3);
    }
  }

  Color _getPolygonBorderColor(String type) {
    switch (type.toLowerCase()) {
      case 'cultivo':
        return Colors.green[900]!;
      case 'potrero':
        return Colors.amber[900]!;
      case 'agua':
        return Colors.blue[900]!;
      case 'corral':
        return Colors.orange[900]!;
      case 'zona dañada':
      case 'zona talada':
        return Colors.red[900]!;
      default:
        return Colors.teal[900]!;
    }
  }

  Color _getCategoryColor(String type) {
    switch (type.toLowerCase()) {
      case 'pozo':
        return Colors.blue[700]!;
      case 'cerca':
        return Colors.brown[700]!;
      case 'corral':
        return Colors.orange[800]!;
      case 'portón':
        return Colors.red[700]!;
      case 'árbol importante':
      case 'árbol':
        return Colors.green[800]!;
      default:
        return Colors.teal[700]!;
    }
  }

  IconData _getCategoryIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pozo':
        return Icons.water_drop;
      case 'cerca':
        return Icons.fence;
      case 'corral':
        return Icons.warehouse;
      case 'portón':
        return Icons.door_sliding;
      case 'árbol importante':
      case 'árbol':
        return Icons.park;
      default:
        return Icons.location_on;
    }
  }

  // Ray-Casting alert trigger system
  void _triggerAlarm(Animal animal) {
    if (_isAlarmActive) return;
    setState(() {
      _isAlarmActive = true;
      _isAlarmPlaying = true;
    });

    _alarmTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _alarmFlash = !_alarmFlash;
      });
      if (_isAlarmPlaying) {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.vibrate();
      }
    });
  }

  void _silenceAlarm() {
    setState(() {
      _isAlarmPlaying = false;
      _isAlarmActive = false;
    });
    _alarmTimer?.cancel();
  }

  // Toggle tracking mode (real device as collar)
  void _toggleTrackerMode(Animal animal, bool enable) async {
    if (enable) {
      _gpsSubscription?.cancel();
      setState(() {
        _isTrackerMode = true;
        _trackingAnimal = animal;
      });

      _gpsSubscription = GpsService.instance.getHighFrequencyStream().listen((pos) async {
        if (!mounted || !_isTrackerMode || _trackingAnimal == null) return;
        final position = LatLng(pos.latitude, pos.longitude);
        
        setState(() {
          _currentLocation = position;
        });

        final geofenceId = _trackingAnimal!.allowedPolygonId;
        String newStatus = 'dentro';
        
        if (geofenceId != null) {
          final polyIndex = _polygons.indexWhere((p) => p.id == geofenceId);
          if (polyIndex != -1) {
            final poly = _polygons[polyIndex];
            final inside = GisHelper.isPointInPolygon(position, poly.coordinates);
            newStatus = inside ? 'dentro' : 'fuera';
            
            final prevStatus = _trackingAnimal!.status;
            if (newStatus == 'fuera' && prevStatus != 'fuera') {
              _triggerAlarm(_trackingAnimal!);
              await _logGeofenceAlert(_trackingAnimal!, pos.latitude, pos.longitude);
            }
          }
        }

        final updated = _trackingAnimal!.copyWith(
          lastLatitude: pos.latitude,
          lastLongitude: pos.longitude,
          status: newStatus,
        );

        setState(() {
          _trackingAnimal = updated;
        });

        await _updateAnimalLocation(updated);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modo Animal Activo en "${animal.name}". Lleva este celular para rastrear en vivo.'),
          backgroundColor: Colors.green[800],
        ),
      );
    } else {
      _gpsSubscription?.cancel();
      setState(() {
        _isTrackerMode = false;
        _trackingAnimal = null;
        _silenceAlarm();
      });
      _startGpsTracking(); // return to standard stream
    }
  }

  Future<void> _updateAnimalLocation(Animal animal) async {
    await DatabaseService.instance.update(
      'animals',
      animal.toMap(),
      where: 'id = ?',
      whereArgs: [animal.id],
    );

    if (SupabaseConfig.isConfigured && !_isOffline) {
      try {
        await Supabase.instance.client.from('animals').upsert(animal.toMap());
        await DatabaseService.instance.update(
          'animals',
          {'sync_status': 'sincronizado'},
          where: 'id = ?',
          whereArgs: [animal.id],
        );
      } catch (e) {
        print('Error backing up animal to Supabase: $e');
      }
    }
    _loadMapData();
  }

  Future<void> _logGeofenceAlert(Animal animal, double lat, double lng) async {
    final alert = AnimalAlert(
      id: 'ALR-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      animalId: animal.id,
      animalName: animal.name,
      animalDetails: animal.details,
      caretaker: animal.caretaker,
      violationLatitude: lat,
      violationLongitude: lng,
      timestamp: DateTime.now(),
      syncStatus: 'pendiente',
    );

    await DatabaseService.instance.insert('animal_alerts', alert.toMap());

    if (SupabaseConfig.isConfigured && !_isOffline) {
      try {
        await Supabase.instance.client.from('animal_alerts').upsert(alert.toMap());
        await DatabaseService.instance.update(
          'animal_alerts',
          {'sync_status': 'sincronizado'},
          where: 'id = ?',
          whereArgs: [alert.id],
        );
      } catch (e) {
        print('Error backing up alert to Supabase: $e');
      }
    }
    _loadMapData();
  }

  // Animal Registration Dialog
  void _showAddAnimalDialog() {
    final nameController = TextEditingController();
    final detailsController = TextEditingController();
    final caretakerController = TextEditingController();
    String? selectedGeofenceId = _polygons.isNotEmpty ? _polygons.first.id : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.pets, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Registrar Animal', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nombre / ID del Animal *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      decoration: const InputDecoration(labelText: 'Detalles (ej. Raza, Peso, Raza)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: caretakerController,
                      decoration: const InputDecoration(labelText: 'Cuidador Designado'),
                    ),
                    const SizedBox(height: 16),
                    if (_polygons.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Geocerca Permitida (Lote):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: selectedGeofenceId,
                        items: _polygons.map((poly) {
                          return DropdownMenuItem<String>(
                            value: poly.id,
                            child: Text('${poly.name} (${poly.areaHectares.toStringAsFixed(1)} Ha)'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedGeofenceId = val;
                          });
                        },
                      ),
                    ] else
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No hay parcelas creadas. Dibuja una parcela para asignarla como geocerca.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('El nombre del animal es obligatorio')),
                      );
                      return;
                    }
                    final animal = Animal(
                      id: 'ANM-${const Uuid().v4().substring(0, 8).toUpperCase()}',
                      farmId: widget.farm.id,
                      name: nameController.text.trim(),
                      details: detailsController.text.trim(),
                      caretaker: caretakerController.text.trim(),
                      allowedPolygonId: selectedGeofenceId,
                      status: 'dentro',
                      syncStatus: 'pendiente',
                    );

                    await DatabaseService.instance.insert('animals', animal.toMap());
                    Navigator.pop(context);
                    _loadMapData();
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Interactive Bottom sheets for Points & Polygons
  void _showPointDetailsSheet(MapPoint point) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(_getCategoryIcon(point.type), color: _getCategoryColor(point.type), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Tipo', point.type.toUpperCase()),
              _buildDetailRow('Coordenadas', '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
              _buildDetailRow('Descripción', point.description.isEmpty ? 'Sin descripción' : point.description),
              _buildDetailRow('Sincronización', point.syncStatus == 'pendiente' ? 'Pendiente (Offline)' : 'Respaldado en Supabase'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PointFormScreen(
                              farmId: widget.farm.id,
                              initialLatitude: point.latitude,
                              initialLongitude: point.longitude,
                              existingPoint: point,
                            ),
                          ),
                        ).then((_) => _loadMapData());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () async {
                        final confirm = await _showConfirmDeleteDialog('punto');
                        if (confirm == true) {
                          await DatabaseService.instance.delete('map_points', where: 'id = ?', whereArgs: [point.id]);
                          Navigator.pop(context);
                          _loadMapData();
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _showPolygonDetailsSheet(MapPolygon poly) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.square_foot, color: _getPolygonBorderColor(poly.type), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      poly.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Tipo de Uso', poly.type),
              _buildDetailRow('Área Calculada', '${poly.areaHectares.toStringAsFixed(4)} Hectáreas'),
              _buildDetailRow('Detalles', poly.description),
              _buildDetailRow('Sincronización', poly.syncStatus == 'pendiente' ? 'Pendiente (Offline)' : 'Respaldado en Supabase'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PolygonFormScreen(
                              farmId: widget.farm.id,
                              coordinates: poly.coordinates,
                              existingPolygon: poly,
                            ),
                          ),
                        ).then((result) {
                          if (result == true) {
                            _loadMapData();
                          }
                        });
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () async {
                        final confirm = await _showConfirmDeleteDialog('lote/parcela');
                        if (confirm == true) {
                          await DatabaseService.instance.delete('map_polygons', where: 'id = ?', whereArgs: [poly.id]);
                          Navigator.pop(context);
                          _loadMapData();
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _showConfirmDeleteDialog(String itemType) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('¿Eliminar $itemType?'),
          content: Text('¿Estás seguro de que deseas eliminar permanentemente este $itemType? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }

  void _showExportOptions() {
    if (_points.isEmpty && _polygons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay elementos registrados para exportar')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Exportar y Compartir Predio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text('Exportar como GeoJSON'),
                subtitle: const Text('Compatible con QGIS, ArcGIS y herramientas GIS'),
                onTap: () async {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Generando archivo GeoJSON...')),
                  );
                  await ExportService.instance.shareGeoJson(widget.farm.name, _points, _polygons);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.orange),
                title: const Text('Exportar como KML'),
                subtitle: const Text('Compatible con Google Earth y QField'),
                onTap: () async {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Generando archivo KML...')),
                  );
                  await ExportService.instance.shareKml(widget.farm.name, _points, _polygons);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('Generar Reporte PDF'),
                subtitle: const Text('Reporte técnico imprimible con tablas y estadísticas'),
                onTap: () async {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Generando reporte PDF...')),
                  );
                  await PdfService.instance.generateAndShareReport(widget.farm, _points, _polygons);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Create markers for points of interest
    final markers = _points.map((point) {
      final color = _getCategoryColor(point.type);
      final icon = _getCategoryIcon(point.type);
      return Marker(
        point: LatLng(point.latitude, point.longitude),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showPointDetailsSheet(point),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color, width: 1),
                ),
                child: Text(
                  point.name,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    // 2. Create markers for polygons centroid labels
    final labelsMarkers = _polygons.map((poly) {
      final centroid = GisHelper.getCentroid(poly.coordinates);
      final borderColor = _getPolygonBorderColor(poly.type);
      return Marker(
        point: centroid,
        width: 80,
        height: 40,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  poly.name,
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${poly.areaHectares.toStringAsFixed(1)} Ha',
                  style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: borderColor),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    // 3. Create markers for simulated tracked animals
    final animalMarkers = _animals
        .where((a) => a.lastLatitude != null && a.lastLongitude != null)
        .map((animal) {
      final isViolating = animal.status == 'fuera';
      final isSimulatedHere = _isTrackerMode && _trackingAnimal?.id == animal.id;
      final markerColor = isViolating ? Colors.red : Colors.green[800]!;

      return Marker(
        point: LatLng(animal.lastLatitude!, animal.lastLongitude!),
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.pets, color: markerColor),
                    const SizedBox(width: 8),
                    Text(animal.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detalles: ${animal.details}'),
                    const SizedBox(height: 6),
                    Text('Cuidador: ${animal.caretaker}'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Estado: '),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isViolating ? Colors.red[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            animal.status.toUpperCase(),
                            style: TextStyle(
                              color: isViolating ? Colors.red : Colors.green[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isSimulatedHere)
                      const Text(
                        '¡Este celular está actuando como el collar de este animal!',
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSimulatedHere ? Colors.red : Colors.green[800],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _toggleTrackerMode(animal, !isSimulatedHere);
                    },
                    child: Text(isSimulatedHere ? 'Desactivar Modo Collar' : 'Usar Celular como Collar'),
                  ),
                ],
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isViolating && _alarmFlash ? Colors.red : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: markerColor, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Icon(
                  isViolating ? Icons.warning : Icons.pets,
                  color: isViolating && _alarmFlash ? Colors.white : markerColor,
                  size: 24,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: markerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  animal.name,
                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    // 4. Create current position marker
    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 5. Convert map polygons to styled Polygons
    final mapPolygons = _polygons.map((poly) {
      return Polygon(
        points: poly.coordinates,
        color: _getPolygonColor(poly.type),
        borderColor: _getPolygonBorderColor(poly.type),
        borderStrokeWidth: 3,
        isFilled: true,
      );
    }).toList();

    // Calculate ruler metric (total distance & area)
    double rulerDistance = 0.0;
    double rulerArea = 0.0;
    if (_isRulerMode && _rulerPoints.isNotEmpty) {
      for (int i = 0; i < _rulerPoints.length - 1; i++) {
        rulerDistance += Geolocator.distanceBetween(
          _rulerPoints[i].latitude,
          _rulerPoints[i].longitude,
          _rulerPoints[i + 1].latitude,
          _rulerPoints[i + 1].longitude,
        );
      }
      if (_rulerPoints.length >= 3) {
        rulerArea = GisHelper.calculateAreaInHectares(_rulerPoints);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.farm.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            Text('Productor: ${widget.farm.ownerName ?? 'Sin asignar'}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SyncScreen()),
              ).then((_) => _loadMapData());
            },
            tooltip: 'Sincronizar datos',
          ),
          IconButton(
            icon: const Icon(Icons.share_location, color: Colors.white, size: 28),
            onPressed: _showExportOptions,
            tooltip: 'Compartir predio',
          ),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 40, bottom: 10, left: 16, right: 16),
              color: Colors.green[800],
              child: Row(
                children: [
                  const Icon(Icons.landscape, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    widget.farm.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: Colors.green[800],
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green[800],
              tabs: const [
                Tab(icon: Icon(Icons.layers), text: 'Mapas'),
                Tab(icon: Icon(Icons.pets), text: 'Animales'),
                Tab(icon: Icon(Icons.notification_important), text: 'Alertas'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLayersTab(),
                  _buildAnimalsTab(),
                  _buildAlertsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. Map Widget
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(GpsService.mockLatitude, GpsService.mockLongitude),
              initialZoom: 15.0,
              maxZoom: 22.0,
              minZoom: 1.0,
              onTap: (tapPosition, point) {
                if (_isDrawingMode) {
                  setState(() {
                    _drawingPoints.add(point);
                  });
                } else if (_isRulerMode) {
                  setState(() {
                    _rulerPoints.add(point);
                  });
                } else {
                  // Find if clicked inside any polygon
                  for (final poly in _polygons) {
                    if (GisHelper.isPointInPolygon(point, poly.coordinates)) {
                      _showPolygonDetailsSheet(poly);
                      return;
                    }
                  }
                }
              },
            ),
            children: [
              if (_showSatellite)
                TileLayer(
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                  userAgentPackageName: 'com.campomap.offline',
                  maxZoom: 22,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.campomap.offline',
                  maxZoom: 22,
                ),
              PolygonLayer(polygons: mapPolygons),
              PolylineLayer(
                polylines: <Polyline<Object>>[
                  if (_isDrawingMode && _drawingPoints.isNotEmpty)
                    Polyline(
                      points: _drawingPoints.length > 2
                          ? [..._drawingPoints, _drawingPoints.first]
                          : _drawingPoints,
                      color: Colors.brown[800]!,
                      strokeWidth: 4.0,
                    ),
                  if (_isRulerMode && _rulerPoints.isNotEmpty)
                    Polyline(
                      points: _rulerPoints,
                      color: Colors.blue[800]!,
                      strokeWidth: 3.0,
                      pattern: const StrokePattern.dotted(),
                    ),
                ],
              ),
              MarkerLayer(markers: [
                ...markers,
                ...labelsMarkers,
                ...animalMarkers,
                if (_isDrawingMode)
                  ..._drawingPoints.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final pt = entry.value;
                    return Marker(
                      point: pt,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.brown[700],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  }),
                if (_isRulerMode)
                  ..._rulerPoints.asMap().entries.map((entry) {
                    final pt = entry.value;
                    return Marker(
                      point: pt,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                      ),
                    );
                  }),
              ]),
            ],
          ),

          // 2. Connection Banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: _connectionColor.withOpacity(0.9),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isOffline ? Icons.cloud_off : Icons.cloud_done,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _connectionText,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // 3. Manual Drawing controls overlay
          if (_isDrawingMode)
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.brown[800],
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(_isWalkDrawingMode ? Icons.directions_walk : Icons.gesture, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isWalkDrawingMode ? 'Mapeo Caminando Activo' : 'Dibujando Lote Manual',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Puntos capturados: ${_drawingPoints.length}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (!_isWalkDrawingMode)
                        IconButton(
                          icon: const Icon(Icons.undo, color: Colors.white),
                          onPressed: _drawingPoints.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _drawingPoints.removeLast();
                                  });
                                },
                        ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _isDrawingMode = false;
                            _isWalkDrawingMode = false;
                            _drawingPoints.clear();
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
                        onPressed: _drawingPoints.length < 3 ? null : _finishDrawingAndSave,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4. Ruler Mode Overlay
          if (_isRulerMode)
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.blue[900],
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.square_foot, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Medición Temporal (${_rulerPoints.length} pts)',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Distancia: ${rulerDistance.toStringAsFixed(1)} m | Área: ${rulerArea.toStringAsFixed(2)} Ha',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _rulerPoints.clear();
                          });
                        },
                        tooltip: 'Limpiar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _isRulerMode = false;
                            _rulerPoints.clear();
                          });
                        },
                        tooltip: 'Cerrar regla',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 5. GPS loading status
          if (_isGpsLoading)
            const Center(
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.green),
                      SizedBox(height: 16),
                      Text('Buscando señal GPS...', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),

          // 6. Real-time active alarm overlay
          if (_isAlarmActive)
            Positioned.fill(
              child: GestureDetector(
                onTap: _silenceAlarm,
                child: Container(
                  color: Colors.red.withOpacity(_alarmFlash ? 0.5 : 0.25),
                  child: Center(
                    child: Card(
                      color: Colors.red[900],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 10,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning, color: Colors.white, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              '¡ALERTA DE GEOCERCA!',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'El animal "${_trackingAnimal?.name}" ha salido de la geocerca permitida.',
                              style: const TextStyle(color: Colors.white70, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Responsable: ${_trackingAnimal?.caretaker}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red[900],
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              onPressed: _silenceAlarm,
                              icon: const Icon(Icons.volume_off),
                              label: const Text('SILENCIAR ALERTA', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Open menu drawer
          Builder(
            builder: (context) {
              return FloatingActionButton(
                heroTag: 'drawer_btn',
                mini: true,
                backgroundColor: Colors.green[800],
                foregroundColor: Colors.white,
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
                tooltip: 'Ver Elementos y Animales',
                child: const Icon(Icons.menu),
              );
            },
          ),
          const SizedBox(height: 12),
          // Toggle satellite view button
          FloatingActionButton(
            heroTag: 'satellite_btn',
            mini: true,
            backgroundColor: _showSatellite ? Colors.green[800] : Colors.white,
            foregroundColor: _showSatellite ? Colors.white : Colors.green[800],
            onPressed: () {
              setState(() {
                _showSatellite = !_showSatellite;
              });
            },
            tooltip: _showSatellite ? 'Mostrar mapa' : 'Mostrar satélite',
            child: Icon(_showSatellite ? Icons.map : Icons.satellite_alt),
          ),
          const SizedBox(height: 12),
          // Center GPS location button
          FloatingActionButton(
            heroTag: 'gps_btn',
            mini: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.green[800],
            onPressed: _centerOnCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 12),
          // Ruler Measurement Mode button
          FloatingActionButton(
            heroTag: 'ruler_btn',
            mini: true,
            backgroundColor: _isRulerMode ? Colors.blue[800] : Colors.white,
            foregroundColor: _isRulerMode ? Colors.white : Colors.blue[800],
            onPressed: () {
              setState(() {
                _isRulerMode = !_isRulerMode;
                _isDrawingMode = false;
                _isWalkDrawingMode = false;
                _rulerPoints.clear();
              });
              if (_isRulerMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Modo regla activo. Toca el mapa para medir distancias.')),
                );
              }
            },
            tooltip: 'Medir distancia/área',
            child: const Icon(Icons.square_foot),
          ),
          const SizedBox(height: 12),
          // Draw parcel button (Popup for manual or walk)
          FloatingActionButton(
            heroTag: 'poly_btn',
            mini: true,
            backgroundColor: _isDrawingMode ? Colors.green[800] : Colors.brown[600],
            foregroundColor: Colors.white,
            onPressed: () {
              if (_isDrawingMode) {
                setState(() {
                  _isDrawingMode = false;
                  _isWalkDrawingMode = false;
                  _drawingPoints.clear();
                });
              } else {
                _showDrawModeSelection();
              }
            },
            tooltip: 'Dibujar Lote/Cerca',
            child: const Icon(Icons.format_shapes),
          ),
          const SizedBox(height: 12),
          // Register point button
          FloatingActionButton.large(
            heroTag: 'add_btn',
            backgroundColor: Colors.green[800],
            foregroundColor: Colors.white,
            onPressed: _showAddPointScreen,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_location_alt, size: 36),
                SizedBox(height: 2),
                Text('PUNTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDrawModeSelection() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              const ListTile(
                title: Text('Mapear Parcela / Lote', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.gesture, color: Colors.green),
                title: const Text('Dibujar Manual en Pantalla'),
                subtitle: const Text('Toca los puntos en la pantalla para trazar el lindero'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isDrawingMode = true;
                    _isWalkDrawingMode = false;
                    _isRulerMode = false;
                    _drawingPoints.clear();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk, color: Colors.green),
                title: const Text('Dibujar Caminando por el Límite'),
                subtitle: const Text('Registra vértices automáticamente con tu señal GPS'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isDrawingMode = true;
                    _isWalkDrawingMode = true;
                    _isRulerMode = false;
                    _drawingPoints.clear();
                  });
                  if (_currentLocation != null) {
                    _drawingPoints.add(_currentLocation!);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mapeo por caminata iniciado. Camina por el límite del lote.')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Drawer Tabs content builders
  Widget _buildLayersTab() {
    if (_points.isEmpty && _polygons.isEmpty) {
      return const Center(child: Text('No hay elementos registrados.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_polygons.isNotEmpty) ...[
          const Text('Parcelas / Lotes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          ..._polygons.map((poly) => ListTile(
                leading: Icon(Icons.square_foot, color: _getPolygonBorderColor(poly.type)),
                title: Text(poly.name),
                subtitle: Text('${poly.areaHectares.toStringAsFixed(2)} Hectáreas | ${poly.type}'),
                onTap: () {
                  Navigator.pop(context);
                  _mapController.move(GisHelper.getCentroid(poly.coordinates), 17.0);
                  _showPolygonDetailsSheet(poly);
                },
              )),
          const Divider(),
        ],
        if (_points.isNotEmpty) ...[
          const Text('Puntos de Interés', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          ..._points.map((pt) => ListTile(
                leading: Icon(_getCategoryIcon(pt.type), color: _getCategoryColor(pt.type)),
                title: Text(pt.name),
                subtitle: Text(pt.type),
                onTap: () {
                  Navigator.pop(context);
                  _mapController.move(LatLng(pt.latitude, pt.longitude), 17.0);
                  _showPointDetailsSheet(pt);
                },
              )),
        ]
      ],
    );
  }

  Widget _buildAnimalsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: _showAddAnimalDialog,
            icon: const Icon(Icons.add_circle),
            label: const Text('REGISTRAR ANIMAL / COLLAR'),
          ),
        ),
        Expanded(
          child: _animals.isEmpty
              ? const Center(child: Text('No hay animales registrados.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _animals.length,
                  itemBuilder: (context, idx) {
                    final animal = _animals[idx];
                    final isViolating = animal.status == 'fuera';
                    final isCollarActive = _isTrackerMode && _trackingAnimal?.id == animal.id;

                    return Card(
                      color: isCollarActive ? Colors.green[50] : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isCollarActive ? Colors.green : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isViolating ? Colors.red[100] : Colors.green[100],
                          child: Icon(
                            isViolating ? Icons.warning : Icons.pets,
                            color: isViolating ? Colors.red[800] : Colors.green[800],
                          ),
                        ),
                        title: Text(animal.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Cuidador: ${animal.caretaker}\nEstado: ${animal.status.toUpperCase()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'collar') {
                              _toggleTrackerMode(animal, !isCollarActive);
                            } else if (val == 'delete') {
                              _deleteAnimal(animal.id);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'collar',
                              child: Row(
                                children: [
                                  Icon(isCollarActive ? Icons.volume_off : Icons.phone_android, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(isCollarActive ? 'Desactivar Modo Collar' : 'Activar Modo Collar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text('Eliminar Animal'),
                                ],
                              ),
                            )
                          ],
                        ),
                        onTap: () {
                          if (animal.lastLatitude != null) {
                            Navigator.pop(context);
                            _mapController.move(LatLng(animal.lastLatitude!, animal.lastLongitude!), 17.0);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteAnimal(String id) async {
    final confirm = await _showConfirmDeleteDialog('animal');
    if (confirm == true) {
      await DatabaseService.instance.delete('animals', where: 'id = ?', whereArgs: [id]);
      await DatabaseService.instance.delete('animal_alerts', where: 'animal_id = ?', whereArgs: [id]);
      _loadMapData();
    }
  }

  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return const Center(child: Text('No hay alertas registradas.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _alerts.length,
      itemBuilder: (context, idx) {
        final alert = _alerts[idx];
        return Card(
          color: Colors.red[50],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: const Icon(Icons.error, color: Colors.red),
            title: Text(alert.animalName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            subtitle: Text(
              'Salida de Geocerca\nCuidador: ${alert.caretaker}\nHora: ${_formatDateTime(alert.timestamp)}',
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.gps_fixed, color: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                _mapController.move(LatLng(alert.violationLatitude, alert.violationLongitude), 17.0);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
