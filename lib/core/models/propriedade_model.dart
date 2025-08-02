import 'package:cloud_firestore/cloud_firestore.dart';

class Propriedade {
  String id;
  String? firebaseId;
  String nome;
  String dono;
  String? parentId;
  int deslocamentos;
  bool hasLotes; // NOVO CAMPO
  String statusSync;
  bool isDeleted;

  Propriedade({
    required this.id,
    this.firebaseId,
    required this.nome,
    required this.dono,
    this.parentId,
    this.deslocamentos = 0,
    this.hasLotes = true, // VALOR PADRÃO
    this.statusSync = 'pending_create',
    this.isDeleted = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Propriedade &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'nome': nome,
      'dono': dono,
      'parentId': parentId,
      'deslocamentos': deslocamentos,
      'hasLotes': hasLotes ? 1 : 0, // NOVO CAMPO
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Propriedade.fromMap(Map<String, dynamic> map) {
    return Propriedade(
      id: map['id'],
      firebaseId: map['firebaseId'],
      nome: map['nome'],
      dono: map['dono'],
      parentId: map['parentId'],
      deslocamentos: map['deslocamentos'] ?? 0,
      hasLotes: map['hasLotes'] == 1, // NOVO CAMPO
      statusSync: map['statusSync'],
      isDeleted: map['isDeleted'] == 1,
    );
  }

  Map<String, dynamic> toMapForFirebase() {
    return {
      'idLocal': id,
      'nome': nome,
      'dono': dono,
      'parentId': parentId,
      'deslocamentos': deslocamentos,
      'hasLotes': hasLotes, // NOVO CAMPO
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory Propriedade.fromFirebaseMap(String docId, Map<String, dynamic> map) {
    return Propriedade(
      id: map['idLocal'] ?? docId,
      firebaseId: docId,
      nome: map['nome'] ?? '',
      dono: map['dono'] ?? '',
      parentId: map['parentId'],
      deslocamentos: map['deslocamentos'] ?? 0,
      hasLotes: map['hasLotes'] ?? true, // NOVO CAMPO
      statusSync: 'synced',
    );
  }

  Propriedade copyWith({
    String? id,
    String? firebaseId,
    String? nome,
    String? dono,
    String? parentId,
    int? deslocamentos,
    bool? hasLotes, // NOVO CAMPO
    String? statusSync,
    bool? isDeleted,
  }) {
    return Propriedade(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      nome: nome ?? this.nome,
      dono: dono ?? this.dono,
      parentId: parentId ?? this.parentId,
      deslocamentos: deslocamentos ?? this.deslocamentos,
      hasLotes: hasLotes ?? this.hasLotes, // NOVO CAMPO
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}