import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/map_point.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/database_service.dart';

class PointFormScreen extends StatefulWidget {
  final String farmId;
  final double initialLatitude;
  final double initialLongitude;
  final MapPoint? existingPoint; // null = create, non-null = edit

  const PointFormScreen({
    super.key,
    required this.farmId,
    required this.initialLatitude,
    required this.initialLongitude,
    this.existingPoint,
  });

  bool get isEditing => existingPoint != null;

  @override
  State<PointFormScreen> createState() => _PointFormScreenState();
}

class _PointFormScreenState extends State<PointFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedType = 'Pozo';
  XFile? _pickedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final ep = widget.existingPoint;
    if (ep != null) {
      _nameController.text = ep.name;
      _descriptionController.text = ep.description;
      _selectedType = ep.type;
    }
  }

  final List<Map<String, dynamic>> _pointTypes = [
    {'name': 'Pozo', 'icon': Icons.water_drop, 'color': Colors.blue},
    {'name': 'Cerca', 'icon': Icons.fence, 'color': Colors.brown},
    {'name': 'Corral', 'icon': Icons.warehouse, 'color': Colors.orange},
    {'name': 'Portón', 'icon': Icons.door_sliding, 'color': Colors.red},
    {'name': 'Árbol importante', 'icon': Icons.park, 'color': Colors.green},
    {'name': 'Casa/Depósito', 'icon': Icons.home, 'color': Colors.grey},
    {'name': 'Punto de agua', 'icon': Icons.opacity, 'color': Colors.cyan},
    {'name': 'Poste', 'icon': Icons.power_input, 'color': Colors.yellow[800]},
    {'name': 'Zona dañada', 'icon': Icons.warning_amber, 'color': Colors.red[900]},
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _pickedImage = image;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.green),
                title: const Text('Tomar Foto con Cámara'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Seleccionar de la Galería'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePoint() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    String? savedPhotoPath = _pickedImage?.path;
    if (_pickedImage != null && !kIsWeb) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final photosDir = Directory('${directory.path}/photos');
        if (!await photosDir.exists()) {
          await photosDir.create(recursive: true);
        }
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(_pickedImage!.path)}';
        final newFile = await File(_pickedImage!.path).copy('${photosDir.path}/$fileName');
        savedPhotoPath = newFile.path;
      } catch (e) {
        print('Error saving photo permanently: $e');
      }
    }

    final ep = widget.existingPoint;
    final newPoint = MapPoint(
      id: ep?.id ?? 'PTO-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      farmId: widget.farmId,
      type: _selectedType,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      latitude: widget.initialLatitude,
      longitude: widget.initialLongitude,
      photoPath: savedPhotoPath ?? ep?.photoPath,
      createdAt: ep?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pendiente',
    );

    try {
      if (widget.isEditing) {
        await DatabaseService.instance.update(
          'map_points',
          newPoint.toMap(),
          where: 'id = ?',
          whereArgs: [newPoint.id],
        );
      } else {
        await DatabaseService.instance.insert('map_points', newPoint.toMap());
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('"${newPoint.name}" ${widget.isEditing ? 'actualizado' : 'guardado'} localmente'),
              ],
            ),
            backgroundColor: Colors.green[800],
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error saving point: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar el punto localmente')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBE7),
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Punto' : 'Registrar Punto', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green[800],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // GPS Card Info
                    Card(
                      elevation: 2,
                      color: Colors.green[50],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.gps_fixed, color: Colors.green[800], size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Ubicación Capturada por GPS',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Latitud: ${widget.initialLatitude.toStringAsFixed(6)}\nLongitud: ${widget.initialLongitude.toStringAsFixed(6)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Type Selector Label
                    const Text(
                      'Tipo de Punto',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        fillColor: Colors.white,
                        filled: true,
                        prefixIcon: Icon(
                          _pointTypes.firstWhere((t) => t['name'] == _selectedType)['icon'] as IconData,
                          color: _pointTypes.firstWhere((t) => t['name'] == _selectedType)['color'] as Color,
                        ),
                      ),
                      items: _pointTypes.map((type) {
                        return DropdownMenuItem<String>(
                          value: type['name'] as String,
                          child: Row(
                            children: [
                              Icon(type['icon'] as IconData, color: type['color'] as Color, size: 20),
                              const SizedBox(width: 10),
                              Text(type['name'] as String),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Name input
                    const Text(
                      'Nombre / Identificador',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ej. Pozo Principal, Portón Norte',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'El nombre es obligatorio';
                        }
                        return null;
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
                        hintText: 'Escribe detalles útiles sobre este punto...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Photo selector
                    const Text(
                      'Evidencia Fotográfica',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
                    ),
                    const SizedBox(height: 8),
                    _buildPhotoPlaceholder(),
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
                      onPressed: _savePoint,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'GUARDAR REGISTRO',
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

  Widget _buildPhotoPlaceholder() {
    if (_pickedImage == null) {
      return Card(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.green[800]!.withOpacity(0.3), width: 1.5, style: BorderStyle.solid),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _showImageSourceActionSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36.0),
            child: Column(
              children: [
                Icon(Icons.add_a_photo, size: 48, color: Colors.green[800]),
                const SizedBox(height: 8),
                Text(
                  'Tomar o adjuntar foto',
                  style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: kIsWeb
              ? Image.network(
                  _pickedImage!.path,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              : Image.file(
                  File(_pickedImage!.path),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: CircleAvatar(
            backgroundColor: Colors.red,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: () {
                setState(() {
                  _pickedImage = null;
                });
              },
            ),
          ),
        ),
      ],
    );
  }
}
