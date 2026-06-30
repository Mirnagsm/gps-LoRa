import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/map_polygon.dart';
import '../services/database_service.dart';
import '../services/gis_helper.dart';

class PolygonFormScreen extends StatefulWidget {
  final String farmId;
  final List<LatLng> coordinates;
  final MapPolygon? existingPolygon; // null = create, non-null = edit

  const PolygonFormScreen({
    super.key,
    required this.farmId,
    required this.coordinates,
    this.existingPolygon,
  });

  bool get isEditing => existingPolygon != null;

  @override
  State<PolygonFormScreen> createState() => _PolygonFormScreenState();
}

class _PolygonFormScreenState extends State<PolygonFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cropController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedUseType = 'Cultivo';
  String _selectedStatus = 'Activo';
  double _calculatedArea = 0.0;

  final List<String> _useTypes = [
    'Cultivo',
    'Potrero',
    'Zona inundable',
    'Zona improductiva',
    'Zona talada',
    'Área en descanso',
    'Corral',
    'Camino',
    'Agua',
    'Infraestructura',
  ];

  final List<String> _statusOptions = [
    'Activo',
    'En descanso',
    'Inundado',
    'Dañado',
    'Preparación',
  ];

  @override
  void initState() {
    super.initState();
    _calculatedArea = GisHelper.calculateAreaInHectares(widget.coordinates);
    final ep = widget.existingPolygon;
    if (ep != null) {
      _nameController.text = ep.name;
      _selectedUseType = ep.type;
      // Extract crop from description if present
      final desc = ep.description;
      final cropMatch = RegExp(r'Cultivo: (.+?)( \||$)').firstMatch(desc);
      if (cropMatch != null) _cropController.text = cropMatch.group(1) ?? '';
      // Remove metadata suffixes for clean description
      _descriptionController.text = desc.replaceAll(RegExp(r' \| Cultivo:.*'), '').replaceAll(RegExp(r' \| Estado:.*'), '').trim();
    }
  }

  Future<void> _savePolygon() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {});

    final descriptionBuffer = StringBuffer();
    descriptionBuffer.write(_descriptionController.text.trim());
    
    // Add crop and status details to description or save in standard format
    if (_selectedUseType == 'Cultivo' && _cropController.text.isNotEmpty) {
      descriptionBuffer.write(' | Cultivo: ${_cropController.text.trim()}');
    }
    descriptionBuffer.write(' | Estado: $_selectedStatus');

    final ep = widget.existingPolygon;
    final newPolygon = MapPolygon(
      id: ep?.id ?? 'PAR-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      farmId: widget.farmId,
      type: _selectedUseType,
      name: _nameController.text.trim(),
      description: descriptionBuffer.toString(),
      areaHectares: _calculatedArea,
      coordinates: widget.coordinates,
      createdAt: ep?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pendiente',
    );

    try {
      if (widget.isEditing) {
        await DatabaseService.instance.update(
          'map_polygons',
          newPolygon.toMap(),
          where: 'id = ?',
          whereArgs: [newPolygon.id],
        );
      } else {
        await DatabaseService.instance.insert('map_polygons', newPolygon.toMap());
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Parcela "${newPolygon.name}" (${_calculatedArea.toStringAsFixed(2)} Ha) guardada'),
              ],
            ),
            backgroundColor: Colors.green[800],
          ),
        );
        Navigator.pop(context, true); // return success
      }
    } catch (e) {
      print('Error saving parcel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar la parcela localmente')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBE7),
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Parcela' : 'Registrar Parcela', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green[800],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Area Summary Card
              Card(
                elevation: 2,
                color: Colors.brown[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.square_foot, color: Colors.brown[700], size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Área de Parcela Calculada',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_calculatedArea.toStringAsFixed(4)} Hectáreas',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.brown[900]),
                            ),
                            Text(
                              '(${( _calculatedArea * 10000.0 ).toStringAsFixed(0)} m² aprox. / ${widget.coordinates.length} vértices)',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Name input
              const Text(
                'Nombre de la Parcela',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ej. Lote Norte, Potrero Las Vacas',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre de la parcela es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Use Type Dropdown
              const Text(
                'Tipo de Uso',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedUseType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  fillColor: Colors.white,
                  filled: true,
                ),
                items: _useTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedUseType = val);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Crop Input if use is Cultivo
              if (_selectedUseType == 'Cultivo') ...[
                const Text(
                  'Tipo de Cultivo Sembrado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cropController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ej. Maíz, Yuca, Pasto de corte',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    fillColor: Colors.white,
                    filled: true,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Status Dropdown
              const Text(
                'Estado del Terreno',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  fillColor: Colors.white,
                  filled: true,
                ),
                items: _statusOptions.map((opt) {
                  return DropdownMenuItem<String>(
                    value: opt,
                    child: Text(opt),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStatus = val);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Description input
              const Text(
                'Observaciones / Detalles',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Ej. Suelo abonado hace 2 semanas, pendiente leve...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
              const SizedBox(height: 36),

              // Save Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                ),
                onPressed: _savePolygon,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'GUARDAR PARCELA',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
