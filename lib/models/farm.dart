class Farm {
  final String id;
  final String name;
  final String? ownerName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // 'pendiente', 'sincronizado', 'error', 'actualizado', 'eliminado'

  Farm({
    required this.id,
    required this.name,
    this.ownerName,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'owner_name': ownerName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory Farm.fromMap(Map<String, dynamic> map) {
    return Farm(
      id: map['id'] as String,
      name: map['name'] as String,
      ownerName: map['owner_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncStatus: map['sync_status'] as String,
    );
  }

  Farm copyWith({
    String? id,
    String? name,
    String? ownerName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return Farm(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
