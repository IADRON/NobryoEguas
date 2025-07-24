import 'package:cloud_firestore/cloud_firestore.dart';

class Egua {
  String id;
  String? firebaseId;
  String nome;
  String rp;
  String pelagem;
  String? cobertura;
  DateTime? dataParto;
  String? sexoPotro;
  String statusReprodutivo;
  int? diasPrenhe;
  String? observacao;
  String propriedadeId;
  String statusSync;
  bool isDeleted;
  String categoria; // Novo campo adicionado

  Egua({
    required this.id,
    this.firebaseId,
    required this.nome,
    required this.rp,
    required this.pelagem,
    this.cobertura,
    this.dataParto,
    this.sexoPotro,
    required this.statusReprodutivo,
    this.diasPrenhe,
    this.observacao,
    required this.propriedadeId,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
    this.categoria = 'Matriz', // Valor padrão
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Egua && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'nome': nome,
      'rp': rp,
      'pelagem': pelagem,
      'cobertura': cobertura,
      'dataParto': dataParto?.toIso8601String(),
      'sexoPotro': sexoPotro,
      'statusReprodutivo': statusReprodutivo,
      'diasPrenhe': diasPrenhe,
      'observacao': observacao,
      'propriedadeId': propriedadeId,
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
      'categoria': categoria,
    };
  }

  factory Egua.fromMap(Map<String, dynamic> map) {
    return Egua(
      id: map['id'],
      firebaseId: map['firebaseId'],
      nome: map['nome'],
      rp: map['rp'],
      pelagem: map['pelagem'],
      cobertura: map['cobertura'],
      dataParto: map['dataParto'] != null ? DateTime.parse(map['dataParto']) : null,
      sexoPotro: map['sexoPotro'],
      statusReprodutivo: map['statusReprodutivo'],
      diasPrenhe: map['diasPrenhe'],
      observacao: map['observacao'],
      propriedadeId: map['propriedadeId'],
      statusSync: map['statusSync'],
      isDeleted: map['isDeleted'] == 1,
      categoria: map['categoria'] ?? 'Matriz',
    );
  }

  Map<String, dynamic> toMapForFirebase(String propriedadeFirebaseId) {
    return {
      'idLocal': id,
      'nome': nome,
      'rp': rp,
      'pelagem': pelagem,
      'cobertura': cobertura,
      'dataParto': dataParto,
      'sexoPotro': sexoPotro,
      'observacao': observacao,
      'statusReprodutivo': statusReprodutivo,
      'diasPrenhe': diasPrenhe,
      'propriedadeFirebaseId': propriedadeFirebaseId,
      'categoria': categoria,
    };
  }

  factory Egua.fromFirebaseMap(String firebaseId, String propId, Map<String, dynamic> map) {
    final dataPartoTimestamp = map['dataParto'] as Timestamp?;
    return Egua(
      id: map['idLocal'] ?? firebaseId,
      firebaseId: firebaseId,
      propriedadeId: propId,
      nome: map['nome'] ?? '',
      rp: map['rp'] ?? '',
      pelagem: map['pelagem'] ?? '',
      cobertura: map['cobertura'],
      dataParto: dataPartoTimestamp?.toDate(),
      sexoPotro: map['sexoPotro'],
      statusReprodutivo: map['statusReprodutivo'] ?? 'Vazia',
      diasPrenhe: map['diasPrenhe'],
      observacao: map['observacao'],
      statusSync: 'synced',
      isDeleted: false, 
      categoria: map['categoria'] ?? 'Matriz',
    );
  }

  Egua copyWith({
    String? id,
    String? firebaseId,
    String? nome,
    String? rp,
    String? pelagem,
    String? cobertura,
    DateTime? dataParto,
    String? sexoPotro,
    String? statusReprodutivo,
    int? diasPrenhe,
    String? observacao,
    String? propriedadeId,
    String? statusSync,
    bool? isDeleted,
    String? categoria,
  }) {
    return Egua(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      nome: nome ?? this.nome,
      rp: rp ?? this.rp,
      pelagem: pelagem ?? this.pelagem,
      cobertura: cobertura ?? this.cobertura,
      dataParto: dataParto ?? this.dataParto,
      sexoPotro: sexoPotro ?? this.sexoPotro,
      statusReprodutivo: statusReprodutivo ?? this.statusReprodutivo,
      diasPrenhe: diasPrenhe ?? this.diasPrenhe,
      observacao: observacao ?? this.observacao,
      propriedadeId: propriedadeId ?? this.propriedadeId,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
      categoria: categoria ?? this.categoria,
    );
  }
}