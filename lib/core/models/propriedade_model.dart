class Propriedade {
  String id;
  String? firebaseId;
  String nome;
  String dono;
  String statusSync;
  bool isDeleted;

  Propriedade({
    required this.id,
    this.firebaseId,
    required this.nome,
    required this.dono,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Propriedade && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'nome': nome,
      'dono': dono,
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Propriedade.fromMap(Map<String, dynamic> map) {
    return Propriedade(
      id: map['id'],
      firebaseId: map['firebaseId'],
      nome: map['nome'] ?? '',
      dono: map['dono'] ?? '',
      statusSync: map['statusSync'] ?? 'synced',
      isDeleted: map['isDeleted'] == 1,
    );
  }

  Propriedade copyWith({
    String? id,
    String? firebaseId,
    String? nome,
    String? dono,
    String? statusSync,
    bool? isDeleted,
  }) {
    return Propriedade(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      nome: nome ?? this.nome,
      dono: dono ?? this.dono,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}