class Medicamento {
  String id;
  String? firebaseId;
  String nome;
  String descricao;
  String statusSync;
  bool isDeleted;

  Medicamento({
    required this.id,
    this.firebaseId,
    required this.nome,
    required this.descricao,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'nome': nome,
      'descricao': descricao,
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Medicamento.fromMap(Map<String, dynamic> map) {
    return Medicamento(
      id: map['id'],
      firebaseId: map['firebaseId'],
      nome: map['nome'] ?? '',
      descricao: map['descricao'] ?? '',
      statusSync: map['statusSync'] ?? 'synced',
      isDeleted: map['isDeleted'] == 1,
    );
  }

  Medicamento copyWith({
    String? id,
    String? firebaseId,
    String? nome,
    String? descricao,
    String? statusSync,
    bool? isDeleted,
  }) {
    return Medicamento(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}