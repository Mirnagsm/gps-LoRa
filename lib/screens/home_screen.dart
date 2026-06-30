import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/farm.dart';
import '../services/database_service.dart';
import 'map_screen.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Farm> _farms = [];
  Map<String, Map<String, dynamic>> _farmStats = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    setState(() => _isLoading = true);
    try {
      final maps = await DatabaseService.instance.query('farms', orderBy: 'created_at DESC');
      final farmsList = maps.map((m) => Farm.fromMap(m)).toList();
      
      final statsMap = <String, Map<String, dynamic>>{};
      for (final farm in farmsList) {
        final points = await DatabaseService.instance.query(
          'map_points',
          where: 'farm_id = ?',
          whereArgs: [farm.id],
        );
        final polygons = await DatabaseService.instance.query(
          'map_polygons',
          where: 'farm_id = ?',
          whereArgs: [farm.id],
        );
        double totalHa = 0.0;
        for (final poly in polygons) {
          totalHa += (poly['area_hectares'] as num?)?.toDouble() ?? 0.0;
        }
        statsMap[farm.id] = {
          'points': points.length,
          'polygons': polygons.length,
          'area': totalHa,
        };
      }

      setState(() {
        _farms = farmsList;
        _farmStats = statsMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading farms: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createFarm(String name, String owner) async {
    final newFarm = Farm(
      id: const Uuid().v4(),
      name: name,
      ownerName: owner.isEmpty ? null : owner,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pendiente',
    );

    await DatabaseService.instance.insert('farms', newFarm.toMap());
    _loadFarms();
  }

  Future<void> _editFarm(String id, String name, String owner) async {
    await DatabaseService.instance.update(
      'farms',
      {
        'name': name,
        'owner_name': owner.isEmpty ? null : owner,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'pendiente',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _loadFarms();
  }

  Future<void> _deleteFarm(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar Finca?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Esta acción eliminará de forma permanente la finca y todas sus parcelas, puntos de interés, animales registrados y alertas de geocercas asociados localmente. Esta acción no se puede deshacer.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.delete('farms', where: 'id = ?', whereArgs: [id]);
      await DatabaseService.instance.delete('map_points', where: 'farm_id = ?', whereArgs: [id]);
      await DatabaseService.instance.delete('map_polygons', where: 'farm_id = ?', whereArgs: [id]);
      
      // Cascade delete animals and their alerts
      final animals = await DatabaseService.instance.query('animals', where: 'farm_id = ?', whereArgs: [id]);
      for (final animal in animals) {
        await DatabaseService.instance.delete('animal_alerts', where: 'animal_id = ?', whereArgs: [animal['id']]);
      }
      await DatabaseService.instance.delete('animals', where: 'farm_id = ?', whereArgs: [id]);
      
      _loadFarms();
    }
  }

  void _showCreateFarmDialog() {
    final nameController = TextEditingController();
    final ownerController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.agriculture, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Nueva Finca', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Finca *',
                  hintText: 'Ej. Finca La Esperanza',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ownerController,
                decoration: const InputDecoration(
                  labelText: 'Productor / Dueño',
                  hintText: 'Ej. Juan Pérez',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  _createFarm(nameController.text.trim(), ownerController.text.trim());
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('El nombre de la finca es obligatorio')),
                  );
                }
              },
              child: const Text('Crear Finca', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showEditFarmDialog(Farm farm) {
    final nameController = TextEditingController(text: farm.name);
    final ownerController = TextEditingController(text: farm.ownerName ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Editar Finca', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Finca *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ownerController,
                decoration: const InputDecoration(
                  labelText: 'Productor / Dueño',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  _editFarm(farm.id, nameController.text.trim(), ownerController.text.trim());
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('El nombre de la finca es obligatorio')),
                  );
                }
              },
              child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBE7), // Light green-yellow organic tone
      appBar: AppBar(
        title: const Text(
          'CampoMap Offline',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
        ),
        backgroundColor: Colors.green[800],
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SyncScreen()),
              ).then((_) => _loadFarms());
            },
            tooltip: 'Sincronizar datos',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFarms,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_farms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar finca por nombre o dueño...',
                  prefixIcon: const Icon(Icons.search, color: Colors.green),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.green))
                : _farms.isEmpty
                    ? _buildEmptyState()
                    : _buildFarmList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateFarmDialog,
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 28),
        label: const Text(
          'REGISTRAR FINCA',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.landscape,
                size: 100,
                color: Colors.green[600],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No hay fincas registradas',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Registra tu primera finca para empezar a mapear linderos, parcelas y puntos de interés sin necesidad de internet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
              ),
              onPressed: _showCreateFarmDialog,
              icon: const Icon(Icons.add_circle, size: 24),
              label: const Text(
                'CREAR FINCA AHORA',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFarmList() {
    final filteredFarms = _farms.where((f) {
      final nameLower = f.name.toLowerCase();
      final ownerLower = (f.ownerName ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return nameLower.contains(query) || ownerLower.contains(query);
    }).toList();

    if (filteredFarms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Ninguna finca coincide con la búsqueda.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 88),
      itemCount: filteredFarms.length,
      itemBuilder: (context, index) {
        final farm = filteredFarms[index];
        final stats = _farmStats[farm.id] ?? {'points': 0, 'polygons': 0, 'area': 0.0};
        final pointsCount = stats['points'] as int;
        final polygonsCount = stats['polygons'] as int;
        final areaHectares = stats['area'] as double;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MapScreen(farm: farm),
                ),
              ).then((_) => _loadFarms());
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.agriculture,
                      size: 36,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farm.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                farm.ownerName ?? 'Sin productor asignado',
                                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Quick Stats Row
                        Row(
                          children: [
                            Icon(Icons.layers, size: 16, color: Colors.brown[600]),
                            const SizedBox(width: 4),
                            Text(
                              '$polygonsCount parc.',
                              style: TextStyle(fontSize: 12, color: Colors.brown[800], fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.square_foot, size: 16, color: Colors.brown[600]),
                            const SizedBox(width: 4),
                            Text(
                              '${areaHectares.toStringAsFixed(1)} Ha',
                              style: TextStyle(fontSize: 12, color: Colors.brown[800], fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.location_on, size: 16, color: Colors.blue[600]),
                            const SizedBox(width: 4),
                            Text(
                              '$pointsCount pts.',
                              style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Creada el ${_formatDate(farm.createdAt)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.green[800]),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditFarmDialog(farm);
                      } else if (value == 'delete') {
                        _deleteFarm(farm.id);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Editar Finca'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Eliminar Finca'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
