import 'package:cloud_firestore/cloud_firestore.dart';

class Propriedade {
  String id;
  String? firebaseId;
  String nome;
  String dono;
  String? parentId;
  String statusSync;
  bool isDeleted;

  Propriedade({
    required this.id,
    this.firebaseId,
    required this.nome,
    required this.dono,
    this.parentId,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'nome': nome,
      'dono': dono,
      'parentId': parentId,
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
      statusSync: 'synced',
    );
  }

  Propriedade copyWith({
    String? id,
    String? firebaseId,
    String? nome,
    String? dono,
    String? parentId,
    String? statusSync,
    bool? isDeleted,
  }) {
    return Propriedade(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      nome: nome ?? this.nome,
      dono: dono ?? this.dono,
      parentId: parentId ?? this.parentId,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}