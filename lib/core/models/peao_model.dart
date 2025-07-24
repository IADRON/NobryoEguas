// lib/core/models/peao_model.dart

class Peao {
  String id;
  String nome;
  String funcao;
  String propriedadeId;
  bool isDeleted;

  Peao({
    required this.id,
    required this.nome,
    required this.funcao,
    required this.propriedadeId,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'funcao': funcao,
      'propriedadeId': propriedadeId,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Peao.fromMap(Map<String, dynamic> map) {
    return Peao(
      id: map['id'],
      nome: map['nome'] ?? '',
      funcao: map['funcao'] ?? '',
      propriedadeId: map['propriedadeId'] ?? '',
      isDeleted: map['isDeleted'] == 1,
    );
  }

  Peao copyWith({
    String? id,
    String? nome,
    String? funcao,
    String? propriedadeId,
    bool? isDeleted,
  }) {
    return Peao(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      funcao: funcao ?? this.funcao,
      propriedadeId: propriedadeId ?? this.propriedadeId,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}